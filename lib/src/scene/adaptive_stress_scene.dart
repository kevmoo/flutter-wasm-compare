import 'package:flutter/material.dart';

import 'stress_workload.dart';

class const AdaptiveStressScene({
  super.key,
  required final StressWorkload workload,
  required final int nodeCount,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      child: workload.build(context, nodeCount),
    );
  }
}
