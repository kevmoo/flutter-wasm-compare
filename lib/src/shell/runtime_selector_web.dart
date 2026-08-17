import 'package:flutter/material.dart';

import 'build_config_web.dart';
import 'engine_mode.dart';

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
              _buildEngineButton(context, 'Wasm', 'wasm'),
            ],
            if (targets.isEmpty || targets.contains('dart2js')) ...[
              const SizedBox(width: 8),
              _buildEngineButton(context, 'JS', 'js'),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEngineButton(BuildContext context, String label, String mode) {
    final queryMode = Uri.base.queryParameters['mode']?.toLowerCase();
    final isCurrent = mode == 'js'
        ? (queryMode == 'js' || queryMode == 'canvaskit')
        : (queryMode == 'wasm' || queryMode == 'skwasm' || queryMode == null);

    return ChoiceChip(
      label: Text(label),
      selected: isCurrent,
      onSelected: (selected) {
        if (selected && !isCurrent) {
          switchEngineMode(context, mode: mode);
        }
      },
    );
  }
}
