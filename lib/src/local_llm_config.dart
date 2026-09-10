class LocalLlmConfig {
  const LocalLlmConfig({
    this.systemPrompt = 'You are a helpful offline AI assistant.',
    this.threads = 4,
    this.contextSize = 4096,
    this.gpuLayers,
    this.temperature = 0.60,
    this.topP = 0.90,
    this.topK = 40,
    this.repeatPenalty = 1.15,
    this.maxTokens = 384,
    this.maxHistoryMessages = 8,
  });

  final String systemPrompt;
  final int threads;
  final int contextSize;

  /// null = auto-detect GPU layers.
  /// 0 = CPU only.
  /// > 0 = request this many GPU layers, with CPU fallback if loading fails.
  final int? gpuLayers;

  final double temperature;
  final double topP;
  final int topK;
  final double repeatPenalty;
  final int maxTokens;

  /// Number of previous user/assistant messages added to each generation.
  final int maxHistoryMessages;

  LocalLlmConfig copyWith({
    String? systemPrompt,
    int? threads,
    int? contextSize,
    int? gpuLayers,
    bool clearGpuLayers = false,
    double? temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    int? maxTokens,
    int? maxHistoryMessages,
  }) {
    return LocalLlmConfig(
      systemPrompt: systemPrompt ?? this.systemPrompt,
      threads: threads ?? this.threads,
      contextSize: contextSize ?? this.contextSize,
      gpuLayers: clearGpuLayers ? null : (gpuLayers ?? this.gpuLayers),
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      maxTokens: maxTokens ?? this.maxTokens,
      maxHistoryMessages: maxHistoryMessages ?? this.maxHistoryMessages,
    );
  }
}
