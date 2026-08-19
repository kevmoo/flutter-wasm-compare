import 'dart:convert';

import 'package:web/web.dart' as web;

import 'benchmark_run.dart';
import 'frame_timing_service.dart';

class BenchmarkStorage {
  static const String _activeNodesKey = 'wasm_compare_active_node_count';
  static const String _wasmRunKey = 'wasm_compare_last_wasm_run';
  static const String _jsRunKey = 'wasm_compare_last_js_run';

  static int? _cachedActiveNodes;
  static BenchmarkRun? _cachedWasmRun;
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

      final wasmStr = storage.getItem(_wasmRunKey);
      if (wasmStr != null && wasmStr.isNotEmpty) {
        _cachedWasmRun = _parseBenchmarkRun(
          jsonDecode(wasmStr) as Map<String, dynamic>,
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
    _cachedWasmRun = null;
    _cachedJsRun = null;
    _cacheLoaded = true;
    try {
      final storage = web.window.localStorage;
      storage.removeItem(_activeNodesKey);
      storage.removeItem(_wasmRunKey);
      storage.removeItem(_jsRunKey);
    } catch (_) {
      // Ignore
    }
  }

  static void invalidateIfNodeCountChanged(int currentNodeCount) {
    _ensureCacheLoaded();
    if (_cachedActiveNodes != null && _cachedActiveNodes != currentNodeCount) {
      clearRuns();
    }
  }

  static void saveMetrics({
    required String mode,
    required FrameTimingMetrics metrics,
    required String stressLevel,
    required int nodeCount,
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
      isPipelined: isPipelined ?? (mode.toLowerCase() == 'wasm'),
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
    bool isPipelined = false,
  }) {
    invalidateIfNodeCountChanged(nodeCount);
    _cachedActiveNodes = nodeCount;

    final run = (
      mode: mode,
      fps: fps,
      buildTimeMs: buildTimeMs,
      rasterTimeMs: rasterTimeMs,
      totalFrameTimeMs: totalFrameTimeMs,
      jitterMs: jitterMs,
      stressLevel: stressLevel,
      nodeCount: nodeCount,
      isPipelined: isPipelined,
    );

    final normMode = mode.toLowerCase();
    if (normMode == 'wasm') {
      _cachedWasmRun = run;
    } else {
      _cachedJsRun = run;
    }

    try {
      final storage = web.window.localStorage;
      storage.setItem(_activeNodesKey, '$nodeCount');

      final data = {
        'mode': mode,
        'fps': fps,
        'buildTimeMs': buildTimeMs,
        'rasterTimeMs': rasterTimeMs,
        'totalFrameTimeMs': totalFrameTimeMs,
        'jitterMs': jitterMs,
        'stressLevel': stressLevel,
        'nodeCount': nodeCount,
        'isPipelined': isPipelined,
      };
      final jsonStr = jsonEncode(data);
      storage.setItem(normMode == 'wasm' ? _wasmRunKey : _jsRunKey, jsonStr);
    } catch (_) {
      // Ignore
    }
  }

  static BenchmarkRun? getRunForMode({
    required String mode,
    int? nodeCount,
    String? stressLevel,
  }) {
    _ensureCacheLoaded();

    if (nodeCount != null &&
        _cachedActiveNodes != null &&
        _cachedActiveNodes != nodeCount) {
      return null;
    }

    final normMode = mode.toLowerCase();
    final run = (normMode == 'wasm') ? _cachedWasmRun : _cachedJsRun;
    if (run == null) return null;

    if (nodeCount != null && run.nodeCount != nodeCount) return null;
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
      isPipelined: isPipelined,
    );
  }
}
