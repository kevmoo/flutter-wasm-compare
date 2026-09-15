import 'dart:convert';

import 'package:meta/meta.dart';

import 'benchmark_run.dart';
import 'benchmark_storage_stub.dart'
    if (dart.library.js_interop) 'benchmark_storage_web.dart';
import 'frame_timing_service.dart';

export 'benchmark_run.dart';

class BenchmarkStorage() {
  static const String _wasmRunKey = 'wasm_compare_last_wasm_run';
  static const String _wimpRunKey = 'wasm_compare_last_wimp_run';
  static const String _jsRunKey = 'wasm_compare_last_js_run';
  static const String _webParagraphRunKey =
      'wasm_compare_last_webparagraph_run';

  static final Map<String, int> _cachedNodesByWorkload = {};
  static final Map<String, BenchmarkRun> _cachedWasmRuns = {};
  static final Map<String, BenchmarkRun> _cachedWimpRuns = {};
  static final Map<String, BenchmarkRun> _cachedJsRuns = {};
  static final Map<String, BenchmarkRun> _cachedWebParagraphRuns = {};
  static bool _cacheLoaded = false;

  @visibleForTesting
  static void resetInMemoryCacheForTesting() {
    _cachedNodesByWorkload.clear();
    _cachedWasmRuns.clear();
    _cachedWimpRuns.clear();
    _cachedJsRuns.clear();
    _cachedWebParagraphRuns.clear();
    _cacheLoaded = false;
  }

  static void _ensureCacheLoaded() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    BenchmarkStoragePersistence.loadAll(
      _cachedNodesByWorkload,
      _cachedWasmRuns,
      _cachedWimpRuns,
      _cachedJsRuns,
      _cachedWebParagraphRuns,
      _parseBenchmarkRun,
    );
  }

  static void clearRuns({String? workloadId}) {
    _ensureCacheLoaded();
    if (workloadId != null) {
      _cachedNodesByWorkload.remove(workloadId);
      _cachedWasmRuns.remove(workloadId);
      _cachedWimpRuns.remove(workloadId);
      _cachedJsRuns.remove(workloadId);
      _cachedWebParagraphRuns.remove(workloadId);
      BenchmarkStoragePersistence.clearWorkload(workloadId);
      return;
    }

    _cachedNodesByWorkload.clear();
    _cachedWasmRuns.clear();
    _cachedWimpRuns.clear();
    _cachedJsRuns.clear();
    _cachedWebParagraphRuns.clear();
    _cacheLoaded = true;
    BenchmarkStoragePersistence.clearAll();
  }

  static void invalidateIfNodeCountChanged(
    int currentNodeCount, {
    String? workloadId,
  }) {
    _ensureCacheLoaded();
    final id = workloadId ?? 'bouncy';
    final prevNodes = _cachedNodesByWorkload[id];
    if (prevNodes != null && prevNodes != currentNodeCount) {
      clearRuns(workloadId: id);
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
    final normMode = mode.toLowerCase();
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
      isPipelined: isPipelined ?? (normMode == 'wasm'),
    );
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

    final normMode = mode.toLowerCase();
    final String baseKey;
    switch (normMode) {
      case 'wimp' || 'impeller':
        _cachedWimpRuns[workloadId] = run;
        baseKey = _wimpRunKey;
      case 'wasm' || 'skwasm':
        _cachedWasmRuns[workloadId] = run;
        baseKey = _wasmRunKey;
      case 'webparagraph' || 'js-webparagraph' || 'canvaskit-webparagraph':
        _cachedWebParagraphRuns[workloadId] = run;
        baseKey = _webParagraphRunKey;
      case 'js' || 'canvaskit':
        _cachedJsRuns[workloadId] = run;
        baseKey = _jsRunKey;
      default:
        throw ArgumentError.value(
          mode,
          'mode',
          'Unsupported benchmark engine mode',
        );
    }

    final data = {
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
    BenchmarkStoragePersistence.saveRun(
      baseKey: baseKey,
      workloadId: workloadId,
      nodeCount: nodeCount,
      jsonStr: jsonEncode(data),
    );
  }

  static BenchmarkRun? getRunForMode({
    required String mode,
    int? nodeCount,
    String? stressLevel,
    String? workloadId,
  }) {
    _ensureCacheLoaded();
    final id = workloadId ?? 'bouncy';
    final cachedNodes = _cachedNodesByWorkload[id];
    if (nodeCount != null && cachedNodes != null && cachedNodes != nodeCount) {
      return null;
    }

    final normMode = mode.toLowerCase();
    final run = switch (normMode) {
      'wimp' || 'impeller' => _cachedWimpRuns[id],
      'wasm' || 'skwasm' => _cachedWasmRuns[id],
      'webparagraph' ||
      'js-webparagraph' ||
      'canvaskit-webparagraph' => _cachedWebParagraphRuns[id],
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

  static BenchmarkRun? _parseBenchmarkRun(
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

    final isPipelined =
        (map['isPipelined'] as bool?) ?? (runMode.toLowerCase() == 'wasm');

    return (
      mode: runMode,
      fps: fps,
      buildTimeMs: (map['buildTimeMs'] as num?)?.toDouble() ?? 0.0,
      rasterTimeMs: (map['rasterTimeMs'] as num?)?.toDouble() ?? 0.0,
      totalFrameTimeMs: (map['totalFrameTimeMs'] as num?)?.toDouble() ?? 0.0,
      jitterMs: (map['jitterMs'] as num?)?.toDouble() ?? 0.0,
      stressLevel: stress,
      nodeCount: nodes,
      workloadId: workloadId,
      isPipelined: isPipelined,
    );
  }
}
