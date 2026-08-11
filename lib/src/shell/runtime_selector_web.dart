import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../metrics/benchmark_storage.dart';
import '../metrics/frame_timing_service.dart';
import '../scene/stress_controller.dart';
import 'build_config_web.dart';

class RuntimeSelector extends StatelessWidget {
  const RuntimeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final targets = availableTargets;
    final isDdc = targets.contains('dartdevc');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Engine: ', style: TextStyle(fontWeight: FontWeight.bold)),
          if (isDdc) ...[
            const SizedBox(width: 8),
            const ChoiceChip(label: Text('DDC (Debug)'), selected: true),
          ] else ...[
            if (targets.isEmpty || targets.contains('dart2wasm')) ...[
              const SizedBox(width: 8),
              _buildEngineButton(context, 'WASM', 'skwasm'),
            ],
            if (targets.isEmpty || targets.contains('dart2js')) ...[
              const SizedBox(width: 8),
              _buildEngineButton(context, 'JS (CanvasKit)', 'canvaskit'),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEngineButton(BuildContext context, String label, String mode) {
    final searchParams = web.window.location.search;
    final isCurrent =
        searchParams.contains('mode=$mode') ||
        (mode == 'skwasm' && !searchParams.contains('mode='));

    return ChoiceChip(
      label: Text(label),
      selected: isCurrent,
      onSelected: (selected) {
        if (selected && !isCurrent) {
          // Save baseline metrics before swapping out
          final metrics = context.read<FrameTimingService>().metrics;
          final stressCtrl = context.read<StressController>();
          final currentMode = searchParams.contains('mode=canvaskit')
              ? 'js'
              : 'wasm';
          final currentUrl = web.URL(web.window.location.href);

          BenchmarkStorage.saveRun(
            mode: currentMode,
            fps: metrics.fps,
            buildTimeMs: metrics.buildTimeMs,
            rasterTimeMs: metrics.rasterTimeMs,
            totalFrameTimeMs: metrics.totalFrameTimeMs,
            stressLevel: stressCtrl.currentLabel,
            nodeCount: stressCtrl.nodeCount,
          );

          currentUrl.searchParams.set('mode', mode);
          web.window.location.href = currentUrl.href;
        }
      },
    );
  }
}
