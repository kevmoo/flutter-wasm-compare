import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../shell/url_helper.dart';

class FrameTimingMetrics {
  final double fps;
  final double buildTimeMs;
  final double rasterTimeMs;
  final double totalFrameTimeMs;

  FrameTimingMetrics({
    this.fps = 0.0,
    this.buildTimeMs = 0.0,
    this.rasterTimeMs = 0.0,
    this.totalFrameTimeMs = 0.0,
  });
}

class FrameTimingService extends ChangeNotifier {
  final Queue<FrameTiming> _timingsLog = Queue<FrameTiming>();
  static const int _maxFrames = 120;

  FrameTimingMetrics _metrics = FrameTimingMetrics();
  FrameTimingMetrics get metrics => _metrics;

  FrameTimingService() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    var hasNew = false;
    for (final timing in timings) {
      _timingsLog.addLast(timing);
      hasNew = true;
    }

    while (_timingsLog.length > _maxFrames) {
      _timingsLog.removeFirst();
    }

    if (hasNew) {
      _computeMetrics();
    }
  }

  void _computeMetrics() {
    if (_timingsLog.isEmpty) return;

    var totalBuild = 0.0;
    var totalRaster = 0.0;
    var totalFrame = 0.0;

    for (final timing in _timingsLog) {
      totalBuild += timing.buildDuration.inMicroseconds / 1000.0;
      totalRaster += timing.rasterDuration.inMicroseconds / 1000.0;
      totalFrame += timing.totalSpan.inMicroseconds / 1000.0;
    }

    final count = _timingsLog.length;

    // FPS computation based on period of frame timings
    final first = _timingsLog.first;
    final last = _timingsLog.last;

    final elapsedMs =
        last.timestampInMicroseconds(FramePhase.buildStart) / 1000.0 -
        first.timestampInMicroseconds(FramePhase.buildStart) / 1000.0;

    var fps = 0.0;
    if (elapsedMs > 0 && count > 1) {
      fps = (count - 1) * 1000.0 / elapsedMs;
    } else {
      fps = 60.0; // fallback default
    }

    _metrics = FrameTimingMetrics(
      fps: fps,
      buildTimeMs: totalBuild / count,
      rasterTimeMs: totalRaster / count,
      totalFrameTimeMs: totalFrame / count,
    );
    exportMetrics(
      fps: _metrics.fps,
      buildTimeMs: _metrics.buildTimeMs,
      rasterTimeMs: _metrics.rasterTimeMs,
      totalFrameTimeMs: _metrics.totalFrameTimeMs,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}
