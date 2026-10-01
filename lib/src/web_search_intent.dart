enum WebSearchIntentReason {
  explicitUrl,
  explicitSearch,
  freshness,
  liveData,
  currentRole,
  recommendation,
  nearby,
  evidenceRequest,
  externalLookup,
}

class WebSearchIntentDecision {
  const WebSearchIntentDecision({
    required this.shouldSearch,
    required this.score,
    required this.searchQuery,
    this.reasons = const <WebSearchIntentReason>[],
  });

  final bool shouldSearch;
  final int score;
  final String searchQuery;
  final List<WebSearchIntentReason> reasons;
}

/// Fast, deterministic search-intent detection for [WebSearchMode.auto].
///
/// The analyzer intentionally does not run another LLM call. This keeps smart
/// generation responsive while making the decision more contextual than a
/// simple "contains keyword" check.
class WebSearchIntentAnalyzer {
  const WebSearchIntentAnalyzer({
    this.threshold = 4,
    this.appendCurrentYearToDynamicQueries = true,
  });

  final int threshold;
  final bool appendCurrentYearToDynamicQueries;

  WebSearchIntentDecision analyze(String prompt) {
    final cleanPrompt = _normalizeWhitespace(prompt);

    if (cleanPrompt.isEmpty) {
      return const WebSearchIntentDecision(
        shouldSearch: false,
        score: 0,
        searchQuery: '',
      );
    }

    final lower = cleanPrompt.toLowerCase();
    var score = 0;
    final reasons = <WebSearchIntentReason>[];

    void add(WebSearchIntentReason reason, int points) {
      score += points;
      if (!reasons.contains(reason)) {
        reasons.add(reason);
      }
    }

    if (_urlPattern.hasMatch(cleanPrompt)) {
      add(WebSearchIntentReason.explicitUrl, 10);
    }

    if (_matchesAny(lower, _explicitSearchPatterns) ||
        _containsAny(lower, _banglaExplicitSearchPhrases)) {
      add(WebSearchIntentReason.explicitSearch, 8);
    }

    final hasFreshnessSignal =
        _matchesAny(lower, _freshnessPatterns) ||
        _containsAny(lower, _banglaFreshnessPhrases);

    if (hasFreshnessSignal) {
      add(WebSearchIntentReason.freshness, 5);
    }

    final hasLiveDataSignal =
        _matchesAny(lower, _liveDataPatterns) ||
        _containsAny(lower, _banglaLiveDataPhrases);

    if (hasLiveDataSignal) {
      add(WebSearchIntentReason.liveData, 5);
    }

    if (_matchesAny(lower, _currentRolePatterns) ||
        _containsAny(lower, _banglaCurrentRolePhrases)) {
      add(WebSearchIntentReason.currentRole, 6);
    }

    final hasNearbySignal =
        _matchesAny(lower, _nearbyPatterns) ||
        _containsAny(lower, _banglaNearbyPhrases);

    if (hasNearbySignal) {
      add(WebSearchIntentReason.nearby, 6);
    }

    final hasRecommendationLanguage =
        _matchesAny(lower, _recommendationPatterns) ||
        _containsAny(lower, _banglaRecommendationPhrases);

    final hasRecommendationContext =
        _matchesAny(lower, _marketOrDiscoveryContextPatterns) ||
        _containsAny(lower, _banglaMarketOrDiscoveryPhrases);

    if (hasRecommendationLanguage &&
        (hasRecommendationContext || hasNearbySignal)) {
      add(WebSearchIntentReason.recommendation, 5);
    }

    if (_matchesAny(lower, _evidenceRequestPatterns) ||
        _containsAny(lower, _banglaEvidenceRequestPhrases)) {
      add(WebSearchIntentReason.evidenceRequest, 5);
    }

    if (_matchesAny(lower, _externalLookupPatterns) ||
        _containsAny(lower, _banglaExternalLookupPhrases)) {
      add(WebSearchIntentReason.externalLookup, 5);
    }

    // A current-year phrase becomes useful when it appears together with a
    // discovery/recommendation signal, but the year alone is not enough to
    // force network access.
    final currentYear = DateTime.now().year.toString();
    if (lower.contains(currentYear) &&
        (hasRecommendationLanguage ||
            hasLiveDataSignal ||
            _matchesAny(lower, _currentRolePatterns))) {
      add(WebSearchIntentReason.freshness, 2);
    }

    final query = _buildSearchQuery(
      cleanPrompt,
      reasons: reasons,
    );

    return WebSearchIntentDecision(
      shouldSearch: score >= threshold,
      score: score,
      searchQuery: query,
      reasons: List<WebSearchIntentReason>.unmodifiable(reasons),
    );
  }

  String _buildSearchQuery(
    String prompt, {
    required List<WebSearchIntentReason> reasons,
  }) {
    var query = prompt
        .replaceAll(_urlPattern, ' ')
        .replaceAll(
          RegExp(
            r'^\s*(please\s+|can you\s+|could you\s+|would you\s+|'
            r'tell me\s+|show me\s+|find me\s+|look up\s+|lookup\s+|'
            r'search the web for\s+|search online for\s+|search for\s+|'
            r'google\s+)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(with|provide|give|include)\s+'
            r'(credible\s+|reliable\s+)?(sources?|references?|citations?)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'(দয়া করে|দয়া করে|আমাকে|একটু|সার্চ করে|সার্চ কর|'
            r'খুঁজে দেখ|খুঁজে দাও|বলো তো|বলো|বল তো|'
            r'amake|ektu|bolo to|bolo|bol to|search kore|search koro|'
            r'khuje dekho|khuje dao)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'(সোর্স|রেফারেন্স|সাইটেশন)\s*(দাও|সহ)?'),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(source|reference|citation|link)\s+'
            r'(dao|diben|please)\b',
            caseSensitive: false,
          ),
          ' ',
        );

    query = _normalizeWhitespace(query);

    if (query.isEmpty) {
      query = _normalizeWhitespace(prompt);
    }

    final dynamicQuery =
        reasons.contains(WebSearchIntentReason.currentRole) ||
        reasons.contains(WebSearchIntentReason.recommendation) ||
        reasons.contains(WebSearchIntentReason.liveData);

    if (appendCurrentYearToDynamicQueries && dynamicQuery) {
      final currentYear = DateTime.now().year.toString();
      final lower = query.toLowerCase();
      final alreadyTimeScoped =
          lower.contains(currentYear) ||
          _matchesAny(lower, _freshnessPatterns) ||
          _containsAny(lower, _banglaFreshnessPhrases);

      if (!alreadyTimeScoped) {
        query = '$query $currentYear';
      }
    }

    if (query.length > 220) {
      final shortened = query.substring(0, 220);
      final lastSpace = shortened.lastIndexOf(' ');
      query = (lastSpace > 160 ? shortened.substring(0, lastSpace) : shortened)
          .trim();
    }

    return query;
  }

  static bool _matchesAny(String value, List<RegExp> patterns) {
    for (final pattern in patterns) {
      if (pattern.hasMatch(value)) return true;
    }
    return false;
  }

  static bool _containsAny(String value, List<String> phrases) {
    for (final phrase in phrases) {
      if (value.contains(phrase)) return true;
    }
    return false;
  }

  static String _normalizeWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static final RegExp _urlPattern = RegExp(
    r'''https?://[^\s<>()\[\]{}"']+''',
    caseSensitive: false,
  );

  static final List<RegExp> _explicitSearchPatterns = <RegExp>[
    RegExp(
      r'\b(search|browse|check)\s+(the\s+)?(web|internet|online)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(look up|lookup|google)\s+.+',
      caseSensitive: false,
    ),
    RegExp(
      r'\bfind\s+.+\s+(online|on the web|on google)\b',
      caseSensitive: false,
    ),
  ];

  static const List<String> _banglaExplicitSearchPhrases = <String>[
    'search kore',
    'search koro',
    'google kore',
    'online e khuj',
    'internet e khuj',
    'khuje dekho',
    'khuje dao',
    'সার্চ করে',
    'সার্চ কর',
    'গুগলে খুঁজ',
    'গুগল করে',
    'অনলাইনে খুঁজ',
    'ওয়েবে খুঁজ',
    'ওয়েবে খুঁজ',
    'ইন্টারনেটে খুঁজ',
    'খুঁজে দেখ',
  ];

  static final List<RegExp> _freshnessPatterns = <RegExp>[
    RegExp(
      r'\b(latest|newest|recent|recently|today|tonight|currently|'
      r'right now|up-to-date|up to date|as of|this week|this month|'
      r'this year)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bcurrent\s+(version|release|price|status|score|schedule|weather|'
      r'ceo|cto|cfo|president|prime minister|mayor|chairman|coach|captain|'
      r'availability|exchange rate|stock price|stable)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(latest|current|stable)\s+.+\s+(version|release)\b',
      caseSensitive: false,
    ),
  ];

  static const List<String> _banglaFreshnessPhrases = <String>[
    'ajker',
    'ajke',
    'bortoman',
    'sorbosesh',
    'shorbosesh',
    'latest ta',
    'আজকের',
    'আজকে',
    'এখনকার',
    'এই মুহূর্তে',
    'বর্তমান দাম',
    'বর্তমান মূল্য',
    'বর্তমান ভার্সন',
    'বর্তমান সংস্করণ',
    'বর্তমান অবস্থা',
    'সর্বশেষ',
    'লেটেস্ট',
    'সাম্প্রতিক',
    'নতুন আপডেট',
  ];

  static final List<RegExp> _liveDataPatterns = <RegExp>[
    RegExp(
      r'\b(weather|forecast)\s+(in|at|for)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(price|cost)\s+(of|for)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(stock price|stock quote|share price|exchange rate|currency rate|'
      r'live score|match score|flight status|traffic|opening hours|'
      r'election results?|polling|polls|news about|news on)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(schedule|fixtures?)\s+(for|of)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bis\s+.+\s+(open|available|in stock)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bavailable\s+(now|today|near me|in)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(flutter|dart|android|python|java|kotlin|ios|sdk|package)\b'
      r'.{0,40}\bversion\s+(koto|ki)\b',
      caseSensitive: false,
    ),
  ];

  static const List<String> _banglaLiveDataPhrases = <String>[
    'dam koto',
    'price koto',
    'weather kemon',
    'score koto',
    'available ase',
    'stock e ase',
    'kobe release',
    'দাম কত',
    'মূল্য কত',
    'আবহাওয়া',
    'আবহাওয়া',
    'স্কোর কত',
    'লাইভ স্কোর',
    'সময়সূচি',
    'সময়সূচি',
    'ফ্লাইট স্ট্যাটাস',
    'এক্সচেঞ্জ রেট',
    'শেয়ার দাম',
    'শেয়ার দাম',
    'খোলা আছে',
    'স্টকে আছে',
    'খবর',
  ];

  static final List<RegExp> _currentRolePatterns = <RegExp>[
    RegExp(
      r'\bwho is\s+(the\s+)?(president|prime minister|ceo|cto|cfo|mayor|'
      r'chairman|chairperson|coach|captain|governor)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(president|prime minister|ceo|cto|cfo|chairman|coach|captain)\s+ke\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(name|tell me)\s+(the\s+)?(current\s+)?'
      r'(president|prime minister|ceo|mayor|chairman|coach|captain)\b',
      caseSensitive: false,
    ),
  ];

  static const List<String> _banglaCurrentRolePhrases = <String>[
    'প্রেসিডেন্ট কে',
    'রাষ্ট্রপতি কে',
    'প্রধানমন্ত্রী কে',
    'সিইও কে',
    'চেয়ারম্যান কে',
    'চেয়ারম্যান কে',
    'ক্যাপ্টেন কে',
    'কোচ কে',
  ];

  static final List<RegExp> _nearbyPatterns = <RegExp>[
    RegExp(
      r'\b(near me|nearby|closest|around me|in my area)\b',
      caseSensitive: false,
    ),
  ];

  static const List<String> _banglaNearbyPhrases = <String>[
    'amar kache',
    'amar ashepashe',
    'ashepashe',
    'amar area te',
    'kacher',
    'আমার কাছে',
    'কাছাকাছি',
    'আমার আশেপাশে',
    'আমার এলাকায়',
    'আমার এলাকায়',
    'নিকটবর্তী',
  ];

  static final List<RegExp> _recommendationPatterns = <RegExp>[
    RegExp(
      r'\b(best|top|recommend|recommendation|suggest|suggestion|'
      r'which should i buy|what should i buy|worth buying|better choice)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bcompare\s+.+\s+(vs|versus|with)\s+.+',
      caseSensitive: false,
    ),
    RegExp(
      r'\b.+\s+(vs|versus)\s+.+',
      caseSensitive: false,
    ),
  ];

  static const List<String> _banglaRecommendationPhrases = <String>[
    'konta valo',
    'konta bhalo',
    'kon ta valo',
    'kon ta bhalo',
    'konti valo',
    'konti bhalo',
    'best konta',
    'kinbo',
    'kena valo',
    'kena bhalo',
    'recommend koro',
    'suggest koro',
    'compare koro',
    'কোনটা ভালো',
    'কোনটা ভাল',
    'কোনটি ভালো',
    'কোনটি ভাল',
    'বেস্ট কোনটা',
    'সেরা কোনটা',
    'কিনব',
    'কেনা ভালো',
    'কেনা ভাল',
    'রেকমেন্ড',
    'সাজেস্ট',
    'তুলনা কর',
  ];

  static final List<RegExp> _marketOrDiscoveryContextPatterns = <RegExp>[
    RegExp(
      r'\b(phone|smartphone|laptop|tablet|printer|watch|smartwatch|camera|'
      r'router|headphones?|earbuds?|monitor|tv|television|car|bike|bicycle|'
      r'bank|credit card|isp|internet provider|restaurant|cafe|hotel|resort|'
      r'flight|airline|hospital|clinic|doctor|university|school|gym|job|'
      r'app|software|package|library|framework|plugin|course|hosting|cloud|'
      r'vpn|keyboard|mouse|ssd|gpu|cpu)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(budget|under|below|within)\s+[\$৳€£]?\s*[\d,]+',
      caseSensitive: false,
    ),
    RegExp(
      r'[\$৳€£]\s*[\d,]+',
      caseSensitive: false,
    ),
  ];

  static const List<String> _banglaMarketOrDiscoveryPhrases = <String>[
    'takar moddhe',
    'damer moddhe',
    'বাজেট',
    'টাকার মধ্যে',
    'দামের মধ্যে',
    'ফোন',
    'ল্যাপটপ',
    'প্রিন্টার',
    'ঘড়ি',
    'ঘড়ি',
    'রাউটার',
    'ব্যাংক',
    'রেস্টুরেন্ট',
    'হোটেল',
    'প্যাকেজ',
    'লাইব্রেরি',
    'প্লাগইন',
    'আইএসপি',
  ];

  static final List<RegExp> _evidenceRequestPatterns = <RegExp>[
    RegExp(
      r'\b(with|provide|give|include|need)\s+'
      r'(credible\s+|reliable\s+)?(sources?|references?|citations?)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(source|reference|citation)\s+(link|links|please)\b',
      caseSensitive: false,
    ),
  ];

  static const List<String> _banglaEvidenceRequestPhrases = <String>[
    'source dao',
    'reference dao',
    'citation dao',
    'link dao',
    'সোর্স দাও',
    'সোর্সসহ',
    'রেফারেন্স দাও',
    'রেফারেন্সসহ',
    'সাইটেশন দাও',
    'প্রমাণসহ',
  ];

  static final List<RegExp> _externalLookupPatterns = <RegExp>[
    RegExp(
      r'\b(find|show|open|read|check|get)\s+.+\s+'
      r'(documentation|docs|github|pub\.dev|release notes|changelog|'
      r'official site|official website)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(documentation|docs|github|pub\.dev|release notes|changelog)\s+'
      r'(link|page|for|of)\b',
      caseSensitive: false,
    ),
  ];

  static const List<String> _banglaExternalLookupPhrases = <String>[
    'অফিসিয়াল সাইট',
    'অফিশিয়াল সাইট',
    'ডকুমেন্টেশন লিংক',
    'গিটহাব লিংক',
    'পাব ডেভ',
    'রিলিজ নোট',
    'চেঞ্জলগ',
  ];
}
