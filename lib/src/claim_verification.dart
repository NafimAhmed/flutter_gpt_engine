import 'web_search_models.dart';

enum ClaimEntailment { supported, contradicted, insufficientEvidence }

/// Implement with an independent NLI model for stronger verification.
abstract class ClaimEntailmentVerifier {
  Future<ClaimEntailment> verify({
    required String claim,
    required String passage,
    required WebSource source,
  });
}

enum FactClaimStatus { supported, contradicted, unverified, invalidCitation }

class CitationValidation {
  const CitationValidation({
    required this.sourceNumber,
    required this.sourceUrl,
    required this.passage,
    required this.status,
  });
  final int sourceNumber;
  final String sourceUrl;
  final String passage;
  final FactClaimStatus status;
}

class FactClaimVerification {
  const FactClaimVerification({
    required this.claim,
    required this.status,
    required this.citations,
  });
  final String claim;
  final FactClaimStatus status;
  final List<CitationValidation> citations;
}

class ClaimVerificationReport {
  const ClaimVerificationReport({
    required this.claims,
    this.limitExceeded = false,
  });
  final List<FactClaimVerification> claims;
  final bool limitExceeded;

  bool get passed => !limitExceeded &&
      claims.isNotEmpty &&
      claims.every((c) => c.status == FactClaimStatus.supported);

  int get supportedClaims =>
      claims.where((c) => c.status == FactClaimStatus.supported).length;
  int get contradictedClaims =>
      claims.where((c) => c.status == FactClaimStatus.contradicted).length;
  int get unverifiedClaims =>
      claims.where((c) => c.status == FactClaimStatus.unverified).length;

  List<String> get correctionFeedback => <String>[
        if (limitExceeded) 'Too many claims. Return a shorter answer.',
        for (final claim in claims)
          if (claim.status != FactClaimStatus.supported)
            'Claim: ' + claim.claim + ' is ' + claim.status.name +
                '. Correct or omit it using retrieved evidence.',
      ];
}

/// Citation-to-source and claim-level evidence checking. Every cited source
/// must support the claim; citation presence alone is never sufficient.
class ClaimVerificationEngine {
  const ClaimVerificationEngine({
    required this.verifier,
    this.maxClaims = 24,
    this.maxPassageCharacters = 1100,
  }) : assert(maxClaims > 0),
       assert(maxPassageCharacters >= 150);

  final ClaimEntailmentVerifier verifier;
  final int maxClaims;
  final int maxPassageCharacters;

  Future<ClaimVerificationReport> verify({
    required String answer,
    required WebSearchResult evidence,
  }) async {
    final claims = answer.trim()
        .split(RegExp(r'(?<=[.!?।])\s+(?!\[\d+\])|\n+'))
        .map((s) => s
            .replaceFirst(RegExp(r'^\s*(?:#{1,6}\s*|[-*]\s+|\d+[.)]\s+)'), '')
            .trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final results = <FactClaimVerification>[];
    for (final claim in claims.take(maxClaims)) {
      final refs = _citations.allMatches(claim)
          .map((m) => int.parse(m.group(1)!)).toSet();

      if (refs.isEmpty ||
          refs.any((i) => i < 1 || i > evidence.sources.length)) {
        results.add(FactClaimVerification(
          claim: claim,
          status: FactClaimStatus.invalidCitation,
          citations: const <CitationValidation>[],
        ));
        continue;
      }

      final bare = claim.replaceAll(_citations, '').trim();
      final citations = <CitationValidation>[];

      for (final i in refs) {
        final source = evidence.sources[i - 1];
        final passage = _bestPassage(bare, source);
        var status = FactClaimStatus.unverified;

        if (passage.isNotEmpty && _matchesLiterals(bare, passage, source)) {
          try {
            final verdict = await verifier.verify(
              claim: bare,
              passage: passage,
              source: source,
            );
            status = switch (verdict) {
              ClaimEntailment.supported => FactClaimStatus.supported,
              ClaimEntailment.contradicted => FactClaimStatus.contradicted,
              ClaimEntailment.insufficientEvidence => FactClaimStatus.unverified,
            };
          } catch (_) {
            status = FactClaimStatus.unverified;
          }
        }

        citations.add(CitationValidation(
          sourceNumber: i,
          sourceUrl: source.url,
          passage: passage,
          status: status,
        ));
      }

      final status = citations.any(
        (c) => c.status == FactClaimStatus.contradicted,
      ) ? FactClaimStatus.contradicted :
          citations.every(
            (c) => c.status == FactClaimStatus.supported,
          ) ? FactClaimStatus.supported : FactClaimStatus.unverified;

      results.add(FactClaimVerification(
        claim: claim,
        status: status,
        citations: List<CitationValidation>.unmodifiable(citations),
      ));
    }

    return ClaimVerificationReport(
      claims: List<FactClaimVerification>.unmodifiable(results),
      limitExceeded: claims.length > maxClaims,
    );
  }

  String _bestPassage(String claim, WebSource source) {
    // Title and URL are metadata, not factual proof. Use actual content.
    final text = source.text.trim().isNotEmpty
        ? source.text : source.snippet;
    final sentences = text
        .split(RegExp(r'(?<=[.!?।])\s+|\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.isEmpty) return '';

    final terms = _terms(claim);
    final numbers = _numbers.allMatches(claim)
        .map((m) => m.group(0)!).toSet();
    var bestScore = -1;
    var best = '';

    for (var i = 0; i < sentences.length; i++) {
      final pair = sentences[i] +
          (i + 1 < sentences.length ? ' ' + sentences[i + 1] : '');
      final passage = pair.length > maxPassageCharacters
          ? pair.substring(0, maxPassageCharacters) : pair;
      final found = _terms(passage);
      final score = terms.intersection(found).length * 2 +
          numbers.where((n) => _containsNumber(passage, n)).length * 5;

      if (score > bestScore) {
        bestScore = score;
        best = passage;
      }
    }

    if (terms.isNotEmpty && terms.intersection(_terms(best)).isEmpty) {
      return '';
    }
    return bestScore > 0 ? best : '';
  }

  static bool _matchesLiterals(
    String claim, String passage, WebSource source,
  ) {
    for (final m in _numbers.allMatches(claim)) {
      if (!_containsNumber(passage, m.group(0)!)) return false;
    }
    for (final m in _urls.allMatches(claim)) {
      final url = m.group(0)!.replaceAll(RegExp(r'[.,;]+$'), '');
      if (url != source.url &&
          !passage.toLowerCase().contains(url.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  static bool _containsNumber(String text, String number) =>
      RegExp(r'(?<![0-9.])' + RegExp.escape(number) +
          r'(?![0-9.])').hasMatch(text);

  static Set<String> _terms(String value) =>
      RegExp(r'[a-zA-Z\u0980-\u09FF]{3,}', unicode: true)
          .allMatches(value.toLowerCase())
          .map((m) => m.group(0)!)
          .where((w) => !_stopWords.contains(w))
          .toSet();

  static final RegExp _citations = RegExp(r'\[(\d{1,3})\]');
  static final RegExp _numbers =
      RegExp(r'(?<![\w])\d+(?:[.,]\d+)*(?![\w])');
  static final RegExp _urls = RegExp(r'https?://[^\s)\]>]+');

  static const Set<String> _stopWords = <String>{
    'the', 'and', 'are', 'was', 'were', 'this', 'that',
    'has', 'have', 'for', 'from', 'with', 'source',
    'sources', 'which', 'when', 'then', 'says', 'version',
    'এবং', 'হলো', 'হচ্ছে', 'থেকে', 'এই', 'একটি',
  };
}
