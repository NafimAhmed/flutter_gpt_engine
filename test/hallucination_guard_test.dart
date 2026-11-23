import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';

void main() {
  const source = WebSource(
    title: 'Official Flutter stable release',
    url: 'https://docs.flutter.dev/release',
    text: 'The Flutter stable release version is 3.50.1. '
        'It was released on November 20, 2026.',
    provider: 'official',
  );
  const evidence = WebSearchResult(
    query: 'Flutter stable version',
    sources: <WebSource>[source],
  );
  const guard = HallucinationGuard();

  test('accepts a cited source-matched version', () {
    final audit = guard.inspect(
      answer: 'Flutter stable release version is 3.50.1 [1].',
      evidence: evidence,
    );
    expect(audit.passed, isTrue);
    expect(audit.checkedClaims, 1);
    expect(audit.issues, isEmpty);
  });

  test('rejects invented version numbers', () {
    final audit = guard.inspect(
      answer: 'Flutter stable release version is 99.99.9 [1].',
      evidence: evidence,
    );
    expect(audit.passed, isFalse);
    expect(
      audit.issues.first.type,
      HallucinationIssueType.unsupportedLiteral,
    );
  });

  test('rejects fake numbered citations', () {
    final audit = guard.inspect(
      answer: 'Flutter stable release version is 3.50.1 [9].',
      evidence: evidence,
    );
    expect(audit.passed, isFalse);
    expect(audit.issues.first.type, HallucinationIssueType.invalidCitation);
  });

  test('rejects factual claims without a citation', () {
    final audit = guard.inspect(
      answer: 'Flutter stable release version is 3.50.1.',
      evidence: evidence,
    );
    expect(audit.passed, isFalse);
    expect(audit.issues.first.type, HallucinationIssueType.missingCitation);
  });

  test('does not match a partial numeric literal', () {
    final audit = guard.inspect(
      answer: 'Flutter stable release version is 50.1 [1].',
      evidence: evidence,
    );
    expect(audit.passed, isFalse);
    expect(
      audit.issues.first.type,
      HallucinationIssueType.unsupportedLiteral,
    );
  });

  test('rejects source-absent URLs', () {
    final audit = guard.inspect(
      answer:
          'Flutter stable release is listed at https://fake.example.com [1].',
      evidence: evidence,
    );
    expect(audit.passed, isFalse);
    expect(
      audit.issues.first.type,
      HallucinationIssueType.unsupportedLiteral,
    );
  });

  test('fails closed when no source exists', () {
    final audit = guard.inspect(
      answer: 'Flutter stable release version is 3.50.1 [1].',
      evidence: const WebSearchResult(
        query: 'Flutter stable version',
        sources: <WebSource>[],
      ),
    );
    expect(audit.passed, isFalse);
    expect(audit.issues.first.type, HallucinationIssueType.noEvidence);
  });

  test('fails closed when too many claims need review', () {
    const tinyGuard = HallucinationGuard(
      config: HallucinationGuardConfig(maxClaims: 1),
    );
    final audit = tinyGuard.inspect(
      answer: 'Flutter stable version is 3.50.1 [1].\n'
          'Flutter was released on November 20, 2026 [1].',
      evidence: evidence,
    );
    expect(audit.passed, isFalse);
    expect(
      audit.issues.any(
        (issue) => issue.type == HallucinationIssueType.incompleteReview,
      ),
      isTrue,
    );
  });

  test('does not classify an abstention as verified', () {
    final audit = guard.inspect(
      answer: 'I could not verify the release from these sources.',
      evidence: evidence,
    );
    expect(audit.passed, isFalse);
    expect(audit.issues.first.type, HallucinationIssueType.abstention);
  });

  test('rejects empty model output', () {
    final audit = guard.inspect(answer: '  ', evidence: evidence);
    expect(audit.passed, isFalse);
    expect(audit.issues.first.type, HallucinationIssueType.emptyAnswer);
  });
}
