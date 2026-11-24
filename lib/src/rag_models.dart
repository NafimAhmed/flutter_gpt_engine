/// Optional retrieval-augmented generation (RAG) primitives.
///
/// Inference works without RAG. Host applications choose an embedding provider
/// and a vector store only when they explicitly enable retrieval.
class RagDocument {
  const RagDocument({
    required this.id,
    required this.text,
    this.title = '',
    this.source = '',
    this.metadata = const <String, String>{},
  });

  final String id;
  final String text;
  final String title;
  final String source;
  final Map<String, String> metadata;
}

class RagChunk {
  const RagChunk({
    required this.id,
    required this.documentId,
    required this.text,
    required this.title,
    required this.source,
    this.metadata = const <String, String>{},
  });

  final String id;
  final String documentId;
  final String text;
  final String title;
  final String source;
  final Map<String, String> metadata;
}

class RagVectorPoint {
  const RagVectorPoint({required this.chunk, required this.vector});
  final RagChunk chunk;
  final List<double> vector;
}

class RagSearchHit {
  const RagSearchHit({required this.chunk, required this.score});
  final RagChunk chunk;
  final double score;
}

class RagRetrievalResult {
  const RagRetrievalResult({
    required this.query,
    required this.hits,
  });

  final String query;
  final List<RagSearchHit> hits;
  bool get isEmpty => hits.isEmpty;

  /// Adds explicit [1], [2], ... markers for local-model grounded responses.
  /// Markers refer to hits in their original order, not full source URLs.
  String toPromptContext({int maxCharacters = 6000}) {
    if (maxCharacters < 1) return '';
    final buffer = StringBuffer();

    for (var i = 0; i < hits.length; i++) {
      final chunk = hits[i].chunk;
      final block = '\n[' + (i + 1).toString() + ']\n' +
          'Document ID: ' + chunk.documentId + '\n' +
          'Title: ' + chunk.title + '\n' +
          'Source: ' + chunk.source + '\n' +
          'Text:\n' + chunk.text + '\n';

      if (buffer.length + block.length > maxCharacters) {
        // Never expose a half-citation or a partially copied document chunk.
        break;
      }

      buffer.write(block);
    }

    return buffer.toString().trim();
  }
}

class RagConfig {
  const RagConfig({
    this.chunkSize = 800,
    this.chunkOverlap = 120,
    this.topK = 4,
    this.minScore = 0.10,
    this.maxContextCharacters = 6000,
  })  : assert(chunkSize >= 100),
        assert(chunkOverlap >= 0),
        assert(chunkOverlap < chunkSize),
        assert(topK > 0),
        assert(minScore >= -1 && minScore <= 1),
        assert(maxContextCharacters > 0);

  final int chunkSize;
  final int chunkOverlap;
  final int topK;
  final double minScore;
  final int maxContextCharacters;
}

/// Supply actual semantic embeddings via a local model or a trusted API.
/// Use the same model/dimensions when indexing and querying a collection.
abstract class RagEmbeddingProvider {
  Future<List<double>> embed(String text);
}

class RagCallbackEmbeddingProvider implements RagEmbeddingProvider {
  const RagCallbackEmbeddingProvider(this.callback);

  final Future<List<double>> Function(String text) callback;

  @override
  Future<List<double>> embed(String text) => callback(text);
}

/// A replaceable vector index: local memory, Qdrant, or a custom database.
abstract class RagVectorStore {
  Future<void> upsert(List<RagVectorPoint> points);

  /// Implementations should rank by similarity, highest score first.
  Future<List<RagSearchHit>> search(
    List<double> queryVector, {
    required int topK,
    required double minScore,
  });

  Future<void> deleteDocument(String documentId);
}

/// Optional atomic whole-document replacement contract.
///
/// Implementations can replace all indexed chunks for a document in a single
/// transaction, preventing data loss if indexing fails midway.
abstract class RagReplaceableVectorStore implements RagVectorStore {
  Future<void> replaceDocument(String documentId, List<RagVectorPoint> points);
}
