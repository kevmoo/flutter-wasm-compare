import 'package:flutter/foundation.dart';

import '../metrics/benchmark_storage.dart';
import '../shell/url_helper.dart';
import 'stress_workload.dart';

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

enum StressPreset(final int nodeCount) {
  none(0),
  light(100),
  medium(500),
  heavy(1500),
  extreme(4000)
}

enum StressMode() {
  preset,
  manual
}

class StressController({Uri? initialUri}) extends ChangeNotifier {
  StressWorkload _workload = const BouncyLayoutWorkload();
  StressMode _mode = StressMode.preset;
  StressPreset _preset = StressPreset.medium;
  late int _nodeCount = _workload.nodeCountForPreset(_preset);

  double _targetRefreshRate = 60.0;
  bool _hasAllowedDeviceDetails = false;
  String? _deviceDetailsLabel;

  StressWorkload get workload => _workload;
  StressMode get mode => _mode;
  StressPreset get preset => _preset;
  int get nodeCount => _nodeCount;

  double get targetRefreshRate => _targetRefreshRate;
  bool get hasAllowedDeviceDetails => _hasAllowedDeviceDetails;
  String? get deviceDetailsLabel => _deviceDetailsLabel;

  List<int> get activeLadder => _workload.ladder;

  bool get canStepDown => _nodeCount > activeLadder.first;
  bool get canStepUp => _nodeCount < activeLadder.last;

  String get formattedNodeCount {
    if (_nodeCount >= 1000) {
      final kVal = _nodeCount / 1000.0;
      return kVal == kVal.roundToDouble()
          ? '${kVal.toInt()}k'
          : '${kVal.toStringAsFixed(1)}k';
    }
    return '$_nodeCount';
  }

  String presetLabelFor(StressPreset p) {
    final count = _workload.nodeCountForPreset(p);
    if (count == 0) return 'None (0)';
    final countText = count >= 1000
        ? '${(count / 1000.0).toStringAsFixed(count % 1000 == 0 ? 0 : 1)}k'
        : '$count';
    final nameCap = p.name[0].toUpperCase() + p.name.substring(1);
    return '$nameCap ($countText)';
  }

  String get currentLabel => switch (_mode) {
    StressMode.preset => _preset.name.toUpperCase(),
    StressMode.manual => 'MANUAL ($formattedNodeCount)',
  };

  this {
    _parseInitialQuery(initialUri ?? Uri.base);
    BenchmarkStorage.invalidateIfNodeCountChanged(
      _nodeCount,
      workloadId: _workload.id,
    );
  }

  void _parseInitialQuery(Uri uri) {
    final persistedHz = getPersistedRefreshRate();
    if (persistedHz != null && persistedHz > 0) {
      _targetRefreshRate = persistedHz;
      _hasAllowedDeviceDetails = true;
      _deviceDetailsLabel = '⚡ ${persistedHz.toInt()} Hz Display';
    }

    final params = uri.queryParameters;
    final workloadParam = params['workload'];
    _workload = resolveWorkload(workloadParam);
    _nodeCount = _workload.nodeCountForPreset(_preset);

    final stressParam = params['stress']?.toLowerCase();
    final nodesParam = int.tryParse(params['nodes'] ?? '');

    if (nodesParam != null) {
      _nodeCount = nodesParam.clamp(0, activeLadder.last);
      _mode = StressMode.manual;
      for (final p in StressPreset.values) {
        if (_workload.nodeCountForPreset(p) == _nodeCount) {
          _preset = p;
          _mode = StressMode.preset;
          break;
        }
      }
    } else if (stressParam != null) {
      for (final p in StressPreset.values) {
        if (p.name == stressParam) {
          _preset = p;
          _nodeCount = _workload.nodeCountForPreset(p);
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

  void setWorkload(StressWorkload newWorkload) {
    if (_workload.id == newWorkload.id) return;
    _workload = newWorkload;

    if (_mode == StressMode.preset) {
      _nodeCount = _workload.nodeCountForPreset(_preset);
    } else {
      _nodeCount = _nodeCount.clamp(0, activeLadder.last);
    }

    BenchmarkStorage.invalidateIfNodeCountChanged(
      _nodeCount,
      workloadId: _workload.id,
    );
    updateUrlQueryParam('workload', _workload.id);
    if (_mode == StressMode.preset) {
      updateUrlQueryParam('stress', _preset.name);
      updateUrlQueryParam('nodes', '');
    } else {
      updateUrlQueryParam('stress', 'manual');
      updateUrlQueryParam('nodes', '$_nodeCount');
    }
    notifyListeners();
  }

  void stepDown() {
    var target = activeLadder.first;
    for (final rung in activeLadder) {
      if (rung < _nodeCount) {
        target = rung;
      } else {
        break;
      }
    }
    setManualNodes(target);
  }

  void stepUp() {
    for (final rung in activeLadder) {
      if (rung > _nodeCount) {
        setManualNodes(rung);
        return;
      }
    }
    setManualNodes(activeLadder.last);
  }

  void setPreset(StressPreset p) {
    _mode = StressMode.preset;
    _preset = p;
    _nodeCount = _workload.nodeCountForPreset(p);
    BenchmarkStorage.invalidateIfNodeCountChanged(
      _nodeCount,
      workloadId: _workload.id,
    );
    updateUrlQueryParam('stress', p.name);
    updateUrlQueryParam('nodes', '');
    notifyListeners();
  }

  void setManualNodes(int count) {
    _mode = StressMode.manual;
    _nodeCount = count.clamp(0, activeLadder.last);
    BenchmarkStorage.invalidateIfNodeCountChanged(
      _nodeCount,
      workloadId: _workload.id,
    );

    // Check if matching preset exists for active workload
    for (final p in StressPreset.values) {
      if (_workload.nodeCountForPreset(p) == _nodeCount) {
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
