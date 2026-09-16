enum WebSearchMode {
  auto,
  always,
  never,
}

class WebSearchConfig {
  const WebSearchConfig({
    this.enabled = true,
    this.useWikipedia = true,
    this.useGoogle = true,
    this.directUrlFetch = true,
    this.useOfficialSourceHints = true,
    this.fallbackOnLocalFailure = false,
    this.minLocalAnswerCharacters = 1,
    this.localFailurePhrases = const <String>[
      "i don't know",
      'i do not know',
      "i'm not sure",
      'i am not sure',
      'i cannot answer',
      "i can't answer",
      "i don't have enough information",
      'i do not have enough information',
      "i don't have information",
      "i don't have access",
      'i cannot verify',
      'unable to answer',
      'unable to determine',
      'insufficient information',
      'not enough information',
      'ami jani na',
      'ami sure na',
      'amar kache information nei',
      'amar kache information nai',
      'information pawa jacche na',
      'bolte parchi na',
      'nischit na',
      'আমি জানি না',
      'আমি নিশ্চিত নই',
      'আমি বলতে পারছি না',
      'আমার কাছে তথ্য নেই',
      'পর্যাপ্ত তথ্য নেই',
      'তথ্য পাওয়া যাচ্ছে না',
      'তথ্য পাওয়া যাচ্ছে না',
    ],
    this.maxResults = 3,
    this.maxPageCharacters = 5000,
    this.maxTotalContextCharacters = 9000,
    this.timeout = const Duration(seconds: 12),
    this.userAgent =
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36',
    this.trustedDomains = const <String>[
      'flutter.dev',
      'docs.flutter.dev',
      'dart.dev',
      'developer.android.com',
      'kotlinlang.org',
      'docs.oracle.com',
      'docs.python.org',
      'developer.mozilla.org',
      'pub.dev',
      'github.com',
      'wikipedia.org',
    ],
    this.officialSourceHints = const <String, List<String>>{
      'flutter': <String>[
        'https://docs.flutter.dev/release',
        'https://docs.flutter.dev/release/release-notes',
        'https://docs.flutter.dev/install/archive',
      ],
      'dart': <String>[
        'https://dart.dev/resources/breaking-changes',
        'https://dart.dev/get-dart/archive',
      ],
      'android': <String>[
        'https://developer.android.com/about/versions',
      ],
      'python': <String>[
        'https://www.python.org/downloads/',
      ],
    },
  });

  final bool enabled;
  final bool useWikipedia;
  final bool useGoogle;
  final bool directUrlFetch;
  final bool useOfficialSourceHints;

  /// If true, smartGenerate() first lets the local model try non-current
  /// questions. When that completed answer clearly says it cannot answer,
  /// the package discards the local candidate, searches the public web, and
  /// generates a new grounded answer.
  ///
  /// This is false by default to preserve the low-latency streaming behavior
  /// of existing apps. Enabling it buffers the local candidate until it has
  /// been validated.
  final bool fallbackOnLocalFailure;

  final int minLocalAnswerCharacters;
  final List<String> localFailurePhrases;

  final int maxResults;
  final int maxPageCharacters;
  final int maxTotalContextCharacters;
  final Duration timeout;
  final String userAgent;
  final List<String> trustedDomains;

  /// Optional direct official pages for common technologies/topics.
  ///
  /// These are tried before HTML search for current/technical questions. This
  /// makes queries such as "latest Flutter version" much more reliable while
  /// keeping the package API-key free.
  final Map<String, List<String>> officialSourceHints;

  WebSearchConfig copyWith({
    bool? enabled,
    bool? useWikipedia,
    bool? useGoogle,
    bool? directUrlFetch,
    bool? useOfficialSourceHints,
    bool? fallbackOnLocalFailure,
    int? minLocalAnswerCharacters,
    List<String>? localFailurePhrases,
    int? maxResults,
    int? maxPageCharacters,
    int? maxTotalContextCharacters,
    Duration? timeout,
    String? userAgent,
    List<String>? trustedDomains,
    Map<String, List<String>>? officialSourceHints,
  }) {
    return WebSearchConfig(
      enabled: enabled ?? this.enabled,
      useWikipedia: useWikipedia ?? this.useWikipedia,
      useGoogle: useGoogle ?? this.useGoogle,
      directUrlFetch: directUrlFetch ?? this.directUrlFetch,
      useOfficialSourceHints:
          useOfficialSourceHints ?? this.useOfficialSourceHints,
      fallbackOnLocalFailure:
          fallbackOnLocalFailure ?? this.fallbackOnLocalFailure,
      minLocalAnswerCharacters:
          minLocalAnswerCharacters ?? this.minLocalAnswerCharacters,
      localFailurePhrases: localFailurePhrases ?? this.localFailurePhrases,
      maxResults: maxResults ?? this.maxResults,
      maxPageCharacters: maxPageCharacters ?? this.maxPageCharacters,
      maxTotalContextCharacters:
          maxTotalContextCharacters ?? this.maxTotalContextCharacters,
      timeout: timeout ?? this.timeout,
      userAgent: userAgent ?? this.userAgent,
      trustedDomains: trustedDomains ?? this.trustedDomains,
      officialSourceHints: officialSourceHints ?? this.officialSourceHints,
    );
  }
}
