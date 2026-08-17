import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/metrics/frame_timing_service.dart';
import 'src/scene/adaptive_stress_scene.dart';
import 'src/scene/stress_controller.dart';
import 'src/shell/build_info.dart';
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

const double largeScreenMinWidth = 768.0;
const double compactAppBarBreakpoint = 768.0;

class DemoDashboard extends StatelessWidget {
  const DemoDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final stressCtrl = context.watch<StressController>();
    final isCompactScreen =
        MediaQuery.sizeOf(context).width < compactAppBarBreakpoint;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: isCompactScreen ? 12.0 : null,
        title: Text(
          isCompactScreen ? 'Wasm vs JS' : 'Wasm vs JS Performance',
          style: TextStyle(
            fontSize: isCompactScreen ? 16 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          BuildInfoButton(isCompact: isCompactScreen),
          _DeviceDetailsButton(
            stressCtrl: stressCtrl,
            isCompact: isCompactScreen,
          ),
          _StressStepperPill(
            stressCtrl: stressCtrl,
            isCompact: isCompactScreen,
          ),
          _PresetDropdown(stressCtrl: stressCtrl, isCompact: isCompactScreen),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeScreen = constraints.maxWidth >= largeScreenMinWidth;

          return Stack(
            children: [
              Positioned.fill(
                key: const ValueKey('stress_scene'),
                child: AdaptiveStressScene(nodeCount: stressCtrl.nodeCount),
              ),
              Positioned(
                key: const ValueKey('perf_hud'),
                top: isLargeScreen ? 20 : null,
                left: isLargeScreen ? 20 : 16,
                bottom: isLargeScreen ? null : 16,
                child: PerformanceHud(initiallyCollapsed: !isLargeScreen),
              ),
              Positioned(
                key: const ValueKey('runtime_selector'),
                top: isLargeScreen ? 20 : 12,
                right: isLargeScreen ? 20 : 12,
                child: const RuntimeSelector(),
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

class _StressStepperPill extends StatelessWidget {
  final StressController stressCtrl;
  final bool isCompact;

  const _StressStepperPill({required this.stressCtrl, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 2.0 : 4.0),
      child: Container(
        height: isCompact ? 30 : 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepperButton(
              icon: Icons.remove,
              isCompact: isCompact,
              tooltip: 'Decrease Stress',
              onPressed: stressCtrl.canStepDown
                  ? () {
                      context.read<FrameTimingService>().resetLog();
                      context.read<StressController>().stepDown();
                    }
                  : null,
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 4.0 : 6.0),
              child: Text(
                isCompact
                    ? stressCtrl.formattedNodeCount
                    : '${stressCtrl.formattedNodeCount} Nodes',
                style: TextStyle(
                  fontSize: isCompact ? 11 : 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add,
              isCompact: isCompact,
              tooltip: 'Increase Stress',
              onPressed: stressCtrl.canStepUp
                  ? () {
                      context.read<FrameTimingService>().resetLog();
                      context.read<StressController>().stepUp();
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final bool isCompact;
  final String tooltip;
  final VoidCallback? onPressed;

  const _StepperButton({
    required this.icon,
    required this.isCompact,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final size = isCompact ? 24.0 : 32.0;
    return IconButton(
      iconSize: isCompact ? 14 : 16,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      icon: Icon(icon),
      onPressed: onPressed,
      tooltip: tooltip,
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
        isDense: isCompact,
        iconSize: isCompact ? 16 : 24,
        value: stressCtrl.mode == StressMode.preset ? stressCtrl.preset : null,
        hint: Text(
          isCompact
              ? stressCtrl.formattedNodeCount
              : 'Custom (${stressCtrl.formattedNodeCount})',
          style: TextStyle(fontSize: isCompact ? 11 : 14),
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
