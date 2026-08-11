import 'dart:math';

import 'package:flutter/material.dart';

class WidgetChurnEngine extends StatefulWidget {
  final int nodeCount;
  final Widget child;

  const WidgetChurnEngine({
    super.key,
    required this.nodeCount,
    required this.child,
  });

  @override
  State<WidgetChurnEngine> createState() => _WidgetChurnEngineState();
}

class _WidgetChurnEngineState extends State<WidgetChurnEngine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random(42);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildLeafNode() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final flexVal =
            (_controller.value * 10 + _random.nextDouble() * 5).toInt() + 1;
        return Expanded(
          flex: flexVal,
          child: Container(
            margin: const EdgeInsets.all(0.2),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(
                alpha: 0.1 + _random.nextDouble() * 0.2,
              ),
              borderRadius: BorderRadius.circular(_controller.value * 4),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChurnBranch(int count, int depth) {
    if (count <= 0) return const SizedBox.shrink();
    if (count <= 1 || depth <= 0) {
      return _buildLeafNode();
    }

    final leftCount = count ~/ 2;
    final rightCount = count - leftCount;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final flexVal =
            (_controller.value * 10 + _random.nextDouble() * 5).toInt() + 1;
        final children = [
          _buildChurnBranch(leftCount, depth - 1),
          _buildChurnBranch(rightCount, depth - 1),
        ];

        return Expanded(
          flex: flexVal,
          child: depth.isEven
              ? Row(children: children)
              : Column(children: children),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodeCount <= 0) {
      return widget.child;
    }

    // Binary tree depth based on log2 of node count
    final depth = (log(widget.nodeCount) / ln2).ceil().clamp(1, 14);

    return Stack(
      children: [
        // Offscreen layout stress layer
        Positioned.fill(
          child: Opacity(
            opacity: 0.01,
            child: ClipRect(
              child: IgnorePointer(
                child: Row(
                  children: [_buildChurnBranch(widget.nodeCount, depth)],
                ),
              ),
            ),
          ),
        ),
        // User visible child
        Positioned.fill(child: widget.child),
      ],
    );
  }
}
