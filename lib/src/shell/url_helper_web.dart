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
  _setStoredBool('wasm_compare_hud_collapsed', collapsed);
}

bool? getPersistedHudCollapsed() =>
    _getStoredBool('wasm_compare_hud_collapsed');

void savePersistedSingleThreaded(bool singleThreaded) {
  _setStoredBool('wasm_compare_single_threaded', singleThreaded);
}

bool isSingleThreaded() {
  try {
    final stParam =
        Uri.base.queryParameters['st'] ??
        Uri.base.queryParameters['single_threaded'];
    if (stParam == '1' || stParam == 'true') return true;
    if (stParam == '0' || stParam == 'false') return false;

    final modeParam = Uri.base.queryParameters['mode'];
    if (modeParam == 'skwasm-st') return true;
    if (modeParam == 'skwasm-mt') return false;

    return _getStoredBool('wasm_compare_single_threaded') ?? false;
  } catch (_) {
    // Ignore
  }
  return false;
}

bool? _getStoredBool(String key) {
  try {
    final stored = web.window.localStorage.getItem(key);
    if (stored != null && stored.isNotEmpty) {
      return stored == 'true';
    }
  } catch (_) {
    // Ignore
  }
  return null;
}

void _setStoredBool(String key, bool value) {
  try {
    web.window.localStorage.setItem(key, value ? 'true' : 'false');
  } catch (_) {
    // Ignore
  }
}

void openExternalUrl(String url) {
  try {
    web.window.open(url, '_blank');
  } catch (_) {
    // Ignore
  }
}

void reloadWithQueryParams(Map<String, String> params) {
  try {
    final url = web.URL(web.window.location.href);
    for (final entry in params.entries) {
      url.searchParams.set(entry.key, entry.value);
    }
    web.window.location.href = url.href;
  } catch (_) {
    // Ignore
  }
}
