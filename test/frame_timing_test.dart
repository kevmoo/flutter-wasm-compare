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

    test('computes speedup multiplier comparing totalFrameTimeMs', () {
      // Live WASM (total: 16.0ms) vs Saved JS (total: 33.6ms) -> 33.6 / 16.0 = 2.1x
      final comparison = evaluateComparisonForTest(
        currentActive: 11.0,
        currentTotal: 16.0,
        currentFps: 60.0,
        targetRefreshRate: 60.0,
        wasmRun: wasmSavedRun,
        jsRun: jsSavedRun,
        isCurrentWasm: true,
        nodeCount: 200,
      );

      expect(comparison.hasBothRuns, isTrue);
      expect(comparison.isWasmFaster, isTrue);
      expect(comparison.speedupBadge, equals('⚡ 2.1x Faster Frame Time'));
      expect(comparison.budgetPct, equals('66')); // 11.0 / 16.666ms = 66%
    });

    test('identifies when JS totalFrameTimeMs is faster', () {
      const slowerWasmRun = (
        mode: 'wasm',
        fps: 30.0,
        buildTimeMs: 25.0,
        rasterTimeMs: 5.0,
        totalFrameTimeMs: 30.0,
        jitterMs: 1.0,
        stressLevel: 'Manual (200)',
        nodeCount: 200,
      );

      final comparison = evaluateComparisonForTest(
        currentActive: 12.0,
        currentTotal: 15.0,
        currentFps: 60.0,
        targetRefreshRate: 60.0,
        wasmRun: slowerWasmRun,
        jsRun: null,
        isCurrentWasm: false,
        nodeCount: 200,
      );

      expect(comparison.hasBothRuns, isTrue);
      expect(comparison.isWasmFaster, isFalse);
      expect(comparison.speedupBadge, equals('⚡ JS is 2.0x Faster Frame Time'));
    });

    test('reports identical frame time when within 5% ratio', () {
      const similarJsRun = (
        mode: 'js',
        fps: 60.0,
        buildTimeMs: 10.0,
        rasterTimeMs: 4.0,
        totalFrameTimeMs: 16.2,
        jitterMs: 0.5,
        stressLevel: 'Manual (200)',
        nodeCount: 200,
      );

      final comparison = evaluateComparisonForTest(
        currentActive: 10.0,
        currentTotal: 16.0,
        currentFps: 60.0,
        targetRefreshRate: 60.0,
        wasmRun: null,
        jsRun: similarJsRun,
        isCurrentWasm: true,
        nodeCount: 200,
      );

      expect(comparison.hasBothRuns, isTrue);
      expect(
        comparison.speedupBadge,
        equals('⚡ Identical Frame Time (16.0 ms)'),
      );
    });

    test('prompts to switch engines when other run is missing', () {
      final comparison = evaluateComparisonForTest(
        currentActive: 11.0,
        currentTotal: 16.0,
        currentFps: 60.0,
        targetRefreshRate: 60.0,
        wasmRun: null,
        jsRun: null,
        isCurrentWasm: true,
        nodeCount: 200,
      );

      expect(comparison.hasBothRuns, isFalse);
      expect(
        comparison.speedupBadge,
        equals('⏳ Switch to JS to test at 200 nodes'),
      );
    });
  });
}
