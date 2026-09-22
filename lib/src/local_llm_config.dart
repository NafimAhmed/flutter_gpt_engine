class LocalLlmConfig {
  const LocalLlmConfig({
    this.systemPrompt = 'You are a helpful AI assistant.',
    this.threads = 4,
    this.contextSize = 4096,
    this.gpuLayers,
    this.temperature = 0.60,
    this.topP = 0.90,
    this.topK = 40,
    this.repeatPenalty = 1.15,
    this.maxTokens = 384,
    this.maxHistoryMessages = 8,
    this.maxHistoryCharacters = 12000,
    this.showThinking = false,
  });

  final String systemPrompt;

  /// CPU threads used by the native inference backend.
  ///
  /// Values greater than 0 are used directly. Set to 0 to choose a conservative
  /// device-aware value from the available logical processors. For best
  /// measured performance, call LocalLlmClient.autoTune after loading a model.
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

  /// Maximum combined character count kept from recent history.
  ///
  /// This is a lightweight context guard for mobile devices. It complements
  /// [maxHistoryMessages] and avoids repeatedly re-processing very large
  /// previous messages. Set to 0 to disable the character budget.
  final int maxHistoryCharacters;

  /// When true, model output inside `<think>...</think>` or
  /// `<analysis>...</analysis>` is exposed through LocalLlmClient.thinkingText
  /// and LocalLlmClient.generationEvents while it is being generated.
  ///
  /// Thinking is never stored in chat history. As soon as final-answer output
  /// starts, thinkingText is cleared so host UIs can automatically replace the
  /// thinking panel with the final answer.
  final bool showThinking;

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
    int? maxHistoryCharacters,
    bool? showThinking,
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
      maxHistoryCharacters:
          maxHistoryCharacters ?? this.maxHistoryCharacters,
      showThinking: showThinking ?? this.showThinking,
    );
  }
}
