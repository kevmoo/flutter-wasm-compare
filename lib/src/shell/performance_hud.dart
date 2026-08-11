import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../metrics/benchmark_storage.dart';
import '../metrics/frame_timing_service.dart';

typedef _ComparisonData = ({
  bool hasValidComparison,
  bool isFaster,
  String speedupBadge,
  double budgetRatio,
  String budgetPct,
  Color budgetColor,
});

_ComparisonData _evaluateComparison(
  double currentTotal,
  BenchmarkRun? savedBaseline,
) {
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

  final budgetRatio = (currentTotal / 16.67).clamp(0.0, 1.0);
  final budgetPct = (currentTotal / 16.67 * 100).toStringAsFixed(0);
  final budgetColor = switch (budgetRatio) {
    < 0.5 => Colors.greenAccent,
    < 0.85 => Colors.amberAccent,
    _ => Colors.redAccent,
  };

  return (
    hasValidComparison: hasValid,
    isFaster: isFaster,
    speedupBadge: badge,
    budgetRatio: budgetRatio,
    budgetPct: budgetPct,
    budgetColor: budgetColor,
  );
}

class PerformanceHud extends StatelessWidget {
  final String? currentStressLevel;

  const PerformanceHud({super.key, this.currentStressLevel});

  @override
  Widget build(BuildContext context) {
    return Consumer<FrameTimingService>(
      builder: (context, timingService, child) {
        final metrics = timingService.metrics;
        final savedBaseline = BenchmarkStorage.getLastRun(
          stressLevel: currentStressLevel,
        );

        final comparison = _evaluateComparison(
          metrics.totalFrameTimeMs,
          savedBaseline,
        );

        return Container(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
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
              _HeaderTitle(stressLevel: currentStressLevel),
              const SizedBox(height: 12),
              _LiveMetricsSection(metrics: metrics),
              const SizedBox(height: 10),
              _BudgetBar(
                budgetRatio: comparison.budgetRatio,
                budgetPct: comparison.budgetPct,
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
  final String? stressLevel;

  const _HeaderTitle({this.stressLevel});

  @override
  Widget build(BuildContext context) {
    final title = stressLevel != null
        ? 'LIVE PERFORMANCE (${stressLevel!.toUpperCase()})'
        : 'LIVE PERFORMANCE';

    return Text(
      title,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: Colors.white54, letterSpacing: 1.0),
    );
  }
}

class _LiveMetricsSection extends StatelessWidget {
  final FrameTimingMetrics metrics;

  const _LiveMetricsSection({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          label: 'FPS',
          value: metrics.fps.toStringAsFixed(1),
          valueColor: Colors.greenAccent,
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
      ],
    );
  }
}

class _BudgetBar extends StatelessWidget {
  final double budgetRatio;
  final String budgetPct;
  final Color budgetColor;

  const _BudgetBar({
    required this.budgetRatio,
    required this.budgetPct,
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
            const Text(
              '16.6ms Budget',
              style: TextStyle(color: Colors.white54, fontSize: 11),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24, color: Colors.white24),
        Text(
          'BASELINE (${savedBaseline.mode.toUpperCase()})',
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
