import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bench_press/bench_press.dart';

/// Automated browser benchmark driver for `flutter-wasm-compare`.
///
/// Supports Chrome, Safari, and Firefox on macOS/Linux with statistical
/// sampling and telemetry powered by `package:bench_press`.
Future<void> main(List<String> rawArgs) async {
  final args = BenchmarkArgs.parse(rawArgs);
  if (args.showHelp) {
    _printUsage();
    return;
  }

  print('=' * 63);
  print(' flutter-wasm-compare Browser Benchmark Runner');
  print('=' * 63);
  print('Target URL:      ${args.baseUrl}');
  print('Browsers:        ${args.browsers.map((b) => b.label).join(', ')}');
  print('Modes:           ${args.modes.map((m) => m.label).join(', ')}');
  print('Nodes:           ${args.nodeCounts.join(', ')}');
  print('Viewport:        ${args.viewportWidth}x${args.viewportHeight} px');
  print(
    'Settle Duration: ${args.settleSeconds}s initial, '
    '${args.samples} samples per run (interval: ${args.sampleIntervalMs}ms)',
  );
  print('=' * 63);
  print('');

  final benchmarkResults =
      <BrowserType, Map<BenchmarkKey, MultiSampleRecord>>{};
  final capabilityResults = <BrowserType, CapabilityRecord>{};

  for (final browserType in args.browsers) {
    final driver = _createDriver(browserType);
    if (!await driver.isAvailable()) {
      print('⚠️  Skipping ${browserType.label}: binary/driver not found.');
      continue;
    }

    print('\n>>> Launching ${browserType.label}...');
    try {
      await driver.start(
        viewportWidth: args.viewportWidth,
        viewportHeight: args.viewportHeight,
      );

      final vpRaw = await driver.evaluate(
        '[window.innerWidth, window.innerHeight]',
      );
      if (vpRaw is List && vpRaw.length >= 2) {
        print('  • Calibrated viewport: ${vpRaw[0]}x${vpRaw[1]} px');
      }

      if (!args.skipCapabilityProbe) {
        print('  • Probing WebAssembly capabilities...');
        final baseWithoutQuery = args.baseUrl.replaceAll(RegExp(r'\?.*$'), '');
        final probeUrl = '$baseWithoutQuery?mode=wasm&optin=true';
        await driver.navigate(probeUrl);
        await Future<void>.delayed(const Duration(seconds: 3));
        final probeRaw = await driver.evaluate(_capabilityProbeScript);
        if (probeRaw != null) {
          final probe = CapabilityRecord.parse(probeRaw);
          capabilityResults[browserType] = probe;
          final passLabel = probe.invertedProbe ? 'YES (PASS)' : 'NO';
          print('    - Wasm JS-String Supported: $passLabel');
          print(
            '    - Cross-Origin Isolated:     ${probe.crossOriginIsolated}',
          );
        }
      }

      final browserMap = <BenchmarkKey, MultiSampleRecord>{};
      for (final mode in args.modes) {
        for (final nodes in args.nodeCounts) {
          final url = _buildUrl(args.baseUrl, mode, nodes);

          // Clear prior benchmark run storage before navigation to prevent
          // stale cross-mode reads.
          await driver.evaluate('''
            try {
              localStorage.removeItem('${mode.storageKey}');
              localStorage.removeItem('wasm_compare_active_node_count');
            } catch (_) {}
          ''');

          stdout.write('  • [${mode.label}] @ $nodes nodes: settling...');
          await driver.navigate(url);

          for (var s = args.settleSeconds; s > 0; s--) {
            stdout.write(' ${s}s');
            await Future<void>.delayed(const Duration(seconds: 1));
          }

          // Multi-sample collection phase
          stdout.write(' sampling (${args.samples}x)...');
          final collected = <BenchmarkRecord>[];
          final readExpr = "localStorage.getItem('${mode.storageKey}')";

          final maxAttempts = args.samples * 3 + 5;
          var attempts = 0;
          var lastTotalFrameTime = -1.0;

          while (collected.length < args.samples && attempts < maxAttempts) {
            attempts++;
            if (collected.isNotEmpty || attempts > 1) {
              await Future<void>.delayed(
                Duration(milliseconds: args.sampleIntervalMs),
              );
            }
            final rawJson = await driver.evaluate(readExpr);
            if (rawJson is String && rawJson.isNotEmpty) {
              final data = jsonDecode(rawJson) as Map<String, dynamic>;
              final record = BenchmarkRecord.fromJson(data);
              if (record.matches(mode, nodes)) {
                // Ensure sample is fresh (not an identical snapshot of the same
                // frame window).
                if (record.totalFrameTimeMs != lastTotalFrameTime ||
                    collected.isEmpty) {
                  collected.add(record);
                  lastTotalFrameTime = record.totalFrameTimeMs;
                }
              }
            }
          }
          stdout.write(' done.\r');

          if (collected.isNotEmpty) {
            final multi = MultiSampleRecord.fromRecords(collected);
            final key = BenchmarkKey(mode, nodes);
            browserMap[key] = multi;

            final label = mode.label.padRight(15);
            final nodeStr = nodes.toString().padLeft(4);
            final fpsStr = multi.fps.medianNs.toStringAsFixed(1);
            final p95Fps = multi.fps.p95Ns.toStringAsFixed(1);
            final buildStr = (multi.buildTime.medianNs / 1e6).toStringAsFixed(
              2,
            );
            final buildMad = (multi.buildTime.madNs / 1e6).toStringAsFixed(2);
            final rasterStr = (multi.rasterTime.medianNs / 1e6).toStringAsFixed(
              2,
            );
            final rasterMad = (multi.rasterTime.madNs / 1e6).toStringAsFixed(2);
            final stabilityTag = multi.buildTime.isRobustStable
                ? 'STABLE'
                : 'UNSTABLE';

            print(
              '  ✓ [$label] @ $nodeStr nodes -> '
              '$fpsStr FPS (p95: $p95Fps) | '
              'Build: ${buildStr}ms (MAD: ${buildMad}ms) | '
              'Raster: ${rasterStr}ms (MAD: ${rasterMad}ms) '
              '[$stabilityTag]',
            );
          } else {
            final label = mode.label.padRight(15);
            final nodeStr = nodes.toString().padLeft(4);
            print(
              '  ✗ [$label] @ $nodeStr nodes -> '
              'No metrics found in localStorage.',
            );
          }
        }
      }
      benchmarkResults[browserType] = browserMap;
    } catch (e, st) {
      print('❌ Error running ${browserType.label}: $e\n$st');
    } finally {
      await driver.stop();
    }
  }

  if (benchmarkResults.isEmpty) {
    print('\nNo benchmark results collected.');
    exitCode = 1;
    return;
  }

  final report = _formatMarkdownReport(
    args: args,
    capabilities: capabilityResults,
    results: benchmarkResults,
  );

  print('\n$report');

  if (args.outputPath != null) {
    final file = File(args.outputPath!);
    await file.parent.create(recursive: true);
    await file.writeAsString(report);
    print('Markdown report saved to ${file.path}');
  }

  final jsonResult = _generateJsonReport(
    args: args,
    capabilities: capabilityResults,
    results: benchmarkResults,
  );

  if (args.jsonOutput) {
    print('\n=== JSON TELEMETRY ===\n');
    print(const JsonEncoder.withIndent('  ').convert(jsonResult));
  }

  if (args.jsonOutputPath != null) {
    final file = File(args.jsonOutputPath!);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonResult),
    );
    print('JSON telemetry saved to ${file.path}');
  }
}

String _buildUrl(String baseUrl, BenchmarkMode mode, int nodes) {
  final uri = Uri.parse(baseUrl);
  final query = Map<String, String>.from(uri.queryParameters);
  query['stress'] = 'manual';
  query['nodes'] = '$nodes';

  switch (mode) {
    case BenchmarkMode.wasmMultithreaded:
      query['mode'] = 'wasm';
      query['optin'] = 'true';
      query['st'] = '0';
    case BenchmarkMode.wasmSingleThreaded:
      query['mode'] = 'wasm';
      query['optin'] = 'true';
      query['st'] = '1';
    case BenchmarkMode.jsCanvasKit:
      query['mode'] = 'js';
      query.remove('optin');
      query.remove('st');
  }

  return uri.replace(queryParameters: query).toString();
}

String _formatMarkdownReport({
  required BenchmarkArgs args,
  required Map<BrowserType, CapabilityRecord> capabilities,
  required Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>> results,
}) {
  final buffer = StringBuffer();
  buffer.writeln(
    '# Browser WebAssembly Benchmark Report (`flutter-wasm-compare`)',
  );
  buffer.writeln();
  buffer.writeln('- **Date**: ${DateTime.now().toUtc().toIso8601String()}');
  buffer.writeln('- **Target App**: [${args.baseUrl}](${args.baseUrl})');
  buffer.writeln(
    '- **Viewport**: ${args.viewportWidth}x${args.viewportHeight} px '
    '(calibrated identically across all browsers)',
  );
  buffer.writeln(
    '- **Sampling**: ${args.samples} trials per run after '
    '${args.settleSeconds}s initial settle',
  );
  buffer.writeln();

  if (capabilities.isNotEmpty) {
    buffer.writeln('## 🧪 Capability & Streaming Probes');
    buffer.writeln();
    buffer.writeln('<!-- mdformat off -->');
    buffer.writeln(
      '| Browser | Cross-Origin Isolated | Wasm JS-String Supported | '
      'User Agent |',
    );
    buffer.writeln('| :--- | :---: | :---: | :--- |');
    for (final entry in capabilities.entries) {
      final b = entry.key.label;
      final c = entry.value;
      final passStr = c.invertedProbe ? '**PASS**' : '**FAIL**';
      buffer.writeln(
        '| $b | ${c.crossOriginIsolated} | $passStr | `${c.userAgent}` |',
      );
    }
    buffer.writeln('<!-- mdformat on -->');
    buffer.writeln();
  }

  buffer.writeln('## 📊 Performance Comparison Matrix (Median Values)');
  buffer.writeln();
  buffer.writeln('<!-- mdformat off -->');

  final columns = <_ReportColumn>[];
  for (final browser in results.keys) {
    for (final mode in args.modes) {
      columns.add(_ReportColumn(browser, mode));
    }
  }

  buffer.write('| Preset / Metric |');
  for (final col in columns) {
    buffer.write(' ${col.header} |');
  }
  buffer.writeln();

  buffer.write('| :--- |');
  for (var i = 0; i < columns.length; i++) {
    buffer.write(' :---: |');
  }
  buffer.writeln();

  for (final nodes in args.nodeCounts) {
    buffer.write('| **Nodes ($nodes)** |');
    for (final col in columns) {
      final rec = results[col.browser]?[BenchmarkKey(col.mode, nodes)];
      if (rec != null) {
        final fpsStr = rec.fps.medianNs.toStringAsFixed(1);
        final buildStr = (rec.buildTime.medianNs / 1e6).toStringAsFixed(2);
        final rasterStr = (rec.rasterTime.medianNs / 1e6).toStringAsFixed(2);
        buffer.write(' **$fpsStr FPS** / ${buildStr}ms / ${rasterStr}ms |');
      } else {
        buffer.write(' N/A |');
      }
    }
    buffer.writeln();
  }
  buffer.writeln('<!-- mdformat on -->');
  buffer.writeln();

  final takeaways = StringBuffer();
  for (final browser in results.keys) {
    final browserResults = results[browser]!;
    final matchingNodes = args.nodeCounts.where((int n) {
      return browserResults.containsKey(
            BenchmarkKey(BenchmarkMode.wasmMultithreaded, n),
          ) &&
          browserResults.containsKey(
            BenchmarkKey(BenchmarkMode.wasmSingleThreaded, n),
          ) &&
          browserResults.containsKey(
            BenchmarkKey(BenchmarkMode.jsCanvasKit, n),
          );
    }).toList();

    for (final nodes in matchingNodes) {
      final mt =
          browserResults[BenchmarkKey(BenchmarkMode.wasmMultithreaded, nodes)]!;
      final st =
          browserResults[BenchmarkKey(
            BenchmarkMode.wasmSingleThreaded,
            nodes,
          )]!;
      final js =
          browserResults[BenchmarkKey(BenchmarkMode.jsCanvasKit, nodes)]!;

      final rasterFieller = FiellerInterval.compute(
        sampleA: mt.rawRasterMs,
        sampleB: st.rawRasterMs,
      );
      final fpsWinFieller = FiellerInterval.compute(
        sampleA: mt.rawFps,
        sampleB: st.rawFps,
      );
      final vsJsWinFieller = FiellerInterval.compute(
        sampleA: mt.rawFps,
        sampleB: js.rawFps,
      );
      final buildSpeedupFieller = FiellerInterval.compute(
        sampleA: js.rawBuildMs,
        sampleB: mt.rawBuildMs,
      );

      final mtRasterMed = (mt.rasterTime.medianNs / 1e6).toStringAsFixed(2);
      final stRasterMed = (st.rasterTime.medianNs / 1e6).toStringAsFixed(2);
      final mtFpsMed = mt.fps.medianNs.toStringAsFixed(1);
      final stFpsMed = st.fps.medianNs.toStringAsFixed(1);
      final mtBuildMed = (mt.buildTime.medianNs / 1e6).toStringAsFixed(2);
      final jsBuildMed = (js.buildTime.medianNs / 1e6).toStringAsFixed(2);

      takeaways.writeln('* **${browser.label} (at $nodes nodes)**:');
      takeaways.writeln(
        '  * Worker Raster Overhead: `st=0` is '
        '**${formatFieller(rasterFieller)}** that of `st=1` '
        '(${mtRasterMed}ms vs ${stRasterMed}ms).',
      );
      takeaways.writeln(
        '  * Pipelining Throughput Win: `st=0` delivers '
        '**${formatFieller(fpsWinFieller)} higher FPS** than `st=1` '
        '($mtFpsMed vs $stFpsMed FPS).',
      );
      takeaways.writeln(
        '  * Dart2Wasm vs Dart2JS: Wasm delivers '
        '**${formatFieller(vsJsWinFieller)} higher FPS** and '
        '**${formatFieller(buildSpeedupFieller)} faster UI build** '
        '(${mtBuildMed}ms vs ${jsBuildMed}ms).',
      );
    }
  }

  if (takeaways.isNotEmpty) {
    buffer.writeln('### Key Takeaways (Fieller 95% Confidence Intervals)');
    buffer.write(takeaways.toString());
  }

  return buffer.toString();
}

String formatFieller(FiellerInterval fieller) {
  if (!fieller.ratio.isFinite) {
    return 'N/A';
  }
  final r = fieller.ratio.toStringAsFixed(2);
  if (!fieller.isValid ||
      !fieller.lowerBound.isFinite ||
      !fieller.upperBound.isFinite) {
    return '${r}x';
  }
  final low = fieller.lowerBound.toStringAsFixed(2);
  final high = fieller.upperBound.toStringAsFixed(2);
  return '${r}x [${low}x, ${high}x] (95% CI)';
}

Map<String, Object?> _generateJsonReport({
  required BenchmarkArgs args,
  required Map<BrowserType, CapabilityRecord> capabilities,
  required Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>> results,
}) {
  final env = EnvironmentInfo.current(
    extra: {
      'viewport': '${args.viewportWidth}x${args.viewportHeight}',
      'settle_seconds': args.settleSeconds,
      'samples': args.samples,
      'sample_interval_ms': args.sampleIntervalMs,
    },
  );

  final benchmarksList = <Map<String, Object?>>[];
  final comparisonsList = <Map<String, Object?>>[];

  for (final browserEntry in results.entries) {
    final browser = browserEntry.key;
    final browserResults = browserEntry.value;
    for (final mapEntry in browserResults.entries) {
      final key = mapEntry.key;
      final multi = mapEntry.value;

      benchmarksList.add({
        'browser': browser.label.toLowerCase(),
        'mode': key.mode.name,
        'mode_label': key.mode.label,
        'nodes': key.nodes,
        'samples': multi.samplesCount,
        'is_pipelined': multi.isPipelined,
        'fps': statsToJson(multi.fps, isMs: false),
        'build_time_ms': statsToJson(multi.buildTime, isMs: true),
        'raster_time_ms': statsToJson(multi.rasterTime, isMs: true),
        'total_frame_time_ms': statsToJson(multi.totalFrameTime, isMs: true),
        'jitter_ms': statsToJson(multi.jitter, isMs: true),
      });
    }

    // Generate comparison ratios for matching node counts
    final matchingNodes = args.nodeCounts.where((int n) {
      return browserResults.containsKey(
            BenchmarkKey(BenchmarkMode.wasmMultithreaded, n),
          ) &&
          browserResults.containsKey(
            BenchmarkKey(BenchmarkMode.wasmSingleThreaded, n),
          ) &&
          browserResults.containsKey(
            BenchmarkKey(BenchmarkMode.jsCanvasKit, n),
          );
    }).toList();

    for (final nodes in matchingNodes) {
      final mt =
          browserResults[BenchmarkKey(BenchmarkMode.wasmMultithreaded, nodes)]!;
      final st =
          browserResults[BenchmarkKey(
            BenchmarkMode.wasmSingleThreaded,
            nodes,
          )]!;
      final js =
          browserResults[BenchmarkKey(BenchmarkMode.jsCanvasKit, nodes)]!;

      comparisonsList.add(
        fiellerToJson(
          browser: browser.label.toLowerCase(),
          nodes: nodes,
          name: 'wasm_mt_vs_wasm_st_raster_overhead',
          fieller: FiellerInterval.compute(
            sampleA: mt.rawRasterMs,
            sampleB: st.rawRasterMs,
          ),
        ),
      );
      comparisonsList.add(
        fiellerToJson(
          browser: browser.label.toLowerCase(),
          nodes: nodes,
          name: 'wasm_mt_vs_wasm_st_fps_pipelining_win',
          fieller: FiellerInterval.compute(
            sampleA: mt.rawFps,
            sampleB: st.rawFps,
          ),
        ),
      );
      comparisonsList.add(
        fiellerToJson(
          browser: browser.label.toLowerCase(),
          nodes: nodes,
          name: 'wasm_mt_vs_js_fps_speedup',
          fieller: FiellerInterval.compute(
            sampleA: mt.rawFps,
            sampleB: js.rawFps,
          ),
        ),
      );
      comparisonsList.add(
        fiellerToJson(
          browser: browser.label.toLowerCase(),
          nodes: nodes,
          name: 'wasm_mt_vs_js_build_speedup',
          fieller: FiellerInterval.compute(
            sampleA: js.rawBuildMs,
            sampleB: mt.rawBuildMs,
          ),
        ),
      );
    }
  }

  return {
    '\$schema_version': 1,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'target_url': args.baseUrl,
    'environment': env.toJson(),
    'capabilities': {
      for (final c in capabilities.entries)
        c.key.label.toLowerCase(): {
          'user_agent': c.value.userAgent,
          'cross_origin_isolated': c.value.crossOriginIsolated,
          'wasm_js_string_supported': c.value.invertedProbe,
        },
    },
    'benchmarks': benchmarksList,
    'comparisons': comparisonsList,
  };
}

Map<String, Object?> statsToJson(
  BenchmarkMetrics metrics, {
  required bool isMs,
}) {
  final scale = isMs ? 1e6 : 1.0;
  double? sanitize(double val) => val.isFinite ? val : null;
  return {
    'mean': sanitize(metrics.meanNs / scale),
    'median': sanitize(metrics.medianNs / scale),
    'min': sanitize(metrics.minNs / scale),
    'max': sanitize(metrics.maxNs / scale),
    'stddev': sanitize(metrics.stddevNs / scale),
    'cv': sanitize(metrics.cv),
    'mad': sanitize(metrics.madNs / scale),
    'robust_cv': sanitize(metrics.robustCv),
    'iqr': sanitize(metrics.iqrNs / scale),
    'p95': sanitize(metrics.p95Ns / scale),
    'p99': sanitize(metrics.p99Ns / scale),
    'is_stable': metrics.isStable,
    'is_robust_stable': metrics.isRobustStable,
  };
}

Map<String, Object?> fiellerToJson({
  required String browser,
  required int nodes,
  required String name,
  required FiellerInterval fieller,
}) => {
  'browser': browser,
  'nodes': nodes,
  'comparison': name,
  'ratio': fieller.ratio.isFinite ? fieller.ratio : null,
  'confidence_interval': {
    'lower': fieller.lowerBound.isFinite ? fieller.lowerBound : null,
    'upper': fieller.upperBound.isFinite ? fieller.upperBound : null,
    'confidence_level': fieller.confidenceLevel,
    'is_valid': fieller.isValid,
  },
};

class _ReportColumn {
  final BrowserType browser;
  final BenchmarkMode mode;
  _ReportColumn(this.browser, this.mode);

  String get header => '${browser.label} ${mode.shortLabel}';
}

const _capabilityProbeScript = '''(() => {
  const opts = { builtins: ["js-string"] };
  const invalidBytes = new Uint8Array([
    0,97,115,109,1,0,0,0,1,4,1,96,0,0,2,23,1,14,
    119,97,115,109,58,106,115,45,115,116,114,105,110,103,
    4,99,97,115,116,0,0
  ]);
  const rawValidate = WebAssembly.validate(invalidBytes);
  const optValidate = WebAssembly.validate(invalidBytes, opts);
  return JSON.stringify({
    userAgent: navigator.userAgent,
    crossOriginIsolated: window.crossOriginIsolated,
    rawValidate: rawValidate,
    optValidate: optValidate,
    invertedProbe: !optValidate
  });
})()''';

enum BrowserType {
  chrome('Chrome'),
  safari('Safari'),
  firefox('Firefox');

  final String label;
  const BrowserType(this.label);
}

enum BenchmarkMode {
  wasmMultithreaded('Wasm MT (st=0)', 'Wasm MT', 'wasm_compare_last_wasm_run'),
  wasmSingleThreaded('Wasm ST (st=1)', 'Wasm ST', 'wasm_compare_last_wasm_run'),
  jsCanvasKit('JS CanvasKit', 'JS', 'wasm_compare_last_js_run');

  final String label;
  final String shortLabel;
  final String storageKey;
  const BenchmarkMode(this.label, this.shortLabel, this.storageKey);
}

class BenchmarkKey {
  final BenchmarkMode mode;
  final int nodes;
  const BenchmarkKey(this.mode, this.nodes);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BenchmarkKey && other.mode == mode && other.nodes == nodes;

  @override
  int get hashCode => Object.hash(mode, nodes);
}

class BenchmarkRecord {
  final double fps;
  final double buildTimeMs;
  final double rasterTimeMs;
  final double totalFrameTimeMs;
  final double jitterMs;
  final bool isPipelined;
  final int nodeCount;
  final String mode;

  BenchmarkRecord({
    required this.fps,
    required this.buildTimeMs,
    required this.rasterTimeMs,
    required this.totalFrameTimeMs,
    required this.jitterMs,
    required this.isPipelined,
    required this.nodeCount,
    required this.mode,
  });

  factory BenchmarkRecord.fromJson(Map<String, dynamic> json) {
    return BenchmarkRecord(
      fps: (json['fps'] as num?)?.toDouble() ?? 0.0,
      buildTimeMs: (json['buildTimeMs'] as num?)?.toDouble() ?? 0.0,
      rasterTimeMs: (json['rasterTimeMs'] as num?)?.toDouble() ?? 0.0,
      totalFrameTimeMs: (json['totalFrameTimeMs'] as num?)?.toDouble() ?? 0.0,
      jitterMs: (json['jitterMs'] as num?)?.toDouble() ?? 0.0,
      isPipelined: json['isPipelined'] as bool? ?? false,
      nodeCount: (json['nodeCount'] as num?)?.toInt() ?? 0,
      mode: json['mode'] as String? ?? '',
    );
  }

  /// Verifies whether this record corresponds to the intended mode and node
  /// count, preventing stale cross-mode or cross-workload reads from
  /// localStorage.
  bool matches(BenchmarkMode expectedMode, int expectedNodes) {
    if (nodeCount != expectedNodes) return false;
    final normMode = mode.toLowerCase();
    switch (expectedMode) {
      case BenchmarkMode.wasmMultithreaded:
        return normMode == 'wasm' && isPipelined;
      case BenchmarkMode.wasmSingleThreaded:
        return normMode == 'wasm' && !isPipelined;
      case BenchmarkMode.jsCanvasKit:
        return normMode == 'js';
    }
  }

  /// Calculates true throughput if the HUD's tab-pause filter fallback
  /// occurred.
  double get effectiveFps {
    if (fps == 60.0 && totalFrameTimeMs > 500.0) {
      final active = isPipelined
          ? (buildTimeMs > rasterTimeMs ? buildTimeMs : rasterTimeMs)
          : (buildTimeMs + rasterTimeMs);
      return active > 0 ? 1000.0 / active : fps;
    }
    return fps;
  }
}

/// Aggregates multi-sample benchmark trials into statistical metrics.
class MultiSampleRecord {
  final int samplesCount;
  final bool isPipelined;
  final BenchmarkMetrics fps;
  final BenchmarkMetrics buildTime;
  final BenchmarkMetrics rasterTime;
  final BenchmarkMetrics totalFrameTime;
  final BenchmarkMetrics jitter;

  final List<double> rawFps;
  final List<double> rawBuildMs;
  final List<double> rawRasterMs;

  MultiSampleRecord({
    required this.samplesCount,
    required this.isPipelined,
    required this.fps,
    required this.buildTime,
    required this.rasterTime,
    required this.totalFrameTime,
    required this.jitter,
    required this.rawFps,
    required this.rawBuildMs,
    required this.rawRasterMs,
  });

  factory MultiSampleRecord.fromRecords(List<BenchmarkRecord> records) {
    final rawFps = records.map((r) => r.effectiveFps).toList();
    final rawBuild = records.map((r) => r.buildTimeMs).toList();
    final rawRaster = records.map((r) => r.rasterTimeMs).toList();
    final rawTotal = records.map((r) => r.totalFrameTimeMs).toList();
    final rawJitter = records.map((r) => r.jitterMs).toList();

    return MultiSampleRecord(
      samplesCount: records.length,
      isPipelined: records.first.isPipelined,
      fps: BenchmarkMetrics.fromSamples(rawFps),
      buildTime: BenchmarkMetrics.fromSamples(
        rawBuild.map((ms) => ms * 1e6).toList(),
      ),
      rasterTime: BenchmarkMetrics.fromSamples(
        rawRaster.map((ms) => ms * 1e6).toList(),
      ),
      totalFrameTime: BenchmarkMetrics.fromSamples(
        rawTotal.map((ms) => ms * 1e6).toList(),
      ),
      jitter: BenchmarkMetrics.fromSamples(
        rawJitter.map((ms) => ms * 1e6).toList(),
      ),
      rawFps: List.unmodifiable(rawFps),
      rawBuildMs: List.unmodifiable(rawBuild),
      rawRasterMs: List.unmodifiable(rawRaster),
    );
  }
}

class CapabilityRecord {
  final String userAgent;
  final bool crossOriginIsolated;
  final bool invertedProbe;

  CapabilityRecord({
    required this.userAgent,
    required this.crossOriginIsolated,
    required this.invertedProbe,
  });

  factory CapabilityRecord.parse(dynamic raw) {
    final map = (raw is String ? jsonDecode(raw) : raw) as Map<String, dynamic>;
    return CapabilityRecord(
      userAgent: map['userAgent'] as String? ?? '',
      crossOriginIsolated: map['crossOriginIsolated'] as bool? ?? false,
      invertedProbe: map['invertedProbe'] as bool? ?? false,
    );
  }
}

abstract interface class BrowserDriver {
  Future<bool> isAvailable();
  Future<void> start({required int viewportWidth, required int viewportHeight});
  Future<void> navigate(String url);
  Future<dynamic> evaluate(String script);
  Future<void> stop();
}

BrowserDriver _createDriver(BrowserType type) => switch (type) {
  BrowserType.chrome => _ChromeCdpDriver(),
  BrowserType.safari => _SafariWebDriver(),
  BrowserType.firefox => _FirefoxWebDriver(),
};

/// Drives Chrome via native Chrome DevTools Protocol (CDP) WebSocket.
class _ChromeCdpDriver implements BrowserDriver {
  Process? _process;
  WebSocket? _ws;
  Directory? _tempDir;
  int _msgId = 0;
  final _pendingResponses = <int, Completer<dynamic>>{};
  StreamSubscription<dynamic>? _wsSub;

  @override
  Future<bool> isAvailable() async {
    final chromePath = _findChromeBinary();
    return chromePath != null && File(chromePath).existsSync();
  }

  static String? _findChromeBinary() {
    if (Platform.isMacOS) {
      return '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    }
    if (Platform.isLinux) {
      return '/usr/bin/google-chrome';
    }
    return null;
  }

  @override
  Future<void> start({
    required int viewportWidth,
    required int viewportHeight,
  }) async {
    final chromePath = _findChromeBinary()!;
    final port = await _findAvailablePort();
    _tempDir = await Directory.systemTemp.createTemp('chrome_bench_');

    _process = await Process.start(chromePath, [
      '--remote-debugging-port=$port',
      '--user-data-dir=${_tempDir!.path}',
      '--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding',
      '--no-first-run',
      '--no-default-browser-check',
      '--window-size=${viewportWidth + 100},${viewportHeight + 100}',
      'about:blank',
    ], mode: ProcessStartMode.normal);

    // Poll until Chrome DevTools HTTP endpoint is ready
    String? wsUrl;
    final client = HttpClient();
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        final uri = Uri.parse('http://127.0.0.1:$port/json/list');
        final req = await client.getUrl(uri);
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final targets = jsonDecode(body) as List<dynamic>;
          for (final t in targets) {
            if (t is Map<String, dynamic> && t['type'] == 'page') {
              wsUrl = t['webSocketDebuggerUrl'] as String?;
              break;
            }
          }
          if (wsUrl != null) break;
        }
      } catch (_) {
        // Retry
      }
    }
    client.close();

    if (wsUrl == null) {
      throw StateError(
        'Failed to obtain Chrome DevTools WebSocket URL on port $port',
      );
    }

    _ws = await WebSocket.connect(wsUrl);
    _wsSub = _ws!.listen((message) {
      if (message is String) {
        final map = jsonDecode(message) as Map<String, dynamic>;
        final id = map['id'] as int?;
        if (id != null && _pendingResponses.containsKey(id)) {
          _pendingResponses.remove(id)!.complete(map['result']);
        }
      }
    });

    // Enforce exact device viewport metrics in Chrome
    await _sendCdp('Emulation.setDeviceMetricsOverride', {
      'width': viewportWidth,
      'height': viewportHeight,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
  }

  Future<dynamic> _sendCdp(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final id = ++_msgId;
    final completer = Completer<dynamic>();
    _pendingResponses[id] = completer;

    _ws!.add(
      jsonEncode({
        'id': id,
        'method': method,
        'params': params ?? <String, dynamic>{},
      }),
    );

    return completer.future.timeout(const Duration(seconds: 30));
  }

  @override
  Future<void> navigate(String url) async {
    await _sendCdp('Page.navigate', {'url': url});
  }

  @override
  Future<dynamic> evaluate(String script) async {
    final res = await _sendCdp('Runtime.evaluate', {
      'expression': script,
      'returnByValue': true,
    });

    if (res is Map<String, dynamic>) {
      final resultObj = res['result'];
      if (resultObj is Map<String, dynamic>) {
        return resultObj['value'];
      }
    }
    return null;
  }

  @override
  Future<void> stop() async {
    await _wsSub?.cancel();
    await _ws?.close();
    _process?.kill();
    _process = null;
    if (_tempDir != null && _tempDir!.existsSync()) {
      try {
        await _tempDir!.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Drives Safari via `/usr/bin/safaridriver` (W3C WebDriver HTTP API).
class _SafariWebDriver implements BrowserDriver {
  Process? _driverProcess;
  int? _port;
  String? _sessionId;
  final HttpClient _client = HttpClient();

  @override
  Future<bool> isAvailable() async {
    return Platform.isMacOS && File('/usr/bin/safaridriver').existsSync();
  }

  @override
  Future<void> start({
    required int viewportWidth,
    required int viewportHeight,
  }) async {
    _port = await _findAvailablePort();
    _driverProcess = await Process.start('/usr/bin/safaridriver', [
      '-p',
      '$_port',
    ], mode: ProcessStartMode.normal);

    await Future<void>.delayed(const Duration(milliseconds: 1000));

    final res = await _wdRequest('POST', '/session', {
      'capabilities': {
        'alwaysMatch': {'browserName': 'safari'},
      },
    });

    final val = res['value'];
    if (val is Map<String, dynamic>) {
      _sessionId = val['sessionId'] as String?;
    }
    if (_sessionId == null) {
      throw StateError('Failed to create Safari WebDriver session');
    }

    await _calibrateViewport(viewportWidth, viewportHeight);
  }

  Future<void> _calibrateViewport(int targetWidth, int targetHeight) async {
    // Set initial window rect
    await _wdRequest('POST', '/session/$_sessionId/window/rect', {
      'width': targetWidth,
      'height': targetHeight + 100,
    });

    // Measure inner viewport and adjust for browser toolbar/chrome
    final inner = await evaluate('[window.innerWidth, window.innerHeight]');
    if (inner is List && inner.length >= 2) {
      final iw = (inner[0] as num).toInt();
      final ih = (inner[1] as num).toInt();
      final deltaW = targetWidth - iw;
      final deltaH = targetHeight - ih;

      if (deltaW != 0 || deltaH != 0) {
        final rectRes = await _wdRequest(
          'GET',
          '/session/$_sessionId/window/rect',
        );
        final currRect = rectRes['value'] as Map<String, dynamic>?;
        final currW =
            (currRect?['width'] as num?)?.toInt() ?? (targetWidth + deltaW);
        final currH =
            (currRect?['height'] as num?)?.toInt() ??
            (targetHeight + 100 + deltaH);

        await _wdRequest('POST', '/session/$_sessionId/window/rect', {
          'width': currW + deltaW,
          'height': currH + deltaH,
        });
      }
    }
  }

  @override
  Future<void> navigate(String url) async {
    await _wdRequest('POST', '/session/$_sessionId/url', {'url': url});
  }

  @override
  Future<dynamic> evaluate(String script) async {
    final normalized = script.trim().startsWith('return ')
        ? script
        : 'return ($script);';
    final res = await _wdRequest('POST', '/session/$_sessionId/execute/sync', {
      'script': normalized,
      'args': <dynamic>[],
    });
    return res['value'];
  }

  @override
  Future<void> stop() async {
    if (_sessionId != null) {
      try {
        await _wdRequest('DELETE', '/session/$_sessionId');
      } catch (_) {}
      _sessionId = null;
    }
    _driverProcess?.kill();
    _driverProcess = null;
    _client.close();
  }

  Future<Map<String, dynamic>> _wdRequest(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    final uri = Uri.parse('http://127.0.0.1:$_port$path');
    final req = await _client.openUrl(method, uri);
    req.headers.contentType = ContentType.json;
    if (data != null) {
      req.write(jsonEncode(data));
    }
    final resp = await req.close().timeout(const Duration(seconds: 30));
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  }
}

/// Drives Firefox via `geckodriver` (W3C WebDriver HTTP API) with
/// unthrottled prefs.
class _FirefoxWebDriver implements BrowserDriver {
  Process? _driverProcess;
  int? _port;
  String? _sessionId;
  final HttpClient _client = HttpClient();

  static String? _resolveFirefoxBinary() {
    if (Platform.isMacOS) {
      const macPath = '/Applications/Firefox.app/Contents/MacOS/firefox';
      if (File(macPath).existsSync()) return macPath;
    } else if (Platform.isLinux) {
      for (final p in ['/usr/bin/firefox', '/snap/bin/firefox']) {
        if (File(p).existsSync()) return p;
      }
    }
    try {
      final res = Process.runSync('which', ['firefox']);
      if (res.exitCode == 0) {
        final path = (res.stdout as String).trim();
        if (path.isNotEmpty && File(path).existsSync()) return path;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<bool> isAvailable() async {
    final binary = _resolveFirefoxBinary();
    if (binary == null) {
      return false;
    }
    try {
      final res = await Process.run('which', ['geckodriver']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start({
    required int viewportWidth,
    required int viewportHeight,
  }) async {
    _port = await _findAvailablePort();
    _driverProcess = await Process.start('geckodriver', [
      '-p',
      '$_port',
    ], mode: ProcessStartMode.normal);

    await Future<void>.delayed(const Duration(milliseconds: 1000));

    final binary = _resolveFirefoxBinary() ?? 'firefox';
    final caps = {
      'capabilities': {
        'alwaysMatch': {
          'browserName': 'firefox',
          'moz:firefoxOptions': {
            'binary': binary,
            'prefs': {
              'widget.windows.window_occlusion_tracking.enabled': false,
              'dom.timeout.enable_budget_timer_throttling': false,
              'dom.min_background_timeout_value': 0,
              'webgl.force-enabled': true,
              'gfx.webrender.all': true,
              'datareporting.policy.dataSubmissionEnabled': false,
              'app.update.auto': false,
            },
          },
        },
      },
    };

    final res = await _wdRequest('POST', '/session', caps);
    final val = res['value'];
    if (val is Map<String, dynamic>) {
      _sessionId = val['sessionId'] as String?;
    }
    if (_sessionId == null) {
      throw StateError('Failed to create Firefox WebDriver session');
    }

    await _calibrateViewport(viewportWidth, viewportHeight);
  }

  Future<void> _calibrateViewport(int targetWidth, int targetHeight) async {
    await _wdRequest('POST', '/session/$_sessionId/window/rect', {
      'width': targetWidth,
      'height': targetHeight + 100,
    });

    final inner = await evaluate('[window.innerWidth, window.innerHeight]');
    if (inner is List && inner.length >= 2) {
      final iw = (inner[0] as num).toInt();
      final ih = (inner[1] as num).toInt();
      final deltaW = targetWidth - iw;
      final deltaH = targetHeight - ih;

      if (deltaW != 0 || deltaH != 0) {
        final rectRes = await _wdRequest(
          'GET',
          '/session/$_sessionId/window/rect',
        );
        final currRect = rectRes['value'] as Map<String, dynamic>?;
        final currW =
            (currRect?['width'] as num?)?.toInt() ?? (targetWidth + deltaW);
        final currH =
            (currRect?['height'] as num?)?.toInt() ??
            (targetHeight + 100 + deltaH);

        await _wdRequest('POST', '/session/$_sessionId/window/rect', {
          'width': currW + deltaW,
          'height': currH + deltaH,
        });
      }
    }
  }

  @override
  Future<void> navigate(String url) async {
    await _wdRequest('POST', '/session/$_sessionId/url', {'url': url});
  }

  @override
  Future<dynamic> evaluate(String script) async {
    final normalized = script.trim().startsWith('return ')
        ? script
        : 'return ($script);';
    final res = await _wdRequest('POST', '/session/$_sessionId/execute/sync', {
      'script': normalized,
      'args': <dynamic>[],
    });
    return res['value'];
  }

  @override
  Future<void> stop() async {
    if (_sessionId != null) {
      try {
        await _wdRequest('DELETE', '/session/$_sessionId');
      } catch (_) {}
      _sessionId = null;
    }
    _driverProcess?.kill();
    _driverProcess = null;
    _client.close();
  }

  Future<Map<String, dynamic>> _wdRequest(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    final uri = Uri.parse('http://127.0.0.1:$_port$path');
    final req = await _client.openUrl(method, uri);
    req.headers.contentType = ContentType.json;
    if (data != null) {
      req.write(jsonEncode(data));
    }
    final resp = await req.close().timeout(const Duration(seconds: 30));
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  }
}

Future<int> _findAvailablePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class BenchmarkArgs {
  final bool showHelp;
  final String baseUrl;
  final List<BrowserType> browsers;
  final List<BenchmarkMode> modes;
  final List<int> nodeCounts;
  final int viewportWidth;
  final int viewportHeight;
  final int settleSeconds;
  final int samples;
  final int sampleIntervalMs;
  final String? outputPath;
  final bool jsonOutput;
  final String? jsonOutputPath;
  final bool skipCapabilityProbe;

  BenchmarkArgs({
    required this.showHelp,
    required this.baseUrl,
    required this.browsers,
    required this.modes,
    required this.nodeCounts,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.settleSeconds,
    required this.samples,
    this.sampleIntervalMs = 1200,
    required this.outputPath,
    required this.jsonOutput,
    required this.jsonOutputPath,
    required this.skipCapabilityProbe,
  });

  factory BenchmarkArgs.parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      return BenchmarkArgs(
        showHelp: true,
        baseUrl: '',
        browsers: const [],
        modes: const [],
        nodeCounts: const [],
        viewportWidth: 0,
        viewportHeight: 0,
        settleSeconds: 0,
        samples: 0,
        sampleIntervalMs: 1200,
        outputPath: null,
        jsonOutput: false,
        jsonOutputPath: null,
        skipCapabilityProbe: false,
      );
    }

    var baseUrl = 'https://flutter-wasm-compare.web.app/';
    var browsers = BrowserType.values.toList();
    var modes = BenchmarkMode.values.toList();
    var nodeCounts = [100, 1000, 8000];
    var viewportWidth = 1280;
    var viewportHeight = 720;
    var settleSeconds = 5;
    var samples = 5;
    var sampleIntervalMs = 1200;
    String? outputPath;
    var jsonOutput = false;
    String? jsonOutputPath;
    var skipCapabilityProbe = false;

    for (final arg in args) {
      if (arg.startsWith('--url=')) {
        baseUrl = arg.substring('--url='.length);
      } else if (arg.startsWith('--browser=') ||
          arg.startsWith('--browsers=')) {
        final val = arg.split('=').last.toLowerCase();
        if (val != 'all') {
          final tokens = val.split(',');
          browsers = [];
          for (final t in tokens) {
            final trimmed = t.trim();
            if (trimmed == 'chrome') browsers.add(BrowserType.chrome);
            if (trimmed == 'safari') browsers.add(BrowserType.safari);
            if (trimmed == 'firefox') browsers.add(BrowserType.firefox);
          }
        }
      } else if (arg.startsWith('--modes=')) {
        final val = arg.substring('--modes='.length).toLowerCase();
        final tokens = val.split(',');
        modes = [];
        for (final t in tokens) {
          final trimmed = t.trim();
          if (trimmed == 'wasm_mt' || trimmed == 'mt') {
            modes.add(BenchmarkMode.wasmMultithreaded);
          }
          if (trimmed == 'wasm_st' || trimmed == 'st') {
            modes.add(BenchmarkMode.wasmSingleThreaded);
          }
          if (trimmed == 'js') {
            modes.add(BenchmarkMode.jsCanvasKit);
          }
        }
      } else if (arg.startsWith('--preset=')) {
        final val = arg.split('=').last.toLowerCase();
        if (val == 'light') {
          nodeCounts = [100];
        } else if (val == 'medium') {
          nodeCounts = [1000];
        } else if (val == 'heavy' || val == 'max') {
          nodeCounts = [8000];
        } else if (val == 'all' || val == 'default') {
          nodeCounts = [100, 1000, 8000];
        }
      } else if (arg.startsWith('--nodes=')) {
        final val = arg.substring('--nodes='.length);
        nodeCounts = val
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
      } else if (arg.startsWith('--viewport=')) {
        final val = arg.substring('--viewport='.length).toLowerCase();
        final parts = val.split('x');
        if (parts.length == 2) {
          final w = int.tryParse(parts[0].trim());
          final h = int.tryParse(parts[1].trim());
          if (w != null && h != null) {
            viewportWidth = w;
            viewportHeight = h;
          }
        }
      } else if (arg.startsWith('--settle-seconds=')) {
        settleSeconds =
            int.tryParse(arg.substring('--settle-seconds='.length)) ??
            settleSeconds;
      } else if (arg.startsWith('--samples=')) {
        samples = int.tryParse(arg.substring('--samples='.length)) ?? samples;
      } else if (arg.startsWith('--sample-interval=') ||
          arg.startsWith('--sample-interval-ms=')) {
        final val = arg.split('=').last;
        sampleIntervalMs = int.tryParse(val) ?? sampleIntervalMs;
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg == '--json') {
        jsonOutput = true;
      } else if (arg.startsWith('--json-output=')) {
        jsonOutputPath = arg.substring('--json-output='.length);
      } else if (arg == '--skip-capability-probe') {
        skipCapabilityProbe = true;
      }
    }

    return BenchmarkArgs(
      showHelp: false,
      baseUrl: baseUrl,
      browsers: browsers.isEmpty ? BrowserType.values.toList() : browsers,
      modes: modes.isEmpty ? BenchmarkMode.values.toList() : modes,
      nodeCounts: nodeCounts.isEmpty ? [100, 1000, 8000] : nodeCounts,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      settleSeconds: settleSeconds,
      samples: samples,
      sampleIntervalMs: sampleIntervalMs,
      outputPath: outputPath,
      jsonOutput: jsonOutput,
      jsonOutputPath: jsonOutputPath,
      skipCapabilityProbe: skipCapabilityProbe,
    );
  }
}

void _printUsage() {
  print('''
Usage: dart tool/benchmark.dart [options]

Automated empirical browser benchmark runner for flutter-wasm-compare.

Options:
  --browser=<name>         Browsers to test: chrome, safari, firefox, or all (comma-separated).
                           Default: all
  --url=<url>              Target app base URL.
                           Default: https://flutter-wasm-compare.web.app/
  --preset=<name>          Convenience workload preset: light (100), medium (1000),
                           heavy (8000), or all (100, 1000, 8000).
  --nodes=<counts>         Comma-separated list of stress node counts.
                           Default: 100,1000,8000
  --modes=<modes>          Comma-separated list of engine modes: wasm_mt, wasm_st, js.
                           Default: wasm_mt,wasm_st,js
  --viewport=<WxH>         Enforced inner viewport size in pixels across all browsers.
                           Default: 1280x720
  --settle-seconds=<sec>   Seconds to wait after navigation before sampling.
                           Default: 5
  --samples=<count>        Number of trial samples to record per workload.
                           Default: 5
  --sample-interval=<ms>   Milliseconds to wait between successive samples.
                           Default: 1200 (exceeds app's 1000ms HUD throttle)
  --output=<file>          Optional file path to save the generated Markdown report.
  --json                   Print formatted JSON telemetry results to stdout.
  --json-output=<file>     Optional file path to save the JSON telemetry results.
  --skip-capability-probe  Skip the initial Wasm JS-string capability probe.
  --help, -h               Show this help message.

Examples:
  dart tool/benchmark.dart --browser=chrome --json
  dart tool/benchmark.dart --browser=safari,firefox --nodes=1000 --json-output=results.json
  dart tool/benchmark.dart --preset=medium --browser=chrome
  dart tool/benchmark.dart --url=http://localhost:8080 --output=doc/benchmarks.md
''');
}
