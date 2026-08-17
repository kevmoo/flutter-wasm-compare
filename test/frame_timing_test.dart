import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasm_compare/src/metrics/frame_timing_service.dart';
import 'package:wasm_compare/src/shell/performance_hud.dart';

FrameTiming _makeTiming({
  required int buildStartUs,
  int buildDurationUs = 4000,
  int rasterDurationUs = 3000,
}) {
  final finish = buildStartUs + buildDurationUs + 500 + rasterDurationUs;
  return FrameTiming(
    vsyncStart: buildStartUs,
    buildStart: buildStartUs,
    buildFinish: buildStartUs + buildDurationUs,
    rasterStart: buildStartUs + buildDurationUs + 500,
    rasterFinish: finish,
    rasterFinishWallTime: finish,
  );
}

void main() {
  group('FrameTimingMetrics activeFrameTimeMs', () {
    test('computes max(build, raster) when isPipelined is true (Wasm)', () {
      final metrics = FrameTimingMetrics(
        fps: 60.0,
        buildTimeMs: 11.7,
        rasterTimeMs: 6.0,
        totalFrameTimeMs: 18.0,
      );

      expect(metrics.activeFrameTimeMs(isPipelined: true), equals(11.7));
    });

    test('computes build + raster when isPipelined is false (JS)', () {
      final metrics = FrameTimingMetrics(
        fps: 27.3,
        buildTimeMs: 30.9,
        rasterTimeMs: 3.9,
        totalFrameTimeMs: 36.4,
      );

      expect(
        metrics.activeFrameTimeMs(isPipelined: false),
        closeTo(34.8, 0.01),
      );
    });

    test('handles raster-heavy frames in pipelined mode', () {
      final metrics = FrameTimingMetrics(
        fps: 60.0,
        buildTimeMs: 4.5,
        rasterTimeMs: 12.8,
        totalFrameTimeMs: 17.5,
      );

      expect(metrics.activeFrameTimeMs(isPipelined: true), equals(12.8));
    });
  });

  group('FrameTimingService pacing jitter', () {
    test('reports near-zero jitter for smooth, evenly paced frames', () {
      // Simulate 10 frames at exact 16.666ms (16666us) intervals
      final timings = <FrameTiming>[];
      for (var i = 0; i < 10; i++) {
        timings.add(_makeTiming(buildStartUs: i * 16666));
      }

      final metrics = FrameTimingService.calculateMetricsForSliceForTest(
        timings,
      );
      expect(metrics.jitterMs, closeTo(0.0, 0.01));
      expect(metrics.fps, closeTo(60.0, 0.1));
    });

    test(
      'reports elevated jitter when frame intervals fluctuate (hitching)',
      () {
        // Simulate alternating intervals: 16.6ms then 33.3ms (dropped frame)
        final timings = <FrameTiming>[];
        var currentUs = 0;
        for (var i = 0; i < 10; i++) {
          timings.add(_makeTiming(buildStartUs: currentUs));
          currentUs += (i.isEven ? 16666 : 33333);
        }

        final metrics = FrameTimingService.calculateMetricsForSliceForTest(
          timings,
        );
        expect(metrics.jitterMs, greaterThan(5.0));
      },
    );

    test('ignores pause gaps from tab switching or backgrounding '
        'in FPS calculation', () {
      // 5 frames at 60 FPS (16.6ms intervals), then a 5-second tab blur pause,
      // then 5 frames at 60 FPS.
      final timings = <FrameTiming>[];
      var currentUs = 0;

      void addFrames(int count) {
        for (var i = 0; i < count; i++) {
          timings.add(_makeTiming(buildStartUs: currentUs));
          currentUs += 16666;
        }
      }

      addFrames(5);
      // 5 second pause (5000000us)
      currentUs += 5000000;
      addFrames(5);

      final metrics = FrameTimingService.calculateMetricsForSliceForTest(
        timings,
      );
      expect(metrics.fps, closeTo(60.0, 0.5));
    });
  });

  group('PerformanceHud evaluateComparisonForTest', () {
    const jsSavedRun = (
      mode: 'js',
      fps: 28.0,
      buildTimeMs: 28.0,
      rasterTimeMs: 4.0,
      totalFrameTimeMs: 33.6,
      jitterMs: 5.2,
      stressLevel: 'Manual (200)',
      nodeCount: 200,
    );

    const wasmSavedRun = (
      mode: 'wasm',
      fps: 60.0,
      buildTimeMs: 11.0,
      rasterTimeMs: 4.5,
      totalFrameTimeMs: 16.0,
      jitterMs: 0.3,
      stressLevel: 'Manual (200)',
      nodeCount: 200,
    );

    test('generates both speed and jitter benefit badges when Wasm leads', () {
      // Live WASM (active: 11.0ms, jitter: 0.3ms) vs
      // Saved JS (active: 32.0ms, jitter: 5.2ms)
      final comparison = evaluateComparisonForTest(
        currentActive: 11.0,
        currentJitter: 0.3,
        currentFps: 60.0,
        targetRefreshRate: 60.0,
        wasmRun: wasmSavedRun,
        jsRun: jsSavedRun,
        isCurrentWasm: true,
        nodeCount: 200,
      );

      expect(comparison.hasBothRuns, isTrue);
      expect(comparison.speedBadge, isNotNull);
      expect(comparison.speedBadge?.title, equals('⚡ Wasm 2.9x Faster'));
      expect(comparison.speedBadge?.detail, equals('11.0ms vs 32.0ms'));

      expect(comparison.jitterBadge, isNotNull);
      expect(comparison.jitterBadge?.title, equals('🎯 Wasm 17x Smoother'));
      expect(comparison.jitterBadge?.detail, equals('±0.3ms vs ±5.2ms'));

      expect(comparison.promptBadge, isNull);
      expect(comparison.budgetPct, equals('66')); // 11.0 / 16.666ms = 66%
    });

    test('does not show badges when Wasm is worse or same', () {
      const fasterJsRun = (
        mode: 'js',
        fps: 60.0,
        buildTimeMs: 8.0,
        rasterTimeMs: 4.0,
        totalFrameTimeMs: 13.0,
        jitterMs: 0.2,
        stressLevel: 'Manual (200)',
        nodeCount: 200,
      );

      final comparison = evaluateComparisonForTest(
        currentActive: 15.0,
        currentJitter: 1.5,
        currentFps: 50.0,
        targetRefreshRate: 60.0,
        wasmRun: null,
        jsRun: fasterJsRun,
        isCurrentWasm: true,
        nodeCount: 200,
      );

      expect(comparison.hasBothRuns, isTrue);
      expect(comparison.speedBadge, isNull);
      expect(comparison.jitterBadge, isNull);
      expect(comparison.promptBadge, isNull);
    });

    test('shows only speed badge when jitter is not significantly better', () {
      const similarJitterJsRun = (
        mode: 'js',
        fps: 30.0,
        buildTimeMs: 25.0,
        rasterTimeMs: 5.0,
        totalFrameTimeMs: 32.0,
        jitterMs: 0.35,
        stressLevel: 'Manual (200)',
        nodeCount: 200,
      );

      final comparison = evaluateComparisonForTest(
        currentActive: 11.0,
        currentJitter: 0.32,
        currentFps: 60.0,
        targetRefreshRate: 60.0,
        wasmRun: wasmSavedRun,
        jsRun: similarJitterJsRun,
        isCurrentWasm: true,
        nodeCount: 200,
      );

      expect(comparison.hasBothRuns, isTrue);
      expect(comparison.speedBadge, isNotNull);
      expect(comparison.speedBadge?.title, equals('⚡ Wasm 2.7x Faster'));
      expect(comparison.speedBadge?.detail, equals('11.0ms vs 30.0ms'));
      expect(comparison.jitterBadge, isNull);
    });

    test('prompts to switch engines when other run is missing', () {
      final comparison = evaluateComparisonForTest(
        currentActive: 11.0,
        currentJitter: 0.3,
        currentFps: 60.0,
        targetRefreshRate: 60.0,
        wasmRun: null,
        jsRun: null,
        isCurrentWasm: true,
        nodeCount: 200,
      );

      expect(comparison.hasBothRuns, isFalse);
      expect(comparison.speedBadge, isNull);
      expect(comparison.jitterBadge, isNull);
      expect(
        comparison.promptBadge,
        equals('⏳ Switch to JS to test at 200 nodes'),
      );
    });
  });
}
