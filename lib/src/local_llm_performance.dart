/// Runtime performance data collected from the native GGUF backend.
class LocalLlmBenchmarkResult {
  const LocalLlmBenchmarkResult({
    required this.threads,
    required this.gpuLayers,
    required this.timeToFirstToken,
    required this.totalDuration,
    required this.decodeDuration,
    required this.generatedTokenCount,
    required this.generatedCharacters,
    required this.tokensPerSecond,
    required this.score,
  });

  final int threads;
  final int gpuLayers;

  /// Time from starting native generation until the first token callback.
  final Duration timeToFirstToken;

  /// Full benchmark duration including prompt evaluation and decoding.
  final Duration totalDuration;

  /// Time spent decoding after the first token arrived.
  final Duration decodeDuration;

  /// Number of native token callbacks received from llama.cpp.
  final int generatedTokenCount;

  final int generatedCharacters;

  /// Decode throughput after the first token. For a one-token response this
  /// falls back to total generation throughput.
  final double tokensPerSecond;

  /// Internal selection score used by LocalLlmClient.autoTune.
  ///
  /// Higher is better. It primarily rewards decode throughput while applying
  /// a small penalty to slow time-to-first-token.
  final double score;

  @override
  String toString() {
    return 'LocalLlmBenchmarkResult('
        'threads: $threads, '
        'gpuLayers: $gpuLayers, '
        'ttftMs: ${timeToFirstToken.inMilliseconds}, '
        'tokens: $generatedTokenCount, '
        'tokensPerSecond: ${tokensPerSecond.toStringAsFixed(2)}, '
        'score: ${score.toStringAsFixed(2)})';
  }
}

/// Result returned after testing safe CPU/GPU configurations.
class LocalLlmAutoTuneResult {
  const LocalLlmAutoTuneResult({
    required this.selected,
    required this.candidates,
    required this.logicalProcessors,
  });

  final LocalLlmBenchmarkResult selected;
  final List<LocalLlmBenchmarkResult> candidates;
  final int logicalProcessors;

  int get threads => selected.threads;
  int get gpuLayers => selected.gpuLayers;
}
