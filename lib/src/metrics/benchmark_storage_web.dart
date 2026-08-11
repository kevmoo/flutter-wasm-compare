import 'dart:convert';

import 'package:web/web.dart' as web;

typedef BenchmarkRun = ({
  String mode,
  double fps,
  double buildTimeMs,
  double rasterTimeMs,
  double totalFrameTimeMs,
  String stressLevel,
  int nodeCount,
});

class BenchmarkStorage {
  static const String _storagePrefix = 'wasm_compare_run_';

  static void saveRun({
    required String mode,
    required double fps,
    required double buildTimeMs,
    required double rasterTimeMs,
    required double totalFrameTimeMs,
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
        'stressLevel': stressLevel,
        'nodeCount': nodeCount,
      };
      final jsonStr = jsonEncode(data);
      storage.setItem('wasm_compare_last_run', jsonStr);
      storage.setItem('$_storagePrefix$stressLevel', jsonStr);
      storage.setItem('${_storagePrefix}nodes_$nodeCount', jsonStr);
    } catch (_) {
      // Ignore
    }
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
      final stress = (map['stressLevel'] as String?) ?? 'medium';
      final nodes = (map['nodeCount'] as num?)?.toInt() ?? 500;

      if (mode != null && fps != null) {
        return (
          mode: mode,
          fps: fps,
          buildTimeMs: buildTimeMs,
          rasterTimeMs: rasterTimeMs,
          totalFrameTimeMs: totalFrameTimeMs,
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
