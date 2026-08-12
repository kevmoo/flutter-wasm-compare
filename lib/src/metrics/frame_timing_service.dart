import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../shell/url_helper.dart';
import 'startup_metrics.dart';

class FrameTimingMetrics {
  final double fps;
  final double buildTimeMs;
  final double rasterTimeMs;
  final double totalFrameTimeMs;
  final double jitterMs;
  final double? startupTimeMs;

  FrameTimingMetrics({
    this.fps = 0.0,
    this.buildTimeMs = 0.0,
    this.rasterTimeMs = 0.0,
    this.totalFrameTimeMs = 0.0,
    this.jitterMs = 0.0,
    this.startupTimeMs,
  });
}

class FrameTimingService extends ChangeNotifier {
  final Queue<FrameTiming> _timingsLog = Queue<FrameTiming>();
  static const int _maxFrames = 120;

  FrameTimingMetrics _metrics = FrameTimingMetrics();
  FrameTimingMetrics get metrics => _metrics;

  double _highestFpsSeen = 60.0;
  double get highestFpsSeen => _highestFpsSeen;

  double? _startupTimeMs;
  double? get startupTimeMs => _startupTimeMs;

  FrameTimingService() {
    _startupTimeMs = getAppStartupTimeMs();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void recordStartupTime(double ms) {
    if (_startupTimeMs == null) {
      _startupTimeMs = ms;
      _computeMetrics();
    }
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

  void resetLog() {
    _timingsLog.clear();
  }

  FrameTimingMetrics sampleRecentMetrics({int frameCount = 15}) {
    if (_timingsLog.isEmpty) {
      return FrameTimingMetrics(
        fps: 60.0,
        startupTimeMs: _startupTimeMs ?? getAppStartupTimeMs(),
      );
    }
    final count = math.min(_timingsLog.length, frameCount);
    final recent = _timingsLog.toList().sublist(_timingsLog.length - count);
    return _calculateMetricsForSlice(
      recent,
      startupTimeMs: _startupTimeMs ?? getAppStartupTimeMs(),
    );
  }

  void _computeMetrics() {
    if (_timingsLog.isEmpty) return;

    _metrics = _calculateMetricsForSlice(
      _timingsLog.toList(),
      startupTimeMs: _startupTimeMs ?? getAppStartupTimeMs(),
    );
    if (_metrics.fps > _highestFpsSeen && _metrics.fps < 150.0) {
      _highestFpsSeen = _metrics.fps;
    }

    exportMetrics(
      fps: _metrics.fps,
      buildTimeMs: _metrics.buildTimeMs,
      rasterTimeMs: _metrics.rasterTimeMs,
      totalFrameTimeMs: _metrics.totalFrameTimeMs,
    );
    notifyListeners();
  }

  static FrameTimingMetrics _calculateMetricsForSlice(
    List<FrameTiming> timings, {
    double? startupTimeMs,
  }) {
    if (timings.isEmpty) {
      return FrameTimingMetrics(startupTimeMs: startupTimeMs);
    }

    var totalBuild = 0.0;
    var totalRaster = 0.0;
    var totalFrame = 0.0;

    for (final timing in timings) {
      totalBuild += timing.buildDuration.inMicroseconds / 1000.0;
      totalRaster += timing.rasterDuration.inMicroseconds / 1000.0;
      totalFrame += timing.totalSpan.inMicroseconds / 1000.0;
    }

    final count = timings.length;
    final meanTotal = totalFrame / count;

    var sumSquaredDiffs = 0.0;
    for (final timing in timings) {
      final frameMs = timing.totalSpan.inMicroseconds / 1000.0;
      final diff = frameMs - meanTotal;
      sumSquaredDiffs += diff * diff;
    }
    final variance = count > 1 ? (sumSquaredDiffs / (count - 1)) : 0.0;
    final jitterMs = math.sqrt(variance);

    final first = timings.first;
    final last = timings.last;

    final elapsedMs =
        last.timestampInMicroseconds(FramePhase.buildStart) / 1000.0 -
        first.timestampInMicroseconds(FramePhase.buildStart) / 1000.0;

    final fps = (elapsedMs > 0 && count > 1)
        ? (count - 1) * 1000.0 / elapsedMs
        : 60.0;

    return FrameTimingMetrics(
      fps: fps,
      buildTimeMs: totalBuild / count,
      rasterTimeMs: totalRaster / count,
      totalFrameTimeMs: meanTotal,
      jitterMs: jitterMs,
      startupTimeMs: startupTimeMs,
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}
