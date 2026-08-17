import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wasm_compare/main.dart';
import 'package:wasm_compare/src/scene/adaptive_stress_scene.dart';
import 'package:wasm_compare/src/scene/morphing_layout_matrix.dart';
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

    // Verify MorphingLayoutMatrix is rendered
    expect(find.byType(AdaptiveStressScene), findsOneWidget);
    expect(find.byType(MorphingLayoutMatrix), findsOneWidget);

    // Verify PerformanceHud is collapsed on compact screens initially
    expect(find.byType(PerformanceHud), findsOneWidget);
    expect(find.text('⚡ Wasm'), findsOneWidget);
    expect(find.text('📜 JS'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    // Expand HUD
    await tester.tap(find.byIcon(Icons.expand_more));
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

      // Verify MorphingLayoutMatrix is used inside AdaptiveStressScene
      expect(find.byType(AdaptiveStressScene), findsOneWidget);
      expect(find.byType(MorphingLayoutMatrix), findsOneWidget);

      // Verify expanded PerformanceHud
      expect(find.byType(PerformanceHud), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    },
  );

  testWidgets('Opens BuildInfoDialog when info button is tapped', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WasmCompareApp());
    await tester.pump();

    final infoButton = find.byIcon(Icons.info_outline);
    expect(infoButton, findsOneWidget);

    await tester.tap(infoButton);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('About & Build Info'), findsOneWidget);
    expect(
      find.text('Flutter Wasm vs JS Performance Comparison Benchmark'),
      findsOneWidget,
    );
    expect(find.text('Commit'), findsOneWidget);
    expect(find.text('Active Engine'), findsOneWidget);

    // Dismiss dialog
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('About & Build Info'), findsNothing);
  });

  testWidgets('PerformanceHud mini-cards and prompt badge are interactive', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const WasmCompareApp());
    await tester.pump();

    // Verify WASM and JS mini-cards are rendered in expanded HUD
    expect(find.text('⚡ WASM'), findsOneWidget);
    expect(find.text('📜 JS'), findsOneWidget);

    // In non-wasm context, WASM card has an interactive InkWell
    final wasmCard = find.text('⚡ WASM');
    expect(wasmCard, findsOneWidget);
    await tester.tap(wasmCard);
    await tester.pump();

    // Verify prompt badge or card tooltips exist
    expect(find.byType(Tooltip), findsWidgets);
  });
}
