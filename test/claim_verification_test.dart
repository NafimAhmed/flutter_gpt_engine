import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';

class _SemanticTestVerifier implements ClaimEntailmentVerifier {
  final List<String> checked = <String>[];

  @override
  Future<ClaimEntailment> verify({
    required String claim,
    required String passage,
    required WebSource source,
  }) async {
    checked.add(source.url);
    if (passage.contains('beta') && claim.contains('stable')) {
      return ClaimEntailment.contradicted;
    }
    if (passage.contains('NOT supported') && claim.contains('supported')) {
      return ClaimEntailment.contradicted;
    }
    return ClaimEntailment.supported;
  }
}

class _UncertainVerifier implements ClaimEntailmentVerifier {
  @override
  Future<ClaimEntailment> verify({
    required String claim,
    required String passage,
    required WebSource source,
  }) async => ClaimEntailment.insufficientEvidence;
}

class _BrokenVerifier implements ClaimEntailmentVerifier {
  @override
  Future<ClaimEntailment> verify({
    required String claim,
    required String passage,
    required WebSource source,
  }) async => throw StateError('NLI service unavailable');
}

void main() {
  const stableSource = WebSource(
    title: 'Flutter release archive',
    url: 'https://docs.flutter.dev/release',
    text: 'The Flutter stable release is 3.50.1. '
        'Release notes were published on November 20, 2026.',
  );
  const betaSource = WebSource(
    title: 'Flutter beta release',
    url: 'https://example.com/beta',
    text: 'Flutter 3.50.1 is beta and not a stable release.',
  );

  test('validates a cited factual claim using actual supporting passage',
      () async {
    final fake = _SemanticTestVerifier();
    final verifier = ClaimVerificationEngine(verifier: fake);
    final report = await verifier.verify(
      answer: 'The Flutter stable release is 3.50.1 [1].',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[stableSource],
      ),
    );

    expect(report.passed, isTrue);
    expect(report.supportedClaims, 1);
    expect(report.claims.single.citations.single.sourceNumber, 1);
    expect(report.claims.single.citations.single.passage, contains('3.50.1'));
    expect(fake.checked, contains('https://docs.flutter.dev/release'));
  });

  test('detects semantic contradiction despite matching keywords', () async {
    final report = await ClaimVerificationEngine(
      verifier: _SemanticTestVerifier(),
    ).verify(
      answer: 'Flutter 3.50.1 is the stable release [1].',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[betaSource],
      ),
    );
    expect(report.passed, isFalse);
    expect(report.contradictedClaims, 1);
    expect(report.claims.single.status, FactClaimStatus.contradicted);
  });

  test('requires every cited source to support the same claim', () async {
    final fake = _SemanticTestVerifier();
    final report = await ClaimVerificationEngine(verifier: fake).verify(
      answer: 'Flutter 3.50.1 is the stable release [1] [2].',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[stableSource, betaSource],
      ),
    );
    expect(report.passed, isFalse);
    expect(report.contradictedClaims, 1);
    expect(fake.checked.length, 2);
  });

  test('rejects citation indexes outside retrieved sources', () async {
    final report = await ClaimVerificationEngine(
      verifier: _SemanticTestVerifier(),
    ).verify(
      answer: 'The Flutter stable release is 3.50.1 [5].',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[stableSource],
      ),
    );
    expect(report.passed, isFalse);
    expect(report.claims.single.status, FactClaimStatus.invalidCitation);
  });

  test('rejects claims without citations', () async {
    final report = await ClaimVerificationEngine(
      verifier: _SemanticTestVerifier(),
    ).verify(
      answer: 'The Flutter stable release is 3.50.1.',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[stableSource],
      ),
    );
    expect(report.claims.single.status, FactClaimStatus.invalidCitation);
  });

  test('rejects invented versions before calling semantic judge', () async {
    final fake = _SemanticTestVerifier();
    final report = await ClaimVerificationEngine(verifier: fake).verify(
      answer: 'The Flutter stable release is 99.12.34 [1].',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[stableSource],
      ),
    );
    expect(report.passed, isFalse);
    expect(report.unverifiedClaims, 1);
    expect(fake.checked, isEmpty);
  });

  test('does not treat source title alone as claim support', () async {
    final fake = _SemanticTestVerifier();
    final report = await ClaimVerificationEngine(verifier: fake).verify(
      answer: 'The Flutter stable release is 3.50.1 [1].',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[
          WebSource(
            title: 'The Flutter stable release is 3.50.1',
            url: 'https://example.com/empty',
            text: '',
          ),
        ],
      ),
    );
    expect(report.passed, isFalse);
    expect(fake.checked, isEmpty);
  });

  test('does not elevate an uncertain NLI result to verified', () async {
    final report = await ClaimVerificationEngine(
      verifier: _UncertainVerifier(),
    ).verify(
      answer: 'The Flutter stable release is 3.50.1 [1].',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[stableSource],
      ),
    );
    expect(report.passed, isFalse);
    expect(report.unverifiedClaims, 1);
  });

  test('fails closed if the external semantic verifier crashes', () async {
    final report = await ClaimVerificationEngine(
      verifier: _BrokenVerifier(),
    ).verify(
      answer: 'The Flutter stable release is 3.50.1 [1].',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[stableSource],
      ),
    );
    expect(report.passed, isFalse);
    expect(report.unverifiedClaims, 1);
  });

  test('does not silently skip claims beyond configured limit', () async {
    final report = await ClaimVerificationEngine(
      verifier: _SemanticTestVerifier(),
      maxClaims: 1,
    ).verify(
      answer: 'The Flutter stable release is 3.50.1 [1].\n'
          'Release notes were published on November 20, 2026 [1].',
      evidence: const WebSearchResult(
        query: 'Flutter stable',
        sources: <WebSource>[stableSource],
      ),
    );
    expect(report.limitExceeded, isTrue);
    expect(report.passed, isFalse);
    expect(report.correctionFeedback, isNotEmpty);
  });

  test('fails closed with empty answer or missing evidence', () async {
    final verifier = ClaimVerificationEngine(
      verifier: _SemanticTestVerifier(),
    );
    final empty = await verifier.verify(
      answer: '',
      evidence: const WebSearchResult(query: '', sources: <WebSource>[]),
    );
    final missing = await verifier.verify(
      answer: 'Flutter 3.50.1 is stable [1].',
      evidence: const WebSearchResult(query: '', sources: <WebSource>[]),
    );
    expect(empty.passed, isFalse);
    expect(missing.passed, isFalse);
  });
}
