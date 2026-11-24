import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';

void main() {
  test('LocalLlmClient exposes optional RAG indexing and retrieval', () async {
    final store = RagInMemoryVectorStore();
    final service = RagService(
      embeddingProvider: const RagKeywordHashEmbeddingProvider(),
      vectorStore: store,
    );
    final client = LocalLlmClient(
      ragService: service,
      deviceContextConfig: const DeviceContextConfig(enabled: false),
    );
    try {
      final indexed = await client.indexRagDocument(
        const RagDocument(
          id: 'erp-guide',
          title: 'ERP Guide',
          source: 'local://erp',
          text: 'Flutter Dart ERP production batch quality inspection.',
        ),
      );
      expect(indexed, 1);

      final result = await client.searchRag('Flutter Dart ERP');
      expect(result.hits, isNotEmpty);
      expect(result.hits.first.chunk.documentId, 'erp-guide');
      expect(client.lastRagRetrievalResult, same(result));

      await client.removeRagDocument('erp-guide');
      expect(store.length, 0);
    } finally {
      client.dispose();
    }
  });

  test('without RAG configuration indexing fails explicitly', () {
    final client = LocalLlmClient(
      deviceContextConfig: const DeviceContextConfig(enabled: false),
    );
    try {
      expect(
        () => client.indexRagDocument(
          const RagDocument(id: 'x', text: 'Document'),
        ),
        throwsStateError,
      );
    } finally {
      client.dispose();
    }
  });
}
