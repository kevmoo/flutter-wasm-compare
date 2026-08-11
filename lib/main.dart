import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/metrics/frame_timing_service.dart';
import 'src/scene/adaptive_stress_scene.dart';
import 'src/scene/stress_controller.dart';
import 'src/shell/compatibility_shield.dart';
import 'src/shell/performance_hud.dart';
import 'src/shell/runtime_selector.dart';

void main() {
  runApp(const WasmCompareApp());
}

class WasmCompareApp extends StatelessWidget {
  const WasmCompareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FrameTimingService()),
        ChangeNotifierProvider(create: (_) => StressController()),
      ],
      child: MaterialApp(
        title: 'Wasm vs JS Compare',
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueAccent,
            brightness: Brightness.dark,
          ),
        ),
        home: const CompatibilityShield(child: DemoDashboard()),
      ),
    );
  }
}

class DemoDashboard extends StatelessWidget {
  const DemoDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final stressCtrl = context.watch<StressController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wasm vs JS Performance'),
        actions: [
          _DeviceDetailsButton(stressCtrl: stressCtrl),
          _AutoTuneButton(stressCtrl: stressCtrl),
          _PresetDropdown(stressCtrl: stressCtrl),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AdaptiveStressScene(nodeCount: stressCtrl.nodeCount),
          ),
          const Positioned(top: 20, left: 20, child: PerformanceHud()),
          const Positioned(top: 20, right: 20, child: RuntimeSelector()),
        ],
      ),
    );
  }
}

class _DeviceDetailsButton extends StatelessWidget {
  final StressController stressCtrl;

  const _DeviceDetailsButton({required this.stressCtrl});

  @override
  Widget build(BuildContext context) {
    if (stressCtrl.hasAllowedDeviceDetails) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Tooltip(
          message:
              '${stressCtrl.deviceDetailsLabel} '
              '(Click to re-query screen)',
          child: ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(
              Icons.refresh,
              size: 14,
              color: Colors.greenAccent,
            ),
            label: Text(
              stressCtrl.deviceDetailsLabel ?? '60 Hz Display',
              style: const TextStyle(fontSize: 11),
            ),
            onPressed: stressCtrl.allowDeviceDetails,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Tooltip(
        message: 'Allow browser to read real screen refresh rate',
        child: OutlinedButton.icon(
          onPressed: stressCtrl.allowDeviceDetails,
          icon: const Icon(Icons.display_settings, size: 14),
          label: const Text('Device details', style: TextStyle(fontSize: 11)),
        ),
      ),
    );
  }
}

class _AutoTuneButton extends StatelessWidget {
  final StressController stressCtrl;

  const _AutoTuneButton({required this.stressCtrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: FilledButton.tonalIcon(
        onPressed: stressCtrl.isAutoTuning
            ? null
            : () {
                final timingService = context.read<FrameTimingService>();
                context.read<StressController>().startAutoTune(timingService);
              },
        icon: const Icon(Icons.flash_on, size: 15),
        label: Text(
          stressCtrl.isAutoTuning ? 'Tuning...' : 'Auto-Tune',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}

class _PresetDropdown extends StatelessWidget {
  final StressController stressCtrl;

  const _PresetDropdown({required this.stressCtrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: DropdownButton<StressPreset>(
        value: stressCtrl.mode == StressMode.preset ? stressCtrl.preset : null,
        hint: Text('Custom (${stressCtrl.nodeCount})'),
        underline: const SizedBox.shrink(),
        onChanged: (preset) {
          if (preset != null) {
            context.read<StressController>().setPreset(preset);
          }
        },
        items: StressPreset.values.map((preset) {
          return DropdownMenuItem(value: preset, child: Text(preset.label));
        }).toList(),
      ),
    );
  }
}
