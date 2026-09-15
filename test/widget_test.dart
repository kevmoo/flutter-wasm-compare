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
  WidgetTester tester, {
  bool isWasm = true,
  bool isWimp = false,
  bool isSingleThreaded = false,
  bool isWebParagraph = false,
  bool hasGitInfo = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BuildInfoDialog(
          isWasmOverride: isWasm,
          isWimpOverride: isWimp,
          isSingleThreadedOverride: isSingleThreaded,
          isWebParagraphOverride: isWebParagraph,
          hasGitInfoOverride: hasGitInfo,
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectTexts(List<String> texts) {
  for (final text in texts) {
    expect(find.text(text), findsOneWidget);
  }
}

Future<void> _tapAndExpectTexts(
  WidgetTester tester,
  Finder trigger,
  List<String> texts,
) async {
  expect(trigger, findsOneWidget);
  await tester.tap(trigger);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  _expectTexts(texts);
}

Future<void> _tapTextAndPump(
  WidgetTester tester,
  String text, [
  int ms = 300,
]) async {
  await tester.tap(find.text(text));
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

void _expectDefaultBouncyScene({
  required String expectedTitle,
  required IconData hudToggleIcon,
}) {
  expect(find.text(expectedTitle), findsOneWidget);
  expect(find.byType(AdaptiveStressScene), findsOneWidget);
  expect(find.byType(BouncyLayoutMatrix), findsOneWidget);
  expect(find.byType(PerformanceHud), findsOneWidget);
  expect(find.byIcon(hudToggleIcon), findsOneWidget);
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

    _expectDefaultBouncyScene(
      expectedTitle: 'Wasm vs JS',
      hudToggleIcon: Icons.expand_more,
    );
    _expectTexts(['⚡ Wasm', '📜 JS']);

    // Expand HUD
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);

    // Verify compact preset dropdown displays calibrated Bouncy label
    expect(find.text('Medium (64)'), findsOneWidget);

    // Verify compact workload selector button exists and switches workloads
    await _selectWorkload(tester, 'Polymorphic Card Grid');
    expect(find.text('Medium (500)'), findsOneWidget);
  });

  testWidgets('Renders adaptive desktop layout on large viewports (>= 720px)', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);

    _expectDefaultBouncyScene(
      expectedTitle: 'Wasm vs JS Performance',
      hudToggleIcon: Icons.expand_less,
    );
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

    await _tapAndExpectTexts(tester, find.byIcon(Icons.info_outline), [
      'About & Build Info',
      'Flutter Wasm vs JS Performance Comparison Benchmark',
      'Commit',
      'Active Engine',
    ]);

    // Dismiss dialog
    await _tapTextAndPump(tester, 'Close');

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

    await _tapAndExpectTexts(
      tester,
      find.byTooltip('Select Rendering Engine (Impeller [Exp] / Skia / JS)'),
      [
        '⚡ Wasm (Impeller) [Exp]',
        '⚡ Wasm (Skia)',
        '📜 JavaScript (CanvasKit)',
        '📜 JS (WebParagraph) [Exp]',
      ],
    );

    // Tap Wasm Impeller: test stub (non-Chromium) should show SnackBar
    await _tapTextAndPump(tester, '⚡ Wasm (Impeller) [Exp]', 500);
    expect(find.textContaining('requires Chromium'), findsOneWidget);
  });

  testWidgets('BuildInfoDialog renders Wasm + Skia MT and Git info', (
    WidgetTester tester,
  ) async {
    await _pumpBuildInfoDialog(tester, hasGitInfo: true);
    _expectTexts([
      '⚡ WASM + Skia',
      'Skia (skwasm.wasm)',
      'Multi-threaded (Toggle)',
      'Commit',
    ]);
  });

  testWidgets('BuildInfoDialog renders Wasm + Skia ST and handles toggle', (
    WidgetTester tester,
  ) async {
    await _pumpBuildInfoDialog(tester, isSingleThreaded: true);

    expect(find.text('⚡ WASM + Skia (ST)'), findsOneWidget);
    final chip = find.text('Single-threaded (Toggle)');
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pump();
  });

  testWidgets('BuildInfoDialog renders Wasm + Impeller (Exp)', (
    WidgetTester tester,
  ) async {
    await _pumpBuildInfoDialog(tester, isWimp: true);
    _expectTexts([
      '⚡ WASM + Impeller (Exp)',
      'Impeller (wimp.wasm) • Experimental',
      'Single-threaded (forced by engine)',
    ]);
  });

  testWidgets('BuildInfoDialog renders JS + WebParagraph (Exp)', (
    WidgetTester tester,
  ) async {
    await _pumpBuildInfoDialog(tester, isWasm: false, isWebParagraph: true);
    _expectTexts([
      '📜 JS (WebParagraph) [Exp]',
      'CanvasKit (webparagraph/canvaskit.wasm • 3.6MB) • Exp',
      'WebParagraph (Chrome TextCluster API) • Experimental',
    ]);
  });
}
