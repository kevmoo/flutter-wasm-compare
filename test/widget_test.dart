import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wasm_compare/main.dart';
import 'package:wasm_compare/src/shell/performance_hud.dart';

void main() {
  testWidgets('App smoke test on default window size', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WasmCompareApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(DemoDashboard), findsOneWidget);
  });

  testWidgets('Renders adaptive mobile layout on small viewports (< 600px)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const WasmCompareApp());
    await tester.pump();

    // Verify compact title is used
    expect(find.text('Wasm vs JS'), findsOneWidget);

    // Verify mobile ListView is used inside AdaptiveStressScene
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(GridView), findsNothing);

    // Verify PerformanceHud is collapsed on compact screens initially
    expect(find.byType(PerformanceHud), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    // Expand HUD
    await tester.tap(find.byType(PerformanceHud));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
  });

  testWidgets(
    'Renders adaptive desktop grid layout on large viewports (>= 720px)',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const WasmCompareApp());
      await tester.pump();

      // Verify full title is used
      expect(find.text('Wasm vs JS Performance'), findsOneWidget);

      // Verify desktop GridView is used inside AdaptiveStressScene
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);

      // Verify expanded PerformanceHud
      expect(find.byType(PerformanceHud), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    },
  );
}
