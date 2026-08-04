import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../metrics/benchmark_storage.dart';
import '../metrics/frame_timing_service.dart';

class PerformanceHud extends StatelessWidget {
  const PerformanceHud({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FrameTimingService>(
      builder: (context, timingService, child) {
        final metrics = timingService.metrics;
        final savedBaseline = BenchmarkStorage.getLastRun();
        final isFaster =
            savedBaseline != null && metrics.fps > savedBaseline.fps;
        final ratio = savedBaseline != null && savedBaseline.fps > 0
            ? (isFaster
                  ? (metrics.fps / savedBaseline.fps).toStringAsFixed(2)
                  : (savedBaseline.fps / metrics.fps).toStringAsFixed(2))
            : '0.00';
        final speedupText = isFaster ? '${ratio}x Faster' : '${ratio}x Slower';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
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
                'LIVE PERFORMANCE',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Colors.white54, letterSpacing: 1.5),
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

              if (savedBaseline != null) ...[
                const Divider(height: 24, color: Colors.white24),
                Text(
                  'BASELINE (${savedBaseline.mode.toUpperCase()})',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: Colors.white54, letterSpacing: 1.5),
                ),
                const SizedBox(height: 8),
                _buildMetricRow(
                  'Recorded FPS',
                  savedBaseline.fps.toStringAsFixed(1),
                  Colors.orangeAccent,
                ),
                if (savedBaseline.fps > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      speedupText,
                      style: TextStyle(
                        color: isFaster ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
