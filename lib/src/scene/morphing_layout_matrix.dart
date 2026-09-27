import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'animated_stress_matrix.dart';
import 'polymorphic_widgets.dart';

class const MorphingLayoutMatrix({super.key, required super.nodeCount})
    extends AnimatedStressMatrix {
  @override
  int get periodSeconds => 4;

  @override
  Widget buildAnimated(BuildContext context, double animationValue) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final aspect = (w > 0 && h > 0) ? (w / h) : 1.6;

        final rawCols = math.sqrt(nodeCount * aspect);
        final columns = rawCols.ceil().clamp(1, nodeCount);
        final rows = (nodeCount / columns).ceil().clamp(1, nodeCount);

        final itemWidth = w / columns;
        final itemHeight = h / rows;
        final childAspectRatio = (itemWidth > 0 && itemHeight > 0)
            ? (itemWidth / itemHeight)
            : 1.6;

        final t = animationValue * 2 * math.pi;
        final dynamicAspect = (childAspectRatio + 0.08 * math.cos(t)).clamp(
          0.4,
          5.0,
        );

        // Ensure inner content doesn't collapse to 0.
        // Required minimum width and height per item is ~6.0 px (2px margin + 4px inner box).
        final maxAllowedSpacingW = (w - 6.0 * columns) / (columns + 1);
        final maxAllowedSpacingH =
            (w - 6.0 * columns * dynamicAspect) / (columns + 1);
        final maxAllowed = math.min(maxAllowedSpacingW, maxAllowedSpacingH);

        final spacingScale = (maxAllowed / 12.0).clamp(0.0, 1.0);
        final spacing = (8.0 + 4.0 * math.sin(t)) * spacingScale;

        final delegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: dynamicAspect,
        );

        return GridView.builder(
          padding: EdgeInsets.all(spacing),
          gridDelegate: delegate,
          itemCount: nodeCount,
          itemBuilder: (context, index) {
            return PolymorphicCard(
              index: index,
              animationValue: animationValue,
            );
          },
        );
      },
    );
  }
}
