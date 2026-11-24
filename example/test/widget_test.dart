import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('Flutter GPT Engine example app shows model selection',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Select a GGUF Model'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });
}
