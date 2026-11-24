import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'rag_models.dart';

/// Durable offline SQLite storage for text chunks and Float64 embeddings.
///
/// This uses cosine similarity over a paged linear scan, not HNSW/ANN.
/// Intended for small and medium device-local collections. The database is
/// not encrypted; protect sensitive contents in the host application.
class RagSqliteVectorStore implements RagReplaceableVectorStore {
  RagSqliteVectorStore._(
    this.databasePath,
    this.collection,
    this.embeddingModelId,
    this._factory,
  );

  final String databasePath;
  final String collection;
  final String embeddingModelId;
  final DatabaseFactory _factory;
  Database? _database;
  bool _closed = false;

  static const _chunks = 'rag_vector_chunks';
  static const _collections = 'rag_vector_collections';

  /// Opens a database file in the app's default SQLite directory.
  ///
  /// Pass an absolute [databasePath] for custom locations/FFI tests.
  /// [embeddingModelId] identifies the model and configuration; keep it the
  /// same on every app restart. For a new embedding model, reindex separately.
  static Future<RagSqliteVectorStore> open({
    String fileName = 'flutter_gpt_engine_vectors.db',
    String? databasePath,
    String collection = 'default',
    String embeddingModelId = 'keyword-hash-256-v1',
    DatabaseFactory? factory,
  }) async {
    if (fileName.isEmpty ||
        fileName != p.basename(fileName) ||
        !fileName.toLowerCase().endsWith('.db')) {
      throw ArgumentError.value(fileName, 'fileName',
          'Use a database file name ending in .db.');
    }
    if (collection.trim().isEmpty || embeddingModelId.trim().isEmpty) {
      throw ArgumentError('Collection and embeddingModelId are required.');
    }
    if (databasePath != null &&
        (databasePath.isEmpty || !p.isAbsolute(databasePath))) {
      throw ArgumentError.value(databasePath, 'databasePath',
          'Provide an absolute SQLite path.');
    }

    final dbFactory = factory ?? databaseFactory;
    final location = databasePath ??
        p.join(await dbFactory.getDatabasesPath(), fileName);
    await Directory(p.dirname(location)).create(recursive: true);

    final store = RagSqliteVectorStore._(
      location, collection, embeddingModelId, dbFactory,
    );
    await store._initialize();
    return store;
  }

  Future<void> _initialize() async {
    final db = await _factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE $_collections ('
            'collection TEXT NOT NULL PRIMARY KEY, '
            'model_id TEXT NOT NULL, dimension INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE $_chunks ('
            'collection TEXT NOT NULL, chunk_id TEXT NOT NULL, '
            'document_id TEXT NOT NULL, title TEXT NOT NULL, '
            'source TEXT NOT NULL, body TEXT NOT NULL, '
            'metadata_json TEXT NOT NULL, embedding BLOB NOT NULL, '
            'PRIMARY KEY (collection, chunk_id))',
          );
          await db.execute(
            'CREATE INDEX rag_chunks_document '
            'ON $_chunks (collection, document_id)',
          );
        },
      ),
    );
    try {
      final rows = await db.query(
        _collections,
        where: 'collection = ?', whereArgs: <Object>[collection], limit: 1,
      );
      if (rows.isNotEmpty && rows.single['model_id'] != embeddingModelId) {
        throw StateError(
          'Embedding model mismatch in collection "$collection". '
          'Use the original embeddingModelId or a new collection.',
        );
      }
      _database = db;
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Database get _db {
    final db = _database;
    if (_closed || db == null) throw StateError('SQLite store is closed.');
    return db;
  }

  @override
  Future<void> upsert(List<RagVectorPoint> points) async {
    if (points.isEmpty) return;
    final dimension = _validate(points);
    await _db.transaction((txn) async {
      await _checkCollection(txn, dimension);
      await _insert(txn, points);
    });
  }

  /// Atomically replaces all chunks of one document.
  /// If any write fails, SQLite rolls back and preserves the old document.
  @override
  Future<void> replaceDocument(
    String documentId,
    List<RagVectorPoint> points,
  ) async {
    if (documentId.trim().isEmpty ||
        points.any((item) => item.chunk.documentId != documentId)) {
      throw ArgumentError('Invalid document ID or mismatched chunk owner.');
    }
    final dimension = points.isEmpty ? null : _validate(points);
    await _db.transaction((txn) async {
      if (dimension != null) await _checkCollection(txn, dimension);
      await txn.delete(_chunks,
        where: 'collection = ? AND document_id = ?',
        whereArgs: <Object>[collection, documentId]);
      await _insert(txn, points);
    });
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    if (documentId.trim().isEmpty) {
      throw ArgumentError.value(documentId, 'documentId');
    }
    await _db.delete(_chunks,
      where: 'collection = ? AND document_id = ?',
      whereArgs: <Object>[collection, documentId]);
  }

  /// Destructive: resets this collection and its embedding model metadata.
  Future<void> clearCollection() async {
    await _db.transaction((txn) async {
      await txn.delete(_chunks,
        where: 'collection = ?', whereArgs: <Object>[collection]);
      await txn.delete(_collections,
        where: 'collection = ?', whereArgs: <Object>[collection]);
    });
  }

  Future<int> countChunks() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_chunks WHERE collection = ?',
      <Object>[collection],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  @override
  Future<List<RagSearchHit>> search(
    List<double> queryVector, {
    required int topK,
    required double minScore,
  }) async {
    if (topK < 1 || !minScore.isFinite ||
        minScore < -1 || minScore > 1) {
      throw ArgumentError('Invalid topK or minScore.');
    }
    if (queryVector.isEmpty || queryVector.any((x) => !x.isFinite)) {
      throw ArgumentError('Invalid query embedding.');
    }
    final db = _db;
    final meta = await db.query(_collections,
      where: 'collection = ?', whereArgs: <Object>[collection], limit: 1);
    if (meta.isEmpty) return <RagSearchHit>[];
    final dimension = meta.single['dimension'] as int;
    if (meta.single['model_id'] != embeddingModelId ||
        queryVector.length != dimension) {
      throw StateError('Embedding model or vector dimension mismatch.');
    }
    final queryNorm = _norm(queryVector);
    if (queryNorm == 0) return <RagSearchHit>[];

    const pageSize = 128;
    final results = <RagSearchHit>[];
    var offset = 0;
    while (true) {
      final rows = await db.query(_chunks,
        where: 'collection = ?',
        whereArgs: <Object>[collection],
        orderBy: 'chunk_id ASC', limit: pageSize, offset: offset);
      for (final row in rows) {
        final embedding = _decode(row['embedding'], dimension);
        final length = _norm(embedding);
        if (length == 0) continue;
        var dot = 0.0;
        for (var i = 0; i < dimension; i++) {
          dot += queryVector[i] * embedding[i];
        }
        final score = (dot / (queryNorm * length))
            .clamp(-1.0, 1.0).toDouble();
        if (score < minScore) continue;

        final decoded = jsonDecode(row['metadata_json'] as String);
        if (decoded is! Map) {
          throw const FormatException('Invalid stored metadata JSON.');
        }
        final metadata = <String, String>{};
        for (final entry in decoded.entries) {
          if (entry.key is! String || entry.value is! String) {
            throw const FormatException('Invalid stored metadata fields.');
          }
          metadata[entry.key as String] = entry.value as String;
        }
        results.add(RagSearchHit(
          chunk: RagChunk(
            id: row['chunk_id'] as String,
            documentId: row['document_id'] as String,
            title: row['title'] as String,
            source: row['source'] as String,
            text: row['body'] as String,
            metadata: metadata,
          ),
          score: score,
        ));
        results.sort((a, b) {
          final compare = b.score.compareTo(a.score);
          return compare == 0
              ? a.chunk.id.compareTo(b.chunk.id) : compare;
        });
        if (results.length > topK) results.removeLast();
      }
      if (rows.length < pageSize) break;
      offset += rows.length;
    }
    return List<RagSearchHit>.unmodifiable(results);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final db = _database;
    _database = null;
    if (db != null) await db.close();
  }

  Future<void> _checkCollection(Transaction txn, int dimension) async {
    final rows = await txn.query(_collections,
      where: 'collection = ?', whereArgs: <Object>[collection], limit: 1);
    if (rows.isEmpty) {
      await txn.insert(_collections, <String, Object>{
        'collection': collection,
        'model_id': embeddingModelId,
        'dimension': dimension,
      });
    } else if (rows.single['model_id'] != embeddingModelId ||
               rows.single['dimension'] != dimension) {
      throw StateError(
        'Collection has another embedding model or dimension. '
        'Use a new collection or intentionally clear/reindex.',
      );
    }
  }

  Future<void> _insert(
    Transaction txn, List<RagVectorPoint> points,
  ) async {
    if (points.isEmpty) return;
    final batch = txn.batch();
    for (final item in points) {
      batch.insert(_chunks, <String, Object>{
        'collection': collection,
        'chunk_id': item.chunk.id,
        'document_id': item.chunk.documentId,
        'title': item.chunk.title,
        'source': item.chunk.source,
        'body': item.chunk.text,
        'metadata_json': jsonEncode(item.chunk.metadata),
        'embedding': _encode(item.vector),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static int _validate(List<RagVectorPoint> points) {
    final dimension = points.first.vector.length;
    if (dimension == 0) throw ArgumentError('Empty embedding vectors.');
    for (final point in points) {
      if (point.chunk.id.trim().isEmpty ||
          point.chunk.documentId.trim().isEmpty ||
          point.chunk.text.trim().isEmpty ||
          point.vector.length != dimension ||
          point.vector.any((value) => !value.isFinite) ||
          _norm(point.vector) == 0) {
        throw ArgumentError('Invalid RAG chunk or embedding vector.');
      }
    }
    return dimension;
  }

  static Uint8List _encode(List<double> vector) {
    final data = ByteData(vector.length * 8);
    for (var i = 0; i < vector.length; i++) {
      data.setFloat64(i * 8, vector[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static List<double> _decode(Object? value, int dimension) {
    if (value is! List<int>) {
      throw const FormatException('Embedding is not stored as BLOB.');
    }
    final data = ByteData.sublistView(Uint8List.fromList(value));
    if (data.lengthInBytes != dimension * 8) {
      throw const FormatException('Stored embedding dimension is corrupt.');
    }
    return List<double>.generate(dimension,
      (i) => data.getFloat64(i * 8, Endian.little), growable: false);
  }

  static double _norm(List<double> vector) => math.sqrt(
    vector.fold<double>(0, (sum, value) => sum + value * value),
  );
}
