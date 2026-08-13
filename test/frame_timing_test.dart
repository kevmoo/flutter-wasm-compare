import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasm_compare/src/metrics/frame_timing_service.dart';

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
}
