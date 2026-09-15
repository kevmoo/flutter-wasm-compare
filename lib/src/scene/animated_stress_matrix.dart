import 'package:flutter/material.dart';

abstract class const AnimatedStressMatrix({
  super.key,
  required final int nodeCount,
}) extends StatefulWidget {
  int get periodSeconds;

  Widget buildAnimated(BuildContext context, double animationValue);

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
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.periodSeconds),
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
      builder: (context, _) => widget.buildAnimated(context, _controller.value),
    );
  }
}
