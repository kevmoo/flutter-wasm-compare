import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../metrics/benchmark_storage.dart';
import '../metrics/frame_timing_service.dart';
import '../scene/stress_controller.dart';
import 'engine_mode.dart';
import 'url_helper.dart';

@visibleForTesting
typedef BenefitBadge = ({String title, String detail});

@visibleForTesting
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

class const PerformanceHud({super.key, final bool initiallyCollapsed = false})
    extends StatefulWidget {
  @override
  State<PerformanceHud> createState() => _PerformanceHudState();
}

class _PerformanceHudState() extends State<PerformanceHud> {
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
                mode: currentEngineMode(),
                metrics: metrics,
                stressLevel: stressCtrl.currentLabel,
                nodeCount: stressCtrl.nodeCount,
                workloadId: stressCtrl.workload.id,
                isPipelined: isCurrentPipelined,
              );
            });
          }
        }

        final wasmRun = _resolveWasmRun(
          nodeCount: stressCtrl.nodeCount,
          stressLevel: stressCtrl.currentLabel,
          workloadId: stressCtrl.workload.id,
        );

        final jsRun = _resolveJsRun(
          nodeCount: stressCtrl.nodeCount,
          stressLevel: stressCtrl.currentLabel,
          workloadId: stressCtrl.workload.id,
        );

        final comparison = evaluateComparisonForTest(
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
                  wasmRun: wasmRun,
                  jsRun: jsRun,
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

  static BenchmarkRun? _resolveEngineRun({
    required bool isExperimental,
    required String defaultMode,
    required String experimentalMode,
    required int nodeCount,
    required String stressLevel,
    required String workloadId,
  }) {
    if (isExperimental) {
      return BenchmarkStorage.getRunForMode(
        mode: experimentalMode,
        nodeCount: nodeCount,
        stressLevel: stressLevel,
        workloadId: workloadId,
      );
    }
    return BenchmarkStorage.getRunForMode(
          mode: defaultMode,
          nodeCount: nodeCount,
          stressLevel: stressLevel,
          workloadId: workloadId,
        ) ??
        BenchmarkStorage.getRunForMode(
          mode: experimentalMode,
          nodeCount: nodeCount,
          stressLevel: stressLevel,
          workloadId: workloadId,
        );
  }

  static BenchmarkRun? _resolveWasmRun({
    required int nodeCount,
    required String stressLevel,
    required String workloadId,
  }) => _resolveEngineRun(
    isExperimental: isCurrentlyWimp(),
    defaultMode: 'wasm',
    experimentalMode: 'wimp',
    nodeCount: nodeCount,
    stressLevel: stressLevel,
    workloadId: workloadId,
  );

  static BenchmarkRun? _resolveJsRun({
    required int nodeCount,
    required String stressLevel,
    required String workloadId,
  }) => _resolveEngineRun(
    isExperimental: isCurrentlyWebParagraph(),
    defaultMode: 'js',
    experimentalMode: 'webparagraph',
    nodeCount: nodeCount,
    stressLevel: stressLevel,
    workloadId: workloadId,
  );
}

BoxDecoration buildPillDecoration() => BoxDecoration(
  color: Colors.white.withValues(alpha: 0.08),
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: Colors.white12),
);

class const _EngineTogglePill({
  required final bool isCurrentWasm,
  final bool isSingleThreaded = false,
  final BenchmarkRun? wasmRun,
  final BenchmarkRun? jsRun,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isWimp = isCurrentWasm
        ? isCurrentlyWimp()
        : wasmRun?.mode.toLowerCase() == 'wimp';
    final isWebParagraph = !isCurrentWasm
        ? isCurrentlyWebParagraph()
        : jsRun?.mode.toLowerCase() == 'webparagraph';
    return Container(
      decoration: buildPillDecoration(),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EnginePillButton(
            label: _wasmLabel(isWimp),
            isSelected: isCurrentWasm,
            selectedColor: Colors.lightBlueAccent,
            onTap: isCurrentWasm
                ? (isWimp ? null : () => toggleSingleThreadedMode(context))
                : () =>
                      switchEngineMode(context, mode: isWimp ? 'wimp' : 'wasm'),
            tooltip: _wasmTooltip(isWimp),
          ),
          const SizedBox(width: 2),
          _EnginePillButton(
            label: isWebParagraph ? '📜 WebParagraph (Exp)' : '📜 JS',
            isSelected: !isCurrentWasm,
            selectedColor: isWebParagraph
                ? Colors.orangeAccent
                : const Color(0xFFF1E05A),
            onTap: !isCurrentWasm
                ? null
                : () => switchEngineMode(
                    context,
                    mode: isWebParagraph ? 'webparagraph' : 'js',
                  ),
            tooltip: _jsTooltip(isWebParagraph),
          ),
        ],
      ),
    );
  }

  String _wasmLabel(bool isWimp) => switch ((isWimp, isSingleThreaded)) {
    (true, true) => '⚡ Impeller (Exp, ST)',
    (true, false) => '⚡ Impeller (Exp)',
    (false, true) => '⚡ Wasm (ST)',
    (false, false) => '⚡ Wasm',
  };

  String _wasmTooltip(bool isWimp) {
    if (!isCurrentWasm) return 'Switch to WebAssembly';
    if (isWimp) return 'Wasm + Impeller (Experimental • Single-threaded)';
    return isSingleThreaded
        ? 'Wasm + Skia (Single-threaded) • Tap to toggle threading'
        : 'Wasm + Skia (Multi-threaded) • Tap to toggle threading';
  }

  String _jsTooltip(bool isWebParagraph) {
    if (isCurrentWasm) return 'Switch to JavaScript';
    return isWebParagraph
        ? 'Running JavaScript (WebParagraph • Experimental)'
        : 'Running JavaScript (CanvasKit)';
  }
}

class const _EnginePillButton({
  required final String label,
  required final bool isSelected,
  required final Color selectedColor,
  required final VoidCallback? onTap,
  final String? tooltip,
}) extends StatelessWidget {
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

class const _HeaderTitle({required final VoidCallback onCollapse})
    extends StatelessWidget {
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

class const _BudgetBar({
  required final double budgetRatio,
  required final String budgetPct,
  required final String budgetLabel,
  required final Color budgetColor,
}) extends StatelessWidget {
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

class const _DualEngineCards({
  required final bool isCurrentWasm,
  required final bool isCurrentST,
  required final FrameTimingMetrics liveMetrics,
  required final BenchmarkRun? wasmRun,
  required final BenchmarkRun? jsRun,
  required final double targetHz,
}) extends StatelessWidget {
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
            subtitle: _wasmSubtitle(isWasmST),
            titleColor: Colors.lightBlueAccent,
            isLive: isCurrentWasm,
            fps: wasmMetrics.fps,
            activeMs: wasmMetrics.activeMs,
            jitterMs: wasmMetrics.jitterMs,
            buildMs: wasmMetrics.buildMs,
            rasterMs: wasmMetrics.rasterMs,
            targetHz: targetHz,
            isSingleThreaded: isWasmST,
            onTap: _wasmOnTap(context),
          ),
        ),
        const SizedBox(width: 8),
        // Right Card: JS
        Expanded(
          child: _EngineMiniCard(
            title: '📜 JS',
            subtitle: _jsSubtitle(),
            titleColor: _jsTitleColor(),
            isLive: !isCurrentWasm,
            fps: jsMetrics.fps,
            activeMs: jsMetrics.activeMs,
            jitterMs: jsMetrics.jitterMs,
            buildMs: jsMetrics.buildMs,
            rasterMs: jsMetrics.rasterMs,
            targetHz: targetHz,
            onTap: _jsOnTap(context),
          ),
        ),
      ],
    );
  }

  String _wasmSubtitle(bool isWasmST) {
    final isWimp = isCurrentWasm
        ? isCurrentlyWimp()
        : wasmRun?.mode.toLowerCase() == 'wimp';
    return switch ((isWimp, isWasmST)) {
      (true, true) => 'Impeller (Exp) • Single-threaded',
      (true, false) => 'Impeller (Experimental)',
      (false, true) => 'Skia • Single-threaded',
      (false, false) => 'Skwasm (Skia)',
    };
  }

  VoidCallback? _wasmOnTap(BuildContext context) {
    if (isCurrentWasm) {
      return isCurrentlyWimp() ? null : () => toggleSingleThreadedMode(context);
    }
    return () => switchEngineMode(
      context,
      mode: wasmRun?.mode.toLowerCase() == 'wimp' ? 'wimp' : 'wasm',
    );
  }

  String _jsSubtitle() {
    final isWp = !isCurrentWasm
        ? isCurrentlyWebParagraph()
        : jsRun?.mode.toLowerCase() == 'webparagraph';
    return isWp ? 'WebParagraph (Exp)' : 'CanvasKit (Serial)';
  }

  Color _jsTitleColor() {
    final isWp = !isCurrentWasm
        ? isCurrentlyWebParagraph()
        : jsRun?.mode.toLowerCase() == 'webparagraph';
    return isWp ? Colors.orangeAccent : const Color(0xFFF1E05A);
  }

  VoidCallback? _jsOnTap(BuildContext context) {
    if (!isCurrentWasm) return null;
    return () => switchEngineMode(
      context,
      mode: jsRun?.mode.toLowerCase() == 'webparagraph' ? 'webparagraph' : 'js',
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

class const _EngineMiniCard({
  required final String title,
  final String? subtitle,
  required final Color titleColor,
  required final bool isLive,
  required final double? fps,
  required final double? activeMs,
  final double? jitterMs,
  required final double? buildMs,
  required final double? rasterMs,
  required final double targetHz,
  final bool isSingleThreaded = false,
  final VoidCallback? onTap,
}) extends StatelessWidget {
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
    final tooltipMessage = _tooltipMessage(isWasmCard);

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
          _buildHeaderRow(isWasmCard: isWasmCard, hasData: hasData),
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

  String _tooltipMessage(bool isWasmCard) {
    if (!isLive) {
      final targetEngine = isWasmCard ? 'Wasm (Skwasm)' : 'JS (CanvasKit)';
      return 'Click to switch to $targetEngine';
    }
    if (!isWasmCard) return 'Currently active runtime engine';
    if (isCurrentlyWimp()) {
      return 'Active: Web Impeller (Experimental • Single-threaded)';
    }
    return isSingleThreaded
        ? 'Active: Single-threaded • Tap or Ctrl+Shift+S to toggle'
        : 'Active: Multi-threaded • Tap or Ctrl+Shift+S to toggle';
  }

  Widget _buildHeaderRow({required bool isWasmCard, required bool hasData}) {
    return Row(
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
          liveLabel: isWasmCard && isSingleThreaded ? 'LIVE (ST)' : 'LIVE',
        ),
      ],
    );
  }
}

class const _EngineStatusBadge({
  required final bool isLive,
  required final bool hasData,
  required final Color titleColor,
  final String liveLabel = 'LIVE',
}) extends StatelessWidget {
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

class const _EngineMetricsContent({
  required final bool hasData,
  required final double? fps,
  required final double? activeMs,
  required final double? jitterMs,
  required final double? buildMs,
  required final double? rasterMs,
  required final double targetHz,
}) extends StatelessWidget {
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

class const _MiniMetricRow({
  required final String label,
  required final String value,
  required final Color valueColor,
}) extends StatelessWidget {
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

class const _BenefitBadges({
  required final BenefitBadge? speedBadge,
  required final BenefitBadge? jitterBadge,
  final String? promptBadge,
  final VoidCallback? onPromptTap,
}) extends StatelessWidget {
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

class const _BenefitPill({required final BenefitBadge badge})
    extends StatelessWidget {
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
