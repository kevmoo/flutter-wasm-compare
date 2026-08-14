import 'package:flutter/foundation.dart';

import '../metrics/benchmark_storage.dart';
import '../shell/url_helper.dart';

const List<int> kDecadeEngineeringLadder = [
  0,
  25,
  50,
  100,
  200,
  350,
  500,
  750,
  1000,
  1500,
  2000,
  3000,
  4000,
  5000,
];

enum StressPreset {
  none(0, 'None (0)'),
  light(100, 'Light (100)'),
  medium(500, 'Medium (500)'),
  heavy(1500, 'Heavy (1.5k)'),
  extreme(4000, 'Extreme (4k)');

  final int nodeCount;
  final String label;

  const StressPreset(this.nodeCount, this.label);
}

enum StressMode { preset, manual }

class StressController extends ChangeNotifier {
  StressMode _mode = StressMode.preset;
  StressPreset _preset = StressPreset.medium;
  int _nodeCount = StressPreset.medium.nodeCount;

  double _targetRefreshRate = 60.0;
  bool _hasAllowedDeviceDetails = false;
  String? _deviceDetailsLabel;

  StressMode get mode => _mode;
  StressPreset get preset => _preset;
  int get nodeCount => _nodeCount;

  double get targetRefreshRate => _targetRefreshRate;
  bool get hasAllowedDeviceDetails => _hasAllowedDeviceDetails;
  String? get deviceDetailsLabel => _deviceDetailsLabel;

  bool get canStepDown => _nodeCount > kDecadeEngineeringLadder.first;
  bool get canStepUp => _nodeCount < kDecadeEngineeringLadder.last;

  String get formattedNodeCount {
    if (_nodeCount >= 1000) {
      final kVal = _nodeCount / 1000.0;
      return kVal == kVal.roundToDouble()
          ? '${kVal.toInt()}k'
          : '${kVal.toStringAsFixed(1)}k';
    }
    return '$_nodeCount';
  }

  String get currentLabel => switch (_mode) {
    StressMode.preset => _preset.name.toUpperCase(),
    StressMode.manual => 'MANUAL ($formattedNodeCount)',
  };

  StressController() {
    _parseInitialQuery();
    BenchmarkStorage.invalidateIfNodeCountChanged(_nodeCount);
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

    if (stressParam == 'manual' && nodesParam != null) {
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

  void stepDown() {
    var target = kDecadeEngineeringLadder.first;
    for (final rung in kDecadeEngineeringLadder) {
      if (rung < _nodeCount) {
        target = rung;
      } else {
        break;
      }
    }
    setManualNodes(target);
  }

  void stepUp() {
    for (final rung in kDecadeEngineeringLadder) {
      if (rung > _nodeCount) {
        setManualNodes(rung);
        return;
      }
    }
    setManualNodes(kDecadeEngineeringLadder.last);
  }

  void setPreset(StressPreset p) {
    _mode = StressMode.preset;
    _preset = p;
    _nodeCount = p.nodeCount;
    BenchmarkStorage.invalidateIfNodeCountChanged(_nodeCount);
    updateUrlQueryParam('stress', p.name);
    updateUrlQueryParam('nodes', '');
    notifyListeners();
  }

  void setManualNodes(int count) {
    _mode = StressMode.manual;
    _nodeCount = count.clamp(0, 8000);
    BenchmarkStorage.invalidateIfNodeCountChanged(_nodeCount);

    // Check if matching preset exists
    for (final p in StressPreset.values) {
      if (p.nodeCount == _nodeCount) {
        _preset = p;
        _mode = StressMode.preset;
        updateUrlQueryParam('stress', p.name);
        updateUrlQueryParam('nodes', '');
        notifyListeners();
        return;
      }
    }

    updateUrlQueryParam('stress', 'manual');
    updateUrlQueryParam('nodes', '$_nodeCount');
    notifyListeners();
  }
}
