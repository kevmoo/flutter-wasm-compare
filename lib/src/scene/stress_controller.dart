import 'dart:async';

import 'package:flutter/foundation.dart';

import '../metrics/frame_timing_service.dart';
import '../shell/url_helper.dart';

enum StressPreset {
  none(0, 'None'),
  light(100, 'Light (100)'),
  medium(500, 'Medium (500)'),
  heavy(1500, 'Heavy (1.5k)'),
  extreme(4000, 'Extreme (4k)');

  final int nodeCount;
  final String label;

  const StressPreset(this.nodeCount, this.label);
}

enum StressMode { preset, float, manual }

typedef _TuneStepResult = ({
  int newNodeCount,
  int newStableRounds,
  bool shouldFinish,
  String status,
});

_TuneStepResult _evaluateTuneStep({
  required int nodeCount,
  required int stableRounds,
  required FrameTimingMetrics metrics,
}) {
  final is120Hz = metrics.fps > 80.0;
  final targetBudgetMs = is120Hz ? 7.8 : 15.0;
  final targetFps = is120Hz ? 115.0 : 57.0;

  final currentMs = metrics.totalFrameTimeMs;
  final currentFps = metrics.fps;
  final msText = currentMs.toStringAsFixed(1);

  if (currentMs < (targetBudgetMs - 1.2) && currentFps >= targetFps) {
    final step = switch (nodeCount) {
      < 500 => 100,
      < 1500 => 200,
      _ => 300,
    };
    final nextNodes = nodeCount + step;
    return (
      newNodeCount: nextNodes,
      newStableRounds: 0,
      shouldFinish: false,
      status: 'Tuning: $nextNodes nodes ($msText ms)',
    );
  }

  final updatedRounds = stableRounds + 1;
  final shouldFinish = updatedRounds >= 2;
  final finalFpsLabel = is120Hz ? '120 FPS' : '60 FPS';
  final status = shouldFinish
      ? 'Locked: $nodeCount nodes at $finalFpsLabel ($msText ms)'
      : 'Stabilizing: $nodeCount nodes ($msText ms)';

  return (
    newNodeCount: nodeCount,
    newStableRounds: updatedRounds,
    shouldFinish: shouldFinish,
    status: status,
  );
}

class StressController extends ChangeNotifier {
  StressMode _mode = StressMode.preset;
  StressPreset _preset = StressPreset.medium;
  int _nodeCount = StressPreset.medium.nodeCount;
  bool _isAutoTuning = false;
  String _autoTuneStatus = '';
  Timer? _tuningTimer;

  StressMode get mode => _mode;
  StressPreset get preset => _preset;
  int get nodeCount => _nodeCount;
  bool get isAutoTuning => _isAutoTuning;
  String get autoTuneStatus => _autoTuneStatus;

  String get currentLabel => switch (_mode) {
    StressMode.preset => _preset.name.toUpperCase(),
    StressMode.float => 'FLOAT ($nodeCount)',
    StressMode.manual => 'MANUAL ($nodeCount)',
  };

  StressController() {
    _parseInitialQuery();
  }

  void _parseInitialQuery() {
    final params = Uri.base.queryParameters;
    final stressParam = params['stress']?.toLowerCase();
    final nodesParam = int.tryParse(params['nodes'] ?? '');

    if (stressParam == 'float') {
      _mode = StressMode.float;
      _nodeCount = nodesParam ?? 1000;
      _autoTuneStatus = 'Capacity: $_nodeCount nodes';
    } else if (stressParam == 'manual' && nodesParam != null) {
      _mode = StressMode.manual;
      _nodeCount = nodesParam.clamp(0, 8000);
    } else if (stressParam != null) {
      for (final p in StressPreset.values) {
        if (p.name == stressParam) {
          _preset = p;
          _nodeCount = p.nodeCount;
          _mode = StressMode.preset;
          break;
        }
      }
    }
  }

  void setPreset(StressPreset p) {
    _stopTuning();
    _mode = StressMode.preset;
    _preset = p;
    _nodeCount = p.nodeCount;
    updateUrlQueryParam('stress', p.name);
    notifyListeners();
  }

  void setManualNodes(int count) {
    _stopTuning();
    _mode = StressMode.manual;
    _nodeCount = count.clamp(0, 8000);
    updateUrlQueryParam('stress', 'manual');
    updateUrlQueryParam('nodes', '$_nodeCount');
    notifyListeners();
  }

  void startAutoTune(FrameTimingService timingService) {
    _stopTuning();
    _mode = StressMode.float;
    _isAutoTuning = true;
    _nodeCount = 100;
    _autoTuneStatus = 'Calibrating baseline...';
    notifyListeners();

    var stableRounds = 0;

    _tuningTimer = Timer.periodic(const Duration(milliseconds: 350), (timer) {
      final metrics = timingService.metrics;
      if (metrics.totalFrameTimeMs <= 0.1) return;

      final result = _evaluateTuneStep(
        nodeCount: _nodeCount,
        stableRounds: stableRounds,
        metrics: metrics,
      );

      _nodeCount = result.newNodeCount;
      stableRounds = result.newStableRounds;
      _autoTuneStatus = result.status;

      if (result.shouldFinish) {
        _stopTuning();
        updateUrlQueryParam('stress', 'float');
        updateUrlQueryParam('nodes', '$_nodeCount');
      }
      notifyListeners();
    });
  }

  void _stopTuning() {
    _isAutoTuning = false;
    _tuningTimer?.cancel();
    _tuningTimer = null;
  }

  @override
  void dispose() {
    _stopTuning();
    super.dispose();
  }
}
