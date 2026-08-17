import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../metrics/benchmark_storage.dart';
import '../metrics/frame_timing_service.dart';
import '../scene/stress_controller.dart';
import 'url_helper.dart';

bool isCurrentlyWasm() => kIsWeb && kIsWasm;

void switchEngineMode(BuildContext context, {required String mode}) {
  final currentMode = isCurrentlyWasm() ? 'wasm' : 'js';
  if (currentMode == mode) return;

  final metrics = context.read<FrameTimingService>().metrics;
  final stressCtrl = context.read<StressController>();

  BenchmarkStorage.saveMetrics(
    mode: currentMode,
    metrics: metrics,
    stressLevel: stressCtrl.currentLabel,
    nodeCount: stressCtrl.nodeCount,
  );

  navigateToEngineMode(mode);
}
