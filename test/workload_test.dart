import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasm_compare/src/metrics/benchmark_storage.dart';
import 'package:wasm_compare/src/scene/bouncy_layout_matrix.dart';
import 'package:wasm_compare/src/scene/stress_controller.dart';
import 'package:wasm_compare/src/scene/stress_workload.dart';

void main() {
  group('StressWorkload calibration & resolution', () {
    test('resolveWorkload resolves bouncy and grid by id', () {
      expect(resolveWorkload('bouncy'), isA<BouncyLayoutWorkload>());
      expect(resolveWorkload('grid'), isA<PolymorphicGridWorkload>());
      expect(resolveWorkload('unknown'), isA<BouncyLayoutWorkload>());
      expect(resolveWorkload(null), isA<BouncyLayoutWorkload>());
    });

    test('BouncyLayoutWorkload calibrates presets appropriately', () {
      const bouncy = BouncyLayoutWorkload();
      expect(bouncy.nodeCountForPreset(StressPreset.none), equals(0));
      expect(bouncy.nodeCountForPreset(StressPreset.light), equals(32));
      expect(bouncy.nodeCountForPreset(StressPreset.medium), equals(64));
      expect(bouncy.nodeCountForPreset(StressPreset.heavy), equals(128));
      expect(bouncy.nodeCountForPreset(StressPreset.extreme), equals(256));
    });

    test('PolymorphicGridWorkload retains original card presets', () {
      const grid = PolymorphicGridWorkload();
      expect(grid.nodeCountForPreset(StressPreset.none), equals(0));
      expect(grid.nodeCountForPreset(StressPreset.light), equals(100));
      expect(grid.nodeCountForPreset(StressPreset.medium), equals(500));
      expect(grid.nodeCountForPreset(StressPreset.heavy), equals(1500));
      expect(grid.nodeCountForPreset(StressPreset.extreme), equals(4000));
    });
  });

  group('BouncyLayoutMatrix arbitrary-N layout stress', () {
    testWidgets('renders idle state when nodeCount is 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BouncyLayoutMatrix(nodeCount: 0)),
        ),
      );
      expect(find.text('Zero Stress (Idle)'), findsOneWidget);
    });

    testWidgets(
      'renders non-power-of-two node counts (N = 17, N = 64, N = 100) '
      'and animates flex layout without overflow errors',
      (tester) async {
        for (final count in [1, 17, 64, 100]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 600,
                  child: BouncyLayoutMatrix(nodeCount: count),
                ),
              ),
            ),
          );
          await tester.pump();
          // Advance animation to trigger Flexible.flex oscillation and
          // relayout.
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pump(const Duration(milliseconds: 500));

          expect(tester.takeException(), isNull);
        }
      },
    );
  });

  group('StressController query parameter parsing & per-workload storage', () {
    StressController parseCtrl(String query) =>
        StressController(initialUri: Uri.parse('https://example.com/?$query'));

    void expectBouncyCtrl(
      String query,
      StressMode mode,
      int nodes, [
      StressPreset? preset,
    ]) {
      final ctrl = parseCtrl(query);
      expect(ctrl.workload.id, equals('bouncy'));
      expect(ctrl.mode, equals(mode));
      if (preset != null) expect(ctrl.preset, equals(preset));
      expect(ctrl.nodeCount, equals(nodes));
    }

    test('honors ?nodes=<N> query parameter without stress=manual', () {
      expectBouncyCtrl('workload=bouncy&nodes=120', StressMode.manual, 120);
    });

    test('matches preset when ?nodes=<N> matches workload preset', () {
      expectBouncyCtrl(
        'workload=bouncy&nodes=128',
        StressMode.preset,
        128,
        StressPreset.heavy,
      );
    });

    test('clamps manual node count to activeLadder.last', () {
      expectBouncyCtrl(
        'workload=bouncy&nodes=99999',
        StressMode.manual,
        const BouncyLayoutWorkload().ladder.last,
      );
    });

    test('BenchmarkStorage isolates runs per workloadId', () {
      void saveWorkloadRun({
        required double fps,
        required double buildTimeMs,
        required double rasterTimeMs,
        required double totalFrameTimeMs,
        required int nodeCount,
        required String workloadId,
      }) {
        BenchmarkStorage.saveRun(
          mode: 'wasm',
          fps: fps,
          buildTimeMs: buildTimeMs,
          rasterTimeMs: rasterTimeMs,
          totalFrameTimeMs: totalFrameTimeMs,
          stressLevel: 'MEDIUM',
          nodeCount: nodeCount,
          workloadId: workloadId,
          isPipelined: true,
        );
      }

      BenchmarkStorage.clearRuns();
      saveWorkloadRun(
        fps: 58.0,
        buildTimeMs: 11.5,
        rasterTimeMs: 2.1,
        totalFrameTimeMs: 13.6,
        nodeCount: 64,
        workloadId: 'bouncy',
      );

      // Switching to grid at 500 nodes should not wipe bouncy's saved run
      BenchmarkStorage.invalidateIfNodeCountChanged(500, workloadId: 'grid');
      saveWorkloadRun(
        fps: 42.0,
        buildTimeMs: 18.0,
        rasterTimeMs: 4.5,
        totalFrameTimeMs: 22.5,
        nodeCount: 500,
        workloadId: 'grid',
      );

      final bouncyRun = BenchmarkStorage.getRunForMode(
        mode: 'wasm',
        nodeCount: 64,
        workloadId: 'bouncy',
      );
      expect(bouncyRun, isNotNull);
      expect(bouncyRun!.fps, equals(58.0));
      expect(bouncyRun.workloadId, equals('bouncy'));

      final gridRun = BenchmarkStorage.getRunForMode(
        mode: 'wasm',
        nodeCount: 500,
        workloadId: 'grid',
      );
      expect(gridRun, isNotNull);
      expect(gridRun!.fps, equals(42.0));
      expect(gridRun.workloadId, equals('grid'));
    });
  });
}
