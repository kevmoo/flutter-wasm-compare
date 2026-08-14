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
  double jitterMs = 0.0,
}) {
  try {
    final map = <String, Object?>{
      'fps': fps,
      'buildTimeMs': buildTimeMs,
      'rasterTimeMs': rasterTimeMs,
      'totalFrameTimeMs': totalFrameTimeMs,
      'jitterMs': jitterMs,
    };
    _lastFrameMetrics = map.jsify() as JSObject?;
  } catch (_) {
    // Ignore
  }
}

Future<double?> requestScreenRefreshRate() async {
  // Screen refresh rate detection via getScreenDetails requires explicit
  // multi-screen browser permissions in Chromium. Return null safely.
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

void savePersistedHudCollapsed(bool collapsed) {
  try {
    web.window.localStorage.setItem(
      'wasm_compare_hud_collapsed',
      collapsed ? 'true' : 'false',
    );
  } catch (_) {
    // Ignore
  }
}

bool? getPersistedHudCollapsed() {
  try {
    final stored = web.window.localStorage.getItem(
      'wasm_compare_hud_collapsed',
    );
    if (stored != null && stored.isNotEmpty) {
      return stored == 'true';
    }
  } catch (_) {
    // Ignore
  }
  return null;
}

void openExternalUrl(String url) {
  try {
    web.window.open(url, '_blank');
  } catch (_) {
    // Ignore
  }
}
