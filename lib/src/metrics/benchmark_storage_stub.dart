import 'benchmark_run.dart';
import 'frame_timing_service.dart';

class BenchmarkStorage {
  static final Map<String, int> _cachedNodesByWorkload = {};
  static final Map<String, BenchmarkRun> _cachedWasmRuns = {};
  static final Map<String, BenchmarkRun> _cachedWimpRuns = {};
  static final Map<String, BenchmarkRun> _cachedJsRuns = {};

  static void resetInMemoryCacheForTesting() {
    _cachedNodesByWorkload.clear();
    _cachedWasmRuns.clear();
    _cachedWimpRuns.clear();
    _cachedJsRuns.clear();
  }

  static void clearRuns({String? workloadId}) {
    if (workloadId != null) {
      _cachedNodesByWorkload.remove(workloadId);
      _cachedWasmRuns.remove(workloadId);
      _cachedWimpRuns.remove(workloadId);
      _cachedJsRuns.remove(workloadId);
      return;
    }
    _cachedNodesByWorkload.clear();
    _cachedWasmRuns.clear();
    _cachedWimpRuns.clear();
    _cachedJsRuns.clear();
  }

  static void invalidateIfNodeCountChanged(
    int currentNodeCount, {
    String? workloadId,
  }) {
    final id = workloadId ?? 'bouncy';
    final prevNodes = _cachedNodesByWorkload[id];
    if (prevNodes != null && prevNodes != currentNodeCount) {
      clearRuns(workloadId: id);
    }
  }

  static void saveRun({
    required String mode,
    required double fps,
    required double buildTimeMs,
    required double rasterTimeMs,
    required double totalFrameTimeMs,
    double jitterMs = 0.0,
    required String stressLevel,
    required int nodeCount,
    String workloadId = 'bouncy',
    bool isPipelined = false,
  }) {
    invalidateIfNodeCountChanged(nodeCount, workloadId: workloadId);
    _cachedNodesByWorkload[workloadId] = nodeCount;
    final run = (
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
    switch (mode.toLowerCase()) {
      case 'wimp' || 'impeller':
        _cachedWimpRuns[workloadId] = run;
      case 'wasm' || 'skwasm':
        _cachedWasmRuns[workloadId] = run;
      case 'js' || 'canvaskit':
        _cachedJsRuns[workloadId] = run;
    }
  }

  static void saveMetrics({
    required String mode,
    required FrameTimingMetrics metrics,
    required String stressLevel,
    required int nodeCount,
    String workloadId = 'bouncy',
    bool? isPipelined,
  }) {
    saveRun(
      mode: mode,
      fps: metrics.fps,
      buildTimeMs: metrics.buildTimeMs,
      rasterTimeMs: metrics.rasterTimeMs,
      totalFrameTimeMs: metrics.totalFrameTimeMs,
      jitterMs: metrics.jitterMs,
      stressLevel: stressLevel,
      nodeCount: nodeCount,
      workloadId: workloadId,
      isPipelined: isPipelined ?? (mode.toLowerCase() == 'wasm'),
    );
  }

  static BenchmarkRun? getRunForMode({
    required String mode,
    String? stressLevel,
    int? nodeCount,
    String? workloadId,
  }) {
    final id = workloadId ?? 'bouncy';
    final cachedNodes = _cachedNodesByWorkload[id];
    if (nodeCount != null && cachedNodes != null && cachedNodes != nodeCount) {
      return null;
    }
    final run = switch (mode.toLowerCase()) {
      'wimp' || 'impeller' => _cachedWimpRuns[id],
      'wasm' || 'skwasm' => _cachedWasmRuns[id],
      'js' || 'canvaskit' => _cachedJsRuns[id],
      _ => null,
    };
    if (run == null) return null;
    if (nodeCount != null && run.nodeCount != nodeCount) return null;
    if (workloadId != null && run.workloadId != workloadId) return null;
    if (stressLevel != null &&
        run.stressLevel.toLowerCase() != stressLevel.toLowerCase()) {
      return null;
    }
    return run;
  }
}
