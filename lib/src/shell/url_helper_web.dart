import 'dart:js_interop';

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
