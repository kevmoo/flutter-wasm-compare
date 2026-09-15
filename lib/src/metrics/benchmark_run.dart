class BenchmarkRun({
  required final String mode,
  required final double fps,
  required final double buildTimeMs,
  required final double rasterTimeMs,
  required final double totalFrameTimeMs,
  final double jitterMs = 0.0,
  final String stressLevel = 'medium',
  final int nodeCount = 200,
  final String workloadId = 'bouncy',
  bool? isPipelined,
}) {
  final bool isPipelined =
      isPipelined ??
      (mode.toLowerCase() == 'wasm' || mode.toLowerCase() == 'wimp');

  static BenchmarkRun sample(
    String mode,
    double fps,
    double buildTimeMs,
    double rasterTimeMs,
    double totalFrameTimeMs,
    double jitterMs, {
    String stressLevel = 'medium',
    int nodeCount = 500,
    String workloadId = 'bouncy',
    bool? isPipelined,
  }) => BenchmarkRun(
    mode: mode,
    fps: fps,
    buildTimeMs: buildTimeMs,
    rasterTimeMs: rasterTimeMs,
    totalFrameTimeMs: totalFrameTimeMs,
    jitterMs: jitterMs,
    stressLevel: stressLevel,
    nodeCount: nodeCount,
    workloadId: workloadId,
    isPipelined: isPipelined,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'fps': fps,
    'buildTimeMs': buildTimeMs,
    'rasterTimeMs': rasterTimeMs,
    'totalFrameTimeMs': totalFrameTimeMs,
    'jitterMs': jitterMs,
    'stressLevel': stressLevel,
    'nodeCount': nodeCount,
    'workloadId': workloadId,
    'isPipelined': isPipelined,
  };

  static BenchmarkRun? fromJson(
    Map<String, dynamic> map, {
    int? expectedNodeCount,
    String? expectedStressLevel,
  }) {
    final nodes = (map['nodeCount'] as num?)?.toInt() ?? 500;
    if (expectedNodeCount != null && nodes != expectedNodeCount) return null;

    final stress = (map['stressLevel'] as String?) ?? 'medium';
    if (expectedStressLevel != null &&
        stress.toLowerCase() != expectedStressLevel.toLowerCase()) {
      return null;
    }

    final workloadId = (map['workloadId'] as String?) ?? 'bouncy';
    final runMode = map['mode'] as String?;
    final fps = (map['fps'] as num?)?.toDouble();
    if (runMode == null || fps == null) return null;

    return BenchmarkRun(
      mode: runMode,
      fps: fps,
      buildTimeMs: (map['buildTimeMs'] as num?)?.toDouble() ?? 0.0,
      rasterTimeMs: (map['rasterTimeMs'] as num?)?.toDouble() ?? 0.0,
      totalFrameTimeMs: (map['totalFrameTimeMs'] as num?)?.toDouble() ?? 0.0,
      jitterMs: (map['jitterMs'] as num?)?.toDouble() ?? 0.0,
      stressLevel: stress,
      nodeCount: nodes,
      workloadId: workloadId,
      isPipelined: map['isPipelined'] as bool?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BenchmarkRun &&
      mode == other.mode &&
      fps == other.fps &&
      buildTimeMs == other.buildTimeMs &&
      rasterTimeMs == other.rasterTimeMs &&
      totalFrameTimeMs == other.totalFrameTimeMs &&
      jitterMs == other.jitterMs &&
      stressLevel == other.stressLevel &&
      nodeCount == other.nodeCount &&
      workloadId == other.workloadId &&
      isPipelined == other.isPipelined;

  @override
  int get hashCode => Object.hash(
    mode,
    fps,
    buildTimeMs,
    rasterTimeMs,
    totalFrameTimeMs,
    jitterMs,
    stressLevel,
    nodeCount,
    workloadId,
    isPipelined,
  );
}
