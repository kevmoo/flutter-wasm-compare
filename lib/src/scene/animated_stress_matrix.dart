import 'package:flutter/material.dart';

class const AnimatedStressMatrix({
  super.key,
  required final int nodeCount,
  required final Duration duration,
  required final Widget Function(
    BuildContext context,
    Animation<double> animation,
  )
  builder,
}) extends StatefulWidget {
  @override
  State<AnimatedStressMatrix> createState() => _AnimatedStressMatrixState();
}

class _AnimatedStressMatrixState()
    extends State<AnimatedStressMatrix>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
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
      builder: (context, _) => widget.builder(context, _controller),
    );
  }
}
