import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../shell/url_helper.dart';

class FrameTimingMetrics {
  final double fps;
  final double buildTimeMs;
  final double rasterTimeMs;
  final double totalFrameTimeMs;
  final double jitterMs;

  FrameTimingMetrics({
    this.fps = 0.0,
    this.buildTimeMs = 0.0,
    this.rasterTimeMs = 0.0,
    this.totalFrameTimeMs = 0.0,
    this.jitterMs = 0.0,
  });

  /// The active execution time on the critical path determining throughput.
  ///
  /// In pipelined/multithreaded mode (Wasm with dedicated raster worker),
  /// the UI thread and raster worker execute concurrently, so the throughput
  /// bottleneck is `max(buildTimeMs, rasterTimeMs)`.
  /// In single-threaded mode (JS CanvasKit), build and raster execute serially
  /// on the main thread, so the throughput bottleneck is
  /// `buildTimeMs + rasterTimeMs`.
  double activeFrameTimeMs({required bool isPipelined}) {
    if (isPipelined) {
      return math.max(buildTimeMs, rasterTimeMs);
    }
    return buildTimeMs + rasterTimeMs;
  }
}

class FrameTimingService extends ChangeNotifier {
  final Queue<FrameTiming> _timingsLog = Queue<FrameTiming>();
  static const int _maxFrames = 120;

  FrameTimingMetrics _metrics = FrameTimingMetrics();
  FrameTimingMetrics get metrics => _metrics;

  double _highestFpsSeen = 60.0;
  double get highestFpsSeen => _highestFpsSeen;

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

  void resetLog() {
    _timingsLog.clear();
  }

  FrameTimingMetrics sampleRecentMetrics({int frameCount = 15}) {
    if (_timingsLog.isEmpty) {
      return FrameTimingMetrics(fps: 60.0);
    }
    final count = math.min(_timingsLog.length, frameCount);
    final recent = _timingsLog.toList().sublist(_timingsLog.length - count);
    return _calculateMetricsForSlice(recent);
  }

  void _computeMetrics() {
    if (_timingsLog.isEmpty) return;

    _metrics = _calculateMetricsForSlice(_timingsLog.toList());
    if (_metrics.fps > _highestFpsSeen && _metrics.fps < 150.0) {
      _highestFpsSeen = _metrics.fps;
    }

    exportMetrics(
      fps: _metrics.fps,
      buildTimeMs: _metrics.buildTimeMs,
      rasterTimeMs: _metrics.rasterTimeMs,
      totalFrameTimeMs: _metrics.totalFrameTimeMs,
      jitterMs: _metrics.jitterMs,
    );
    notifyListeners();
  }

  @visibleForTesting
  static FrameTimingMetrics calculateMetricsForSliceForTest(
    List<FrameTiming> timings,
  ) => _calculateMetricsForSlice(timings);

  static FrameTimingMetrics _calculateMetricsForSlice(
    List<FrameTiming> timings,
  ) {
    if (timings.isEmpty) {
      return FrameTimingMetrics();
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

    // Calculate frame pacing jitter as the standard deviation of inter-frame
    // arrival intervals (delta between consecutive buildStart timestamps).
    final intervals = <double>[];
    for (var i = 1; i < count; i++) {
      final deltaMs =
          (timings[i].timestampInMicroseconds(FramePhase.buildStart) -
              timings[i - 1].timestampInMicroseconds(FramePhase.buildStart)) /
          1000.0;
      // Filter out extreme gaps caused by tab switching / pausing (> 500ms)
      if (deltaMs > 0 && deltaMs < 500.0) {
        intervals.add(deltaMs);
      }
    }

    var jitterMs = 0.0;
    if (intervals.length > 1) {
      final meanInterval = intervals.reduce((a, b) => a + b) / intervals.length;
      var sumSquaredDiffs = 0.0;
      for (final interval in intervals) {
        final diff = interval - meanInterval;
        sumSquaredDiffs += diff * diff;
      }
      final variance = sumSquaredDiffs / (intervals.length - 1);
      jitterMs = math.sqrt(variance);
    }

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
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}
