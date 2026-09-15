import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wasm_compare/main.dart';
import 'package:wasm_compare/src/scene/adaptive_stress_scene.dart';
import 'package:wasm_compare/src/scene/bouncy_layout_matrix.dart';
import 'package:wasm_compare/src/scene/morphing_layout_matrix.dart';
import 'package:wasm_compare/src/shell/build_info.dart';
import 'package:wasm_compare/src/shell/performance_hud.dart';

Future<void> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const WasmCompareApp());
  await tester.pump();
}

Future<void> _pumpBuildInfoDialog(
  WidgetTester tester,
  BuildInfoDialog dialog,
) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: dialog)));
  await tester.pump();
}

Future<void> _selectWorkload(WidgetTester tester, String workloadTitle) async {
  final workloadSelector = find.byTooltip(
    'Select Benchmark Workload (Layout Churn / Card Grid)',
  );
  expect(workloadSelector, findsOneWidget);
  await tester.tap(workloadSelector);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text(workloadTitle), findsOneWidget);
  await tester.tap(find.text(workloadTitle));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

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
    await _pumpApp(tester, size: const Size(400, 800));

    // Verify compact title is used
    expect(find.text('Wasm vs JS'), findsOneWidget);

    // Verify default BouncyLayoutMatrix is rendered inside AdaptiveStressScene
    expect(find.byType(AdaptiveStressScene), findsOneWidget);
    expect(find.byType(BouncyLayoutMatrix), findsOneWidget);

    // Verify PerformanceHud is collapsed on compact screens initially
    expect(find.byType(PerformanceHud), findsOneWidget);
    expect(find.text('⚡ Wasm'), findsOneWidget);
    expect(find.text('📜 JS'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    // Expand HUD
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);

    // Verify compact preset dropdown displays calibrated Bouncy label
    // (Medium (64))
    expect(find.text('Medium (64)'), findsOneWidget);

    // Verify compact workload selector button exists and switches workloads
    await _selectWorkload(tester, 'Polymorphic Card Grid');
    expect(find.text('Medium (500)'), findsOneWidget);
  });

  testWidgets('Renders adaptive desktop layout on large viewports (>= 720px)', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);

    // Verify full title is used
    expect(find.text('Wasm vs JS Performance'), findsOneWidget);

    // Verify default BouncyLayoutMatrix is used inside AdaptiveStressScene
    expect(find.byType(AdaptiveStressScene), findsOneWidget);
    expect(find.byType(BouncyLayoutMatrix), findsOneWidget);

    // Verify expanded PerformanceHud
    expect(find.byType(PerformanceHud), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
  });

  testWidgets(
    'Switches between Bouncy Layout Churn and Polymorphic Card Grid workloads',
    (WidgetTester tester) async {
      await _pumpApp(tester);

      // Starts on BouncyLayoutMatrix with calibrated medium preset (64 Widgets)
      expect(find.byType(BouncyLayoutMatrix), findsOneWidget);
      expect(find.text('64 Widgets'), findsOneWidget);

      // Switch to Polymorphic Card Grid
      await _selectWorkload(tester, 'Polymorphic Card Grid');

      expect(find.byType(MorphingLayoutMatrix), findsOneWidget);
      expect(find.text('500 Cards'), findsOneWidget);
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
    await _pumpApp(tester);

    // Verify WASM and JS mini-cards are rendered in expanded HUD
    expect(find.textContaining('⚡ WASM'), findsOneWidget);
    expect(find.text('📜 JS'), findsOneWidget);

    // In non-wasm context, WASM card has an interactive InkWell
    final wasmCard = find.textContaining('⚡ WASM');
    expect(wasmCard, findsOneWidget);
    await tester.tap(wasmCard);
    await tester.pump();

    // Verify prompt badge or card tooltips exist
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('Responds to Ctrl+Shift+S / Cmd+Shift+S keyboard shortcut', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WasmCompareApp());
    await tester.pump();

    // Simulate pressing Ctrl+Shift+S
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // Verify app handles the shortcut without error
    expect(find.byType(DemoDashboard), findsOneWidget);
  });

  testWidgets('Renders _EngineSelectorButton on desktop, opens popup menu, '
      'and handles selection', (WidgetTester tester) async {
    await _pumpApp(tester);

    // Find engine selector button in AppBar
    final engineSelector = find.byTooltip(
      'Select Rendering Engine (Impeller [Exp] / Skia / JS)',
    );
    expect(engineSelector, findsOneWidget);

    // Tap to open popup menu
    await tester.tap(engineSelector);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('⚡ Wasm (Impeller) [Exp]'), findsOneWidget);
    expect(find.text('⚡ Wasm (Skia)'), findsOneWidget);
    expect(find.text('📜 JavaScript (CanvasKit)'), findsOneWidget);
    expect(find.text('📜 JS (WebParagraph) [Exp]'), findsOneWidget);

    // Tap Wasm Impeller: test stub (non-Chromium) should show SnackBar
    await tester.tap(find.text('⚡ Wasm (Impeller) [Exp]'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('requires Chromium'), findsOneWidget);
  });

  testWidgets('BuildInfoDialog renders Wasm + Skia MT and Git info', (
    WidgetTester tester,
  ) async {
    await _pumpBuildInfoDialog(
      tester,
      const BuildInfoDialog(
        isWasmOverride: true,
        isWimpOverride: false,
        isSingleThreadedOverride: false,
        hasGitInfoOverride: true,
      ),
    );

    expect(find.text('⚡ WASM + Skia'), findsOneWidget);
    expect(find.text('Skia (skwasm.wasm)'), findsOneWidget);
    expect(find.text('Multi-threaded (Toggle)'), findsOneWidget);
    expect(find.text('Commit'), findsOneWidget);
  });

  testWidgets('BuildInfoDialog renders Wasm + Skia ST and handles toggle', (
    WidgetTester tester,
  ) async {
    await _pumpBuildInfoDialog(
      tester,
      const BuildInfoDialog(
        isWasmOverride: true,
        isWimpOverride: false,
        isSingleThreadedOverride: true,
      ),
    );

    expect(find.text('⚡ WASM + Skia (ST)'), findsOneWidget);
    final chip = find.text('Single-threaded (Toggle)');
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pump();
  });

  testWidgets('BuildInfoDialog renders Wasm + Impeller (Exp)', (
    WidgetTester tester,
  ) async {
    await _pumpBuildInfoDialog(
      tester,
      const BuildInfoDialog(
        isWasmOverride: true,
        isWimpOverride: true,
        isSingleThreadedOverride: false,
      ),
    );

    expect(find.text('⚡ WASM + Impeller (Exp)'), findsOneWidget);
    expect(find.text('Impeller (wimp.wasm) • Experimental'), findsOneWidget);
    expect(find.text('Single-threaded (forced by engine)'), findsOneWidget);
  });

  testWidgets('BuildInfoDialog renders JS + WebParagraph (Exp)', (
    WidgetTester tester,
  ) async {
    await _pumpBuildInfoDialog(
      tester,
      const BuildInfoDialog(
        isWasmOverride: false,
        isWebParagraphOverride: true,
      ),
    );

    expect(find.text('📜 JS (WebParagraph) [Exp]'), findsOneWidget);
    expect(
      find.text('CanvasKit (webparagraph/canvaskit.wasm • 3.6MB) • Exp'),
      findsOneWidget,
    );
    expect(
      find.text('WebParagraph (Chrome TextCluster API) • Experimental'),
      findsOneWidget,
    );
  });
}
