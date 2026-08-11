typedef BenchmarkRun = ({
  String mode,
  double fps,
  double buildTimeMs,
  double rasterTimeMs,
  double totalFrameTimeMs,
  String stressLevel,
  int nodeCount,
});

class BenchmarkStorage {
  static void saveRun({
    required String mode,
    required double fps,
    required double buildTimeMs,
    required double rasterTimeMs,
    required double totalFrameTimeMs,
    required String stressLevel,
    required int nodeCount,
  }) {}

  static BenchmarkRun? getLastRun({String? stressLevel, int? nodeCount}) =>
      null;
}
