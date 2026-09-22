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

class ThinkParseDelta {
  const ThinkParseDelta({
    required this.thinkingDelta,
    required this.answerDelta,
    required this.isThinking,
  });

  final String thinkingDelta;
  final String answerDelta;
  final bool isThinking;

  bool get isEmpty => thinkingDelta.isEmpty && answerDelta.isEmpty;
}

/// Incremental parser for common local-model reasoning tags.
///
/// Only the newly received chunk plus a tiny possible split-tag suffix is
/// inspected. Full cumulative strings are materialized only when [snapshot]
/// is requested, which keeps the hot token loop allocation-light.
class LocalLlmThinkParser {
  final StringBuffer _raw = StringBuffer();
  final StringBuffer _thinking = StringBuffer();
  final StringBuffer _answer = StringBuffer();

  StringBuffer _thinkingDelta = StringBuffer();
  StringBuffer _answerDelta = StringBuffer();

  String _pending = '';
  bool _isThinking = false;

  static const List<String> _openTags = <String>[
    '<think>',
    '<analysis>',
  ];

  static const List<String> _closeTags = <String>[
    '</think>',
    '</analysis>',
  ];

  static const List<String> _allTags = <String>[
    ..._openTags,
    ..._closeTags,
  ];

  void add(String chunk) {
    if (chunk.isEmpty) return;

    _raw.write(chunk);
    _pending += chunk;
    _drainPending();
  }

  String get rawText => _raw.toString();
  bool get isThinking => _isThinking;

  /// Returns only text produced since the previous [takeDelta] call.
  ///
  /// This is the preferred API for the native token hot path.
  ThinkParseDelta takeDelta() {
    final result = ThinkParseDelta(
      thinkingDelta: _thinkingDelta.toString(),
      answerDelta: _answerDelta.toString(),
      isThinking: _isThinking,
    );

    _thinkingDelta = StringBuffer();
    _answerDelta = StringBuffer();
    return result;
  }

  /// Materializes the complete parsed result.
  ///
  /// Call this sparingly (for example at the end of generation) because it
  /// intentionally creates cumulative Strings.
  ThinkParseSnapshot snapshot() {
    return ThinkParseSnapshot(
      thinking: _thinking.toString(),
      answer: _answer.toString(),
      isThinking: _isThinking,
    );
  }

  void _drainPending() {
    while (_pending.isNotEmpty) {
      final lower = _pending.toLowerCase();
      final match = _findNextTag(lower);

      if (match != null) {
        if (match.index > 0) {
          _writeVisible(_pending.substring(0, match.index));
        }

        _isThinking = match.isOpening;
        _pending = _pending.substring(match.index + match.tag.length);
        continue;
      }

      // Keep only a suffix that may become a complete tag after the next
      // native chunk. Everything before it is safe to publish immediately.
      final retained = _partialTagSuffixLength(lower);
      final visibleLength = _pending.length - retained;

      if (visibleLength > 0) {
        _writeVisible(_pending.substring(0, visibleLength));
        _pending = _pending.substring(visibleLength);
      }

      break;
    }
  }

  _TagMatch? _findNextTag(String lower) {
    _TagMatch? best;

    for (final tag in _allTags) {
      final index = lower.indexOf(tag);
      if (index < 0) continue;

      final candidate = _TagMatch(
        index: index,
        tag: tag,
        isOpening: _openTags.contains(tag),
      );

      if (best == null || candidate.index < best.index) {
        best = candidate;
      }
    }

    return best;
  }

  int _partialTagSuffixLength(String lower) {
    final maxLength = _allTags
        .map((tag) => tag.length - 1)
        .reduce((a, b) => a > b ? a : b);

    final upperBound =
        lower.length < maxLength ? lower.length : maxLength;

    for (var length = upperBound; length > 0; length--) {
      final suffix = lower.substring(lower.length - length);

      for (final tag in _allTags) {
        if (tag.startsWith(suffix)) {
          return length;
        }
      }
    }

    return 0;
  }

  void _writeVisible(String value) {
    if (value.isEmpty) return;

    if (_isThinking) {
      _thinking.write(value);
      _thinkingDelta.write(value);
    } else {
      _answer.write(value);
      _answerDelta.write(value);
    }
  }
}

class _TagMatch {
  const _TagMatch({
    required this.index,
    required this.tag,
    required this.isOpening,
  });

  final int index;
  final String tag;
  final bool isOpening;
}
