import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A recursive binary space partitioning (`Row`/`Column`) layout stress scene
/// modeled after Yegor's `bouncy_demo` (`kevmoo/holdings/bouncy_demo`).
///
/// Every internal node in the binary tree continuously oscillates its
/// `Flexible.flex` ratio (`5000 + delta` vs `5000 - delta`) on every frame,
/// invalidating `ParentData` and forcing a full-tree
/// `RenderFlex.performLayout()` cascade down to all [nodeCount] Material and
/// Cupertino leaf widgets.
class BouncyLayoutMatrix extends StatefulWidget {
  final int nodeCount;

  const new({super.key, required this.nodeCount});

  @override
  State<BouncyLayoutMatrix> createState() => _BouncyLayoutMatrixState();
}

class _BouncyLayoutMatrixState extends State<BouncyLayoutMatrix>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
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

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return _buildSubtree(
          context,
          nodeIndex: 1,
          count: widget.nodeCount,
          depth: 0,
        );
      },
    );
  }

  Widget _buildSubtree(
    BuildContext context, {
    required int nodeIndex,
    required int count,
    required int depth,
  }) {
    if (count <= 1) {
      return _BouncyLeafWidget(key: ValueKey<int>(nodeIndex), index: nodeIndex);
    }

    final firstCount = count ~/ 2;
    final secondCount = count - firstCount;

    // Deterministic per-node oscillation phase and direction matching
    // bouncy_demo.
    final isReversed = ((nodeIndex * 2654435761) >>> 16).isOdd;
    final phaseOffset = (nodeIndex * 0.17) % 1.0;
    final animVal = (_controller.value + phaseOffset) % 1.0;
    final delta =
        ((animVal - 0.5).abs() * 3000).toInt() * (isReversed ? -1 : 1);

    final children = <Widget>[
      Flexible(
        key: ValueKey<int>(nodeIndex * 2),
        flex: 5000 + delta,
        child: _buildSubtree(
          context,
          nodeIndex: nodeIndex * 2,
          count: firstCount,
          depth: depth + 1,
        ),
      ),
      Flexible(
        key: ValueKey<int>(nodeIndex * 2 + 1),
        flex: 5000 - delta,
        child: _buildSubtree(
          context,
          nodeIndex: nodeIndex * 2 + 1,
          count: secondCount,
          depth: depth + 1,
        ),
      ),
    ];

    if (depth.isEven) {
      return Column(key: ValueKey<int>(nodeIndex), children: children);
    } else {
      return Row(key: ValueKey<int>(nodeIndex), children: children);
    }
  }
}

enum _BouncyWidgetKind {
  button,
  checkbox,
  plainText,
  datePicker,
  progressIndicator,
  slider,
  appBar,
}

class _BouncyLeafWidget extends StatelessWidget {
  final int index;

  const new({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    final kind =
        _BouncyWidgetKind.values[index % _BouncyWidgetKind.values.length];

    final leafContent = switch (kind) {
      _BouncyWidgetKind.button => TextButton(
        onPressed: () {},
        child: const Text('Button'),
      ),
      _BouncyWidgetKind.checkbox => Checkbox(
        value: true,
        onChanged: (state) {},
      ),
      _BouncyWidgetKind.plainText => const Padding(
        padding: EdgeInsets.all(4),
        child: Text(
          'Flutter WebAssembly & JavaScript engine layout benchmark: '
          'continuous flex oscillation forces multi-line paragraph reflow, '
          'glyph shaping, and line-wrap recalculation on every frame.',
          style: TextStyle(fontSize: 11, height: 1.2),
        ),
      ),
      _BouncyWidgetKind.datePicker => CupertinoTimerPicker(
        onTimerDurationChanged: (duration) {},
      ),
      _BouncyWidgetKind.progressIndicator => const CircularProgressIndicator(),
      _BouncyWidgetKind.slider => Slider(
        value: 50,
        max: 100,
        onChanged: (value) {},
      ),
      _BouncyWidgetKind.appBar => AppBar(
        primary: false,
        leading: TextButton(onPressed: () {}, child: const Text('H')),
        title: const Text('ello'),
        actions: <Widget>[
          TextButton(onPressed: () {}, child: const Text('W')),
          TextButton(onPressed: () {}, child: const Text('o')),
          TextButton(onPressed: () {}, child: const Text('r')),
          TextButton(onPressed: () {}, child: const Text('l')),
          TextButton(onPressed: () {}, child: const Text('d')),
          TextButton(onPressed: () {}, child: const Text('!')),
        ],
      ),
    };

    return Container(
      margin: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // For plainText leaves, let effectiveWidth oscillate directly with
            // incoming flex width (down to 72px) so RenderParagraph /
            // SkParagraph is forced to recompute line breaks and word wrapping
            // on every single frame. For AppBar/CupertinoTimerPicker leaves,
            // maintain a 520px floor to prevent RenderFlex overflow assertions.
            final isReflowText = kind == _BouncyWidgetKind.plainText;
            final effectiveWidth = isReflowText
                ? math.max(72.0, constraints.maxWidth)
                : math.max(
                    constraints.maxWidth,
                    520.0 + (constraints.maxWidth * 0.2),
                  );
            final effectiveHeight = math.max(
              constraints.maxHeight,
              240.0 + (constraints.maxHeight * 0.2),
            );
            return OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: effectiveWidth,
              maxWidth: effectiveWidth,
              minHeight: effectiveHeight,
              maxHeight: effectiveHeight,
              child: leafContent,
            );
          },
        ),
      ),
    );
  }
}
