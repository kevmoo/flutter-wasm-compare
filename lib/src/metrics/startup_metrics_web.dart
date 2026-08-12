import 'package:web/web.dart' as web;

double? getAppStartupTimeMs() {
  try {
    return web.window.performance.now();
  } catch (_) {
    return null;
  }
}
