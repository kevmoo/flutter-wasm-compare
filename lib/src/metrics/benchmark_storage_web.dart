import 'dart:convert';

import 'package:web/web.dart' as web;

import 'benchmark_run.dart';
import 'frame_timing_service.dart';

class BenchmarkStorage {
  static const String _activeNodesKey = 'wasm_compare_active_node_count';
  static const String _wasmRunKey = 'wasm_compare_last_wasm_run';
  static const String _jsRunKey = 'wasm_compare_last_js_run';

  static void clearRuns() {
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
    try {
      final storage = web.window.localStorage;
      final activeNodesStr = storage.getItem(_activeNodesKey);
      if (activeNodesStr != null) {
        final activeNodes = int.tryParse(activeNodesStr);
        if (activeNodes != null && activeNodes != currentNodeCount) {
          clearRuns();
        }
      }
    } catch (_) {
      // Ignore
    }
  }

  static void saveMetrics({
    required String mode,
    required FrameTimingMetrics metrics,
    required String stressLevel,
    required int nodeCount,
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
  }) {
    try {
      final storage = web.window.localStorage;

      // Invalidate existing runs if nodeCount changed
      invalidateIfNodeCountChanged(nodeCount);

      // Record new active node count
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
      };
      final jsonStr = jsonEncode(data);

      final normMode = mode.toLowerCase();
      if (normMode == 'wasm') {
        storage.setItem(_wasmRunKey, jsonStr);
      } else {
        storage.setItem(_jsRunKey, jsonStr);
      }
    } catch (_) {
      // Ignore
    }
  }

  static BenchmarkRun? getRunForMode({
    required String mode,
    int? nodeCount,
    String? stressLevel,
  }) {
    try {
      final storage = web.window.localStorage;
      if (!_matchesActiveNodes(storage, nodeCount)) return null;

      final normMode = mode.toLowerCase();
      final key = (normMode == 'wasm') ? _wasmRunKey : _jsRunKey;
      final jsonStr = storage.getItem(key);
      if (jsonStr == null || jsonStr.isEmpty) return null;

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return _parseBenchmarkRun(
        map,
        expectedNodeCount: nodeCount,
        expectedStressLevel: stressLevel,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _matchesActiveNodes(web.Storage storage, int? expectedNodeCount) {
    if (expectedNodeCount == null) return true;
    final activeNodesStr = storage.getItem(_activeNodesKey);
    if (activeNodesStr == null) return true;
    final activeNodes = int.tryParse(activeNodesStr);
    return activeNodes == null || activeNodes == expectedNodeCount;
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

    return (
      mode: runMode,
      fps: fps,
      buildTimeMs: (map['buildTimeMs'] as num?)?.toDouble() ?? 0.0,
      rasterTimeMs: (map['rasterTimeMs'] as num?)?.toDouble() ?? 0.0,
      totalFrameTimeMs: (map['totalFrameTimeMs'] as num?)?.toDouble() ?? 0.0,
      jitterMs: (map['jitterMs'] as num?)?.toDouble() ?? 0.0,
      stressLevel: stress,
      nodeCount: nodes,
    );
  }
}
