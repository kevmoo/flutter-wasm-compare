import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:wasm_compare/src/metrics/benchmark_storage.dart';
import 'package:provider/provider.dart';
import 'package:wasm_compare/src/metrics/frame_timing_service.dart';

class RuntimeSelector extends StatelessWidget {
  const RuntimeSelector({super.key});

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(width: 8),
          _buildEngineButton(context, 'WASM', 'skwasm'),
          const SizedBox(width: 8),
          _buildEngineButton(context, 'JS (CanvasKit)', 'canvaskit'),
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
          final currentFps = context.read<FrameTimingService>().metrics.fps;
          final currentMode = searchParams.contains('mode=canvaskit')
              ? 'js'
              : 'wasm';
          BenchmarkStorage.saveRun(currentMode, currentFps);

          final url = web.URL(web.window.location.href);
          url.searchParams.set('mode', mode);
          web.window.location.href = url.href;
        }
      },
    );
  }
}
