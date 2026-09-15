@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wasm_compare/src/metrics/benchmark_storage.dart';
import 'package:wasm_compare/src/metrics/frame_timing_service.dart';
import 'package:web/web.dart' as web;

void _saveTestRun({
  required String mode,
  required double fps,
  required double buildTimeMs,
  required double rasterTimeMs,
  required double totalFrameTimeMs,
  required double jitterMs,
  String stressLevel = 'medium',
  int nodeCount = 500,
  String workloadId = 'bouncy',
  bool isPipelined = false,
}) {
  BenchmarkStorage.saveRun(
    mode: mode,
    fps: fps,
    buildTimeMs: buildTimeMs,
    rasterTimeMs: rasterTimeMs,
    totalFrameTimeMs: totalFrameTimeMs,
    jitterMs: jitterMs,
    stressLevel: stressLevel,
    nodeCount: nodeCount,
    workloadId: workloadId,
    isPipelined: isPipelined,
  );
}

void main() {
  setUp(() {
    web.window.localStorage.clear();
    BenchmarkStorage.resetInMemoryCacheForTesting();
  });

  tearDown(() {
    web.window.localStorage.clear();
    BenchmarkStorage.resetInMemoryCacheForTesting();
  });

  test('BenchmarkStorage persists to localStorage and reloads cache', () {
    _saveTestRun(
      mode: 'wasm',
      fps: 59.5,
      buildTimeMs: 4.1,
      rasterTimeMs: 1.5,
      totalFrameTimeMs: 5.6,
      jitterMs: 0.4,
      isPipelined: true,
    );
    _saveTestRun(
      mode: 'wimp',
      fps: 58.2,
      buildTimeMs: 4.5,
      rasterTimeMs: 1.8,
      totalFrameTimeMs: 6.3,
      jitterMs: 0.6,
    );
    _saveTestRun(
      mode: 'js',
      fps: 34.0,
      buildTimeMs: 18.2,
      rasterTimeMs: 3.1,
      totalFrameTimeMs: 21.3,
      jitterMs: 3.2,
    );
    _saveTestRun(
      mode: 'webparagraph',
      fps: 52.4,
      buildTimeMs: 7.4,
      rasterTimeMs: 2.2,
      totalFrameTimeMs: 9.6,
      jitterMs: 0.9,
    );

    // Save a run for grid as well
    _saveTestRun(
      mode: 'wasm',
      fps: 60.0,
      buildTimeMs: 2.1,
      rasterTimeMs: 1.0,
      totalFrameTimeMs: 3.1,
      jitterMs: 0.2,
      stressLevel: 'light',
      nodeCount: 250,
      workloadId: 'grid',
      isPipelined: true,
    );

    // Reset in-memory cache so _ensureCacheLoaded parses from localStorage
    BenchmarkStorage.resetInMemoryCacheForTesting();

    final wasmBouncy = BenchmarkStorage.getRunForMode(
      mode: 'wasm',
      workloadId: 'bouncy',
    );
    expect(wasmBouncy, isNotNull);
    expect(wasmBouncy!.fps, 59.5);
    expect(wasmBouncy.isPipelined, isTrue);

    final wimpBouncy = BenchmarkStorage.getRunForMode(
      mode: 'wimp',
      workloadId: 'bouncy',
    );
    expect(wimpBouncy, isNotNull);
    expect(wimpBouncy!.fps, 58.2);

    final jsBouncy = BenchmarkStorage.getRunForMode(
      mode: 'js',
      workloadId: 'bouncy',
    );
    expect(jsBouncy, isNotNull);
    expect(jsBouncy!.fps, 34.0);

    final wpBouncy = BenchmarkStorage.getRunForMode(
      mode: 'webparagraph',
      workloadId: 'bouncy',
    );
    expect(wpBouncy, isNotNull);
    expect(wpBouncy!.fps, 52.4);

    final wasmGrid = BenchmarkStorage.getRunForMode(
      mode: 'wasm',
      workloadId: 'grid',
    );
    expect(wasmGrid, isNotNull);
    expect(wasmGrid!.fps, 60.0);
    expect(wasmGrid.nodeCount, 250);
  });

  test(
    'BenchmarkStorage.saveMetrics and clearRuns / invalidateIfNodeCountChanged',
    () {
      final metrics = FrameTimingMetrics(
        fps: 57.0,
        buildTimeMs: 5.0,
        rasterTimeMs: 2.0,
        totalFrameTimeMs: 7.0,
        jitterMs: 0.5,
      );

      BenchmarkStorage.saveMetrics(
        mode: 'wasm',
        metrics: metrics,
        stressLevel: 'heavy',
        nodeCount: 1000,
        workloadId: 'bouncy',
      );

      expect(
        BenchmarkStorage.getRunForMode(mode: 'wasm', workloadId: 'bouncy')?.fps,
        57.0,
      );

      // Changing nodeCount invalidates bouncy runs
      BenchmarkStorage.invalidateIfNodeCountChanged(500, workloadId: 'bouncy');
      expect(
        BenchmarkStorage.getRunForMode(mode: 'wasm', workloadId: 'bouncy'),
        isNull,
      );

      // Clear all runs
      BenchmarkStorage.saveMetrics(
        mode: 'js',
        metrics: metrics,
        stressLevel: 'heavy',
        nodeCount: 1000,
        workloadId: 'grid',
      );
      BenchmarkStorage.clearRuns();
      expect(
        BenchmarkStorage.getRunForMode(mode: 'js', workloadId: 'grid'),
        isNull,
      );
    },
  );
}
