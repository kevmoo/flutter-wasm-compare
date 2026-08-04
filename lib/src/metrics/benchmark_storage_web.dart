import 'package:web/web.dart' as web;

class BenchmarkStorage {
  static const String _lastRunModeKey = 'wasm_compare_last_mode';
  static const String _lastFpsKey = 'wasm_compare_last_fps';

  static void saveRun(String mode, double fps) {
    try {
      final storage = web.window.localStorage;
      storage.setItem(_lastRunModeKey, mode);
      storage.setItem(_lastFpsKey, fps.toString());
    } catch (e) {
      // Ignore
    }
  }

  static ({String mode, double fps})? getLastRun() {
    try {
      final storage = web.window.localStorage;
      final mode = storage.getItem(_lastRunModeKey);
      final fpsStr = storage.getItem(_lastFpsKey);
      if (mode != null && fpsStr != null && fpsStr.isNotEmpty) {
        final fps = double.tryParse(fpsStr);
        if (fps != null) {
          return (mode: mode, fps: fps);
        }
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }
}
