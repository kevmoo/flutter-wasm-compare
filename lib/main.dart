import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'src/metrics/frame_timing_service.dart';
import 'src/scene/adaptive_stress_scene.dart';
import 'src/scene/stress_controller.dart';
import 'src/scene/stress_workload.dart';
import 'src/shell/build_info.dart';
import 'src/shell/compatibility_shield.dart';
import 'src/shell/engine_mode.dart';
import 'src/shell/performance_hud.dart';

void main() {
  runApp(const WasmCompareApp());
}

class WasmCompareApp extends StatelessWidget {
  const new({super.key});

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
const double compactAppBarBreakpoint = 960.0;

class DemoDashboard extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final stressCtrl = context.watch<StressController>();
    final isCompactScreen =
        MediaQuery.sizeOf(context).width < compactAppBarBreakpoint;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): () =>
            toggleSingleThreadedMode(context),
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          meta: true,
          shift: true,
        ): () =>
            toggleSingleThreadedMode(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: isCompactScreen ? 6.0 : null,
            title: Text(
              isCompactScreen ? 'Wasm vs JS' : 'Wasm vs JS Performance',
              style: TextStyle(
                fontSize: isCompactScreen ? 13 : 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              _WorkloadSelectorButton(
                stressCtrl: stressCtrl,
                isCompact: isCompactScreen,
              ),
              if (!isCompactScreen) const _EngineSelectorButton(),
              BuildInfoButton(isCompact: isCompactScreen),
              if (isCurrentlySingleThreaded() && !isCurrentlyWimp())
                _ThreadingModeButton(isCompact: isCompactScreen),
              _DeviceDetailsButton(
                stressCtrl: stressCtrl,
                isCompact: isCompactScreen,
              ),
              _StressStepperPill(
                stressCtrl: stressCtrl,
                isCompact: isCompactScreen,
              ),
              _PresetDropdown(
                stressCtrl: stressCtrl,
                isCompact: isCompactScreen,
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isLargeScreen = constraints.maxWidth >= largeScreenMinWidth;

              return Stack(
                children: [
                  Positioned.fill(
                    key: const ValueKey('stress_scene'),
                    child: AdaptiveStressScene(
                      workload: stressCtrl.workload,
                      nodeCount: stressCtrl.nodeCount,
                    ),
                  ),
                  Positioned(
                    key: const ValueKey('perf_hud'),
                    top: isLargeScreen ? 20 : null,
                    left: isLargeScreen ? 20 : 16,
                    bottom: isLargeScreen ? null : 16,
                    child: PerformanceHud(initiallyCollapsed: !isLargeScreen),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EngineSelectorButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final current = currentEngineMode();
    final color = _engineColor(current);
    final label = _engineLabel(current);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: PopupMenuButton<String>(
        tooltip: 'Select Rendering Engine (Impeller [Exp] / Skia / JS)',
        initialValue: current,
        onSelected: (mode) => _handleSelected(context, mode, current),
        itemBuilder: (context) => _buildMenuItems(current),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.45),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                current == 'js' ? Icons.javascript : Icons.bolt,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }

  static Color _engineColor(String mode) => switch (mode) {
    'wimp' => Colors.tealAccent,
    'wasm' => Colors.lightBlueAccent,
    _ => const Color(0xFFF1E05A),
  };

  static String _engineLabel(String mode) => switch (mode) {
    'wimp' => 'Impeller (Exp)',
    'wasm' => 'Skia',
    _ => 'JS',
  };

  void _handleSelected(BuildContext context, String mode, String current) {
    if (mode == current) return;
    if (mode == 'wimp' && !isWimpSupportedInBrowser) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Impeller on Web (wimp) requires Chromium '
            '(ImageDecoder and V8 iterators). '
            'On Safari and Firefox, Flutter Web falls back to Skia.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    switchEngineMode(context, mode: mode);
  }

  List<PopupMenuEntry<String>> _buildMenuItems(String current) => [
    PopupMenuItem(
      value: 'wimp',
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.bolt, color: Colors.tealAccent),
        title: const Text('⚡ Wasm (Impeller) [Exp]'),
        subtitle: Text(
          isWimpSupportedInBrowser
              ? 'Web Impeller (wimp.wasm) • Experimental (Unstable)'
              : 'Impeller (Unsupported on Safari/Firefox)',
          style: TextStyle(
            fontSize: 11,
            color: isWimpSupportedInBrowser
                ? Colors.amberAccent
                : Colors.redAccent,
          ),
        ),
        trailing: current == 'wimp'
            ? const Icon(Icons.check, size: 16, color: Colors.tealAccent)
            : null,
      ),
    ),
    PopupMenuItem(
      value: 'wasm',
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.bolt, color: Colors.lightBlueAccent),
        title: const Text('⚡ Wasm (Skia)'),
        subtitle: const Text(
          'Skwasm (skwasm.wasm)',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        trailing: current == 'wasm'
            ? const Icon(Icons.check, size: 16, color: Colors.lightBlueAccent)
            : null,
      ),
    ),
    PopupMenuItem(
      value: 'js',
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.javascript, color: Color(0xFFF1E05A)),
        title: const Text('📜 JavaScript (CanvasKit)'),
        subtitle: const Text(
          'CanvasKit (canvaskit.wasm)',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        trailing: current == 'js'
            ? const Icon(Icons.check, size: 16, color: Color(0xFFF1E05A))
            : null,
      ),
    ),
  ];
}

class _ThreadingModeButton extends StatelessWidget {
  final bool isCompact;

  const new({this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    final isSt = isCurrentlySingleThreaded();
    final tooltip = isSt
        ? 'Wasm Single-threaded (Serial) • Tap or Ctrl+Shift+S to toggle'
        : 'Wasm Multi-threaded (Worker) • Tap or Ctrl+Shift+S to toggle';
    final color = isSt ? Colors.amberAccent : Colors.lightBlueAccent;
    final label = isSt ? 'Single-threaded' : 'Multi-threaded';

    final iconWidget = isSt
        ? const Icon(Icons.trending_flat, size: 14, color: Colors.amberAccent)
        : const Icon(Icons.call_split, size: 14, color: Colors.lightBlueAccent);

    final compactIconWidget = isSt
        ? const Icon(Icons.trending_flat, size: 18, color: Colors.amberAccent)
        : const Icon(Icons.call_split, size: 18, color: Colors.lightBlueAccent);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Tooltip(
        message: tooltip,
        child: isCompact
            ? IconButton(
                icon: compactIconWidget,
                onPressed: () => toggleSingleThreadedMode(context),
              )
            : OutlinedButton.icon(
                onPressed: () => toggleSingleThreadedMode(context),
                icon: iconWidget,
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(
                    color: color.withValues(alpha: 0.45),
                    width: 1.0,
                  ),
                  backgroundColor: color.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
      ),
    );
  }
}

class _DeviceDetailsButton extends StatelessWidget {
  final StressController stressCtrl;
  final bool isCompact;

  const new({required this.stressCtrl, this.isCompact = false});

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

  const new({required this.stressCtrl, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 1.0 : 4.0),
      child: Container(
        height: isCompact ? 28 : 36,
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
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 2.0 : 6.0),
              child: Text(
                isCompact
                    ? stressCtrl.formattedNodeCount
                    : '${stressCtrl.formattedNodeCount} '
                          '${stressCtrl.workload.unitLabel}',
                style: TextStyle(
                  fontSize: isCompact ? 10 : 12,
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

  const new({
    required this.icon,
    required this.isCompact,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final size = isCompact ? 22.0 : 32.0;
    return IconButton(
      iconSize: isCompact ? 13 : 16,
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

  const new({required this.stressCtrl, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 1.0 : 6.0),
      child: DropdownButton<StressPreset>(
        isDense: isCompact,
        iconSize: isCompact ? 14 : 24,
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
              stressCtrl.presetLabelFor(preset),
              style: TextStyle(fontSize: isCompact ? 11 : 14),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WorkloadSelectorButton extends StatelessWidget {
  final StressController stressCtrl;
  final bool isCompact;

  const new({required this.stressCtrl, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    final current = stressCtrl.workload;
    final color = _workloadColor(current.id);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 1.0 : 2.0),
      child: PopupMenuButton<String>(
        tooltip: 'Select Benchmark Workload (Layout Churn / Card Grid)',
        initialValue: current.id,
        padding: EdgeInsets.zero,
        constraints: isCompact
            ? const BoxConstraints(minWidth: 28, minHeight: 28)
            : null,
        onSelected: (id) {
          if (id == current.id) return;
          context.read<FrameTimingService>().resetLog();
          stressCtrl.setWorkload(resolveWorkload(id));
        },
        itemBuilder: (context) => [
          for (final workload in kAllWorkloads)
            _buildMenuItem(workload, current.id),
        ],
        child: _buildTriggerChild(current, color),
      ),
    );
  }

  static Color _workloadColor(String id) =>
      id == 'bouncy' ? Colors.purpleAccent : Colors.orangeAccent;

  static IconData _workloadIcon(String id) =>
      id == 'bouncy' ? Icons.account_tree_outlined : Icons.grid_view_outlined;

  PopupMenuItem<String> _buildMenuItem(
    StressWorkload workload,
    String currentId,
  ) {
    final itemColor = _workloadColor(workload.id);
    return PopupMenuItem<String>(
      value: workload.id,
      child: ListTile(
        dense: true,
        leading: Icon(_workloadIcon(workload.id), color: itemColor),
        title: Text(workload.title),
        subtitle: Text(
          workload.subtitle,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        trailing: workload.id == currentId
            ? Icon(Icons.check, size: 16, color: itemColor)
            : null,
      ),
    );
  }

  Widget _buildTriggerChild(StressWorkload current, Color color) {
    final iconData = _workloadIcon(current.id);
    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: Icon(iconData, size: 18, color: color),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            current.title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 14, color: color),
        ],
      ),
    );
  }
}
