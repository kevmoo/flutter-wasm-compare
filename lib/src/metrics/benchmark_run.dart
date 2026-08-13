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
