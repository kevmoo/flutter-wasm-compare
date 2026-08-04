import 'dart:math';

import 'package:flutter/material.dart';

enum StressLevel { none, light, medium, heavy, extreme }

class WidgetChurnEngine extends StatefulWidget {
  final StressLevel stressLevel;
  final Widget child;

  const WidgetChurnEngine({
    super.key,
    required this.stressLevel,
    required this.child,
  });

  @override
  State<WidgetChurnEngine> createState() => _WidgetChurnEngineState();
}

class _WidgetChurnEngineState extends State<WidgetChurnEngine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _nodeCount {
    switch (widget.stressLevel) {
      case StressLevel.none:
        return 0;
      case StressLevel.light:
        return 50;
      case StressLevel.medium:
        return 200;
      case StressLevel.heavy:
        return 500;
      case StressLevel.extreme:
        return 1500;
    }
  }

  Widget _buildChurnNode(int depth) {
    if (depth <= 0) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // High frequency layout mutations
        final flexVal =
            (_controller.value * 10 + _random.nextDouble() * 5).toInt() + 1;

        return Expanded(
          flex: flexVal,
          child: Container(
            margin: const EdgeInsets.all(0.5),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(
                alpha: 0.1 + _random.nextDouble() * 0.2,
              ),
              borderRadius: BorderRadius.circular(_controller.value * 4),
            ),
            child: _buildChurnNode(depth - 1),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stressLevel == StressLevel.none) {
      return widget.child;
    }

    // A hidden, offscreen or clipped layer that does the heavy layout/paint computation
    // without messing up the main user-facing responsive view.
    return Stack(
      children: [
        // Hidden stress layer
        Positioned.fill(
          child: Opacity(
            opacity: 0.01,
            child: ClipRect(
              child: IgnorePointer(
                child: Row(
                  children: List.generate(
                    (_nodeCount / 10).clamp(1, 20).toInt(),
                    (index) {
                      return _buildChurnNode(
                        (_nodeCount / 20).clamp(1, 10).toInt(),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        // Visible child
        Positioned.fill(child: widget.child),
      ],
    );
  }
}
