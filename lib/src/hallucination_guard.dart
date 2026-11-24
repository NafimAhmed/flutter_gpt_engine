import 'dart:math' as math;
import 'web_search_models.dart';

/// A source-consistency check is not a guarantee of truth or entailment.
enum HallucinationIssueType {
  noEvidence,
  emptyAnswer,
  abstention,
  missingCitation,
  invalidCitation,
  unsupportedLiteral,
  weakSourceMatch,
  incompleteReview,
}

class HallucinationIssue {
  const HallucinationIssue({
    required this.type,
    required this.claim,
    required this.explanation,
  });
  final HallucinationIssueType type;
  final String claim;
  final String explanation;
}

class HallucinationAudit {
  const HallucinationAudit({
    required this.checkedClaims,
    required this.issues,
  });
  final int checkedClaims;
  final List<HallucinationIssue> issues;
  bool get passed => checkedClaims > 0 && issues.isEmpty;
}

class HallucinationGuardConfig {
  const HallucinationGuardConfig({
    this.maxCorrectionAttempts = 2,
    this.maxClaims = 24,
    this.minSharedTerms = 2,
  })  : assert(maxCorrectionAttempts >= 0 && maxCorrectionAttempts <= 5),
        assert(maxClaims > 0),
        assert(minSharedTerms >= 1);

  final int maxCorrectionAttempts;
  final int maxClaims;
  final int minSharedTerms;
}

enum ProtectedAnswerStatus {
  /// The citations and surface-level evidence checks passed. Not fact-proof.
  evidenceMatched,
  /// The model draft was withheld because it could not be supported.
  notVerified,
  /// The operation was cancelled.
  cancelled,
}

class ProtectedAnswerResult {
  const ProtectedAnswerResult({
    required this.answer,
    required this.status,
    required this.audit,
    required this.attempts,
    required this.webResult,
  });
  final String answer;
  final ProtectedAnswerStatus status;
  final HallucinationAudit audit;
  final int attempts;
  final WebSearchResult webResult;
  bool get hasEvidenceMatch =>
      status == ProtectedAnswerStatus.evidenceMatched;
}

/// Deterministic evidence checks without requiring an additional model.
///
/// Checks citation indexes, claimed numbers/versions/URLs and relevance of
/// cited text. Lexical agreement cannot prove a claim is factually correct:
/// contradictions, paraphrases and source reliability require more checks.
class HallucinationGuard {
  const HallucinationGuard({
    this.config = const HallucinationGuardConfig(),
  });

  final HallucinationGuardConfig config;

  HallucinationAudit inspect({
    required String answer,
    required WebSearchResult evidence,
  }) {
    final cleaned = answer.trim();
    final issues = <HallucinationIssue>[];

    if (cleaned.isEmpty) {
      return const HallucinationAudit(
        checkedClaims: 0,
        issues: <HallucinationIssue>[
          HallucinationIssue(
            type: HallucinationIssueType.emptyAnswer,
            claim: '',
            explanation: 'The model returned no answer.',
          ),
        ],
      );
    }

    if (evidence.sources.isEmpty) {
      return const HallucinationAudit(
        checkedClaims: 0,
        issues: <HallucinationIssue>[
          HallucinationIssue(
            type: HallucinationIssueType.noEvidence,
            claim: '',
            explanation: 'No retrieved evidence is available.',
          ),
        ],
      );
    }

    if (_isAbstention(cleaned)) {
      return HallucinationAudit(
        checkedClaims: 0,
        issues: <HallucinationIssue>[
          HallucinationIssue(
            type: HallucinationIssueType.abstention,
            claim: cleaned,
            explanation: 'The answer explicitly says it cannot be verified.',
          ),
        ],
      );
    }

    // Split sentences on punctuation + whitespace, preserving dotted versions.
    final claims = cleaned
        .split(RegExp(r'[.!?।]\s+|\n+'))
        .map((part) => part
            .replaceFirst(RegExp(r'^\s*(?:#{1,6}|[-*]|\d+[.)])\s*'), '')
            .trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (claims.length > config.maxClaims) {
      issues.add(const HallucinationIssue(
        type: HallucinationIssueType.incompleteReview,
        claim: '',
        explanation: 'Answer exceeds the configured review limit.',
      ));
    }

    final selected = claims.take(config.maxClaims).toList();

    for (final claim in selected) {
      final refs = _citations
          .allMatches(claim)
          .map((match) => int.parse(match.group(1)!))
          .toSet();

      if (refs.isEmpty) {
        issues.add(HallucinationIssue(
          type: HallucinationIssueType.missingCitation,
          claim: claim,
          explanation: 'A source citation is required for each statement.',
        ));
        continue;
      }

      if (refs.any((i) => i < 1 || i > evidence.sources.length)) {
        issues.add(HallucinationIssue(
          type: HallucinationIssueType.invalidCitation,
          claim: claim,
          explanation: 'The answer cites an unknown source index.',
        ));
        continue;
      }

      final bare = claim.replaceAll(_citations, '').trim();
      final numbers = _numbers
          .allMatches(bare)
          .map((m) => m.group(0)!)
          .toSet();
      final urls = _urls
          .allMatches(bare)
          .map((m) => m.group(0)!.replaceAll(RegExp(r'[.,;]+$'), ''))
          .toSet();
      final terms = _terms(bare);

      final matched = refs.any((index) {
        final source = evidence.sources[index - 1];
        final sourceText = <String>[
          source.title,
          source.snippet,
          source.text,
          source.url,
        ].join(' ').toLowerCase();

        if (numbers.any((n) => !_containsLiteral(sourceText, n))) {
          return false;
        }
        if (urls.any((u) => !sourceText.contains(u.toLowerCase()))) {
          return false;
        }

        final sourceTerms = _terms(sourceText);
        final common = terms.where(sourceTerms.contains).length;
        return terms.isNotEmpty &&
            common >= math.min(config.minSharedTerms, terms.length);
      });

      if (!matched) {
        issues.add(HallucinationIssue(
          type: numbers.isNotEmpty || urls.isNotEmpty
              ? HallucinationIssueType.unsupportedLiteral
              : HallucinationIssueType.weakSourceMatch,
          claim: claim,
          explanation: 'The cited source does not sufficiently match this claim.',
        ));
      }
    }

    return HallucinationAudit(
      checkedClaims: selected.length,
      issues: List<HallucinationIssue>.unmodifiable(issues),
    );
  }

  static bool _containsLiteral(String text, String literal) {
    final pattern = RegExp(
      r'(?<![0-9.])' + RegExp.escape(literal.toLowerCase()) + r'(?![0-9]|\.[0-9])',
    );
    return pattern.hasMatch(text);
  }

  static Set<String> _terms(String value) {
    return RegExp(r'[a-zA-Z\u0980-\u09FF]{3,}', unicode: true)
        .allMatches(value.toLowerCase())
        .map((m) => m.group(0)!)
        .where((word) => !_stopWords.contains(word))
        .toSet();
  }

  static bool _isAbstention(String answer) {
    final text = answer.toLowerCase();
    return <String>[
      'could not verify',
      'cannot verify',
      "can't verify",
      'unable to verify',
      'not enough evidence',
      'পর্যাপ্ত তথ্য পাওয়া যায়নি',
      'যাচাই করা যায়নি',
      'নিশ্চিত করতে পারছি না',
    ].any(text.contains);
  }

  static final RegExp _citations = RegExp(r'\[(\d{1,3})\]');
  static final RegExp _numbers =
      RegExp(r'(?<![\w])\d+(?:[.,]\d+)*(?![\w])');
  static final RegExp _urls = RegExp(r'https?://[^\s)\]>]+');

  static const Set<String> _stopWords = <String>{
    'the', 'and', 'are', 'was', 'were', 'with', 'from', 'for',
    'that', 'this', 'which', 'into', 'have', 'has', 'its',
    'their', 'latest', 'current', 'answer', 'source', 'sources',
    'according', 'version', 'release',
    'এবং', 'হলো', 'হচ্ছে', 'থেকে', 'যেটি', 'এই',
    'সাথে', 'জন্য', 'একটি', 'আছে', 'হয়েছে',
  };
}
