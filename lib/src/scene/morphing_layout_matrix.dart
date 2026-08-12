import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'polymorphic_widgets.dart';

class MorphingLayoutMatrix extends StatefulWidget {
  final int nodeCount;

  const MorphingLayoutMatrix({super.key, required this.nodeCount});

  @override
  State<MorphingLayoutMatrix> createState() => _MorphingLayoutMatrixState();
}

class _MorphingLayoutMatrixState extends State<MorphingLayoutMatrix>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodeCount <= 0) {
      return const Center(
        child: Text(
          'Zero Stress (Idle)',
          style: TextStyle(color: Colors.white38, fontSize: 16),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final aspect = (w > 0 && h > 0) ? (w / h) : 1.6;

        final rawCols = math.sqrt(widget.nodeCount * aspect);
        final columns = rawCols.ceil().clamp(1, widget.nodeCount);
        final rows = (widget.nodeCount / columns).ceil().clamp(
          1,
          widget.nodeCount,
        );

        final itemWidth = w / columns;
        final itemHeight = h / rows;
        final childAspectRatio = (itemWidth > 0 && itemHeight > 0)
            ? (itemWidth / itemHeight)
            : 1.6;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return GridView.builder(
              key: ValueKey('grid_${widget.nodeCount}'),
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(2.0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 2.0,
                mainAxisSpacing: 2.0,
              ),
              itemCount: widget.nodeCount,
              itemBuilder: (context, index) {
                return PolymorphicCard(
                  key: ValueKey('card_$index'),
                  index: index,
                  animationValue: _controller.value,
                );
              },
            );
          },
        );
      },
    );
  }
}
