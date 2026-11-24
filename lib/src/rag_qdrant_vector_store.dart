import 'dart:convert';
import 'dart:io';

import 'rag_models.dart';

/// Optional Qdrant REST adapter for a PRE-EXISTING vector collection.
///
/// The Qdrant collection must use an unnamed dense vector with the same
/// dimensionality and similarity metric as the embedding provider.
/// This adapter sends chunk text and embeddings to the configured server.
/// Never embed a production API key inside a distributed mobile application:
/// use an authenticated proxy/backend in production.
class RagQdrantVectorStore implements RagVectorStore {
  RagQdrantVectorStore({
    required Uri endpoint,
    required this.collection,
    this.apiKey,
    this.timeout = const Duration(seconds: 15),
    HttpClient? httpClient,
  }) : _endpoint = _validateEndpoint(endpoint),
       _client = httpClient ?? HttpClient(),
       _ownsClient = httpClient == null {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(collection)) {
      throw ArgumentError.value(collection, 'collection', 'Invalid name.');
    }
  }

  final Uri _endpoint;
  final String collection;
  final String? apiKey;
  final Duration timeout;
  final HttpClient _client;
  final bool _ownsClient;

  void dispose() {
    if (_ownsClient) _client.close(force: true);
  }

  @override
  Future<void> upsert(List<RagVectorPoint> points) async {
    if (points.isEmpty) return;
    final expected = points.first.vector.length;
    if (expected < 1) throw ArgumentError('Empty vector.');
    for (final point in points) {
      if (point.vector.length != expected ||
          point.vector.any((v) => !v.isFinite)) {
        throw ArgumentError('Invalid vector dimension or value.');
      }
    }

    await _request('PUT', 'points?wait=true', <String, Object?>{
      'points': <Object>[
        for (final point in points)
          <String, Object?>{
            // Qdrant point IDs must be UUID strings or unsigned integers.
            'id': _stablePointId(point.chunk.id),
            'vector': point.vector,
            'payload': <String, Object?>{
              'chunkId': point.chunk.id,
              'documentId': point.chunk.documentId,
              'title': point.chunk.title,
              'source': point.chunk.source,
              'text': point.chunk.text,
              'metadata': point.chunk.metadata,
            },
          },
      ],
    });
  }

  @override
  Future<List<RagSearchHit>> search(
    List<double> queryVector, {
    required int topK,
    required double minScore,
  }) async {
    if (topK < 1) throw ArgumentError.value(topK, 'topK');
    if (queryVector.isEmpty ||
        queryVector.any((value) => !value.isFinite)) {
      throw ArgumentError('Query vector must contain finite values.');
    }

    final response = await _request('POST', 'points/query', <String, Object?>{
      'query': queryVector,
      'limit': topK,
      'score_threshold': minScore,
      'with_payload': true,
    });

    final result = response['result'];
    if (result is! Map || result['points'] is! List) {
      throw FormatException('Unexpected Qdrant query response.');
    }

    final hits = <RagSearchHit>[];
    for (final item in result['points'] as List) {
      if (item is! Map || item['payload'] is! Map ||
          item['score'] is! num) {
        continue;
      }
      final payload = item['payload'] as Map;
      final id = payload['chunkId'];
      final documentId = payload['documentId'];
      final text = payload['text'];
      if (id is! String || documentId is! String || text is! String) {
        continue;
      }
      final rawMetadata = payload['metadata'];
      final metadata = <String, String>{};
      if (rawMetadata is Map) {
        for (final entry in rawMetadata.entries) {
          if (entry.key is String && entry.value is String) {
            metadata[entry.key as String] = entry.value as String;
          }
        }
      }
      final score = (item['score'] as num).toDouble();
      if (!score.isFinite || score < minScore) continue;

      hits.add(RagSearchHit(
        chunk: RagChunk(
          id: id,
          documentId: documentId,
          text: text,
          title: payload['title'] is String
              ? payload['title'] as String : '',
          source: payload['source'] is String
              ? payload['source'] as String : '',
          metadata: metadata,
        ),
        score: score,
      ));
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(topK).toList(growable: false);
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    if (documentId.trim().isEmpty) {
      throw ArgumentError.value(documentId, 'documentId');
    }
    await _request('POST', 'points/delete?wait=true', <String, Object?>{
      'filter': <String, Object?>{
        'must': <Object>[
          <String, Object?>{
            'key': 'documentId',
            'match': <String, Object?>{'value': documentId},
          },
        ],
      },
    });
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String suffix,
    Map<String, Object?> payload,
  ) async {
    final collectionSegment = Uri.encodeComponent(collection);
    final basePath = _endpoint.path.endsWith('/')
        ? _endpoint.path.substring(0, _endpoint.path.length - 1)
        : _endpoint.path;
    final uri = _endpoint.replace(
      path: basePath + '/collections/' + collectionSegment +
          '/' + suffix.split('?').first,
      query: suffix.contains('?') ? suffix.split('?').last : null,
    );

    final request = await _client.openUrl(method, uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    if (apiKey != null && apiKey!.isNotEmpty) {
      request.headers.set('api-key', apiKey!);
    }
    request.write(jsonEncode(payload));

    final response = await request.close().timeout(timeout);
    final text = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Qdrant HTTP ' + response.statusCode.toString() +
            ': ' + text.substring(0, text.length > 300 ? 300 : text.length),
        uri: uri,
      );
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Qdrant returned non-object JSON.');
    }
    final status = decoded['status'];
    if (status is String && status != 'ok') {
      throw StateError('Qdrant returned error: ' + status);
    }
    return decoded;
  }

  static Uri _validateEndpoint(Uri uri) {
    if (!<String>['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(uri, 'endpoint', 'Invalid Qdrant endpoint.');
    }
    return uri;
  }

  /// Stable positive 63-bit FNV-1a ID for Qdrant's integer point ID format.
  /// This is not a cryptographic digest; collisions, although unlikely, can
  /// occur for distinct chunk IDs.
  static int _stablePointId(String id) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(id)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
