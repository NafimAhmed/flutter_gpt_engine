class LocalLlmMessage {
  LocalLlmMessage({
    required this.role,
    required this.text,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String role;
  String text;
  final DateTime createdAt;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  LocalLlmMessage copy() {
    return LocalLlmMessage(
      role: role,
      text: text,
      createdAt: createdAt,
    );
  }
}
