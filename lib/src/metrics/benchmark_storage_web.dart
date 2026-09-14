import 'dart:convert';

import 'package:web/web.dart' as web;

import 'benchmark_run.dart';
import 'frame_timing_service.dart';

class BenchmarkStorage {
  static const String _activeNodesKey = 'wasm_compare_active_node_count';
  static const String _activeWorkloadKey = 'wasm_compare_active_workload_id';
  static const String _wasmRunKey = 'wasm_compare_last_wasm_run';
  static const String _wimpRunKey = 'wasm_compare_last_wimp_run';
  static const String _jsRunKey = 'wasm_compare_last_js_run';

  static int? _cachedActiveNodes;
  static String? _cachedActiveWorkloadId;
  static BenchmarkRun? _cachedWasmRun;
  static BenchmarkRun? _cachedWimpRun;
  static BenchmarkRun? _cachedJsRun;
  static bool _cacheLoaded = false;

  static void _ensureCacheLoaded() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final storage = web.window.localStorage;
      final activeNodesStr = storage.getItem(_activeNodesKey);
      _cachedActiveNodes = activeNodesStr != null
          ? int.tryParse(activeNodesStr)
          : null;
      _cachedActiveWorkloadId = storage.getItem(_activeWorkloadKey);

      final wasmStr = storage.getItem(_wasmRunKey);
      if (wasmStr != null && wasmStr.isNotEmpty) {
        _cachedWasmRun = _parseBenchmarkRun(
          jsonDecode(wasmStr) as Map<String, dynamic>,
        );
      }

      final wimpStr = storage.getItem(_wimpRunKey);
      if (wimpStr != null && wimpStr.isNotEmpty) {
        _cachedWimpRun = _parseBenchmarkRun(
          jsonDecode(wimpStr) as Map<String, dynamic>,
        );
      }

      final jsStr = storage.getItem(_jsRunKey);
      if (jsStr != null && jsStr.isNotEmpty) {
        _cachedJsRun = _parseBenchmarkRun(
          jsonDecode(jsStr) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Ignore
    }
  }

  static void clearRuns() {
    _cachedActiveNodes = null;
    _cachedActiveWorkloadId = null;
    _cachedWasmRun = null;
    _cachedWimpRun = null;
    _cachedJsRun = null;
    _cacheLoaded = true;
    try {
      final storage = web.window.localStorage;
      storage.removeItem(_activeNodesKey);
      storage.removeItem(_activeWorkloadKey);
      storage.removeItem(_wasmRunKey);
      storage.removeItem(_wimpRunKey);
      storage.removeItem(_jsRunKey);
    } catch (_) {
      // Ignore
    }
  }

  static void invalidateIfNodeCountChanged(
    int currentNodeCount, {
    String? workloadId,
  }) {
    _ensureCacheLoaded();
    final nodesChanged =
        _cachedActiveNodes != null && _cachedActiveNodes != currentNodeCount;
    final workloadChanged =
        workloadId != null &&
        _cachedActiveWorkloadId != null &&
        _cachedActiveWorkloadId != workloadId;
    if (nodesChanged || workloadChanged) {
      clearRuns();
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
    _cachedActiveNodes = nodeCount;
    _cachedActiveWorkloadId = workloadId;

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
    final String storageKey;
    switch (normMode) {
      case 'wimp' || 'impeller':
        _cachedWimpRun = run;
        storageKey = _wimpRunKey;
      case 'wasm' || 'skwasm':
        _cachedWasmRun = run;
        storageKey = _wasmRunKey;
      case 'js' || 'canvaskit':
        _cachedJsRun = run;
        storageKey = _jsRunKey;
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
      storage.setItem(storageKey, jsonStr);
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

    if (nodeCount != null &&
        _cachedActiveNodes != null &&
        _cachedActiveNodes != nodeCount) {
      return null;
    }

    if (workloadId != null &&
        _cachedActiveWorkloadId != null &&
        _cachedActiveWorkloadId != workloadId) {
      return null;
    }

    final normMode = mode.toLowerCase();
    final BenchmarkRun? run;
    switch (normMode) {
      case 'wimp' || 'impeller':
        run = _cachedWimpRun;
      case 'wasm' || 'skwasm':
        run = _cachedWasmRun;
      case 'js' || 'canvaskit':
        run = _cachedJsRun;
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
