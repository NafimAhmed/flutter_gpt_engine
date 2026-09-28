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

  test('default config preserves pre-phase-1 generation behaviour', () {
    const config = LocalLlmConfig();

    expect(config.maxHistoryTokens, 0);
    expect(config.tokenAwareContextManagement, isFalse);
    expect(config.contextSize, 4096);
    expect(config.maxTokens, 384);
    expect(config.persistAutoTuneProfile, isTrue);
  });

  test('performance presets provide opt-in mobile tuning', () {
    final fast = LocalLlmConfig.preset(LocalLlmPerformanceMode.fast);
    final balanced = LocalLlmConfig.preset(LocalLlmPerformanceMode.balanced);
    final quality = LocalLlmConfig.preset(LocalLlmPerformanceMode.quality);

    expect(fast.contextSize, 2048);
    expect(fast.maxTokens, 256);
    expect(fast.tokenAwareContextManagement, isTrue);

    expect(balanced.contextSize, 4096);
    expect(balanced.maxHistoryTokens, 2200);

    expect(quality.contextSize, 8192);
    expect(quality.maxTokens, 512);
  });

  test('benchmark diagnostics remain backwards compatible', () {
    const result = LocalLlmBenchmarkResult(
      threads: 4,
      gpuLayers: 0,
      timeToFirstToken: Duration(milliseconds: 100),
      totalDuration: Duration(seconds: 1),
      decodeDuration: Duration(milliseconds: 900),
      generatedTokenCount: 20,
      generatedCharacters: 80,
      tokensPerSecond: 21.1,
      score: 20.0,
      warmupRuns: 1,
      measuredRuns: 3,
      runTokensPerSecond: <double>[20.0, 21.1, 22.0],
    );

    expect(result.warmupRuns, 1);
    expect(result.measuredRuns, 3);
    expect(result.runTokensPerSecond.length, 3);
  });

  test('GPU verification result exposes measured speedup', () {
    const cpu = LocalLlmBenchmarkResult(
      threads: 4,
      gpuLayers: 0,
      timeToFirstToken: Duration(milliseconds: 200),
      totalDuration: Duration(seconds: 2),
      decodeDuration: Duration(milliseconds: 1800),
      generatedTokenCount: 32,
      generatedCharacters: 120,
      tokensPerSecond: 10,
      score: 9,
    );
    const gpu = LocalLlmBenchmarkResult(
      threads: 4,
      gpuLayers: 16,
      timeToFirstToken: Duration(milliseconds: 150),
      totalDuration: Duration(seconds: 1),
      decodeDuration: Duration(milliseconds: 850),
      generatedTokenCount: 32,
      generatedCharacters: 120,
      tokensPerSecond: 20,
      score: 18,
    );
    const result = LocalLlmGpuVerificationResult(
      vulkanSupported: true,
      recommendedGpuLayers: 16,
      cpu: cpu,
      gpu: gpu,
    );

    expect(result.gpuLoadSucceeded, isTrue);
    expect(result.decodeSpeedup, 2.0);
    expect(result.scoreSpeedup, 2.0);
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
