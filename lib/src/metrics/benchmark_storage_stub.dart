typedef BenchmarkRun = ({
  String mode,
  double fps,
  double buildTimeMs,
  double rasterTimeMs,
  double totalFrameTimeMs,
  double jitterMs,
  String stressLevel,
  int nodeCount,
});

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
  }) {}

  static BenchmarkRun? getRunForMode({
    required String mode,
    String? stressLevel,
    int? nodeCount,
  }) => null;

  static BenchmarkRun? getLastRun({String? stressLevel, int? nodeCount}) =>
      null;
}
