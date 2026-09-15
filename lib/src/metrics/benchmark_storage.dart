import 'dart:convert';

import 'package:meta/meta.dart';

import 'benchmark_run.dart';
import 'benchmark_storage_stub.dart'
    if (dart.library.js_interop) 'benchmark_storage_web.dart';
import 'frame_timing_service.dart';

export 'benchmark_run.dart';

class BenchmarkStorage() {
  static const String _wasmRunKey = 'wasm_compare_last_wasm_run';
  static const String _wimpRunKey = 'wasm_compare_last_wimp_run';
  static const String _jsRunKey = 'wasm_compare_last_js_run';
  static const String _webParagraphRunKey =
      'wasm_compare_last_webparagraph_run';

  static final Map<String, int> _cachedNodesByWorkload = {};
  static final Map<String, Map<String, BenchmarkRun>> _cachedRunsByKey = {
    _wasmRunKey: {},
    _wimpRunKey: {},
    _jsRunKey: {},
    _webParagraphRunKey: {},
  };
  static bool _cacheLoaded = false;

  static String? _baseKeyForMode(String mode) => switch (mode.toLowerCase()) {
    'wimp' || 'impeller' => _wimpRunKey,
    'wasm' || 'skwasm' => _wasmRunKey,
    'webparagraph' ||
    'js-webparagraph' ||
    'canvaskit-webparagraph' => _webParagraphRunKey,
    'js' || 'canvaskit' => _jsRunKey,
    _ => null,
  };

  @visibleForTesting
  static void resetInMemoryCacheForTesting() {
    _cachedNodesByWorkload.clear();
    for (final cache in _cachedRunsByKey.values) {
      cache.clear();
    }
    _cacheLoaded = false;
  }

  static void _ensureCacheLoaded() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    BenchmarkStoragePersistence.loadAll(
      _cachedNodesByWorkload,
      _cachedRunsByKey,
    );
  }

  static void clearRuns({String? workloadId}) {
    _ensureCacheLoaded();
    if (workloadId != null) {
      _cachedNodesByWorkload.remove(workloadId);
      for (final cache in _cachedRunsByKey.values) {
        cache.remove(workloadId);
      }
      BenchmarkStoragePersistence.clearWorkload(workloadId);
      return;
    }

    _cachedNodesByWorkload.clear();
    for (final cache in _cachedRunsByKey.values) {
      cache.clear();
    }
    _cacheLoaded = true;
    BenchmarkStoragePersistence.clearAll();
  }

  static void invalidateIfNodeCountChanged(
    int currentNodeCount, {
    String? workloadId,
  }) {
    _ensureCacheLoaded();
    final id = workloadId ?? 'bouncy';
    final prevNodes = _cachedNodesByWorkload[id];
    if (prevNodes != null && prevNodes != currentNodeCount) {
      clearRuns(workloadId: id);
    }
  }

  static void saveMetrics({
    required String mode,
    required FrameTimingMetrics metrics,
    required String stressLevel,
    required int nodeCount,
    String workloadId = 'bouncy',
    bool? isPipelined,
  }) {
    saveRun(
      mode: mode,
      fps: metrics.fps,
      buildTimeMs: metrics.buildTimeMs,
      rasterTimeMs: metrics.rasterTimeMs,
      totalFrameTimeMs: metrics.totalFrameTimeMs,
      jitterMs: metrics.jitterMs,
      stressLevel: stressLevel,
      nodeCount: nodeCount,
      workloadId: workloadId,
      isPipelined: isPipelined ?? (mode.toLowerCase() == 'wasm'),
    );
  }

  static void save(BenchmarkRun run) {
    invalidateIfNodeCountChanged(run.nodeCount, workloadId: run.workloadId);
    _cachedNodesByWorkload[run.workloadId] = run.nodeCount;

    final baseKey = _baseKeyForMode(run.mode);
    if (baseKey == null) {
      throw ArgumentError.value(
        run.mode,
        'mode',
        'Unsupported benchmark engine mode',
      );
    }

    _cachedRunsByKey[baseKey]![run.workloadId] = run;

    BenchmarkStoragePersistence.saveRun(
      baseKey: baseKey,
      workloadId: run.workloadId,
      nodeCount: run.nodeCount,
      jsonStr: jsonEncode(run.toJson()),
    );
  }

  static void saveRun({
    required String mode,
    required double fps,
    required double buildTimeMs,
    required double rasterTimeMs,
    required double totalFrameTimeMs,
    double jitterMs = 0.0,
    required String stressLevel,
    required int nodeCount,
    String workloadId = 'bouncy',
    bool isPipelined = false,
  }) => save(
    BenchmarkRun.sample(
      mode,
      fps,
      buildTimeMs,
      rasterTimeMs,
      totalFrameTimeMs,
      jitterMs,
      stressLevel: stressLevel,
      nodeCount: nodeCount,
      workloadId: workloadId,
      isPipelined: isPipelined,
    ),
  );

  static BenchmarkRun? getRunForMode({
    required String mode,
    int? nodeCount,
    String? stressLevel,
    String? workloadId,
  }) {
    _ensureCacheLoaded();
    final id = workloadId ?? 'bouncy';
    final cachedNodes = _cachedNodesByWorkload[id];
    if (nodeCount != null && cachedNodes != null && cachedNodes != nodeCount) {
      return null;
    }

    final baseKey = _baseKeyForMode(mode);
    final run = baseKey != null ? (_cachedRunsByKey[baseKey]?[id]) : null;
    if (run == null) return null;

    if (nodeCount != null && run.nodeCount != nodeCount) return null;
    if (workloadId != null && run.workloadId != workloadId) return null;
    if (stressLevel != null &&
        run.stressLevel.toLowerCase() != stressLevel.toLowerCase()) {
      return null;
    }

    return run;
  }
}
