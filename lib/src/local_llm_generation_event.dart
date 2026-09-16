enum LocalLlmGenerationPhase {
  thinking,
  searchingWeb,
  answer,
  done,
}

class LocalLlmGenerationEvent {
  const LocalLlmGenerationEvent({
    required this.phase,
    required this.text,
    this.delta = '',
  });

  final LocalLlmGenerationPhase phase;

  /// Cumulative text for the current phase.
  final String text;

  /// Newly produced text since the previous event for this phase.
  final String delta;

  bool get isThinking => phase == LocalLlmGenerationPhase.thinking;
  bool get isSearchingWeb => phase == LocalLlmGenerationPhase.searchingWeb;
  bool get isAnswer => phase == LocalLlmGenerationPhase.answer;
  bool get isDone => phase == LocalLlmGenerationPhase.done;
}
