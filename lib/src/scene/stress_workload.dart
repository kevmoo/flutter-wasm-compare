import 'package:flutter/material.dart';

import 'bouncy_layout_matrix.dart';
import 'morphing_layout_matrix.dart';
import 'stress_controller.dart';

/// Abstraction for a pluggable Flutter performance exercise workload.
///
/// Each workload exercises a distinct aspect of the Flutter framework and
/// engine pipeline (e.g., deep `RenderFlex` layout invalidation vs. canvas
/// paint/rasterization) and defines its own calibrated difficulty ladder.
abstract class const StressWorkload({
  required final String id,
  required final String title,
  required final String subtitle,
  required final String unitLabel,
  required final List<int> ladder,
}) {
  /// Returns the calibrated node count `N` for the given [preset].
  int nodeCountForPreset(StressPreset preset);

  /// Builds the active workload widget tree for [nodeCount].
  Widget build(BuildContext context, int nodeCount);
}

/// Exercises deep recursive `RenderFlex` layout invalidation (`performLayout`)
/// and Material/Cupertino widget churn, modeled after Yegor's `bouncy_demo`.
class const BouncyLayoutWorkload() extends StressWorkload {
  this
    : super(
        id: 'bouncy',
        title: 'Bouncy Layout Churn',
        subtitle: 'Recursive RenderFlex relayout & widget tree churn',
        unitLabel: 'Widgets',
        ladder: kBouncyLadder,
      );

  static const List<int> kBouncyLadder = [
    0,
    8,
    16,
    32,
    48,
    64,
    96,
    128,
    192,
    256,
    384,
    512,
    768,
    1024,
  ];

  @override
  int nodeCountForPreset(StressPreset preset) => switch (preset) {
    StressPreset.none => 0,
    StressPreset.light => 32,
    StressPreset.medium => 64,
    StressPreset.heavy => 128,
    StressPreset.extreme => 256,
  };

  @override
  Widget build(BuildContext context, int nodeCount) {
    return BouncyLayoutMatrix(nodeCount: nodeCount);
  }
}

/// Exercises high-density vector path painting and Skwasm/CanvasKit rasterization
/// across a responsive grid of polymorphic dashboard cards.
class const PolymorphicGridWorkload() extends StressWorkload {
  this
    : super(
        id: 'grid',
        title: 'Polymorphic Card Grid',
        subtitle: 'Canvas path painting & multi-threaded rasterization',
        unitLabel: 'Cards',
        ladder: kDecadeEngineeringLadder,
      );

  @override
  int nodeCountForPreset(StressPreset preset) => preset.nodeCount;

  @override
  Widget build(BuildContext context, int nodeCount) {
    return MorphingLayoutMatrix(nodeCount: nodeCount);
  }
}

const List<StressWorkload> kAllWorkloads = [
  BouncyLayoutWorkload(),
  PolymorphicGridWorkload(),
];

StressWorkload resolveWorkload(String? id) {
  final normalized = id?.trim().toLowerCase();
  for (final workload in kAllWorkloads) {
    if (workload.id == normalized) {
      return workload;
    }
  }
  return const BouncyLayoutWorkload();
}
