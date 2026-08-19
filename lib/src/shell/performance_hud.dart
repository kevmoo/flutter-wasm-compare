import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../metrics/benchmark_storage.dart';
import '../metrics/frame_timing_service.dart';
import '../scene/stress_controller.dart';
import 'engine_mode.dart';
import 'url_helper.dart';

typedef BenefitBadge = ({String title, String detail});

typedef ComparisonData = ({
  bool hasBothRuns,
  BenefitBadge? speedBadge,
  BenefitBadge? jitterBadge,
  String? promptBadge,
  double budgetRatio,
  String budgetPct,
  String budgetLabel,
  Color budgetColor,
  Color fpsColor,
});

@visibleForTesting
ComparisonData evaluateComparisonForTest({
  required double currentActive,
  required double currentJitter,
  required double currentFps,
  required double targetRefreshRate,
  required BenchmarkRun? wasmRun,
  required BenchmarkRun? jsRun,
  required bool isCurrentWasm,
  required int nodeCount,
  bool isSingleThreaded = false,
}) => _evaluateComparison(
  currentActive: currentActive,
  currentJitter: currentJitter,
  currentFps: currentFps,
  targetRefreshRate: targetRefreshRate,
  wasmRun: wasmRun,
  jsRun: jsRun,
  isCurrentWasm: isCurrentWasm,
  nodeCount: nodeCount,
  isSingleThreaded: isSingleThreaded,
);

Color _getFpsColor(double fps, double targetHz) {
  final ratio = fps / targetHz;
  if (ratio >= 0.9) return Colors.greenAccent;
  if (ratio >= 0.7) return Colors.amberAccent;
  return Colors.redAccent;
}

Color _getJitterColor(double jitterMs) {
  if (jitterMs < 1.2) return Colors.greenAccent;
  if (jitterMs < 3.0) return Colors.amberAccent;
  return Colors.redAccent;
}

const _hudDecoration = BoxDecoration(
  color: Colors.black87,
  borderRadius: BorderRadius.all(Radius.circular(12)),
  border: Border.fromBorderSide(BorderSide(color: Colors.white12)),
  boxShadow: [
    BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
  ],
);

double _activeTimeForRun(BenchmarkRun? run, {bool? isPipelined}) {
  if (run == null) return 0.0;
  final pipelined = isPipelined ?? run.isPipelined;
  return pipelined
      ? math.max(run.buildTimeMs, run.rasterTimeMs)
      : (run.buildTimeMs + run.rasterTimeMs);
}

BenefitBadge? _computeSpeedBadge({
  required double wasmActive,
  required double jsActive,
  bool isWasmSingleThreaded = false,
}) {
  if (wasmActive <= 0.01 || (jsActive / wasmActive) < 1.05) return null;
  final ratio = jsActive / wasmActive;
  final modeLabel = isWasmSingleThreaded ? ' (ST)' : '';
  return (
    title: '⚡ Wasm$modeLabel ${ratio.toStringAsFixed(1)}x Faster',
    detail:
        '${wasmActive.toStringAsFixed(1)}ms '
        'vs ${jsActive.toStringAsFixed(1)}ms',
  );
}

BenefitBadge? _computeJitterBadge({
  required double wasmJitter,
  required double jsJitter,
}) {
  final baseline = wasmJitter > 0.01 ? wasmJitter : 0.1;
  if (jsJitter <= 0.05 || (jsJitter / baseline) < 1.15) return null;
  final ratio = jsJitter / baseline;
  final ratioText = ratio >= 10
      ? '${ratio.toStringAsFixed(0)}x'
      : '${ratio.toStringAsFixed(1)}x';
  return (
    title: '🎯 Wasm $ratioText Smoother',
    detail:
        '±${wasmJitter.toStringAsFixed(1)}ms '
        'vs ±${jsJitter.toStringAsFixed(1)}ms',
  );
}

ComparisonData _evaluateComparison({
  required double currentActive,
  required double currentJitter,
  required double currentFps,
  required double targetRefreshRate,
  required BenchmarkRun? wasmRun,
  required BenchmarkRun? jsRun,
  required bool isCurrentWasm,
  required int nodeCount,
  bool isSingleThreaded = false,
}) {
  final budgetTargetMs = 1000.0 / targetRefreshRate;
  final budgetLabel =
      '${budgetTargetMs.toStringAsFixed(1)}ms (${targetRefreshRate.toInt()}Hz)';

  final isWasmST = isCurrentWasm
      ? isSingleThreaded
      : !(wasmRun?.isPipelined ?? true);
  final wasmActive = isCurrentWasm
      ? currentActive
      : _activeTimeForRun(wasmRun, isPipelined: !isWasmST);
  final jsActive = !isCurrentWasm
      ? currentActive
      : _activeTimeForRun(jsRun, isPipelined: false);

  final wasmJitter = isCurrentWasm ? currentJitter : (wasmRun?.jitterMs ?? 0.0);
  final jsJitter = !isCurrentWasm ? currentJitter : (jsRun?.jitterMs ?? 0.0);

  final hasBoth = wasmActive > 0.1 && jsActive > 0.1;
  final otherEngine = isCurrentWasm ? 'JS' : 'Wasm';

  final (speedBadge, jitterBadge, promptBadge) = hasBoth
      ? (
          _computeSpeedBadge(
            wasmActive: wasmActive,
            jsActive: jsActive,
            isWasmSingleThreaded: isWasmST,
          ),
          _computeJitterBadge(wasmJitter: wasmJitter, jsJitter: jsJitter),
          null,
        )
      : (null, null, '⏳ Switch to $otherEngine to test at $nodeCount nodes');

  final rawRatio = budgetTargetMs > 0 ? (currentActive / budgetTargetMs) : 0.0;
  final budgetRatio = rawRatio.clamp(0.0, 1.0);
  final budgetPct = (rawRatio * 100).toStringAsFixed(0);
  final budgetColor = switch (rawRatio) {
    < 0.80 => Colors.greenAccent,
    < 0.90 => Colors.amberAccent,
    <= 1.00 => Colors.orangeAccent,
    _ => Colors.redAccent,
  };

  return (
    hasBothRuns: hasBoth,
    speedBadge: speedBadge,
    jitterBadge: jitterBadge,
    promptBadge: promptBadge,
    budgetRatio: budgetRatio,
    budgetPct: budgetPct,
    budgetLabel: budgetLabel,
    budgetColor: budgetColor,
    fpsColor: _getFpsColor(currentFps, targetRefreshRate),
  );
}

class PerformanceHud extends StatefulWidget {
  final bool initiallyCollapsed;

  const PerformanceHud({super.key, this.initiallyCollapsed = false});

  @override
  State<PerformanceHud> createState() => _PerformanceHudState();
}

class _PerformanceHudState extends State<PerformanceHud> {
  late bool _isCollapsed;
  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final persisted = getPersistedHudCollapsed();
    _isCollapsed = persisted ?? widget.initiallyCollapsed;
  }

  void _setCollapsed(bool value) {
    setState(() => _isCollapsed = value);
    savePersistedHudCollapsed(value);
  }

  @override
  void didUpdateWidget(PerformanceHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (getPersistedHudCollapsed() == null &&
        oldWidget.initiallyCollapsed != widget.initiallyCollapsed) {
      _isCollapsed = widget.initiallyCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<FrameTimingService, StressController>(
      builder: (context, timingService, stressCtrl, child) {
        final metrics = timingService.metrics;
        final isCurrentWasm = isCurrentlyWasm();
        final isCurrentST = isCurrentlySingleThreaded();
        final isCurrentPipelined = isCurrentlyPipelined();
        final currentActive = metrics.activeFrameTimeMs(
          isPipelined: isCurrentPipelined,
        );

        // Throttle benchmark storage writes to at most once per 1000ms
        // to avoid frame stalls while ensuring localStorage stays fresh.
        if (metrics.totalFrameTimeMs > 0.1) {
          final now = DateTime.now();
          if (now.difference(_lastSaved).inMilliseconds >= 1000) {
            _lastSaved = now;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              BenchmarkStorage.saveMetrics(
                mode: isCurrentWasm ? 'wasm' : 'js',
                metrics: metrics,
                stressLevel: stressCtrl.currentLabel,
                nodeCount: stressCtrl.nodeCount,
                isPipelined: isCurrentPipelined,
              );
            });
          }
        }

        final wasmRun = BenchmarkStorage.getRunForMode(
          mode: 'wasm',
          nodeCount: stressCtrl.nodeCount,
          stressLevel: stressCtrl.currentLabel,
        );

        final jsRun = BenchmarkStorage.getRunForMode(
          mode: 'js',
          nodeCount: stressCtrl.nodeCount,
          stressLevel: stressCtrl.currentLabel,
        );

        final comparison = _evaluateComparison(
          currentActive: currentActive,
          currentJitter: metrics.jitterMs,
          currentFps: metrics.fps,
          targetRefreshRate: stressCtrl.targetRefreshRate,
          wasmRun: wasmRun,
          jsRun: jsRun,
          isCurrentWasm: isCurrentWasm,
          nodeCount: stressCtrl.nodeCount,
          isSingleThreaded: isCurrentST,
        );

        if (_isCollapsed) {
          return Container(
            decoration: _hudDecoration,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _EngineTogglePill(
                  isCurrentWasm: isCurrentWasm,
                  isSingleThreaded: isCurrentST,
                ),
                const SizedBox(width: 6),
                Container(width: 1, height: 18, color: Colors.white12),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _setCollapsed(false),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.speed, size: 15, color: comparison.fpsColor),
                        const SizedBox(width: 5),
                        Text(
                          '${metrics.fps.toStringAsFixed(1)} FPS',
                          style: TextStyle(
                            color: comparison.fpsColor,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${currentActive.toStringAsFixed(1)}ms',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.expand_more,
                          size: 16,
                          color: Colors.white54,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 340),
          padding: const EdgeInsets.all(14),
          decoration: _hudDecoration,

          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderTitle(onCollapse: () => _setCollapsed(true)),
              const SizedBox(height: 10),

              _BudgetBar(
                budgetRatio: comparison.budgetRatio,
                budgetPct: comparison.budgetPct,
                budgetLabel: comparison.budgetLabel,
                budgetColor: comparison.budgetColor,
              ),
              const SizedBox(height: 12),
              _DualEngineCards(
                isCurrentWasm: isCurrentWasm,
                isCurrentST: isCurrentST,
                liveMetrics: metrics,
                wasmRun: wasmRun,
                jsRun: jsRun,
                targetHz: stressCtrl.targetRefreshRate,
              ),
              const SizedBox(height: 10),
              _BenefitBadges(
                speedBadge: comparison.speedBadge,
                jitterBadge: comparison.jitterBadge,
                promptBadge: comparison.promptBadge,
                onPromptTap: () => switchEngineMode(
                  context,
                  mode: isCurrentWasm ? 'js' : 'wasm',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EngineTogglePill extends StatelessWidget {
  final bool isCurrentWasm;
  final bool isSingleThreaded;

  const _EngineTogglePill({
    required this.isCurrentWasm,
    this.isSingleThreaded = false,
  });

  @override
  Widget build(BuildContext context) {
    final wasmLabel = isSingleThreaded ? '⚡ Wasm (ST)' : '⚡ Wasm';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EnginePillButton(
            label: wasmLabel,
            isSelected: isCurrentWasm,
            selectedColor: Colors.lightBlueAccent,
            onTap: isCurrentWasm
                ? () => toggleSingleThreadedMode(context)
                : () => switchEngineMode(context, mode: 'wasm'),
            tooltip: isCurrentWasm
                ? (isSingleThreaded
                      ? 'Wasm (Single-threaded) • Tap or Ctrl+Shift+S to toggle'
                      : 'Wasm (Multi-threaded) • Tap or Ctrl+Shift+S to toggle')
                : 'Switch to WebAssembly',
          ),
          const SizedBox(width: 2),
          _EnginePillButton(
            label: '📜 JS',
            isSelected: !isCurrentWasm,
            selectedColor: const Color(0xFFF1E05A),
            onTap: !isCurrentWasm
                ? null
                : () => switchEngineMode(context, mode: 'js'),
            tooltip: !isCurrentWasm
                ? 'Running JavaScript (CanvasKit)'
                : 'Switch to JavaScript',
          ),
        ],
      ),
    );
  }
}

class _EnginePillButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback? onTap;
  final String? tooltip;

  const _EnginePillButton({
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? selectedColor.withValues(alpha: 0.25)
        : Colors.transparent;
    final textColor = isSelected ? selectedColor : Colors.white54;
    final fontWeight = isSelected ? FontWeight.bold : FontWeight.normal;

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: fontWeight,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 300),
        child: button,
      );
    }

    return button;
  }
}

class _HeaderTitle extends StatelessWidget {
  final VoidCallback onCollapse;

  const _HeaderTitle({required this.onCollapse});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.analytics_outlined,
              size: 14,
              color: Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              'PERFORMANCE HUD',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white70,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        InkWell(
          onTap: onCollapse,
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
            padding: EdgeInsets.all(4.0),
            child: Icon(Icons.expand_less, size: 18, color: Colors.white54),
          ),
        ),
      ],
    );
  }
}

class _BudgetBar extends StatelessWidget {
  final double budgetRatio;
  final String budgetPct;
  final String budgetLabel;
  final Color budgetColor;

  const _BudgetBar({
    required this.budgetRatio,
    required this.budgetPct,
    required this.budgetLabel,
    required this.budgetColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$budgetLabel Budget',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            Text(
              '$budgetPct%',
              style: TextStyle(
                color: budgetColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: budgetRatio,
            minHeight: 4,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(budgetColor),
          ),
        ),
      ],
    );
  }
}

class _DualEngineCards extends StatelessWidget {
  final bool isCurrentWasm;
  final bool isCurrentST;
  final FrameTimingMetrics liveMetrics;
  final BenchmarkRun? wasmRun;
  final BenchmarkRun? jsRun;
  final double targetHz;

  const _DualEngineCards({
    required this.isCurrentWasm,
    required this.isCurrentST,
    required this.liveMetrics,
    required this.wasmRun,
    required this.jsRun,
    required this.targetHz,
  });

  @override
  Widget build(BuildContext context) {
    final isWasmST = isCurrentWasm
        ? isCurrentST
        : !(wasmRun?.isPipelined ?? true);

    final wasmMetrics = _resolveCardMetrics(
      isLive: isCurrentWasm,
      liveMetrics: liveMetrics,
      savedRun: wasmRun,
      isPipelined: !isWasmST,
    );
    final jsMetrics = _resolveCardMetrics(
      isLive: !isCurrentWasm,
      liveMetrics: liveMetrics,
      savedRun: jsRun,
      isPipelined: false,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Card: WASM
        Expanded(
          child: _EngineMiniCard(
            title: isWasmST ? '⚡ WASM (ST)' : '⚡ WASM',
            subtitle: isWasmST ? 'Single-threaded' : null,

            titleColor: Colors.lightBlueAccent,
            isLive: isCurrentWasm,
            fps: wasmMetrics.fps,
            activeMs: wasmMetrics.activeMs,
            jitterMs: wasmMetrics.jitterMs,
            buildMs: wasmMetrics.buildMs,
            rasterMs: wasmMetrics.rasterMs,
            targetHz: targetHz,
            isSingleThreaded: isWasmST,
            onTap: isCurrentWasm
                ? () => toggleSingleThreadedMode(context)
                : () => switchEngineMode(context, mode: 'wasm'),
          ),
        ),
        const SizedBox(width: 8),
        // Right Card: JS
        Expanded(
          child: _EngineMiniCard(
            title: '📜 JS',
            subtitle: 'CanvasKit (Serial)',
            titleColor: const Color(0xFFF1E05A),
            isLive: !isCurrentWasm,
            fps: jsMetrics.fps,
            activeMs: jsMetrics.activeMs,
            jitterMs: jsMetrics.jitterMs,
            buildMs: jsMetrics.buildMs,
            rasterMs: jsMetrics.rasterMs,
            targetHz: targetHz,
            onTap: !isCurrentWasm
                ? null
                : () => switchEngineMode(context, mode: 'js'),
          ),
        ),
      ],
    );
  }
}

typedef _CardMetrics = ({
  double? fps,
  double? activeMs,
  double? jitterMs,
  double? buildMs,
  double? rasterMs,
});

_CardMetrics _resolveCardMetrics({
  required bool isLive,
  required FrameTimingMetrics liveMetrics,
  required BenchmarkRun? savedRun,
  required bool isPipelined,
}) {
  if (isLive) {
    return (
      fps: liveMetrics.fps,
      activeMs: liveMetrics.activeFrameTimeMs(isPipelined: isPipelined),
      jitterMs: liveMetrics.jitterMs,
      buildMs: liveMetrics.buildTimeMs,
      rasterMs: liveMetrics.rasterTimeMs,
    );
  }
  if (savedRun != null) {
    return (
      fps: savedRun.fps,
      activeMs: _activeTimeForRun(savedRun, isPipelined: isPipelined),
      jitterMs: savedRun.jitterMs,
      buildMs: savedRun.buildTimeMs,
      rasterMs: savedRun.rasterTimeMs,
    );
  }
  return (
    fps: null,
    activeMs: null,
    jitterMs: null,
    buildMs: null,
    rasterMs: null,
  );
}

class _EngineMiniCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color titleColor;
  final bool isLive;
  final double? fps;
  final double? activeMs;
  final double? jitterMs;
  final double? buildMs;
  final double? rasterMs;
  final double targetHz;
  final bool isSingleThreaded;
  final VoidCallback? onTap;

  const _EngineMiniCard({
    required this.title,
    this.subtitle,
    required this.titleColor,
    required this.isLive,
    required this.fps,
    required this.activeMs,
    this.jitterMs,
    required this.buildMs,
    required this.rasterMs,
    required this.targetHz,
    this.isSingleThreaded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = activeMs != null && activeMs! > 0.0;
    final borderColor = isLive
        ? titleColor.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.20);
    final bgColor = isLive
        ? titleColor.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.04);

    final isWasmCard = title.contains('WASM');
    final targetEngine = isWasmCard ? 'Wasm (Skwasm)' : 'JS (CanvasKit)';
    final tooltipMessage = isLive
        ? (isWasmCard
              ? (isSingleThreaded
                    ? 'Active: Single-threaded • Tap or Ctrl+Shift+S to toggle'
                    : 'Active: Multi-threaded • Tap or Ctrl+Shift+S to toggle')
              : 'Currently active runtime engine')
        : 'Click to switch to $targetEngine';

    final cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: isLive ? 1.5 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: isLive ? Colors.white70 : Colors.white38,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _EngineStatusBadge(
                isLive: isLive,
                hasData: hasData,
                titleColor: titleColor,
                liveLabel: isWasmCard && isSingleThreaded
                    ? 'LIVE (ST)'
                    : 'LIVE',
              ),
            ],
          ),
          const Divider(height: 10, color: Colors.white10),
          _EngineMetricsContent(
            hasData: hasData,
            fps: fps,
            activeMs: activeMs,
            jitterMs: jitterMs,
            buildMs: buildMs,
            rasterMs: rasterMs,
            targetHz: targetHz,
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Tooltip(
        message: tooltipMessage,
        waitDuration: const Duration(milliseconds: 500),
        child: cardContent,
      );
    }

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 200),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: titleColor.withValues(alpha: 0.12),
          splashColor: titleColor.withValues(alpha: 0.20),
          highlightColor: titleColor.withValues(alpha: 0.08),
          mouseCursor: SystemMouseCursors.click,
          child: cardContent,
        ),
      ),
    );
  }
}

class _EngineStatusBadge extends StatelessWidget {
  final bool isLive;
  final bool hasData;
  final Color titleColor;
  final String liveLabel;

  const _EngineStatusBadge({
    required this.isLive,
    required this.hasData,
    required this.titleColor,
    this.liveLabel = 'LIVE',
  });

  @override
  Widget build(BuildContext context) {
    if (isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Text(
          liveLabel,
          style: const TextStyle(
            color: Colors.greenAccent,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: titleColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: titleColor.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, size: 8.5, color: titleColor),
          const SizedBox(width: 2),
          Text(
            'SWITCH',
            style: TextStyle(
              color: titleColor,
              fontSize: 8.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineMetricsContent extends StatelessWidget {
  final bool hasData;
  final double? fps;
  final double? activeMs;
  final double? jitterMs;
  final double? buildMs;
  final double? rasterMs;
  final double targetHz;

  const _EngineMetricsContent({
    required this.hasData,
    required this.fps,
    required this.activeMs,
    required this.jitterMs,
    required this.buildMs,
    required this.rasterMs,
    required this.targetHz,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12.0),
        child: Center(
          child: Text(
            'Not run yet',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final jitter = jitterMs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniMetricRow(
          label: 'FPS',
          value: fps!.toStringAsFixed(1),
          valueColor: _getFpsColor(fps!, targetHz),
        ),
        _MiniMetricRow(
          label: 'Active',
          value: '${activeMs!.toStringAsFixed(1)}ms',
          valueColor: Colors.white,
        ),
        if (jitter != null && jitter > 0.0)
          _MiniMetricRow(
            label: 'Jitter',
            value: '±${jitter.toStringAsFixed(1)}ms',
            valueColor: _getJitterColor(jitter),
          ),
        _MiniMetricRow(
          label: 'Build',
          value: '${buildMs!.toStringAsFixed(1)}ms',
          valueColor: Colors.white70,
        ),
        _MiniMetricRow(
          label: 'Raster',
          value: '${rasterMs!.toStringAsFixed(1)}ms',
          valueColor: Colors.white70,
        ),
      ],
    );
  }
}

class _MiniMetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _MiniMetricRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontFamily: 'monospace',
              fontSize: 10.5,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitBadges extends StatelessWidget {
  final BenefitBadge? speedBadge;
  final BenefitBadge? jitterBadge;
  final String? promptBadge;
  final VoidCallback? onPromptTap;

  const _BenefitBadges({
    required this.speedBadge,
    required this.jitterBadge,
    this.promptBadge,
    this.onPromptTap,
  });

  @override
  Widget build(BuildContext context) {
    if (promptBadge != null) {
      final promptWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          promptBadge!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white54,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      );

      if (onPromptTap != null) {
        return Tooltip(
          message: 'Click to switch engine',
          waitDuration: const Duration(milliseconds: 300),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPromptTap,
              borderRadius: BorderRadius.circular(6),
              hoverColor: Colors.white.withValues(alpha: 0.08),
              mouseCursor: SystemMouseCursors.click,
              child: promptWidget,
            ),
          ),
        );
      }

      return promptWidget;
    }

    final badges = [?speedBadge, ?jitterBadge];

    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < badges.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _BenefitPill(badge: badges[i]),
        ],
      ],
    );
  }
}

class _BenefitPill extends StatelessWidget {
  final BenefitBadge badge;

  const _BenefitPill({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            badge.title,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          Text(
            badge.detail,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
