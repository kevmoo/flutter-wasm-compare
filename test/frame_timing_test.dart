import 'package:flutter_test/flutter_test.dart';
import 'package:wasm_compare/src/metrics/frame_timing_service.dart';

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
}
