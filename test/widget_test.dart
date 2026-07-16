import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:punchin_app/main.dart';

void main() {
  testWidgets('Login screen loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const AttendanceApp());

    // Check main UI elements
    expect(find.text('EDUBOTICS GLOBAL'), findsOneWidget);
    expect(find.text('Employee ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
  });
}