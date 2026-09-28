enum LocalLlmPerformanceMode {
  fast,
  balanced,
  quality,
}

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
    this.maxHistoryTokens = 0,
    this.tokenAwareContextManagement = false,
    this.persistAutoTuneProfile = true,
    this.benchmarkWarmupRuns = 1,
    this.benchmarkRuns = 3,
    this.showThinking = false,
    this.performanceMode,
  });

  /// Creates a ready-made mobile performance profile.
  ///
  /// Existing callers do not need to use this API. The default constructor
  /// keeps the package's existing behaviour unchanged.
  factory LocalLlmConfig.preset(LocalLlmPerformanceMode mode) {
    switch (mode) {
      case LocalLlmPerformanceMode.fast:
        return const LocalLlmConfig(
          threads: 0,
          contextSize: 2048,
          maxTokens: 256,
          maxHistoryMessages: 6,
          maxHistoryCharacters: 6000,
          maxHistoryTokens: 900,
          tokenAwareContextManagement: true,
          performanceMode: LocalLlmPerformanceMode.fast,
        );
      case LocalLlmPerformanceMode.balanced:
        return const LocalLlmConfig(
          threads: 0,
          contextSize: 4096,
          maxTokens: 384,
          maxHistoryMessages: 8,
          maxHistoryCharacters: 12000,
          maxHistoryTokens: 2200,
          tokenAwareContextManagement: true,
          performanceMode: LocalLlmPerformanceMode.balanced,
        );
      case LocalLlmPerformanceMode.quality:
        return const LocalLlmConfig(
          threads: 0,
          contextSize: 8192,
          maxTokens: 512,
          maxHistoryMessages: 12,
          maxHistoryCharacters: 24000,
          maxHistoryTokens: 5200,
          tokenAwareContextManagement: true,
          performanceMode: LocalLlmPerformanceMode.quality,
        );
    }
  }

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
  /// This guard remains available for complete backward compatibility.
  final int maxHistoryCharacters;

  /// Optional estimated-token budget for recent conversation history.
  ///
  /// A value <= 0 disables token-based trimming. Presets enable this using the
  /// same ContextHelper estimator exposed by llama_flutter_android.
  final int maxHistoryTokens;

  /// When true, generation estimates prompt usage and reduces maxTokens when
  /// needed to stay inside the native backend's safe context window.
  final bool tokenAwareContextManagement;

  /// Persist successful autoTune profiles in Application Support and restore
  /// them automatically for the same GGUF file on later app launches.
  final bool persistAutoTuneProfile;

  /// Number of unmeasured warm-up runs for benchmark/autoTune candidates.
  final int benchmarkWarmupRuns;

  /// Number of measured benchmark runs. Median values are returned.
  final int benchmarkRuns;

  /// When true, model output inside `<think>...</think>` or
  /// `<analysis>...</analysis>` is exposed through LocalLlmClient.thinkingText
  /// and LocalLlmClient.generationEvents while it is being generated.
  ///
  /// Thinking is never stored in chat history. As soon as final-answer output
  /// starts, thinkingText is cleared so host UIs can automatically replace the
  /// thinking panel with the final answer.
  final bool showThinking;

  /// Non-null when this config was created from [LocalLlmConfig.preset].
  final LocalLlmPerformanceMode? performanceMode;

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
    int? maxHistoryTokens,
    bool? tokenAwareContextManagement,
    bool? persistAutoTuneProfile,
    int? benchmarkWarmupRuns,
    int? benchmarkRuns,
    bool? showThinking,
    LocalLlmPerformanceMode? performanceMode,
    bool clearPerformanceMode = false,
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
      maxHistoryTokens: maxHistoryTokens ?? this.maxHistoryTokens,
      tokenAwareContextManagement:
          tokenAwareContextManagement ?? this.tokenAwareContextManagement,
      persistAutoTuneProfile:
          persistAutoTuneProfile ?? this.persistAutoTuneProfile,
      benchmarkWarmupRuns: benchmarkWarmupRuns ?? this.benchmarkWarmupRuns,
      benchmarkRuns: benchmarkRuns ?? this.benchmarkRuns,
      showThinking: showThinking ?? this.showThinking,
      performanceMode: clearPerformanceMode
          ? null
          : (performanceMode ?? this.performanceMode),
    );
  }
}
