typedef BenchmarkRun = ({
  String mode,
  double fps,
  double buildTimeMs,
  double rasterTimeMs,
  double totalFrameTimeMs,
  double jitterMs,
  double? startupTimeMs,
  String stressLevel,
  int nodeCount,
});

class BenchmarkStorage {
  static void saveStartupTime({
    required String mode,
    required double startupTimeMs,
  }) {}

  static double? getStartupTime({required String mode}) => null;

  static void saveRun({
    required String mode,
    required double fps,
    required double buildTimeMs,
    required double rasterTimeMs,
    required double totalFrameTimeMs,
    double jitterMs = 0.0,
    double? startupTimeMs,
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
