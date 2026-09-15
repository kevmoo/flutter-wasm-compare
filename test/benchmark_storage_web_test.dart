@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wasm_compare/src/metrics/benchmark_storage.dart';
import 'package:wasm_compare/src/metrics/frame_timing_service.dart';
import 'package:web/web.dart' as web;

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
    for (final run in [
      BenchmarkRun.sample('wasm', 59.5, 4.1, 1.5, 5.6, 0.4, isPipelined: true),
      BenchmarkRun.sample('wimp', 58.2, 4.5, 1.8, 6.3, 0.6),
      BenchmarkRun.sample('js', 34.0, 18.2, 3.1, 21.3, 3.2),
      BenchmarkRun.sample('webparagraph', 52.4, 7.4, 2.2, 9.6, 0.9),
      BenchmarkRun.sample(
        'wasm',
        60.0,
        2.1,
        1.0,
        3.1,
        0.2,
        stressLevel: 'light',
        nodeCount: 250,
        workloadId: 'grid',
        isPipelined: true,
      ),
    ]) {
      BenchmarkStorage.save(run);
    }

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
