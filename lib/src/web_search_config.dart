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
