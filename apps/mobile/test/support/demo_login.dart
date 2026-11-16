import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openDemoLogin(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
  await tester.pumpAndSettle();
}

Future<void> submitDemoLogin(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'admin-demo');
  await tester.enterText(fields.at(1), 'sandi-demo');
  final submit = find.widgetWithText(FilledButton, 'Masuk');
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}
