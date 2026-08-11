import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../metrics/benchmark_storage.dart';
import '../metrics/frame_timing_service.dart';

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

        final currentTotal = metrics.totalFrameTimeMs;
        final baseTotal = savedBaseline?.totalFrameTimeMs ?? 0.0;
        final hasValidComparison =
            savedBaseline != null && baseTotal > 0.1 && currentTotal > 0.1;

        final isFaster = hasValidComparison && currentTotal < baseTotal;
        final ratio = hasValidComparison
            ? (isFaster ? baseTotal / currentTotal : currentTotal / baseTotal)
            : 1.0;

        final pctDiff = hasValidComparison
            ? (isFaster
                      ? ((1.0 - (currentTotal / baseTotal)) * 100).clamp(0, 99)
                      : (((currentTotal / baseTotal) - 1.0) * 100))
                  .toStringAsFixed(0)
            : '0';

        final speedupBadge = isFaster
            ? '⚡ ${ratio.toStringAsFixed(1)}x Faster Frame Time (-$pctDiff%)'
            : '⚠️ ${ratio.toStringAsFixed(1)}x Slower Frame Time (+$pctDiff%)';

        // 60 FPS Target budget = 16.67ms
        final budgetRatio = (currentTotal / 16.67).clamp(0.0, 1.0);
        final budgetPct = (currentTotal / 16.67 * 100).toStringAsFixed(0);
        final budgetColor = budgetRatio < 0.5
            ? Colors.greenAccent
            : (budgetRatio < 0.85 ? Colors.amberAccent : Colors.redAccent);

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
              Text(
                currentStressLevel != null
                    ? 'LIVE PERFORMANCE (${currentStressLevel!.toUpperCase()})'
                    : 'LIVE PERFORMANCE',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Colors.white54, letterSpacing: 1.0),
              ),
              const SizedBox(height: 12),
              _buildMetricRow(
                'FPS',
                metrics.fps.toStringAsFixed(1),
                Colors.greenAccent,
              ),
              _buildMetricRow(
                'Build Time',
                '${metrics.buildTimeMs.toStringAsFixed(1)} ms',
                Colors.white,
              ),
              _buildMetricRow(
                'Raster Time',
                '${metrics.rasterTimeMs.toStringAsFixed(1)} ms',
                Colors.white,
              ),
              _buildMetricRow(
                'Total Frame',
                '${metrics.totalFrameTimeMs.toStringAsFixed(1)} ms',
                Colors.white,
              ),
              const SizedBox(height: 10),
              // Frame Budget Bar
              Column(
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
              ),

              if (savedBaseline != null) ...[
                const Divider(height: 24, color: Colors.white24),
                Text(
                  'BASELINE (${savedBaseline.mode.toUpperCase()})',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: Colors.white54, letterSpacing: 1.0),
                ),
                const SizedBox(height: 8),
                _buildMetricRow(
                  'Base Frame',
                  '${savedBaseline.totalFrameTimeMs.toStringAsFixed(1)} ms',
                  Colors.orangeAccent,
                ),
                _buildMetricRow(
                  'Base Build',
                  '${savedBaseline.buildTimeMs.toStringAsFixed(1)} ms',
                  Colors.white70,
                ),
                _buildMetricRow(
                  'Base Raster',
                  '${savedBaseline.rasterTimeMs.toStringAsFixed(1)} ms',
                  Colors.white70,
                ),
                if (hasValidComparison) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isFaster
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isFaster
                            ? Colors.greenAccent.withValues(alpha: 0.3)
                            : Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      speedupBadge,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isFaster ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor) {
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
