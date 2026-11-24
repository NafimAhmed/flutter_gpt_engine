import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late String databasePath;
  final openStores = <RagSqliteVectorStore>[];

  Future<RagSqliteVectorStore> openStore({
    String collection = 'erp',
    String embeddingModelId = 'keyword-hash-256-v1',
  }) async {
    final store = await RagSqliteVectorStore.open(
      databasePath: databasePath,
      collection: collection,
      embeddingModelId: embeddingModelId,
      factory: databaseFactoryFfi,
    );
    openStores.add(store);
    return store;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rag-sqlite-test-');
    databasePath = p.join(directory.path, 'rag_vectors.db');
    openStores.clear();
  });

  tearDown(() async {
    for (final store in openStores.reversed) {
      await store.close();
    }
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('persists document text and embeddings across closed/reopened store',
      () async {
    final store = await openStore();
    final rag = RagService(
      embeddingProvider: const RagKeywordHashEmbeddingProvider(),
      vectorStore: store,
    );
    expect(await rag.addDocument(const RagDocument(
      id: 'work-guide',
      title: 'ERP guide',
      source: 'file://erp-guide',
      text: 'Production batches are completed after inspection.',
      metadata: <String, String>{'department': 'production'},
    )), 1);
    expect(await store.countChunks(), 1);
    await store.close();

    final reopened = await openStore();
    final freshService = RagService(
      embeddingProvider: const RagKeywordHashEmbeddingProvider(),
      vectorStore: reopened,
    );
    final result = await freshService.retrieve('production batches inspection');
    expect(result.hits, hasLength(1));
    expect(result.hits.single.chunk.documentId, 'work-guide');
    expect(result.hits.single.chunk.title, 'ERP guide');
    expect(result.hits.single.chunk.source, 'file://erp-guide');
    expect(result.hits.single.chunk.metadata['department'], 'production');
    expect(result.hits.single.chunk.text, contains('inspection'));
  });

  test('replaces a document atomically and removes obsolete chunks', () async {
    final store = await openStore();
    final rag = RagService(
      embeddingProvider: const RagKeywordHashEmbeddingProvider(),
      vectorStore: store,
      config: const RagConfig(chunkSize: 100, chunkOverlap: 10),
    );
    final original = List<String>.filled(10, 'Flutter Dart ERP batch')
        .join(' ');
    final n = await rag.addDocument(RagDocument(
      id: 'guide', text: original,
    ));
    expect(n, greaterThan(1));
    await rag.addDocument(const RagDocument(
      id: 'guide', text: 'Flutter guide batch',
    ));
    expect(await store.countChunks(), 1);
    expect((await rag.retrieve('Flutter batch')).hits.single.chunk.text,
        'Flutter guide batch');

    await expectLater(
      store.replaceDocument('guide', const <RagVectorPoint>[
        RagVectorPoint(
          chunk: RagChunk(
            id: 'invalid',
            documentId: 'different-document',
            text: 'broken',
            title: '',
            source: '',
          ),
          vector: <double>[1, 0],
        ),
      ]),
      throwsArgumentError,
    );
    expect(await store.countChunks(), 1);
  });

  test('separate collections are isolated inside the same database', () async {
    final a = await openStore(collection: 'a');
    final b = await openStore(collection: 'b');
    // close/reopen is not needed for independent collections
    final ragA = RagService(
      embeddingProvider: const RagKeywordHashEmbeddingProvider(),
      vectorStore: a,
    );
    await ragA.addDocument(const RagDocument(
      id: 'one', text: 'Flutter smartphone application',
    ));
    expect(await a.countChunks(), 1);
    expect(await b.countChunks(), 0);
  });

  test('detects a different embedding model on reopen', () async {
    final store = await openStore();
    await RagService(
      embeddingProvider: const RagKeywordHashEmbeddingProvider(),
      vectorStore: store,
    ).addDocument(const RagDocument(
      id: 'x', text: 'Dart Flutter mobile guide',
    ));
    await store.close();
    await expectLater(
      openStore(embeddingModelId: 'new-embeddings-v2'),
      throwsStateError,
    );
  });

  test('rejects different vector dimensions and invalid vectors', () async {
    final store = await openStore();
    const chunk = RagChunk(
      id: 'doc:0',
      documentId: 'doc',
      text: 'A document chunk',
      title: '',
      source: '',
    );
    await store.upsert(const <RagVectorPoint>[
      RagVectorPoint(
        chunk: chunk,
        vector: <double>[0.6, 0.8],
      ),
    ]);
    expect(
      store.search(const <double>[1, 0, 0], topK: 2, minScore: 0),
      throwsStateError,
    );
    await expectLater(
      store.upsert(const <RagVectorPoint>[
        RagVectorPoint(chunk: chunk, vector: <double>[double.nan, 0]),
      ]),
      throwsArgumentError,
    );
    expect(await store.countChunks(), 1);
  });

  test('deletion is durable and clearCollection allows reindexing', () async {
    final store = await openStore();
    const chunk = RagChunk(
      id: 'doc:0', documentId: 'doc',
      text: 'Vector document', title: '', source: '',
    );
    await store.upsert(const <RagVectorPoint>[
      RagVectorPoint(chunk: chunk, vector: <double>[1, 0]),
    ]);
    await store.deleteDocument('doc');
    expect(await store.countChunks(), 0);
    await store.clearCollection();
    await store.upsert(const <RagVectorPoint>[
      RagVectorPoint(chunk: chunk, vector: <double>[1, 0, 0]),
    ]);
    expect(await store.countChunks(), 1);
    await store.close();

    final reopened = await openStore();
    expect(await reopened.countChunks(), 1);
    final hits = await reopened.search(
      const <double>[1, 0, 0], topK: 4, minScore: 0.5,
    );
    expect(hits, hasLength(1));
    expect(hits.single.score, closeTo(1, 0.00001));
  });

  test('offline search ranking returns top relevant local chunks', () async {
    final store = await openStore();
    const c1 = RagChunk(
      id: 'a:0', documentId: 'a', text: 'Flutter mobile',
      title: 'Mobile', source: 'local://a',
    );
    const c2 = RagChunk(
      id: 'b:0', documentId: 'b', text: 'Desktop database',
      title: 'Database', source: 'local://b',
    );
    await store.upsert(const <RagVectorPoint>[
      RagVectorPoint(chunk: c1, vector: <double>[1, 0]),
      RagVectorPoint(chunk: c2, vector: <double>[0, 1]),
    ]);
    final hits = await store.search(
      const <double>[1, 0], topK: 1, minScore: 0.1,
    );
    expect(hits, hasLength(1));
    expect(hits.single.chunk.documentId, 'a');
  });
}
