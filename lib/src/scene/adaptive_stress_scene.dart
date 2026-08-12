import 'package:flutter/material.dart';

import 'morphing_layout_matrix.dart';

class AdaptiveStressScene extends StatelessWidget {
  final int nodeCount;

  const AdaptiveStressScene({super.key, required this.nodeCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      child: MorphingLayoutMatrix(nodeCount: nodeCount),
    );
  }
}
