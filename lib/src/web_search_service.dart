import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'web_search_config.dart';
import 'web_search_models.dart';

class WebSearchService {
  WebSearchService({
    this.config = const WebSearchConfig(),
  }) : _client = HttpClient() {
    _client
      ..connectionTimeout = config.timeout
      ..userAgent = config.userAgent;
  }

  final WebSearchConfig config;
  final HttpClient _client;
  bool _disposed = false;

  /// Releases pooled HTTP connections.
  ///
  /// A single client is intentionally reused while this service is alive so
  /// DNS/TCP/TLS setup and keep-alive connections can be reused across search
  /// result pages.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close(force: true);
  }

  Future<WebSearchResult> search(
    String query, {
    String? originalPrompt,
  }) async {
    final cleanQuery = _normalizeSearchQuery(query);

    if (!config.enabled || cleanQuery.isEmpty) {
      return WebSearchResult(
        query: cleanQuery,
        sources: const <WebSource>[],
      );
    }

    // 1) If the user supplied an explicit URL, read that page directly.
    if (config.directUrlFetch) {
      final urls = _extractUrls(originalPrompt ?? cleanQuery);

      if (urls.isNotEmpty) {
        final fetched = await Future.wait(
          urls.take(config.maxResults).map(
                (url) => fetchUrl(
                  url,
                  query: cleanQuery,
                  provider: 'direct',
                ),
              ),
        );

        final directSources = fetched.whereType<WebSource>().toList();

        if (directSources.isNotEmpty) {
          return WebSearchResult(
            query: cleanQuery,
            sources: directSources,
            provider: 'direct',
          );
        }
      }
    }

    final isCurrent = _looksCurrent(cleanQuery);
    final isTechnical = _looksTechnical(cleanQuery);

    // 2) For common technical/current topics, prefer known official pages.
    //    This avoids stale snippets and makes "latest version" questions much
    //    more reliable without requiring an API key.
    if (config.useOfficialSourceHints && (isCurrent || isTechnical)) {
      final official = await _searchOfficialHints(cleanQuery);
      if (official.isNotEmpty) return official;
    }

    // 3) Wikipedia is good for stable background knowledge, but is not the
    //    first choice for current/version/price/news questions.
    if (config.useWikipedia && !isCurrent && !isTechnical) {
      final wiki = await _searchWikipedia(cleanQuery);
      if (wiki.isNotEmpty) return wiki;
    }

    // 4) Google HTML search fallback.
    if (config.useGoogle) {
      final google = await _searchGoogle(cleanQuery);
      if (google.isNotEmpty) return google;
    }

    // 5) Last fallback: Wikipedia.
    if (config.useWikipedia) {
      final wiki = await _searchWikipedia(cleanQuery);
      if (wiki.isNotEmpty) return wiki;
    }

    return WebSearchResult(
      query: cleanQuery,
      sources: const <WebSource>[],
    );
  }

  Future<WebSource?> fetchUrl(
    String url, {
    String? query,
    String provider = 'direct',
  }) async {
    final uri = Uri.tryParse(_cleanUrl(url));

    if (uri == null || !_isAllowedPublicUri(uri)) {
      return null;
    }

    try {
      final response = await _get(uri);
      if (response == null) return null;

      final document = html_parser.parse(response.body);
      _removeNoise(document);

      final title = _extractTitle(document, fallback: uri.host);
      final text = _extractRelevantText(
        document,
        query: query ?? '',
      );

      if (text.trim().isEmpty) return null;

      return WebSource(
        title: title,
        url: uri.toString(),
        text: _limit(text, config.maxPageCharacters),
        provider: provider,
      );
    } catch (_) {
      return null;
    }
  }

  Future<WebSearchResult> _searchOfficialHints(String query) async {
    final lower = query.toLowerCase();
    final urls = <String>[];
    final seen = <String>{};

    for (final entry in config.officialSourceHints.entries) {
      final keyword = entry.key.toLowerCase();
      if (!lower.contains(keyword)) continue;

      for (final url in entry.value) {
        if (seen.add(url)) urls.add(url);
      }
    }

    if (urls.isEmpty) {
      return WebSearchResult(
        query: query,
        sources: const <WebSource>[],
        provider: 'official',
      );
    }

    final fetched = await Future.wait(
      urls.take(config.maxResults).map(
            (url) => fetchUrl(
              url,
              query: query,
              provider: 'official',
            ),
          ),
    );

    final sources = fetched.whereType<WebSource>().toList();

    return WebSearchResult(
      query: query,
      sources: sources,
      provider: 'official',
    );
  }

  Future<WebSearchResult> _searchWikipedia(String query) async {
    final language = _containsBangla(query) ? 'bn' : 'en';
    final base = Uri.parse('https://$language.wikipedia.org');
    final searchUri = Uri.https(
      '$language.wikipedia.org',
      '/w/index.php',
      <String, String>{
        'search': query,
        'title': 'Special:Search',
        'ns0': '1',
      },
    );

    try {
      final response = await _get(searchUri);
      if (response == null) {
        return WebSearchResult(query: query, sources: const <WebSource>[]);
      }

      final document = html_parser.parse(response.body);
      final resultLinks = document.querySelectorAll('.mw-search-result-heading a');
      final sources = <WebSource>[];

      if (resultLinks.isNotEmpty) {
        final targets = resultLinks
            .take(config.maxResults)
            .map((link) => link.attributes['href'])
            .whereType<String>()
            .where((href) => href.isNotEmpty)
            .map(base.resolve)
            .toList();

        final fetched = await Future.wait(
          targets.map(
            (target) => fetchUrl(
              target.toString(),
              query: query,
              provider: 'wikipedia',
            ),
          ),
        );

        sources.addAll(fetched.whereType<WebSource>());
      } else {
        final heading = document.querySelector('#firstHeading')?.text.trim() ?? '';
        final isSearchPage = heading.toLowerCase().contains('search') ||
            heading.contains('অনুসন্ধান');

        if (!isSearchPage) {
          _removeNoise(document);
          final text = _extractRelevantText(document, query: query);
          final canonical = document
                  .querySelector('link[rel="canonical"]')
                  ?.attributes['href'] ??
              searchUri.toString();

          if (text.isNotEmpty) {
            sources.add(
              WebSource(
                title: heading.isEmpty ? query : heading,
                url: canonical,
                text: _limit(text, config.maxPageCharacters),
                provider: 'wikipedia',
              ),
            );
          }
        }
      }

      return WebSearchResult(
        query: query,
        sources: sources,
        provider: 'wikipedia',
      );
    } catch (_) {
      return WebSearchResult(query: query, sources: const <WebSource>[]);
    }
  }

  Future<WebSearchResult> _searchGoogle(String query) async {
    final searchUri = Uri.https(
      'www.google.com',
      '/search',
      <String, String>{
        'q': query,
        'num': '${config.maxResults + 5}',
        'hl': _containsBangla(query) ? 'bn' : 'en',
        'filter': '0',
      },
    );

    try {
      final response = await _get(searchUri);
      if (response == null) {
        return WebSearchResult(query: query, sources: const <WebSource>[]);
      }

      final document = html_parser.parse(response.body);
      final candidates = <_SearchCandidate>[];
      final seen = <String>{};
      var order = 0;

      for (final h3 in document.querySelectorAll('h3')) {
        Element? anchor = h3.parent;

        while (anchor != null && anchor.localName != 'a') {
          anchor = anchor.parent;
        }

        if (anchor == null) continue;

        final href = anchor.attributes['href'];
        if (href == null || href.isEmpty) continue;

        final target = _googleTargetUri(href);
        if (target == null || !_isAllowedPublicUri(target)) continue;
        if (_isGoogleHost(target.host)) continue;

        final url = target.toString();
        if (!seen.add(url)) continue;

        var snippet = '';
        Element? container = h3.parent;
        for (var i = 0; i < 5 && container != null; i++) {
          snippet = container.querySelector('.VwiC3b')?.text.trim() ??
              container.querySelector('.aCOpRe')?.text.trim() ??
              container.querySelector('[data-sncf]')?.text.trim() ??
              snippet;
          if (snippet.isNotEmpty) break;
          container = container.parent;
        }

        candidates.add(
          _SearchCandidate(
            title: h3.text.trim(),
            uri: target,
            snippet: snippet,
            order: order++,
          ),
        );
      }

      candidates.sort((a, b) {
        final aRank = _trustedRank(a.uri.host);
        final bRank = _trustedRank(b.uri.host);

        if (aRank != bRank) return aRank.compareTo(bRank);
        return a.order.compareTo(b.order);
      });

      final sources = <WebSource>[];
      final candidateLimit = config.maxResults <= 0
          ? 0
          : (config.maxResults * 2) + 2;
      final selectedCandidates = candidates.take(candidateLimit).toList();

      final fetchedPages = await Future.wait(
        selectedCandidates.map(
          (candidate) => fetchUrl(
            candidate.uri.toString(),
            query: query,
            provider: 'google',
          ),
        ),
      );

      for (var i = 0; i < selectedCandidates.length; i++) {
        if (sources.length >= config.maxResults) break;

        final candidate = selectedCandidates[i];
        final fetched = fetchedPages[i];

        if (fetched != null) {
          sources.add(
            WebSource(
              title: fetched.title.isEmpty ? candidate.title : fetched.title,
              url: fetched.url,
              text: fetched.text,
              snippet: candidate.snippet,
              provider: 'google',
            ),
          );
        } else if (candidate.snippet.isNotEmpty) {
          sources.add(
            WebSource(
              title: candidate.title,
              url: candidate.uri.toString(),
              text: candidate.snippet,
              snippet: candidate.snippet,
              provider: 'google',
            ),
          );
        }
      }

      return WebSearchResult(
        query: query,
        sources: sources,
        provider: 'google',
      );
    } catch (_) {
      return WebSearchResult(query: query, sources: const <WebSource>[]);
    }
  }

  Future<_HttpPage?> _get(Uri uri) async {
    if (_disposed || !_isAllowedPublicUri(uri)) return null;

    final request = await _client.getUrl(uri).timeout(config.timeout);
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5',
    );
    request.headers.set('Accept-Language', 'en-US,en;q=0.9,bn;q=0.8');

    final response = await request.close().timeout(config.timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final contentType = response.headers.contentType;
    final mime = contentType?.mimeType.toLowerCase() ?? '';

    if (mime.isNotEmpty &&
        !mime.contains('html') &&
        !mime.contains('text/plain')) {
      return null;
    }

    final body = await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(config.timeout);

    return _HttpPage(body: body);
  }

  void _removeNoise(Document document) {
    document.querySelectorAll(
      'script,style,noscript,svg,canvas,iframe,nav,aside,form,button,input,'
      'select,textarea,.advertisement,.ads,.ad,.cookie,.mw-editsection,'
      'sup.reference',
    ).forEach((element) => element.remove());
  }

  String _extractTitle(Document document, {required String fallback}) {
    final heading = document.querySelector('h1')?.text.trim();
    if (heading != null && heading.isNotEmpty) return heading;

    final title = document.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) return title;

    return fallback;
  }

  String _extractRelevantText(
    Document document, {
    required String query,
  }) {
    final root = document.querySelector('article') ??
        document.querySelector('main') ??
        document.querySelector('[role="main"]') ??
        document.querySelector('#mw-content-text') ??
        document.querySelector('#content') ??
        document.body;

    if (root == null) return '';

    final blocks = root.querySelectorAll(
      'h1,h2,h3,h4,p,li,dt,dd,tr,blockquote,pre',
    );

    if (blocks.isEmpty) {
      return _normalizeWhitespace(root.text);
    }

    final tokens = _queryTokens(query);
    final currentIntent = _looksCurrent(query);
    final now = DateTime.now();
    final currentYear = now.year.toString();
    final previousYear = (now.year - 1).toString();

    final scored = <_ScoredBlock>[];

    for (var i = 0; i < blocks.length; i++) {
      final element = blocks[i];
      final text = _normalizeWhitespace(element.text);

      if (text.length < 12) continue;

      final lower = text.toLowerCase();
      var score = 0;

      for (final token in tokens) {
        if (lower.contains(token)) score += 4;
      }

      if (const <String>{'h1', 'h2', 'h3', 'h4'}.contains(element.localName)) {
        score += 2;
      }

      if (currentIntent) {
        const currentTerms = <String>[
          'latest',
          'current',
          'stable',
          'release',
          'version',
          'reflects',
          'updated',
          'released',
          'today',
          'now',
        ];

        for (final term in currentTerms) {
          if (lower.contains(term)) score += 2;
        }

        if (text.contains(currentYear)) score += 8;
        if (text.contains(previousYear)) score += 3;
        if (_versionPattern.hasMatch(text)) score += 5;
        if (_datePattern.hasMatch(text)) score += 3;

        // Down-rank clearly historical/example wording for current questions.
        if (lower.contains('example') ||
            lower.contains('previous') ||
            lower.contains('earlier') ||
            lower.contains('archived')) {
          score -= 2;
        }
      }

      if (score > 0) {
        scored.add(
          _ScoredBlock(
            index: i,
            score: score,
            text: text,
          ),
        );
      }
    }

    // If nothing matched, use the first readable blocks rather than the entire
    // page. Keeping the context focused helps small local models.
    if (scored.isEmpty) {
      final fallback = <String>[];
      for (final block in blocks) {
        final text = _normalizeWhitespace(block.text);
        if (text.length >= 20) fallback.add(text);
        if (fallback.length >= 18) break;
      }
      return fallback.join('\n\n').trim();
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.index.compareTo(b.index);
    });

    final selectedIndices = <int>{};
    for (final item in scored.take(12)) {
      selectedIndices.add(item.index);

      // Include one neighbour on each side so a heading and its explanatory
      // paragraph stay together.
      if (item.index > 0) selectedIndices.add(item.index - 1);
      if (item.index + 1 < blocks.length) selectedIndices.add(item.index + 1);
    }

    final ordered = selectedIndices.toList()..sort();
    final parts = <String>[];

    for (final index in ordered) {
      final text = _normalizeWhitespace(blocks[index].text);
      if (text.length >= 12 && !parts.contains(text)) {
        parts.add(text);
      }
    }

    return parts.join('\n\n').trim();
  }

  Uri? _googleTargetUri(String href) {
    try {
      if (href.startsWith('/url?')) {
        final wrapped = Uri.parse('https://www.google.com$href');
        final target =
            wrapped.queryParameters['q'] ?? wrapped.queryParameters['url'];
        if (target == null || target.isEmpty) return null;
        return Uri.tryParse(target);
      }

      if (href.startsWith('http://') || href.startsWith('https://')) {
        return Uri.tryParse(href);
      }
    } catch (_) {}

    return null;
  }

  int _trustedRank(String host) {
    final lowerHost = host.toLowerCase();

    for (var i = 0; i < config.trustedDomains.length; i++) {
      final trusted = config.trustedDomains[i].toLowerCase();
      if (lowerHost == trusted || lowerHost.endsWith('.$trusted')) {
        return i;
      }
    }

    return 1000;
  }

  bool _looksCurrent(String query) {
    final lower = query.toLowerCase();
    const terms = <String>[
      'latest',
      'current',
      'today',
      'now',
      'recent',
      'newest',
      'news',
      'price',
      'weather',
      'score',
      'release',
      'version',
      'update',
      '2025',
      '2026',
      '2027',
      'আজ',
      'আজকের',
      'এখন',
      'বর্তমান',
      'সর্বশেষ',
      'লেটেস্ট',
      'খবর',
      'দাম',
      'মূল্য',
      'আবহাওয়া',
      'স্কোর',
      'রিলিজ',
      'ভার্সন',
      'আপডেট',
    ];

    return terms.any((term) => lower.contains(term));
  }

  bool _looksTechnical(String query) {
    final lower = query.toLowerCase();
    const terms = <String>[
      'flutter',
      'dart',
      'android',
      'kotlin',
      'java',
      'python',
      'oracle',
      'api',
      'sdk',
      'package',
      'pub.dev',
      'github',
      'documentation',
      'docs',
      'error',
      'exception',
      'build.gradle',
    ];

    return terms.any((term) => lower.contains(term));
  }

  List<String> _extractUrls(String text) {
    final matches = RegExp(
      r'''https?://[^\s<>()\[\]{}"']+''',
      caseSensitive: false,
    ).allMatches(text);

    final urls = <String>[];
    final seen = <String>{};

    for (final match in matches) {
      final value = _cleanUrl(match.group(0) ?? '');
      if (value.isNotEmpty && seen.add(value)) urls.add(value);
    }

    return urls;
  }

  String _cleanUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'[.,;:!?]+$'), '');
  }

  String _normalizeSearchQuery(String value) {
    var query = value
        .replaceAll(
          RegExp(
            r'''https?://[^\s<>()\[\]{}"']+''',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const noisePhrases = <String>[
      'please search in web',
      'please search the web',
      'search in web',
      'search the web',
      'search internet',
      'search online',
      'google this',
    ];

    final lower = query.toLowerCase();
    for (final phrase in noisePhrases) {
      if (lower == phrase) return query;
      query = query.replaceAll(RegExp(phrase, caseSensitive: false), ' ');
    }

    query = query.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (query.length > 300) {
      query = query.substring(0, 300).trim();
    }

    return query;
  }

  List<String> _queryTokens(String query) {
    final cleaned = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0980-\u09FF.]+'), ' ')
        .trim();

    if (cleaned.isEmpty) return const <String>[];

    const stopWords = <String>{
      'the',
      'a',
      'an',
      'is',
      'are',
      'of',
      'to',
      'for',
      'in',
      'on',
      'and',
      'or',
      'tell',
      'me',
      'what',
      'which',
      'please',
      'read',
      'page',
      'about',
      'this',
      'that',
      'web',
      'search',
    };

    return cleaned
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2 && !stopWords.contains(token))
        .toSet()
        .toList();
  }

  bool _isAllowedPublicUri(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;

    final host = uri.host.toLowerCase();

    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return false;
    }

    if (_isPrivateIpv4(host)) return false;
    if (host == '::1' ||
        host.startsWith('fc') ||
        host.startsWith('fd') ||
        host.startsWith('fe80:')) {
      return false;
    }

    return true;
  }

  bool _isPrivateIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;

    final nums = parts.map((part) => int.tryParse(part)).toList();
    if (nums.any((n) => n == null || n < 0 || n > 255)) return false;

    final a = nums[0]!;
    final b = nums[1]!;

    if (a == 10 || a == 127 || a == 0) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;

    return false;
  }

  bool _isGoogleHost(String host) {
    final lower = host.toLowerCase();
    return lower == 'google.com' ||
        lower.endsWith('.google.com') ||
        lower == 'googleusercontent.com' ||
        lower.endsWith('.googleusercontent.com');
  }

  bool _containsBangla(String value) {
    return RegExp(r'[\u0980-\u09FF]').hasMatch(value);
  }

  String _normalizeWhitespace(String value) {
    return value
        .replaceAll(RegExp(r'[\t\r ]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _limit(String value, int maxCharacters) {
    if (maxCharacters <= 0 || value.length <= maxCharacters) return value;
    return '${value.substring(0, maxCharacters)}…';
  }

  static final RegExp _versionPattern = RegExp(
    r'\b\d+\.\d+(?:\.\d+)?(?:[-+][A-Za-z0-9.-]+)?\b',
  );

  static final RegExp _datePattern = RegExp(
    r'\b(?:20\d{2}[-/]\d{1,2}[-/]\d{1,2}|'
    r'\d{1,2}[-/]\d{1,2}[-/]20\d{2}|'
    r'(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|'
    r'Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|'
    r'Dec(?:ember)?)\s+\d{1,2},?\s+20\d{2})\b',
    caseSensitive: false,
  );
}

class _SearchCandidate {
  const _SearchCandidate({
    required this.title,
    required this.uri,
    required this.snippet,
    required this.order,
  });

  final String title;
  final Uri uri;
  final String snippet;
  final int order;
}

class _ScoredBlock {
  const _ScoredBlock({
    required this.index,
    required this.score,
    required this.text,
  });

  final int index;
  final int score;
  final String text;
}

class _HttpPage {
  const _HttpPage({required this.body});

  final String body;
}
