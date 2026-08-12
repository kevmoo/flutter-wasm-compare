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
  static const String _storagePrefix = 'wasm_compare_run_';
  static const String _startupPrefix = 'wasm_compare_startup_';

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
      storage.setItem('wasm_compare_last_run', jsonStr);
      storage.setItem('$_storagePrefix$stressLevel', jsonStr);
      storage.setItem('${_storagePrefix}nodes_$nodeCount', jsonStr);

      // Store separate mode-specific keys
      final normMode = mode.toLowerCase();
      storage.setItem('$_storagePrefix${normMode}_last', jsonStr);
      storage.setItem('$_storagePrefix${normMode}_nodes_$nodeCount', jsonStr);
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
      final normMode = mode.toLowerCase();
      final nodeKey = '$_storagePrefix${normMode}_nodes_$nodeCount';
      final stressKey = '$_storagePrefix${normMode}_$stressLevel';
      final lastKey = '$_storagePrefix${normMode}_last';

      final jsonStr = nodeCount != null
          ? (storage.getItem(nodeKey) ?? storage.getItem(lastKey))
          : (stressLevel != null
                ? (storage.getItem(stressKey) ?? storage.getItem(lastKey))
                : storage.getItem(lastKey));

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
    try {
      final storage = web.window.localStorage;
      final jsonStr = nodeCount != null
          ? (storage.getItem('${_storagePrefix}nodes_$nodeCount') ??
                storage.getItem('wasm_compare_last_run'))
          : (stressLevel != null
                ? (storage.getItem('$_storagePrefix$stressLevel') ??
                      storage.getItem('wasm_compare_last_run'))
                : storage.getItem('wasm_compare_last_run'));

      if (jsonStr == null || jsonStr.isEmpty) return null;

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final mode = map['mode'] as String?;
      final fps = (map['fps'] as num?)?.toDouble();
      final buildTimeMs = (map['buildTimeMs'] as num?)?.toDouble() ?? 0.0;
      final rasterTimeMs = (map['rasterTimeMs'] as num?)?.toDouble() ?? 0.0;
      final totalFrameTimeMs =
          (map['totalFrameTimeMs'] as num?)?.toDouble() ?? 0.0;
      final jitterMs = (map['jitterMs'] as num?)?.toDouble() ?? 0.0;
      final startupTimeMs = (map['startupTimeMs'] as num?)?.toDouble();
      final stress = (map['stressLevel'] as String?) ?? 'medium';
      final nodes = (map['nodeCount'] as num?)?.toInt() ?? 500;

      if (mode != null && fps != null) {
        return (
          mode: mode,
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
}
