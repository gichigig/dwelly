import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:realestate/app_shell.dart';

void main() {
  testWidgets('App shell smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppShell()));

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Find Your Home'), findsOneWidget);
  });
}
