import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('Flutter GPT Engine example app loads',
          (WidgetTester tester) async {
        await tester.pumpWidget(const ExampleApp());

        expect(find.text('Host App UI'), findsOneWidget);
        expect(find.text('Pick GGUF'), findsOneWidget);
        expect(find.text('Send'), findsOneWidget);
      });
}