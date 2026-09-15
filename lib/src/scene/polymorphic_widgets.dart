import 'dart:math' as math;

import 'package:flutter/material.dart';

enum _WidgetCategory() {
  sparklineCard,
  gaugeCard,
  progressCard,
  chipCard,
  statusCard,
  waveCard,
}

class const PolymorphicCard({
  super.key,
  required final int index,
  required final double animationValue,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final categories = _WidgetCategory.values;
    final category = categories[index % categories.length];

    return Container(
      margin: const EdgeInsets.all(1.0),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.none,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(
          width: 140,
          height: 80,
          child: Padding(
            padding: const EdgeInsets.all(6.0),
            child: switch (category) {
              _WidgetCategory.sparklineCard => _buildSparklineCard(context),
              _WidgetCategory.gaugeCard => _buildGaugeCard(context),
              _WidgetCategory.progressCard => _buildProgressCard(context),
              _WidgetCategory.chipCard => _buildChipCard(context),
              _WidgetCategory.statusCard => _buildStatusCard(context),
              _WidgetCategory.waveCard => _buildWaveCard(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSparklineCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'WAVE #$index',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Icon(Icons.show_chart, size: 12, color: Colors.orangeAccent),
          ],
        ),
        const SizedBox(height: 2),
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _SparklinePainter(
              animationValue: animationValue,
              index: index,
              color: Colors.orangeAccent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGaugeCard(BuildContext context) {
    final gauge =
        ((math.sin(animationValue * 3 * math.pi + index * 1.2) + 1) * 50)
            .toStringAsFixed(0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CORE #$index',
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$gauge ops',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const Icon(Icons.speed, size: 20, color: Colors.cyanAccent),
      ],
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    final progress =
        ((math.cos(animationValue * 2 * math.pi + index * 0.5) + 1) / 2).clamp(
          0.05,
          0.95,
        );
    return Row(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 3,
            color: Colors.purpleAccent,
            backgroundColor: Colors.white10,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SYNC $index',
                style: const TextStyle(
                  color: Colors.purpleAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: Colors.purpleAccent,
                  backgroundColor: Colors.white10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChipCard(BuildContext context) {
    final isOdd = index.isOdd;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.amberAccent.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOdd ? Icons.bolt : Icons.auto_awesome,
              size: 11,
              color: Colors.amberAccent,
            ),
            const SizedBox(width: 4),
            Text(
              'Node $index',
              style: const TextStyle(
                fontSize: 9,
                color: Colors.amberAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final active = math.sin(animationValue * 4 * math.pi + index) > 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'TH #$index',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: active ? Colors.greenAccent : Colors.white38,
          ),
        ),
        Icon(
          active ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: active ? Colors.greenAccent : Colors.white24,
        ),
      ],
    );
  }

  Widget _buildWaveCard(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.tealAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.tealAccent.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.memory, size: 12, color: Colors.tealAccent),
            const SizedBox(width: 4),
            Text(
              'WASM #$index',
              style: const TextStyle(
                color: Colors.tealAccent,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter({
  required final double animationValue,
  required final int index,
  required final Color color,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 2 || size.height <= 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    const pointsCount = 8;
    for (var i = 0; i < pointsCount; i++) {
      final x = (i / (pointsCount - 1)) * size.width;
      final phase = animationValue * 2 * math.pi + i * 0.7 + index;
      final y = (size.height / 2) + math.sin(phase) * (size.height * 0.35);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => true;
}
