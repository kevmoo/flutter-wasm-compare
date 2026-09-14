import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
