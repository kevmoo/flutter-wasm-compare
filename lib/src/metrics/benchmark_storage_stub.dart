typedef BenchmarkRun = ({
  String mode,
  double fps,
  double buildTimeMs,
  double rasterTimeMs,
  double totalFrameTimeMs,
  String stressLevel,
});

class BenchmarkStorage {
  static void saveRun({
    required String mode,
    required double fps,
    required double buildTimeMs,
    required double rasterTimeMs,
    required double totalFrameTimeMs,
    required String stressLevel,
  }) {}

  static BenchmarkRun? getLastRun({String? stressLevel}) => null;
}
