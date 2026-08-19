import 'benchmark_run.dart';
import 'frame_timing_service.dart';

class BenchmarkStorage {
  static void clearRuns() {}

  static void invalidateIfNodeCountChanged(int currentNodeCount) {}

  static void saveRun({
    required String mode,
    required double fps,
    required double buildTimeMs,
    required double rasterTimeMs,
    required double totalFrameTimeMs,
    double jitterMs = 0.0,
    required String stressLevel,
    required int nodeCount,
    bool isPipelined = false,
  }) {}

  static void saveMetrics({
    required String mode,
    required FrameTimingMetrics metrics,
    required String stressLevel,
    required int nodeCount,
    bool? isPipelined,
  }) {}

  static BenchmarkRun? getRunForMode({
    required String mode,
    String? stressLevel,
    int? nodeCount,
  }) => null;
}
