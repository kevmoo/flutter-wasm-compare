import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('window._lastFrameMetrics')
external set _lastFrameMetrics(JSObject? value);

void updateUrlQueryParam(String key, String value) {
  try {
    final url = web.URL(web.window.location.href);
    url.searchParams.set(key, value);
    web.window.history.replaceState(null, '', url.href);
  } catch (_) {
    // Ignore in non-browser or restricted contexts
  }
}

void exportMetrics({
  required double fps,
  required double buildTimeMs,
  required double rasterTimeMs,
  required double totalFrameTimeMs,
}) {
  try {
    final map = <String, Object?>{
      'fps': fps,
      'buildTimeMs': buildTimeMs,
      'rasterTimeMs': rasterTimeMs,
      'totalFrameTimeMs': totalFrameTimeMs,
    };
    _lastFrameMetrics = map.jsify() as JSObject?;
  } catch (_) {
    // Ignore
  }
}

Future<double?> requestScreenRefreshRate() async {
  try {
    final win = web.window as JSObject;
    if (win.hasProperty('getScreenDetails'.toJS).toDart) {
      final promise = win.callMethod<JSPromise<JSObject>>(
        'getScreenDetails'.toJS,
      );
      final details = await promise.toDart;
      final currentScreen = details.getProperty<JSObject>('currentScreen'.toJS);
      final rate = currentScreen
          .getProperty<JSNumber?>('refreshRate'.toJS)
          ?.toDartDouble;
      if (rate != null && rate > 0) return rate;
    }
  } catch (_) {
    // Permission denied or unsupported
  }
  return null;
}

void savePersistedRefreshRate(double rate) {
  try {
    web.window.localStorage.setItem('wasm_compare_screen_hz', rate.toString());
    updateUrlQueryParam('hz', rate.toInt().toString());
  } catch (_) {
    // Ignore
  }
}

double? getPersistedRefreshRate() {
  try {
    final hzParam = Uri.base.queryParameters['hz'];
    if (hzParam != null) {
      final parsed = double.tryParse(hzParam);
      if (parsed != null && parsed > 0) return parsed;
    }
    final stored = web.window.localStorage.getItem('wasm_compare_screen_hz');
    if (stored != null && stored.isNotEmpty) {
      final parsed = double.tryParse(stored);
      if (parsed != null && parsed > 0) return parsed;
    }
  } catch (_) {
    // Ignore
  }
  return null;
}
