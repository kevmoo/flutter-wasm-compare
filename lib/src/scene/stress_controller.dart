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

enum _TuningPhase { ramping, backingOff, settled }

typedef _TuningState = ({
  int nodeCount,
  _TuningPhase phase,
  String status,
  bool isFinished,
});

_TuningState _evaluateAdaptiveStep({
  required int nodeCount,
  required _TuningPhase phase,
  required double budgetTargetMs,
  required int targetHz,
  required FrameTimingMetrics recentMetrics,
}) {
  final currentMs = recentMetrics.totalFrameTimeMs;
  final currentFps = recentMetrics.fps;
  final msText = currentMs.toStringAsFixed(1);
  final targetMinFps = targetHz == 120 ? 110.0 : 56.0;

  if (phase == _TuningPhase.backingOff) {
    return (
      nodeCount: nodeCount,
      phase: _TuningPhase.settled,
      status: 'Locked: $nodeCount nodes at $targetHz FPS ($msText ms)',
      isFinished: true,
    );
  }

  // Check if current load is within budget
  final isWithinBudget =
      currentMs < budgetTargetMs && currentFps >= targetMinFps;

  if (isWithinBudget) {
    final step = switch (currentMs / budgetTargetMs) {
      < 0.5 => 300,
      < 0.75 => 150,
      < 0.9 => 50,
      _ => 25,
    };
    final nextNodes = nodeCount + step;
    return (
      nodeCount: nextNodes,
      phase: _TuningPhase.ramping,
      status: 'Tuning: $nextNodes nodes ($msText ms)',
      isFinished: false,
    );
  }

  // Overshot budget: back off by 12% to guarantee stable headroom
  final backedOffNodes = (nodeCount * 0.88).toInt().clamp(50, 8000);
  return (
    nodeCount: backedOffNodes,
    phase: _TuningPhase.backingOff,
    status: 'Settling at $backedOffNodes nodes ($msText ms)...',
    isFinished: false,
  );
}

class StressController extends ChangeNotifier {
  StressMode _mode = StressMode.preset;
  StressPreset _preset = StressPreset.medium;
  int _nodeCount = StressPreset.medium.nodeCount;
  bool _isAutoTuning = false;
  String _autoTuneStatus = '';
  Timer? _tuningTimer;

  double _targetRefreshRate = 60.0;
  bool _hasAllowedDeviceDetails = false;
  String? _deviceDetailsLabel;

  StressMode get mode => _mode;
  StressPreset get preset => _preset;
  int get nodeCount => _nodeCount;
  bool get isAutoTuning => _isAutoTuning;
  String get autoTuneStatus => _autoTuneStatus;

  double get targetRefreshRate => _targetRefreshRate;
  bool get hasAllowedDeviceDetails => _hasAllowedDeviceDetails;
  String? get deviceDetailsLabel => _deviceDetailsLabel;

  String get currentLabel => switch (_mode) {
    StressMode.preset => _preset.name.toUpperCase(),
    StressMode.float => 'FLOAT ($nodeCount)',
    StressMode.manual => 'MANUAL ($nodeCount)',
  };

  StressController() {
    _parseInitialQuery();
  }

  void _parseInitialQuery() {
    final persistedHz = getPersistedRefreshRate();
    if (persistedHz != null && persistedHz > 0) {
      _targetRefreshRate = persistedHz;
      _hasAllowedDeviceDetails = true;
      _deviceDetailsLabel = '⚡ ${persistedHz.toInt()} Hz Display';
    }

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

  Future<void> allowDeviceDetails() async {
    final rate = await requestScreenRefreshRate();
    _hasAllowedDeviceDetails = true;
    if (rate != null && rate > 0) {
      _targetRefreshRate = rate;
      _deviceDetailsLabel = '⚡ ${rate.toInt()} Hz Display';
      savePersistedRefreshRate(rate);
    } else {
      _targetRefreshRate = 60.0;
      _deviceDetailsLabel = '60 Hz Default';
      savePersistedRefreshRate(60.0);
    }
    notifyListeners();
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

    final targetHz = _targetRefreshRate.toInt();
    // 85% of budget target: 7.1ms for 120Hz (8.33ms), 14.2ms for 60Hz (16.67ms)
    final budgetTargetMs = targetHz >= 100 ? 7.1 : 14.2;

    _autoTuneStatus = 'Calibrating ($targetHz FPS target)...';
    timingService.resetLog();
    notifyListeners();

    var currentPhase = _TuningPhase.ramping;

    _tuningTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      final recent = timingService.sampleRecentMetrics(frameCount: 12);
      if (recent.totalFrameTimeMs <= 0.1) return;

      final result = _evaluateAdaptiveStep(
        nodeCount: _nodeCount,
        phase: currentPhase,
        budgetTargetMs: budgetTargetMs,
        targetHz: targetHz,
        recentMetrics: recent,
      );

      _nodeCount = result.nodeCount;
      currentPhase = result.phase;
      _autoTuneStatus = result.status;

      if (result.isFinished) {
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
