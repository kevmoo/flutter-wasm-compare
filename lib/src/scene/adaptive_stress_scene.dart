import 'package:flutter/material.dart';

import 'stress_workload.dart';

class AdaptiveStressScene extends StatelessWidget {
  final StressWorkload workload;
  final int nodeCount;

  const new({super.key, required this.workload, required this.nodeCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      child: workload.build(context, nodeCount),
    );
  }
}
