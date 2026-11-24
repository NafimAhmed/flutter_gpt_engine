import 'dart:convert';
import 'dart:math' as math;

import 'rag_models.dart';

/// Small, dependency-free lexical hashing for offline demos and testing.
///
/// NOT a semantic embedding model. Synonyms/meaning may not be recognized.
/// Plug in a real embedding provider for production RAG.
class RagKeywordHashEmbeddingProvider implements RagEmbeddingProvider {
  const RagKeywordHashEmbeddingProvider({this.dimensions = 256})
      : assert(dimensions >= 16);

  final int dimensions;

  @override
  Future<List<double>> embed(String text) async {
    final vector = List<double>.filled(dimensions, 0);
    final tokens = RegExp(r'[a-zA-Z0-9\u0980-\u09FF]+', unicode: true)
        .allMatches(text.toLowerCase());
    for (final match in tokens) {
      final word = match.group(0)!;
      // Fixed 32-bit FNV-1a to make the same query stable across sessions.
      var hash = 0x811c9dc5;
      for (final byte in utf8.encode(word)) {
        hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
      }
      vector[hash % dimensions] += 1;
    }

    final length = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + value * value),
    );
    if (length == 0) return vector;
    return vector.map((value) => value / length).toList(growable: false);
  }
}

class RagInMemoryVectorStore implements RagVectorStore {
  final Map<String, RagVectorPoint> _points = <String, RagVectorPoint>{};
  int? _dimension;

  int get length => _points.length;

  @override
  Future<void> upsert(List<RagVectorPoint> points) async {
    if (points.isEmpty) return;
    final expected = _dimension ?? points.first.vector.length;
    if (expected < 1) throw ArgumentError('Vectors must not be empty.');

    // Validate the entire batch before changing the store.
    for (final point in points) {
      if (point.chunk.id.isEmpty) {
        throw ArgumentError('A chunk ID cannot be empty.');
      }
      if (point.vector.length != expected ||
          point.vector.any((value) => !value.isFinite)) {
        throw ArgumentError('Invalid vector dimension or non-finite value.');
      }
      if (_norm(point.vector) == 0) {
        throw ArgumentError('A zero-length embedding is not searchable.');
      }
    }

    _dimension = expected;
    for (final point in points) {
      _points[point.chunk.id] = point;
    }
  }

  @override
  Future<List<RagSearchHit>> search(
    List<double> queryVector, {
    required int topK,
    required double minScore,
  }) async {
    if (topK < 1) throw ArgumentError.value(topK, 'topK');
    if (_points.isEmpty) return <RagSearchHit>[];

    if (queryVector.length != _dimension ||
        queryVector.any((value) => !value.isFinite)) {
      throw ArgumentError('Query embedding dimension does not match index.');
    }
    final norm = _norm(queryVector);
    if (norm == 0) return <RagSearchHit>[];

    final hits = <RagSearchHit>[];
    for (final point in _points.values) {
      final other = _norm(point.vector);
      if (other == 0) continue;
      var dot = 0.0;
      for (var i = 0; i < queryVector.length; i++) {
        dot += queryVector[i] * point.vector[i];
      }
      final similarity = (dot / (norm * other)).clamp(-1.0, 1.0).toDouble();
      if (similarity >= minScore) {
        hits.add(RagSearchHit(chunk: point.chunk, score: similarity));
      }
    }

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore == 0 ? a.chunk.id.compareTo(b.chunk.id) : byScore;
    });
    return hits.take(topK).toList(growable: false);
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    _points.removeWhere((_, point) => point.chunk.documentId == documentId);
    if (_points.isEmpty) _dimension = null;
  }

  static double _norm(List<double> vector) => math.sqrt(
        vector.fold<double>(0, (sum, value) => sum + value * value),
      );
}

/// Text ingestion, chunking, embeddings and vector retrieval.
///
/// Remote vector stores transmit document text and embeddings to the configured
/// server. Host apps are responsible for consent and server-side security.
class RagService {
  const RagService({
    required this.embeddingProvider,
    required this.vectorStore,
    this.config = const RagConfig(),
  });

  final RagEmbeddingProvider embeddingProvider;
  final RagVectorStore vectorStore;
  final RagConfig config;

  Future<int> addDocument(RagDocument document) async {
    if (document.id.trim().isEmpty || document.text.trim().isEmpty) {
      throw ArgumentError('Document ID and text must not be empty.');
    }
    final chunks = splitDocument(document);
    final points = <RagVectorPoint>[];

    // Sequential embeddings avoid loading many expensive local models at once.
    for (final chunk in chunks) {
      final embedding = await embeddingProvider.embed(chunk.text);
      points.add(RagVectorPoint(chunk: chunk, vector: embedding));
    }

    // Persistent stores can replace all chunks atomically. Legacy stores
    // retain their existing delete-then-upsert behavior.
    final store = vectorStore;
    if (store is RagReplaceableVectorStore) {
      await store.replaceDocument(document.id, points);
    } else {
      await store.deleteDocument(document.id);
      await store.upsert(points);
    }
    return points.length;
  }

  Future<void> removeDocument(String documentId) =>
      vectorStore.deleteDocument(documentId);

  Future<RagRetrievalResult> retrieve(
    String question, {
    int? topK,
    double? minScore,
  }) async {
    if (question.trim().isEmpty) {
      throw ArgumentError.value(question, 'question', 'Cannot be empty.');
    }
    final vector = await embeddingProvider.embed(question);
    if (vector.isEmpty || vector.any((value) => !value.isFinite)) {
      throw StateError('Embedding provider returned an invalid vector.');
    }

    final hits = await vectorStore.search(
      vector,
      topK: topK ?? config.topK,
      minScore: minScore ?? config.minScore,
    );
    return RagRetrievalResult(
      query: question,
      hits: List<RagSearchHit>.unmodifiable(hits),
    );
  }

  List<RagChunk> splitDocument(RagDocument document) {
    final characters = document.text.runes.toList(growable: false);
    final result = <RagChunk>[];
    final overlap = config.chunkOverlap;
    final size = config.chunkSize;
    var start = 0;

    while (start < characters.length) {
      var end = math.min(start + size, characters.length);
      if (end < characters.length) {
        // Prefer a nearby word boundary, without producing tiny chunks.
        final threshold = start + size ~/ 2;
        for (var at = end - 1; at > threshold; at--) {
          if (characters[at] == 32 ||
              characters[at] == 10 ||
              characters[at] == 9) {
            end = at + 1;
            break;
          }
        }
      }
      final text = String.fromCharCodes(
        characters.sublist(start, end),
      ).trim();

      if (text.isNotEmpty) {
        result.add(RagChunk(
          id: document.id + ':' + result.length.toString(),
          documentId: document.id,
          text: text,
          title: document.title,
          source: document.source,
          metadata: document.metadata,
        ));
      }
      if (end >= characters.length) break;
      start = math.max(end - overlap, start + 1);
    }

    return result;
  }
}
