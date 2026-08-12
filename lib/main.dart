import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/metrics/benchmark_storage.dart';
import 'src/metrics/frame_timing_service.dart';
import 'src/metrics/startup_metrics.dart';
import 'src/scene/adaptive_stress_scene.dart';
import 'src/scene/stress_controller.dart';
import 'src/shell/compatibility_shield.dart';
import 'src/shell/engine_mode.dart';
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

const double largeScreenMinWidth = 720.0;
const double compactAppBarBreakpoint = 600.0;

class DemoDashboard extends StatefulWidget {
  const DemoDashboard({super.key});

  @override
  State<DemoDashboard> createState() => _DemoDashboardState();
}

class _DemoDashboardState extends State<DemoDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final startupMs = getAppStartupTimeMs();
      if (startupMs != null) {
        final mode = isCurrentlyWasm() ? 'wasm' : 'js';
        BenchmarkStorage.saveStartupTime(mode: mode, startupTimeMs: startupMs);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final stressCtrl = context.watch<StressController>();
    final isCompactScreen =
        MediaQuery.sizeOf(context).width < compactAppBarBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: Text(isCompactScreen ? 'Wasm vs JS' : 'Wasm vs JS Performance'),
        actions: [
          _DeviceDetailsButton(
            stressCtrl: stressCtrl,
            isCompact: isCompactScreen,
          ),
          _AutoTuneButton(stressCtrl: stressCtrl, isCompact: isCompactScreen),
          _PresetDropdown(stressCtrl: stressCtrl, isCompact: isCompactScreen),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeScreen = constraints.maxWidth >= largeScreenMinWidth;

          if (isLargeScreen) {
            return Stack(
              children: [
                Positioned.fill(
                  child: AdaptiveStressScene(nodeCount: stressCtrl.nodeCount),
                ),
                const Positioned(top: 20, left: 20, child: PerformanceHud()),
                const Positioned(top: 20, right: 20, child: RuntimeSelector()),
              ],
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: AdaptiveStressScene(nodeCount: stressCtrl.nodeCount),
              ),
              const Positioned(top: 12, right: 12, child: RuntimeSelector()),
              const Positioned(
                bottom: 16,
                left: 16,
                child: PerformanceHud(initiallyCollapsed: true),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeviceDetailsButton extends StatelessWidget {
  final StressController stressCtrl;
  final bool isCompact;

  const _DeviceDetailsButton({
    required this.stressCtrl,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (stressCtrl.hasAllowedDeviceDetails) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: Tooltip(
          message:
              '${stressCtrl.deviceDetailsLabel} '
              '(Click to re-query screen)',
          child: isCompact
              ? IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    size: 18,
                    color: Colors.greenAccent,
                  ),
                  onPressed: stressCtrl.allowDeviceDetails,
                  tooltip: stressCtrl.deviceDetailsLabel ?? '60 Hz Display',
                )
              : ActionChip(
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
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Tooltip(
        message: 'Allow browser to read real screen refresh rate',
        child: isCompact
            ? IconButton(
                onPressed: stressCtrl.allowDeviceDetails,
                icon: const Icon(Icons.display_settings, size: 18),
                tooltip: 'Device details',
              )
            : OutlinedButton.icon(
                onPressed: stressCtrl.allowDeviceDetails,
                icon: const Icon(Icons.display_settings, size: 14),
                label: const Text(
                  'Device details',
                  style: TextStyle(fontSize: 11),
                ),
              ),
      ),
    );
  }
}

class _AutoTuneButton extends StatelessWidget {
  final StressController stressCtrl;
  final bool isCompact;

  const _AutoTuneButton({required this.stressCtrl, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    final onPressed = stressCtrl.isAutoTuning
        ? null
        : () {
            final timingService = context.read<FrameTimingService>();
            context.read<StressController>().startAutoTune(timingService);
          };

    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: IconButton.filledTonal(
          onPressed: onPressed,
          icon: stressCtrl.isAutoTuning
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.flash_on, size: 18),
          tooltip: stressCtrl.isAutoTuning ? 'Tuning...' : 'Auto-Tune',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
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
  final bool isCompact;

  const _PresetDropdown({required this.stressCtrl, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 2.0 : 6.0),
      child: DropdownButton<StressPreset>(
        value: stressCtrl.mode == StressMode.preset ? stressCtrl.preset : null,
        hint: Text(
          isCompact
              ? '${stressCtrl.nodeCount}'
              : 'Custom (${stressCtrl.nodeCount})',
          style: TextStyle(fontSize: isCompact ? 12 : 14),
        ),
        underline: const SizedBox.shrink(),
        onChanged: (preset) {
          if (preset != null) {
            context.read<FrameTimingService>().resetLog();
            context.read<StressController>().setPreset(preset);
          }
        },
        items: StressPreset.values.map((preset) {
          return DropdownMenuItem(
            value: preset,
            child: Text(
              preset.label,
              style: TextStyle(fontSize: isCompact ? 12 : 14),
            ),
          );
        }).toList(),
      ),
    );
  }
}
