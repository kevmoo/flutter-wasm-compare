void updateUrlQueryParam(String key, String value) {}

void exportMetrics({
  required double fps,
  required double buildTimeMs,
  required double rasterTimeMs,
  required double totalFrameTimeMs,
}) {}

Future<double?> requestScreenRefreshRate() async => null;

void savePersistedRefreshRate(double rate) {}

double? getPersistedRefreshRate() => null;

void savePersistedHudCollapsed(bool collapsed) {}

bool? getPersistedHudCollapsed() => null;
