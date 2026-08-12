import 'dart:convert';

import 'package:web/web.dart' as web;

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
  static const String _startupPrefix = 'wasm_compare_startup_';
  static const String _activeNodesKey = 'wasm_compare_active_node_count';
  static const String _wasmRunKey = 'wasm_compare_last_wasm_run';
  static const String _jsRunKey = 'wasm_compare_last_js_run';

  static void saveStartupTime({
    required String mode,
    required double startupTimeMs,
  }) {
    try {
      final storage = web.window.localStorage;
      final normMode = mode.toLowerCase();
      storage.setItem(
        '$_startupPrefix$normMode',
        startupTimeMs.toStringAsFixed(1),
      );
    } catch (_) {
      // Ignore
    }
  }

  static double? getStartupTime({required String mode}) {
    try {
      final storage = web.window.localStorage;
      final normMode = mode.toLowerCase();
      final str = storage.getItem('$_startupPrefix$normMode');
      if (str == null || str.isEmpty) return null;
      return double.tryParse(str);
    } catch (_) {
      return null;
    }
  }

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
  }) {
    try {
      final storage = web.window.localStorage;

      // Invalidate existing runs if nodeCount changed
      final activeNodesStr = storage.getItem(_activeNodesKey);
      if (activeNodesStr != null) {
        final activeNodes = int.tryParse(activeNodesStr);
        if (activeNodes != null && activeNodes != nodeCount) {
          clearRuns();
        }
      }

      // Record new active node count
      storage.setItem(_activeNodesKey, '$nodeCount');

      final data = {
        'mode': mode,
        'fps': fps,
        'buildTimeMs': buildTimeMs,
        'rasterTimeMs': rasterTimeMs,
        'totalFrameTimeMs': totalFrameTimeMs,
        'jitterMs': jitterMs,
        'startupTimeMs': startupTimeMs,
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

      // Ensure active node count matches
      final activeNodesStr = storage.getItem(_activeNodesKey);
      if (nodeCount != null && activeNodesStr != null) {
        final activeNodes = int.tryParse(activeNodesStr);
        if (activeNodes != null && activeNodes != nodeCount) {
          return null;
        }
      }

      final normMode = mode.toLowerCase();
      final key = (normMode == 'wasm') ? _wasmRunKey : _jsRunKey;
      final jsonStr = storage.getItem(key);

      if (jsonStr == null || jsonStr.isEmpty) return null;

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final runMode = map['mode'] as String?;
      final fps = (map['fps'] as num?)?.toDouble();
      final buildTimeMs = (map['buildTimeMs'] as num?)?.toDouble() ?? 0.0;
      final rasterTimeMs = (map['rasterTimeMs'] as num?)?.toDouble() ?? 0.0;
      final totalFrameTimeMs =
          (map['totalFrameTimeMs'] as num?)?.toDouble() ?? 0.0;
      final jitterMs = (map['jitterMs'] as num?)?.toDouble() ?? 0.0;
      final startupTimeMs =
          (map['startupTimeMs'] as num?)?.toDouble() ??
          getStartupTime(mode: runMode ?? normMode);
      final stress = (map['stressLevel'] as String?) ?? 'medium';
      final nodes = (map['nodeCount'] as num?)?.toInt() ?? 500;

      if (nodeCount != null && nodes != nodeCount) {
        return null;
      }

      if (runMode != null && fps != null) {
        return (
          mode: runMode,
          fps: fps,
          buildTimeMs: buildTimeMs,
          rasterTimeMs: rasterTimeMs,
          totalFrameTimeMs: totalFrameTimeMs,
          jitterMs: jitterMs,
          startupTimeMs: startupTimeMs,
          stressLevel: stress,
          nodeCount: nodes,
        );
      }
    } catch (_) {
      // Ignore
    }
    return null;
  }

  static BenchmarkRun? getLastRun({String? stressLevel, int? nodeCount}) {
    return getRunForMode(
          mode: 'wasm',
          nodeCount: nodeCount,
          stressLevel: stressLevel,
        ) ??
        getRunForMode(
          mode: 'js',
          nodeCount: nodeCount,
          stressLevel: stressLevel,
        );
  }
}
