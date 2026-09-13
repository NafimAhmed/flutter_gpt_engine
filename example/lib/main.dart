import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ExamplePage(),
    );
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  late final LocalLlmClient gpt;

  final controller = TextEditingController();

  StreamSubscription<String>? generationSubscription;

  @override
  void initState() {
    super.initState();

    gpt = LocalLlmClient(
      config: const LocalLlmConfig(
        systemPrompt: 'You are a helpful AI assistant.',
      ),

      // Explicitly enabling web features
      webSearchConfig: const WebSearchConfig(
        enabled: true,

        // Wikipedia search
        useWikipedia: true,

        // Google fallback
        useGoogle: true,

        // User gives URL -> fetch website directly
        directUrlFetch: true,

        // Search results
        maxResults: 3,

        // Timeout
        timeout: Duration(seconds: 10),
      ),
    );

    gpt.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickModel() async {
    try {
      await gpt.pickModel();
    } catch (e) {
      debugPrint('MODEL ERROR: $e');
    }
  }

  Future<void> _send() async {
    final text = controller.text.trim();

    if (text.isEmpty ||
        !gpt.isLoaded ||
        gpt.isGenerating) {
      return;
    }

    controller.clear();

    await generationSubscription?.cancel();

    debugPrint('======================================');
    debugPrint('USER: $text');
    debugPrint('Starting smart generation...');
    debugPrint('======================================');

    generationSubscription = gpt
        .smartGenerate(
      text,

      // Automatically decides when web search is needed.
      searchMode: WebSearchMode.auto,
    )
        .listen(
          (token) {
        // No need to store token separately.
        // gpt.messages is already updated automatically.
      },
      onDone: () {
        final result = gpt.lastWebSearchResult;

        debugPrint('');
        debugPrint('========== WEB SEARCH DEBUG ==========');

        if (result == null) {
          debugPrint('WEB SEARCH: NOT USED');
        } else {
          debugPrint('QUERY: ${result.query}');
          debugPrint(
            'SOURCES: ${result.sources.length}',
          );

          for (int i = 0;
          i < result.sources.length;
          i++) {
            final source = result.sources[i];

            debugPrint('');
            debugPrint('SOURCE ${i + 1}');
            debugPrint('TITLE: ${source.title}');
            debugPrint('URL: ${source.url}');
          }
        }

        debugPrint('======================================');
      },
      onError: (error) {
        debugPrint('GENERATION ERROR: $error');
      },
    );
  }

  /// Force web search test
  Future<void> _testWebSearch() async {
    if (!gpt.isLoaded || gpt.isGenerating) {
      return;
    }

    await generationSubscription?.cancel();

    generationSubscription = gpt
        .smartGenerate(
      'What is the latest stable version of Flutter?',

      // Force internet search
      searchMode: WebSearchMode.always,
    )
        .listen(
          (token) {},
      onDone: () {
        final result = gpt.lastWebSearchResult;

        debugPrint('========= FORCE SEARCH =========');

        if (result == null) {
          debugPrint('No web result');
          return;
        }

        debugPrint('Query: ${result.query}');
        debugPrint(
          'Sources: ${result.sources.length}',
        );

        for (final source in result.sources) {
          debugPrint('TITLE: ${source.title}');
          debugPrint('URL: ${source.url}');
        }
      },
      onError: (error) {
        debugPrint('SEARCH ERROR: $error');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Flutter GPT Engine',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FilledButton(
              onPressed:
              gpt.isLoading ? null : _pickModel,
              child: const Text('Pick GGUF'),
            ),

            const SizedBox(height: 8),

            // Status
            Text(
              gpt.status,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            // Web search indicator
            if (gpt.isSearchingWeb)
              const Text(
                '🌐 Searching web...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),

            const SizedBox(height: 16),

            Expanded(
              child: ListView.builder(
                itemCount: gpt.messages.length,
                itemBuilder: (context, index) {
                  final message =
                  gpt.messages[index];

                  return Padding(
                    padding:
                    const EdgeInsets.only(
                      bottom: 10,
                    ),
                    child: Text(
                      '${message.role}: ${message.text}',
                      style: const TextStyle(
                        fontSize: 16,
                      ),
                    ),
                  );
                },
              ),
            ),

            TextField(
              controller: controller,
              enabled: !gpt.isGenerating,
              decoration: const InputDecoration(
                hintText:
                'Ask something...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _send(),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed:
                    gpt.isLoaded &&
                        !gpt.isGenerating
                        ? _send
                        : null,
                    child: const Text(
                      'Send',
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: OutlinedButton(
                    onPressed:
                    gpt.isLoaded &&
                        !gpt.isGenerating
                        ? _testWebSearch
                        : null,
                    child: const Text(
                      'Test Web',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    generationSubscription?.cancel();

    gpt.removeListener(_refresh);
    gpt.dispose();

    controller.dispose();

    super.dispose();
  }
}