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
}) => _evaluateComparison(
  currentActive: currentActive,
  currentJitter: currentJitter,
  currentFps: currentFps,
  targetRefreshRate: targetRefreshRate,
  wasmRun: wasmRun,
  jsRun: jsRun,
  isCurrentWasm: isCurrentWasm,
  nodeCount: nodeCount,
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

ComparisonData _evaluateComparison({
  required double currentActive,
  required double currentJitter,
  required double currentFps,
  required double targetRefreshRate,
  required BenchmarkRun? wasmRun,
  required BenchmarkRun? jsRun,
  required bool isCurrentWasm,
  required int nodeCount,
}) {
  final budgetTargetMs = 1000.0 / targetRefreshRate;
  final budgetLabel =
      '${budgetTargetMs.toStringAsFixed(1)}ms (${targetRefreshRate.toInt()}Hz)';

  final wasmActive = isCurrentWasm
      ? currentActive
      : (wasmRun != null
            ? math.max(wasmRun.buildTimeMs, wasmRun.rasterTimeMs)
            : 0.0);
  final jsActive = !isCurrentWasm
      ? currentActive
      : (jsRun != null ? (jsRun.buildTimeMs + jsRun.rasterTimeMs) : 0.0);

  final wasmJitter = isCurrentWasm ? currentJitter : (wasmRun?.jitterMs ?? 0.0);
  final jsJitter = !isCurrentWasm ? currentJitter : (jsRun?.jitterMs ?? 0.0);

  final hasBoth = wasmActive > 0.1 && jsActive > 0.1;

  BenefitBadge? speedBadge;
  BenefitBadge? jitterBadge;
  String? promptBadge;

  if (hasBoth) {
    if (wasmActive > 0.01 && (jsActive / wasmActive) >= 1.05) {
      final ratio = jsActive / wasmActive;
      speedBadge = (
        title: '⚡ Wasm ${ratio.toStringAsFixed(1)}x Faster',
        detail:
            '${wasmActive.toStringAsFixed(1)}ms '
            'vs ${jsActive.toStringAsFixed(1)}ms',
      );
    }

    final baselineWasmJitter = wasmJitter > 0.01 ? wasmJitter : 0.1;
    if (jsJitter > 0.05 && (jsJitter / baselineWasmJitter) >= 1.15) {
      final jitterRatio = jsJitter / baselineWasmJitter;
      final ratioText = jitterRatio >= 10
          ? '${jitterRatio.toStringAsFixed(0)}x'
          : '${jitterRatio.toStringAsFixed(1)}x';
      jitterBadge = (
        title: '🎯 Wasm $ratioText Smoother',
        detail:
            '±${wasmJitter.toStringAsFixed(1)}ms '
            'vs ±${jsJitter.toStringAsFixed(1)}ms',
      );
    }
  } else {
    final otherEngine = isCurrentWasm ? 'JS' : 'Wasm';
    promptBadge = '⏳ Switch to $otherEngine to test at $nodeCount nodes';
  }

  final rawRatio = budgetTargetMs > 0 ? (currentActive / budgetTargetMs) : 0.0;
  final budgetRatio = rawRatio.clamp(0.0, 1.0);
  final budgetPct = (rawRatio * 100).toStringAsFixed(0);
  final budgetColor = switch (rawRatio) {
    < 0.80 => Colors.greenAccent,
    < 0.90 => Colors.amberAccent,
    <= 1.00 => Colors.orangeAccent,
    _ => Colors.redAccent,
  };

  final fpsColor = _getFpsColor(currentFps, targetRefreshRate);

  return (
    hasBothRuns: hasBoth,
    speedBadge: speedBadge,
    jitterBadge: jitterBadge,
    promptBadge: promptBadge,
    budgetRatio: budgetRatio,
    budgetPct: budgetPct,
    budgetLabel: budgetLabel,
    budgetColor: budgetColor,
    fpsColor: fpsColor,
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
        final currentActive = metrics.activeFrameTimeMs(
          isPipelined: isCurrentWasm,
        );

        // Throttle benchmark storage writes to at most once per 1000ms
        // to avoid frame stalls while ensuring localStorage stays fresh.
        if (metrics.totalFrameTimeMs > 0.1) {
          final now = DateTime.now();
          if (now.difference(_lastSaved).inMilliseconds >= 1000) {
            _lastSaved = now;
            BenchmarkStorage.saveMetrics(
              mode: isCurrentWasm ? 'wasm' : 'js',
              metrics: metrics,
              stressLevel: stressCtrl.currentLabel,
              nodeCount: stressCtrl.nodeCount,
            );
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
        );

        if (_isCollapsed) {
          return InkWell(
            onTap: () => _setCollapsed(false),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: _hudDecoration,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.speed, size: 16, color: comparison.fpsColor),
                  const SizedBox(width: 8),
                  Text(
                    '${metrics.fps.toStringAsFixed(1)} FPS',
                    style: TextStyle(
                      color: comparison.fpsColor,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${currentActive.toStringAsFixed(1)}ms',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.expand_more,
                    size: 16,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          constraints: const BoxConstraints(minWidth: 260, maxWidth: 330),
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
              ),
            ],
          ),
        );
      },
    );
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
        Text(
          'PERFORMANCE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white54,
            letterSpacing: 0.8,
            fontWeight: FontWeight.bold,
          ),
        ),
        InkWell(
          onTap: onCollapse,
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
            padding: EdgeInsets.all(2.0),
            child: Icon(Icons.expand_less, size: 16, color: Colors.white54),
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
  final FrameTimingMetrics liveMetrics;
  final BenchmarkRun? wasmRun;
  final BenchmarkRun? jsRun;
  final double targetHz;

  const _DualEngineCards({
    required this.isCurrentWasm,
    required this.liveMetrics,
    required this.wasmRun,
    required this.jsRun,
    required this.targetHz,
  });

  @override
  Widget build(BuildContext context) {
    final wasm = wasmRun;
    final js = jsRun;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Card: WASM
        Expanded(
          child: _EngineMiniCard(
            title: '⚡ WASM',
            titleColor: Colors.lightBlueAccent,
            isLive: isCurrentWasm,
            fps: isCurrentWasm ? liveMetrics.fps : wasm?.fps,
            activeMs: isCurrentWasm
                ? liveMetrics.activeFrameTimeMs(isPipelined: true)
                : (wasm != null
                      ? math.max(wasm.buildTimeMs, wasm.rasterTimeMs)
                      : null),
            jitterMs: isCurrentWasm ? liveMetrics.jitterMs : wasm?.jitterMs,
            buildMs: isCurrentWasm
                ? liveMetrics.buildTimeMs
                : wasm?.buildTimeMs,
            rasterMs: isCurrentWasm
                ? liveMetrics.rasterTimeMs
                : wasm?.rasterTimeMs,
            targetHz: targetHz,
          ),
        ),
        const SizedBox(width: 8),
        // Right Card: JS
        Expanded(
          child: _EngineMiniCard(
            title: '📜 JS',
            titleColor: const Color(0xFFF1E05A),
            isLive: !isCurrentWasm,
            fps: !isCurrentWasm ? liveMetrics.fps : js?.fps,
            activeMs: !isCurrentWasm
                ? liveMetrics.activeFrameTimeMs(isPipelined: false)
                : (js != null ? js.buildTimeMs + js.rasterTimeMs : null),
            jitterMs: !isCurrentWasm ? liveMetrics.jitterMs : js?.jitterMs,
            buildMs: !isCurrentWasm ? liveMetrics.buildTimeMs : js?.buildTimeMs,
            rasterMs: !isCurrentWasm
                ? liveMetrics.rasterTimeMs
                : js?.rasterTimeMs,
            targetHz: targetHz,
          ),
        ),
      ],
    );
  }
}

class _EngineMiniCard extends StatelessWidget {
  final String title;
  final Color titleColor;
  final bool isLive;
  final double? fps;
  final double? activeMs;
  final double? jitterMs;
  final double? buildMs;
  final double? rasterMs;
  final double targetHz;

  const _EngineMiniCard({
    required this.title,
    required this.titleColor,
    required this.isLive,
    required this.fps,
    required this.activeMs,
    this.jitterMs,
    required this.buildMs,
    required this.rasterMs,
    required this.targetHz,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = activeMs != null && activeMs! > 0.0;
    final borderColor = isLive
        ? titleColor.withValues(alpha: 0.35)
        : Colors.white12;
    final bgColor = isLive
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.02);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isLive
                      ? Colors.green.withValues(alpha: 0.2)
                      : (hasData ? Colors.white12 : Colors.transparent),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  isLive ? 'LIVE' : (hasData ? 'SAVED' : 'UNRUN'),
                  style: TextStyle(
                    color: isLive
                        ? Colors.greenAccent
                        : (hasData ? Colors.white54 : Colors.white24),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 10, color: Colors.white10),
          if (hasData) ...[
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
            if (jitterMs != null && jitterMs! > 0.0)
              _MiniMetricRow(
                label: 'Jitter',
                value: '±${jitterMs!.toStringAsFixed(1)}ms',
                valueColor: _getJitterColor(jitterMs!),
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
          ] else ...[
            const Padding(
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
            ),
          ],
        ],
      ),
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

  const _BenefitBadges({
    required this.speedBadge,
    required this.jitterBadge,
    this.promptBadge,
  });

  @override
  Widget build(BuildContext context) {
    if (promptBadge != null) {
      return Container(
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
