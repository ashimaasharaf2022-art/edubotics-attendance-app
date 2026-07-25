import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workora/main.dart';

void main() {
  testWidgets('Login screen loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const AttendanceApp());

    // Check main UI elements
    expect(find.text('Workora'), findsOneWidget);
    expect(find.text('Employee ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
  });
}
