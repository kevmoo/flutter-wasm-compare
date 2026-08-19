import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../metrics/benchmark_storage.dart';
import '../metrics/frame_timing_service.dart';
import '../scene/stress_controller.dart';
import 'url_helper.dart';

bool isCurrentlyWasm() => kIsWeb && kIsWasm;

bool isCurrentlySingleThreaded() => isCurrentlyWasm() && isSingleThreaded();

bool isCurrentlyPipelined() => isCurrentlyWasm() && !isSingleThreaded();

void toggleSingleThreadedMode(BuildContext context) {
  final currentSt = isSingleThreaded();
  final newSt = !currentSt;
  savePersistedSingleThreaded(newSt);

  if (isCurrentlyWasm()) {
    final metrics = context.read<FrameTimingService>().metrics;
    final stressCtrl = context.read<StressController>();

    BenchmarkStorage.saveMetrics(
      mode: 'wasm',
      metrics: metrics,
      stressLevel: stressCtrl.currentLabel,
      nodeCount: stressCtrl.nodeCount,
      isPipelined: !currentSt,
    );

    reloadWithQueryParams({'st': newSt ? '1' : '0'});
  } else {
    updateUrlQueryParam('st', newSt ? '1' : '0');
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          newSt
              ? '⚡ Wasm single-threaded mode enabled (will apply on Wasm)'
              : '⚡ Wasm multi-threaded mode enabled (will apply on Wasm)',
        ),
      ),
    );
  }
}

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
    isPipelined: isCurrentlyPipelined(),
  );

  reloadWithQueryParams({'mode': mode});
}
