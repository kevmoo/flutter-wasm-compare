import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../metrics/benchmark_storage.dart';
import '../metrics/frame_timing_service.dart';
import '../scene/stress_controller.dart';

typedef _ComparisonData = ({
  bool hasValidComparison,
  bool isFaster,
  String speedupBadge,
  double budgetRatio,
  String budgetPct,
  String budgetLabel,
  Color budgetColor,
  Color fpsColor,
});

_ComparisonData _evaluateComparison({
  required double currentTotal,
  required double currentFps,
  required double targetRefreshRate,
  required BenchmarkRun? savedBaseline,
}) {
  final budgetTargetMs = 1000.0 / targetRefreshRate;
  final budgetLabel =
      '${budgetTargetMs.toStringAsFixed(1)}ms (${targetRefreshRate.toInt()}Hz)';

  final baseTotal = savedBaseline?.totalFrameTimeMs ?? 0.0;
  final hasValid =
      savedBaseline != null && baseTotal > 0.1 && currentTotal > 0.1;
  final isFaster = hasValid && currentTotal < baseTotal;
  final ratio = hasValid
      ? (isFaster ? baseTotal / currentTotal : currentTotal / baseTotal)
      : 1.0;

  final pctDiff = hasValid
      ? (isFaster
                ? ((1.0 - (currentTotal / baseTotal)) * 100).clamp(0, 99)
                : (((currentTotal / baseTotal) - 1.0) * 100))
            .toStringAsFixed(0)
      : '0';

  final badge = isFaster
      ? '⚡ ${ratio.toStringAsFixed(1)}x Faster Frame Time (-$pctDiff%)'
      : '⚠️ ${ratio.toStringAsFixed(1)}x Slower Frame Time (+$pctDiff%)';

  final budgetRatio = (currentTotal / budgetTargetMs).clamp(0.0, 1.0);
  final budgetPct = (currentTotal / budgetTargetMs * 100).toStringAsFixed(0);
  final budgetColor = switch (budgetRatio) {
    < 0.80 => Colors.greenAccent,
    < 0.90 => Colors.amberAccent,
    _ => Colors.redAccent,
  };

  final fpsRatio = currentFps / targetRefreshRate;
  final fpsColor = switch (fpsRatio) {
    >= 0.9 => Colors.greenAccent,
    >= 0.7 => Colors.amberAccent,
    _ => Colors.redAccent,
  };

  return (
    hasValidComparison: hasValid,
    isFaster: isFaster,
    speedupBadge: badge,
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
  late bool _isCollapsed = widget.initiallyCollapsed;

  @override
  void didUpdateWidget(PerformanceHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyCollapsed != widget.initiallyCollapsed) {
      _isCollapsed = widget.initiallyCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<FrameTimingService, StressController>(
      builder: (context, timingService, stressCtrl, child) {
        final metrics = timingService.metrics;
        final savedBaseline = BenchmarkStorage.getLastRun(
          stressLevel: stressCtrl.currentLabel,
          nodeCount: stressCtrl.nodeCount,
        );

        final comparison = _evaluateComparison(
          currentTotal: metrics.totalFrameTimeMs,
          currentFps: metrics.fps,
          targetRefreshRate: stressCtrl.targetRefreshRate,
          savedBaseline: savedBaseline,
        );

        if (_isCollapsed) {
          return InkWell(
            onTap: () => setState(() => _isCollapsed = false),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
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
                    '${metrics.totalFrameTimeMs.toStringAsFixed(1)}ms',
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
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderTitle(
                label: stressCtrl.currentLabel,
                nodeCount: stressCtrl.nodeCount,
                onCollapse: () => setState(() => _isCollapsed = true),
              ),
              if (stressCtrl.autoTuneStatus.isNotEmpty) ...[
                const SizedBox(height: 6),
                _AutoTuneStatusBanner(
                  status: stressCtrl.autoTuneStatus,
                  isTuning: stressCtrl.isAutoTuning,
                ),
              ],
              const SizedBox(height: 12),
              _LiveMetricsSection(
                metrics: metrics,
                nodeCount: stressCtrl.nodeCount,
                fpsColor: comparison.fpsColor,
              ),
              const SizedBox(height: 10),
              _BudgetBar(
                budgetRatio: comparison.budgetRatio,
                budgetPct: comparison.budgetPct,
                budgetLabel: comparison.budgetLabel,
                budgetColor: comparison.budgetColor,
              ),
              if (savedBaseline != null)
                _BaselineSection(
                  savedBaseline: savedBaseline,
                  hasValidComparison: comparison.hasValidComparison,
                  isFaster: comparison.isFaster,
                  speedupBadge: comparison.speedupBadge,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  final String label;
  final int nodeCount;
  final VoidCallback onCollapse;

  const _HeaderTitle({
    required this.label,
    required this.nodeCount,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            'LIVE PERFORMANCE ($label)',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: Colors.white54, letterSpacing: 1.0),
          ),
        ),
        const SizedBox(width: 4),
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

class _AutoTuneStatusBanner extends StatelessWidget {
  final String status;
  final bool isTuning;

  const _AutoTuneStatusBanner({required this.status, required this.isTuning});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isTuning
            ? Colors.blue.withValues(alpha: 0.2)
            : Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isTuning ? Colors.blueAccent : Colors.greenAccent,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTuning)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.blueAccent,
                ),
              ),
            ),
          Flexible(
            child: Text(
              status,
              style: TextStyle(
                color: isTuning ? Colors.blueAccent : Colors.greenAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveMetricsSection extends StatelessWidget {
  final FrameTimingMetrics metrics;
  final int nodeCount;
  final Color fpsColor;

  const _LiveMetricsSection({
    required this.metrics,
    required this.nodeCount,
    required this.fpsColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          label: 'FPS',
          value: metrics.fps.toStringAsFixed(1),
          valueColor: fpsColor,
        ),
        _MetricRow(
          label: 'Build Time',
          value: '${metrics.buildTimeMs.toStringAsFixed(1)} ms',
          valueColor: Colors.white,
        ),
        _MetricRow(
          label: 'Raster Time',
          value: '${metrics.rasterTimeMs.toStringAsFixed(1)} ms',
          valueColor: Colors.white,
        ),
        _MetricRow(
          label: 'Total Frame',
          value: '${metrics.totalFrameTimeMs.toStringAsFixed(1)} ms',
          valueColor: Colors.white,
        ),
        _MetricRow(
          label: 'Churn Nodes',
          value: '$nodeCount',
          valueColor: Colors.lightBlueAccent,
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
            minHeight: 5,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(budgetColor),
          ),
        ),
      ],
    );
  }
}

class _BaselineSection extends StatelessWidget {
  final BenchmarkRun savedBaseline;
  final bool hasValidComparison;
  final bool isFaster;
  final String speedupBadge;

  const _BaselineSection({
    required this.savedBaseline,
    required this.hasValidComparison,
    required this.isFaster,
    required this.speedupBadge,
  });

  @override
  Widget build(BuildContext context) {
    final mode = savedBaseline.mode.toUpperCase();
    final nodes = savedBaseline.nodeCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24, color: Colors.white24),
        Text(
          'BASELINE ($mode • $nodes NODES)',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Colors.white54, letterSpacing: 1.0),
        ),
        const SizedBox(height: 8),
        _MetricRow(
          label: 'Base Frame',
          value: '${savedBaseline.totalFrameTimeMs.toStringAsFixed(1)} ms',
          valueColor: Colors.orangeAccent,
        ),
        _MetricRow(
          label: 'Base Build',
          value: '${savedBaseline.buildTimeMs.toStringAsFixed(1)} ms',
          valueColor: Colors.white70,
        ),
        _MetricRow(
          label: 'Base Raster',
          value: '${savedBaseline.rasterTimeMs.toStringAsFixed(1)} ms',
          valueColor: Colors.white70,
        ),
        if (hasValidComparison) ...[
          const SizedBox(height: 8),
          _SpeedupBadge(isFaster: isFaster, badgeText: speedupBadge),
        ],
      ],
    );
  }
}

class _SpeedupBadge extends StatelessWidget {
  final bool isFaster;
  final String badgeText;

  const _SpeedupBadge({required this.isFaster, required this.badgeText});

  @override
  Widget build(BuildContext context) {
    final baseColor = isFaster ? Colors.green : Colors.red;
    final accentColor = isFaster ? Colors.greenAccent : Colors.redAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        badgeText,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: accentColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _MetricRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
