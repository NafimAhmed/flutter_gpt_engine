import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';
import 'package:flutter_gpt_engine/src/think_parser.dart';

void main() {
  test('LocalLlmConfig default values are correct', () {
    const config = LocalLlmConfig();

    expect(config.threads, 4);
    expect(config.contextSize, 4096);
    expect(config.maxTokens, 384);
    expect(config.maxHistoryCharacters, 12000);
    expect(config.temperature, 0.60);
  });

  test('LocalLlmBenchmarkResult stores performance metrics', () {
    const result = LocalLlmBenchmarkResult(
      threads: 4,
      gpuLayers: 16,
      timeToFirstToken: Duration(milliseconds: 250),
      totalDuration: Duration(seconds: 2),
      decodeDuration: Duration(milliseconds: 1750),
      generatedTokenCount: 32,
      generatedCharacters: 120,
      tokensPerSecond: 17.7,
      score: 15.1,
    );

    expect(result.threads, 4);
    expect(result.gpuLayers, 16);
    expect(result.generatedTokenCount, 32);
    expect(result.tokensPerSecond, 17.7);
  });

  test('LocalLlmConfig supports adaptive threads and history budget', () {
    const config = LocalLlmConfig(
      threads: 0,
      maxHistoryCharacters: 6000,
    );

    expect(config.threads, 0);
    expect(config.maxHistoryCharacters, 6000);
  });

  group('LocalLlmThinkParser', () {
    test('parses split think tags incrementally', () {
      final parser = LocalLlmThinkParser();

      parser.add('<thi');
      var delta = parser.takeDelta();
      expect(delta.isEmpty, isTrue);
      expect(delta.isThinking, isFalse);

      parser.add('nk>reasoning');
      delta = parser.takeDelta();
      expect(delta.thinkingDelta, 'reasoning');
      expect(delta.answerDelta, isEmpty);
      expect(delta.isThinking, isTrue);

      parser.add('</th');
      delta = parser.takeDelta();
      expect(delta.isEmpty, isTrue);

      parser.add('ink>final answer');
      delta = parser.takeDelta();
      expect(delta.thinkingDelta, isEmpty);
      expect(delta.answerDelta, 'final answer');
      expect(delta.isThinking, isFalse);

      final snapshot = parser.snapshot();
      expect(snapshot.thinking, 'reasoning');
      expect(snapshot.answer, 'final answer');
      expect(snapshot.isThinking, isFalse);
    });

    test('parses analysis tags case-insensitively', () {
      final parser = LocalLlmThinkParser();

      parser.add('<ANALYSIS>hidden</ANALYSIS>visible');
      final delta = parser.takeDelta();
      final snapshot = parser.snapshot();

      expect(delta.thinkingDelta, 'hidden');
      expect(delta.answerDelta, 'visible');
      expect(snapshot.thinking, 'hidden');
      expect(snapshot.answer, 'visible');
      expect(snapshot.isThinking, isFalse);
    });

    test('passes normal text through without reparsing history', () {
      final parser = LocalLlmThinkParser();

      parser.add('Hello ');
      expect(parser.takeDelta().answerDelta, 'Hello ');

      parser.add('world');
      expect(parser.takeDelta().answerDelta, 'world');

      expect(parser.snapshot().answer, 'Hello world');
    });
  });
}
