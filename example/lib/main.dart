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

/// This UI belongs to the example app.
/// Flutter_GPT itself contains no UI widgets.
class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  late final LocalLlmClient gpt;

  final controller = TextEditingController();

  StreamSubscription<String>? generationSubscription;
  String streamingText = '';

  @override
  void initState() {
    super.initState();

    gpt = LocalLlmClient(
      config: const LocalLlmConfig(
        systemPrompt:
        'You are a helpful offline AI assistant.',
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
    await gpt.pickModel();
  }

  Future<void> _send() async {
    final text = controller.text.trim();

    if (text.isEmpty || !gpt.isLoaded || gpt.isGenerating) {
      return;
    }

    controller.clear();
    streamingText = '';
    setState(() {});

    await generationSubscription?.cancel();

    generationSubscription = gpt.generate(text).listen(
          (token) {
        streamingText += token;

        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host App UI'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FilledButton(
              onPressed: gpt.isLoading ? null : _pickModel,
              child: const Text('Pick GGUF'),
            ),
            const SizedBox(height: 8),
            Text(gpt.status),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  for (final message in gpt.messages)
                    Text('${message.role}: ${message.text}'),
                  if (streamingText.isNotEmpty)
                    Text('stream: $streamingText'),
                ],
              ),
            ),
            TextField(
              controller: controller,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed:
              gpt.isLoaded && !gpt.isGenerating ? _send : null,
              child: const Text('Send'),
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
