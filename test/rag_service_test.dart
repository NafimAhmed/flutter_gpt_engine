import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';

void main() {
  group('RAG in-memory service', () {
    late RagInMemoryVectorStore store;
    late RagService rag;

    setUp(() {
      store = RagInMemoryVectorStore();
      rag = RagService(
        embeddingProvider: const RagKeywordHashEmbeddingProvider(),
        vectorStore: store,
        config: const RagConfig(chunkSize: 100, chunkOverlap: 20),
      );
    });

    test('indexes and retrieves a relevant source', () async {
      final n = await rag.addDocument(const RagDocument(
        id: 'flutter',
        title: 'Flutter notes',
        source: 'https://docs.flutter.dev/',
        text: 'Flutter builds mobile applications with Dart. '
            'It renders UI widgets on Android and iOS.',
      ));
      expect(n, 1);
      final found = await rag.retrieve('Flutter Dart mobile widgets');
      expect(found.hits, isNotEmpty);
      expect(found.hits.first.chunk.documentId, 'flutter');
      expect(found.hits.first.chunk.source, 'https://docs.flutter.dev/');
      expect(found.toPromptContext(), contains('[1]'));
      expect(found.toPromptContext(), contains('Dart'));
    });

    test('works with Bangla text and Unicode rune chunking', () async {
      const document = RagDocument(
        id: 'bn',
        text: 'বাংলাদেশে নদী আছে। বাংলাদেশ একটি দেশ। ' 
            'নদী সম্পর্কে কিছু আলোচনা।',
      );
      final chunks = rag.splitDocument(document);
      expect(chunks, isNotEmpty);
      final n = await rag.addDocument(document);
      expect(n, greaterThan(0));
      final found = await rag.retrieve('বাংলাদেশ নদী');
      expect(found.hits, isNotEmpty);
    });

    test('removes previously indexed chunks when replacing a document',
        () async {
      const large = 'Flutter Dart mobile widgets render pages and layouts. ';
      await rag.addDocument(const RagDocument(
        id: 'same', text: large + large + large + large,
      ));
      final countBefore = store.length;
      await rag.addDocument(const RagDocument(
        id: 'same', text: 'Flutter Dart mobile widgets.',
      ));
      expect(store.length, lessThan(countBefore));
      await rag.removeDocument('same');
      expect(store.length, 0);
    });

    test('refuses malformed document metadata and empty text', () async {
      expect(
        rag.addDocument(const RagDocument(id: '', text: 'Hello')),
        throwsArgumentError,
      );
      expect(
        rag.addDocument(const RagDocument(id: 'x', text: '')),
        throwsArgumentError,
      );
    });

    test('fails closed on empty or unrelated indexed documents', () async {
      final empty = await rag.retrieve('database vector');
      expect(empty.hits, isEmpty);
      expect(empty.toPromptContext(), isEmpty);

      await rag.addDocument(const RagDocument(
        id: 'x',
        text: 'Cats, dogs, and domestic animals.',
      ));
      final unrelated = await rag.retrieve(
        'quantum photon',
        minScore: 0.99,
      );
      expect(unrelated.hits, isEmpty);
    });

    test('rejects inconsistent vector dimensions and NaN', () async {
      const chunk = RagChunk(
        id: 'test:1', documentId: 'test',
        text: 'hello', title: 'Example', source: '',
      );
      await store.upsert(const <RagVectorPoint>[
        RagVectorPoint(chunk: chunk, vector: <double>[1, 0]),
      ]);
      expect(
        store.search(const <double>[1, 0, 0], topK: 3, minScore: 0),
        throwsArgumentError,
      );
      expect(
        store.upsert(<RagVectorPoint>[
          RagVectorPoint(chunk: chunk, vector: <double>[double.nan, 0]),
        ]),
        throwsArgumentError,
      );
    });

    test('supports callback embedding providers', () async {
      final callback = RagCallbackEmbeddingProvider(
        (text) async => text.contains('ERP')
            ? <double>[1, 0]
            : <double>[0, 1],
      );
      expect(await callback.embed('ERP'), <double>[1, 0]);
      expect(await callback.embed('Other'), <double>[0, 1]);
    });

    test('limits retrieved context without partial citation blocks',
        () async {
      const source = RagChunk(
        id: 'one', documentId: 'doc',
        text: 'Flutter documentation page one.',
        title: 'Documentation', source: 'source://one',
      );
      final result = RagRetrievalResult(
        query: 'Flutter',
        hits: const <RagSearchHit>[
          RagSearchHit(chunk: source, score: 0.90),
          RagSearchHit(chunk: source, score: 0.85),
        ],
      );
      final one = result.toPromptContext(maxCharacters: 130);
      expect(one, contains('[1]'));
      expect(one, isNot(contains('[2]')));
      expect(
        result.toPromptContext(maxCharacters: 10),
        isEmpty,
      );
    });

    test('cosine similarity sorts relevant results first', () async {
      const first = RagChunk(
        id: 'a', documentId: 'docA', text: 'A', title: 'A', source: '',
      );
      const second = RagChunk(
        id: 'b', documentId: 'docB', text: 'B', title: 'B', source: '',
      );
      await store.upsert(const <RagVectorPoint>[
        RagVectorPoint(chunk: first, vector: <double>[1, 0]),
        RagVectorPoint(chunk: second, vector: <double>[0.1, 0.9]),
      ]);
      final results = await store.search(
        const <double>[1, 0], topK: 1, minScore: 0,
      );
      expect(results.single.chunk.id, 'a');
    });
  });

  test('Qdrant adapter sends point vectors and reads scored payloads',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    final payloads = <Map<String, dynamic>>[];
    server.listen((request) async {
      requests.add(request.method + ' ' + request.uri.toString());
      final text = await utf8.decoder.bind(request).join();
      payloads.add(jsonDecode(text) as Map<String, dynamic>);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/points/query')) {
        request.response.write(jsonEncode({
          'status': 'ok',
          'result': {
            'points': <Object>[
              {
                'id': 12,
                'score': 0.91,
                'payload': {
                  'chunkId': 'doc:0',
                  'documentId': 'doc',
                  'title': 'Test document',
                  'source': 'test://source',
                  'text': 'Embedding search response',
                  'metadata': <String, String>{'kind': 'manual'},
                },
              },
            ],
          },
        }));
      } else {
        request.response.write('{"status":"ok","result":{}}');
      }
      await request.response.close();
    });
    final adapter = RagQdrantVectorStore(
      endpoint: Uri.parse('http://127.0.0.1:' + server.port.toString()),
      collection: 'my_docs',
    );

    try {
      const chunk = RagChunk(
        id: 'doc:0', documentId: 'doc', text: 'Hello Qdrant',
        title: 'Test document', source: 'test://source',
      );
      await adapter.upsert(const <RagVectorPoint>[
        RagVectorPoint(chunk: chunk, vector: <double>[0.6, 0.8]),
      ]);
      final results = await adapter.search(
        const <double>[0.6, 0.8], topK: 5, minScore: 0.1,
      );
      expect(results, hasLength(1));
      expect(results.first.chunk.source, 'test://source');
      expect(results.first.chunk.metadata['kind'], 'manual');
      await adapter.deleteDocument('doc');

      expect(requests, hasLength(3));
      expect(requests[0], contains('/collections/my_docs/points?wait=true'));
      expect(requests[1], contains('/collections/my_docs/points/query'));
      expect(requests[2], contains('/collections/my_docs/points/delete'));
      expect(payloads[0]['points'], isA<List>());
      expect(payloads[1]['with_payload'], isTrue);
      expect(payloads[2]['filter'], isA<Map>());
    } finally {
      adapter.dispose();
      await server.close(force: true);
    }
  });
}
