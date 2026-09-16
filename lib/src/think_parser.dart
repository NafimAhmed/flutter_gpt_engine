class ThinkParseSnapshot {
  const ThinkParseSnapshot({
    required this.thinking,
    required this.answer,
    required this.isThinking,
  });

  final String thinking;
  final String answer;
  final bool isThinking;
}

/// Incremental parser for common local-model reasoning tags.
///
/// It accepts arbitrary token/chunk boundaries, including tags split across
/// multiple chunks. The caller receives cumulative thinking and final-answer
/// text without exposing the raw XML-like tags.
class LocalLlmThinkParser {
  final StringBuffer _raw = StringBuffer();

  static const _tags = <String>[
    '<think>',
    '</think>',
    '<analysis>',
    '</analysis>',
  ];

  void add(String chunk) {
    _raw.write(chunk);
  }

  String get rawText => _raw.toString();

  ThinkParseSnapshot snapshot() {
    final raw = _raw.toString();
    final lower = raw.toLowerCase();

    final thinkOpen = lower.lastIndexOf('<think>');
    final analysisOpen = lower.lastIndexOf('<analysis>');
    final thinkClose = lower.lastIndexOf('</think>');
    final analysisClose = lower.lastIndexOf('</analysis>');

    final lastOpen = thinkOpen > analysisOpen ? thinkOpen : analysisOpen;
    final lastClose = thinkClose > analysisClose ? thinkClose : analysisClose;
    final isThinking = lastOpen >= 0 && lastOpen > lastClose;

    String thinking = '';
    String answerSource = raw;

    if (isThinking) {
      final openTag =
          lastOpen == thinkOpen ? '<think>' : '<analysis>';
      final contentStart = lastOpen + openTag.length;
      thinking = raw.substring(contentStart);
      answerSource = raw.substring(0, lastOpen);
    }

    var answer = answerSource
        .replaceAll(
          RegExp(
            r'<think>[\s\S]*?</think>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'<analysis>[\s\S]*?</analysis>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'</?(?:think|analysis)>',
            caseSensitive: false,
          ),
          '',
        );

    thinking = thinking.replaceAll(
      RegExp(
        r'</?(?:think|analysis)>',
        caseSensitive: false,
      ),
      '',
    );

    // Do not leak a tag while the native token stream is still spelling it.
    answer = _removePossibleTagPrefixAtEnd(answer);
    thinking = _removePossibleTagPrefixAtEnd(thinking);

    return ThinkParseSnapshot(
      thinking: thinking,
      answer: answer,
      isThinking: isThinking,
    );
  }

  static String _removePossibleTagPrefixAtEnd(String value) {
    var result = value;

    for (final tag in _tags) {
      for (var length = 1; length < tag.length; length++) {
        final prefix = tag.substring(0, length);
        if (result.toLowerCase().endsWith(prefix.toLowerCase())) {
          result = result.substring(0, result.length - prefix.length);
          break;
        }
      }
    }

    return result;
  }
}
