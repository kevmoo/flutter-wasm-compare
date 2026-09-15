import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:web/web.dart' as web;

import 'benchmark_run.dart';
import 'frame_timing_service.dart';

class BenchmarkStorage() {
  static const String _activeNodesKey = 'wasm_compare_active_node_count';
  static const String _activeWorkloadKey = 'wasm_compare_active_workload_id';
  static const String _wasmRunKey = 'wasm_compare_last_wasm_run';
  static const String _wimpRunKey = 'wasm_compare_last_wimp_run';
  static const String _jsRunKey = 'wasm_compare_last_js_run';
  static const String _webParagraphRunKey =
      'wasm_compare_last_webparagraph_run';

  static String _nodesKeyFor(String workloadId) =>
      '${_activeNodesKey}_$workloadId';
  static String _runKeyFor(String baseKey, String workloadId) =>
      '${baseKey}_$workloadId';

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
    try {
      final storage = web.window.localStorage;
      for (final workloadId in const ['bouncy', 'grid']) {
        _loadWorkloadFromStorage(storage, workloadId);
      }
    } catch (_) {
      // Ignore
    }
  }

  static void _loadWorkloadFromStorage(web.Storage storage, String workloadId) {
    final nodesStr = storage.getItem(_nodesKeyFor(workloadId));
    final nodes = nodesStr != null ? int.tryParse(nodesStr) : null;
    if (nodes != null) {
      _cachedNodesByWorkload[workloadId] = nodes;
    }

    _loadCachedRun(storage, _wasmRunKey, workloadId, _cachedWasmRuns);
    _loadCachedRun(storage, _wimpRunKey, workloadId, _cachedWimpRuns);
    _loadCachedRun(storage, _jsRunKey, workloadId, _cachedJsRuns);
    _loadCachedRun(
      storage,
      _webParagraphRunKey,
      workloadId,
      _cachedWebParagraphRuns,
    );
  }

  static void _loadCachedRun(
    web.Storage storage,
    String baseKey,
    String workloadId,
    Map<String, BenchmarkRun> targetCache,
  ) {
    final rawStr = storage.getItem(_runKeyFor(baseKey, workloadId));
    if (rawStr == null || rawStr.isEmpty) return;
    final parsed = _parseBenchmarkRun(
      jsonDecode(rawStr) as Map<String, dynamic>,
    );
    if (parsed != null) {
      targetCache[workloadId] = parsed;
    }
  }

  static void clearRuns({String? workloadId}) {
    _ensureCacheLoaded();
    if (workloadId != null) {
      _cachedNodesByWorkload.remove(workloadId);
      _cachedWasmRuns.remove(workloadId);
      _cachedWimpRuns.remove(workloadId);
      _cachedJsRuns.remove(workloadId);
      _cachedWebParagraphRuns.remove(workloadId);
      try {
        final storage = web.window.localStorage;
        storage.removeItem(_nodesKeyFor(workloadId));
        storage.removeItem(_runKeyFor(_wasmRunKey, workloadId));
        storage.removeItem(_runKeyFor(_wimpRunKey, workloadId));
        storage.removeItem(_runKeyFor(_jsRunKey, workloadId));
        storage.removeItem(_runKeyFor(_webParagraphRunKey, workloadId));
      } catch (_) {
        // Ignore
      }
      return;
    }

    _cachedNodesByWorkload.clear();
    _cachedWasmRuns.clear();
    _cachedWimpRuns.clear();
    _cachedJsRuns.clear();
    _cachedWebParagraphRuns.clear();
    _cacheLoaded = true;
    try {
      final storage = web.window.localStorage;
      storage.removeItem(_activeNodesKey);
      storage.removeItem(_activeWorkloadKey);
      storage.removeItem(_wasmRunKey);
      storage.removeItem(_wimpRunKey);
      storage.removeItem(_jsRunKey);
      storage.removeItem(_webParagraphRunKey);
      for (final id in const ['bouncy', 'grid']) {
        storage.removeItem(_nodesKeyFor(id));
        storage.removeItem(_runKeyFor(_wasmRunKey, id));
        storage.removeItem(_runKeyFor(_wimpRunKey, id));
        storage.removeItem(_runKeyFor(_jsRunKey, id));
        storage.removeItem(_runKeyFor(_webParagraphRunKey, id));
      }
    } catch (_) {
      // Ignore
    }
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

    try {
      final storage = web.window.localStorage;
      storage.setItem(_activeNodesKey, '$nodeCount');
      storage.setItem(_nodesKeyFor(workloadId), '$nodeCount');
      storage.setItem(_activeWorkloadKey, workloadId);

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
      final jsonStr = jsonEncode(data);
      storage.setItem(baseKey, jsonStr);
      storage.setItem(_runKeyFor(baseKey, workloadId), jsonStr);
    } catch (_) {
      // Ignore
    }
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
    final BenchmarkRun? run;
    switch (normMode) {
      case 'wimp' || 'impeller':
        run = _cachedWimpRuns[id];
      case 'wasm' || 'skwasm':
        run = _cachedWasmRuns[id];
      case 'webparagraph' || 'js-webparagraph' || 'canvaskit-webparagraph':
        run = _cachedWebParagraphRuns[id];
      case 'js' || 'canvaskit':
        run = _cachedJsRuns[id];
      default:
        run = null;
    }
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
