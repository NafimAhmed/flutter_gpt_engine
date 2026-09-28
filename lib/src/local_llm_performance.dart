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
    this.warmupRuns = 0,
    this.measuredRuns = 1,
    this.runTokensPerSecond = const <double>[],
  });

  final int threads;
  final int gpuLayers;

  /// Time from starting native generation until the first token callback.
  final Duration timeToFirstToken;

  /// Full benchmark duration including prompt evaluation and decoding.
  final Duration totalDuration;

  /// Time spent decoding after the first token arrived.
  final Duration decodeDuration;

  /// Median number of native token callbacks received from llama.cpp.
  final int generatedTokenCount;

  final int generatedCharacters;

  /// Median decode throughput after the first token.
  final double tokensPerSecond;

  /// Internal selection score used by LocalLlmClient.autoTune.
  final double score;

  /// Number of unmeasured warm-up runs performed before measurement.
  final int warmupRuns;

  /// Number of measured runs included in this median result.
  final int measuredRuns;

  /// Per-run decode throughput values, useful for diagnostics.
  final List<double> runTokensPerSecond;

  @override
  String toString() {
    return 'LocalLlmBenchmarkResult('
        'threads: $threads, '
        'gpuLayers: $gpuLayers, '
        'ttftMs: ${timeToFirstToken.inMilliseconds}, '
        'tokens: $generatedTokenCount, '
        'tokensPerSecond: ${tokensPerSecond.toStringAsFixed(2)}, '
        'runs: $measuredRuns, '
        'score: ${score.toStringAsFixed(2)})';
  }
}

/// Result returned after testing safe CPU/GPU configurations.
class LocalLlmAutoTuneResult {
  const LocalLlmAutoTuneResult({
    required this.selected,
    required this.candidates,
    required this.logicalProcessors,
    this.restoredFromPersistentProfile = false,
  });

  final LocalLlmBenchmarkResult selected;
  final List<LocalLlmBenchmarkResult> candidates;
  final int logicalProcessors;

  /// True only for diagnostics when a caller receives a result restored from
  /// persistent storage rather than newly benchmarked candidates.
  final bool restoredFromPersistentProfile;

  int get threads => selected.threads;
  int get gpuLayers => selected.gpuLayers;
}

/// Diagnostic comparison between CPU-only and GPU-offloaded inference.
class LocalLlmGpuVerificationResult {
  const LocalLlmGpuVerificationResult({
    required this.vulkanSupported,
    required this.recommendedGpuLayers,
    required this.cpu,
    required this.gpu,
  });

  final bool vulkanSupported;
  final int recommendedGpuLayers;
  final LocalLlmBenchmarkResult cpu;
  final LocalLlmBenchmarkResult? gpu;

  bool get gpuLoadSucceeded => gpu != null;

  double? get decodeSpeedup {
    final gpuResult = gpu;
    if (gpuResult == null || cpu.tokensPerSecond <= 0) return null;
    return gpuResult.tokensPerSecond / cpu.tokensPerSecond;
  }

  double? get scoreSpeedup {
    final gpuResult = gpu;
    if (gpuResult == null || cpu.score <= 0) return null;
    return gpuResult.score / cpu.score;
  }
}
