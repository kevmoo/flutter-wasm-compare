import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wasm_compare/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WasmCompareApp());

    // Basic smoke test to ensure there are no startup crashes.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
