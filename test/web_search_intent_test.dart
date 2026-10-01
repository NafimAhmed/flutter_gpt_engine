import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gpt_engine/flutter_gpt_engine.dart';

void main() {
  group('WebSearchIntentAnalyzer', () {
    const analyzer = WebSearchIntentAnalyzer();

    test('searches explicit fresh-information requests', () {
      final decision = analyzer.analyze(
        'What is the latest stable Flutter version?',
      );

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.freshness),
      );
    });

    test('searches current role questions', () {
      final decision = analyzer.analyze('Who is the CEO of OpenAI?');

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.currentRole),
      );
      expect(
        decision.searchQuery,
        contains(DateTime.now().year.toString()),
      );
    });

    test('searches shopping recommendations', () {
      final decision = analyzer.analyze(
        'Best WiFi printer under 20000 BDT?',
      );

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.recommendation),
      );
    });

    test('searches nearby discovery requests', () {
      final decision = analyzer.analyze('Find a good restaurant near me');

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.nearby),
      );
    });

    test('searches requests that explicitly ask for evidence', () {
      final decision = analyzer.analyze(
        'Explain lithium battery recycling with reliable sources',
      );

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.evidenceRequest),
      );
    });

    test('searches Bangla current-price requests', () {
      final decision = analyzer.analyze('আজকের সোনার দাম কত?');

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.liveData),
      );
    });

    test('searches Banglish price requests', () {
      final decision = analyzer.analyze('Samsung S26 er price koto?');

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.liveData),
      );
    });

    test('searches Banglish current-role requests', () {
      final decision = analyzer.analyze('OpenAI er CEO ke?');

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.currentRole),
      );
    });

    test('searches Banglish shopping recommendations', () {
      final decision = analyzer.analyze(
        '30 hazar takar moddhe best phone konta valo?',
      );

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.recommendation),
      );
    });

    test('does not search stable version-control explanation', () {
      final decision = analyzer.analyze('Explain version control');

      expect(decision.shouldSearch, isFalse);
    });

    test('does not search source-code explanation', () {
      final decision = analyzer.analyze('What is source code?');

      expect(decision.shouldSearch, isFalse);
    });

    test('does not search online-learning explanation', () {
      final decision = analyzer.analyze('Explain online learning');

      expect(decision.shouldSearch, isFalse);
    });

    test('does not search SQL update coding request', () {
      final decision = analyzer.analyze(
        'How do I update a database row in SQL?',
      );

      expect(decision.shouldSearch, isFalse);
    });

    test('does not confuse weathering with weather', () {
      final decision = analyzer.analyze('What is chemical weathering?');

      expect(decision.shouldSearch, isFalse);
    });

    test('explicit URL always uses web retrieval', () {
      final decision = analyzer.analyze(
        'Summarize https://docs.flutter.dev/release',
      );

      expect(decision.shouldSearch, isTrue);
      expect(
        decision.reasons,
        contains(WebSearchIntentReason.explicitUrl),
      );
    });

    test('search query removes conversational search noise', () {
      final decision = analyzer.analyze(
        'Please search the web for the latest Flutter stable version with sources',
      );

      expect(decision.shouldSearch, isTrue);
      expect(decision.searchQuery.toLowerCase(), contains('flutter'));
      expect(decision.searchQuery.toLowerCase(), isNot(contains('please')));
      expect(
        decision.searchQuery.toLowerCase(),
        isNot(contains('with sources')),
      );
    });
  });

  test('WebSearchConfig copyWith keeps intent settings', () {
    const config = WebSearchConfig(
      autoSearchThreshold: 6,
      appendCurrentYearToDynamicQueries: false,
    );

    final copied = config.copyWith();

    expect(copied.autoSearchThreshold, 6);
    expect(copied.appendCurrentYearToDynamicQueries, isFalse);
  });
}
