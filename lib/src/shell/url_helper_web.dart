import 'package:web/web.dart' as web;

void updateUrlQueryParam(String key, String value) {
  try {
    final url = web.URL(web.window.location.href);
    url.searchParams.set(key, value);
    web.window.history.replaceState(null, '', url.href);
  } catch (_) {
    // Ignore in non-browser or restricted contexts
  }
}
