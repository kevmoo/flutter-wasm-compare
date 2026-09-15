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

  _printHeader(args);

  final benchmarkResults =
      <BrowserType, Map<BenchmarkKey, MultiSampleRecord>>{};
  final capabilityResults = <BrowserType, CapabilityRecord>{};

  for (final browserType in args.browsers) {
    final browserMap = await _runBrowserSuite(
      browserType: browserType,
      args: args,
      capabilityResults: capabilityResults,
    );
    if (browserMap != null) {
      benchmarkResults[browserType] = browserMap;
    }
  }

  if (benchmarkResults.isEmpty) {
    print('\nNo benchmark results collected.');
    exitCode = 1;
    return;
  }

  await _emitOutputs(
    args: args,
    capabilityResults: capabilityResults,
    benchmarkResults: benchmarkResults,
  );
}

void _printHeader(BenchmarkArgs args) {
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
}

Future<Map<BenchmarkKey, MultiSampleRecord>?> _runBrowserSuite({
  required BrowserType browserType,
  required BenchmarkArgs args,
  required Map<BrowserType, CapabilityRecord> capabilityResults,
}) async {
  final driver = _createDriver(browserType);
  if (!await driver.isAvailable()) {
    print('⚠️  Skipping ${browserType.label}: binary/driver not found.');
    return null;
  }

  print('\n>>> Launching ${browserType.label}...');
  try {
    await driver.start(
      viewportWidth: args.viewportWidth,
      viewportHeight: args.viewportHeight,
      initialUrl: args.baseUrl,
    );

    final vpRaw = await driver.evaluate(
      '[window.innerWidth, window.innerHeight]',
    );
    if (vpRaw is List && vpRaw.length >= 2) {
      print('  • Calibrated viewport: ${vpRaw[0]}x${vpRaw[1]} px');
    }

    if (!args.skipCapabilityProbe) {
      await _probeCapabilities(
        driver: driver,
        browserType: browserType,
        args: args,
        capabilityResults: capabilityResults,
      );
    }

    final browserMap = <BenchmarkKey, MultiSampleRecord>{};
    for (final mode in args.modes) {
      for (final nodes in args.nodeCounts) {
        final multi = await _runWorkloadForModeAndNodes(
          driver: driver,
          args: args,
          mode: mode,
          nodes: nodes,
        );
        if (multi != null) {
          browserMap[BenchmarkKey(mode, nodes)] = multi;
        }
      }
    }
    return browserMap;
  } catch (e, st) {
    print('❌ Error running ${browserType.label}: $e\n$st');
    return null;
  } finally {
    await driver.stop();
  }
}

Future<void> _probeCapabilities({
  required BrowserDriver driver,
  required BrowserType browserType,
  required BenchmarkArgs args,
  required Map<BrowserType, CapabilityRecord> capabilityResults,
}) async {
  print('  • Probing WebAssembly capabilities...');
  final baseWithoutQuery = args.baseUrl.replaceAll(RegExp(r'\?.*$'), '');
  final probeUrl = '$baseWithoutQuery?mode=wasm&optin=true';
  await driver.navigate(probeUrl);
  await Future<void>.delayed(const Duration(seconds: 3));
  final probeRaw = await driver.evaluate(_capabilityProbeScript);
  if (probeRaw == null) return;
  final probe = CapabilityRecord.parse(probeRaw);
  capabilityResults[browserType] = probe;
  final passLabel = probe.invertedProbe ? 'YES (PASS)' : 'NO';
  print('    - Wasm JS-String Supported: $passLabel');
  print('    - Cross-Origin Isolated:     ${probe.crossOriginIsolated}');
}

Future<MultiSampleRecord?> _runWorkloadForModeAndNodes({
  required BrowserDriver driver,
  required BenchmarkArgs args,
  required BenchmarkMode mode,
  required int nodes,
}) async {
  final url = buildBenchmarkUrl(
    args.baseUrl,
    mode,
    nodes,
    workload: args.workload,
  );

  await driver.evaluate('''
    try {
      localStorage.removeItem('${mode.storageKey}');
      localStorage.removeItem('${mode.storageKey}_${args.workload}');
      localStorage.removeItem('wasm_compare_active_node_count');
      localStorage.removeItem('wasm_compare_active_node_count_${args.workload}');
      localStorage.removeItem('wasm_compare_active_workload_id');
    } catch (_) {}
  ''');

  stdout.write(
    '  • [${mode.label} / ${args.workload}] @ $nodes nodes: settling...',
  );
  await driver.navigate(url);

  for (var s = args.settleSeconds; s > 0; s--) {
    stdout.write(' ${s}s');
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  stdout.write(' sampling (${args.samples}x)...');
  final collected = await _collectSamples(
    driver: driver,
    args: args,
    mode: mode,
    nodes: nodes,
  );
  stdout.write(' done.\r');

  final multi = collected.isNotEmpty
      ? MultiSampleRecord.fromRecords(collected)
      : null;
  _printWorkloadSummary(mode, nodes, multi);
  return multi;
}

Future<List<BenchmarkRecord>> _collectSamples({
  required BrowserDriver driver,
  required BenchmarkArgs args,
  required BenchmarkMode mode,
  required int nodes,
}) async {
  final collected = <BenchmarkRecord>[];
  final readExpr = "localStorage.getItem('${mode.storageKey}')";
  final maxAttempts = args.samples * 3 + 5;
  var attempts = 0;
  var lastTotalFrameTime = -1.0;

  while (collected.length < args.samples && attempts < maxAttempts) {
    attempts++;
    if (collected.isNotEmpty || attempts > 1) {
      await Future<void>.delayed(Duration(milliseconds: args.sampleIntervalMs));
    }
    final rawJson = await driver.evaluate(readExpr);
    if (rawJson is! String || rawJson.isEmpty) continue;
    final data = jsonDecode(rawJson) as Map<String, dynamic>;
    final record = BenchmarkRecord.fromJson(data);
    if (!record.matches(mode, nodes, expectedWorkloadId: args.workload)) {
      continue;
    }
    if (record.totalFrameTimeMs != lastTotalFrameTime || collected.isEmpty) {
      collected.add(record);
      lastTotalFrameTime = record.totalFrameTimeMs;
    }
  }
  return collected;
}

void _printWorkloadSummary(
  BenchmarkMode mode,
  int nodes,
  MultiSampleRecord? multi,
) {
  final label = mode.label.padRight(15);
  final nodeStr = nodes.toString().padLeft(4);
  if (multi == null) {
    print(
      '  ✗ [$label] @ $nodeStr nodes -> '
      'No metrics found in localStorage.',
    );
    return;
  }

  final fpsStr = multi.fps.medianNs.toStringAsFixed(1);
  final p95Fps = multi.fps.p95Ns.toStringAsFixed(1);
  final buildStr = (multi.buildTime.medianNs / 1e6).toStringAsFixed(2);
  final buildMad = (multi.buildTime.madNs / 1e6).toStringAsFixed(2);
  final rasterStr = (multi.rasterTime.medianNs / 1e6).toStringAsFixed(2);
  final rasterMad = (multi.rasterTime.madNs / 1e6).toStringAsFixed(2);
  final stabilityTag = multi.buildTime.isRobustStable ? 'STABLE' : 'UNSTABLE';

  print(
    '  ✓ [$label] @ $nodeStr nodes -> '
    '$fpsStr FPS (p95: $p95Fps) | '
    'Build: ${buildStr}ms (MAD: ${buildMad}ms) | '
    'Raster: ${rasterStr}ms (MAD: ${rasterMad}ms) '
    '[$stabilityTag]',
  );
}

Future<void> _emitOutputs({
  required BenchmarkArgs args,
  required Map<BrowserType, CapabilityRecord> capabilityResults,
  required Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>>
  benchmarkResults,
}) async {
  final report = formatMarkdownReport(
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

String buildBenchmarkUrl(
  String baseUrl,
  BenchmarkMode mode,
  int nodes, {
  String workload = 'bouncy',
}) {
  final uri = Uri.parse(baseUrl);
  final query = Map<String, String>.from(uri.queryParameters);
  query['workload'] = workload;
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

String formatMarkdownReport({
  required BenchmarkArgs args,
  required Map<BrowserType, CapabilityRecord> capabilities,
  required Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>> results,
}) {
  final buffer = StringBuffer();
  _writeMarkdownHeader(buffer, args);
  _writeMarkdownCapabilities(buffer, capabilities);
  _writeMarkdownMatrix(buffer, args, results);
  _writeMarkdownTakeaways(buffer, args, results);
  return buffer.toString();
}

void _writeMarkdownHeader(StringBuffer buffer, BenchmarkArgs args) {
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
}

void _writeMarkdownCapabilities(
  StringBuffer buffer,
  Map<BrowserType, CapabilityRecord> capabilities,
) {
  if (capabilities.isEmpty) return;
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

void _writeMarkdownMatrix(
  StringBuffer buffer,
  BenchmarkArgs args,
  Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>> results,
) {
  buffer.writeln('## 📊 Performance Comparison Matrix (Median Values)');
  buffer.writeln();
  buffer.writeln('<!-- mdformat off -->');

  final columns = <_ReportColumn>[
    for (final browser in results.keys)
      for (final mode in args.modes) _ReportColumn(browser, mode),
  ];

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
}

void _writeMarkdownTakeaways(
  StringBuffer buffer,
  BenchmarkArgs args,
  Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>> results,
) {
  final takeaways = StringBuffer();
  for (final browser in results.keys) {
    final browserResults = results[browser]!;
    final matchingNodes = args.nodeCounts.where(
      (int n) =>
          browserResults.containsKey(
            BenchmarkKey(BenchmarkMode.wasmMultithreaded, n),
          ) &&
          browserResults.containsKey(
            BenchmarkKey(BenchmarkMode.wasmSingleThreaded, n),
          ) &&
          browserResults.containsKey(
            BenchmarkKey(BenchmarkMode.jsCanvasKit, n),
          ),
    );

    for (final nodes in matchingNodes) {
      _writeNodeTakeaways(takeaways, browser, nodes, browserResults);
    }
  }

  if (takeaways.isNotEmpty) {
    buffer.writeln('### Key Takeaways (Fieller 95% Confidence Intervals)');
    buffer.write(takeaways.toString());
  }
}

void _writeNodeTakeaways(
  StringBuffer takeaways,
  BrowserType browser,
  int nodes,
  Map<BenchmarkKey, MultiSampleRecord> browserResults,
) {
  final mt =
      browserResults[BenchmarkKey(BenchmarkMode.wasmMultithreaded, nodes)]!;
  final st =
      browserResults[BenchmarkKey(BenchmarkMode.wasmSingleThreaded, nodes)]!;
  final js = browserResults[BenchmarkKey(BenchmarkMode.jsCanvasKit, nodes)]!;

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

class _ReportColumn(final BrowserType browser, final BenchmarkMode mode) {
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

enum BrowserType(final String label) {
  chrome('Chrome'),
  safari('Safari'),
  firefox('Firefox')
}

enum BenchmarkMode(
  final String label,
  final String shortLabel,
  final String storageKey,
) {
  wasmMultithreaded('Wasm MT (st=0)', 'Wasm MT', 'wasm_compare_last_wasm_run'),
  wasmSingleThreaded('Wasm ST (st=1)', 'Wasm ST', 'wasm_compare_last_wasm_run'),
  jsCanvasKit('JS CanvasKit', 'JS', 'wasm_compare_last_js_run')
}

class const BenchmarkKey(final BenchmarkMode mode, final int nodes) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BenchmarkKey && other.mode == mode && other.nodes == nodes;

  @override
  int get hashCode => Object.hash(mode, nodes);
}

class BenchmarkRecord({
  required final double fps,
  required final double buildTimeMs,
  required final double rasterTimeMs,
  required final double totalFrameTimeMs,
  required final double jitterMs,
  required final bool isPipelined,
  required final int nodeCount,
  required final String mode,
  final String workloadId = 'bouncy',
}) {
  factory fromJson(Map<String, dynamic> json) {
    return BenchmarkRecord(
      fps: (json['fps'] as num?)?.toDouble() ?? 0.0,
      buildTimeMs: (json['buildTimeMs'] as num?)?.toDouble() ?? 0.0,
      rasterTimeMs: (json['rasterTimeMs'] as num?)?.toDouble() ?? 0.0,
      totalFrameTimeMs: (json['totalFrameTimeMs'] as num?)?.toDouble() ?? 0.0,
      jitterMs: (json['jitterMs'] as num?)?.toDouble() ?? 0.0,
      isPipelined: json['isPipelined'] as bool? ?? false,
      nodeCount: (json['nodeCount'] as num?)?.toInt() ?? 0,
      mode: json['mode'] as String? ?? '',
      workloadId: json['workloadId'] as String? ?? 'bouncy',
    );
  }

  /// Verifies whether this record corresponds to the intended mode, node
  /// count, and workload, preventing stale cross-mode or cross-workload reads
  /// from localStorage.
  bool matches(
    BenchmarkMode expectedMode,
    int expectedNodes, {
    String? expectedWorkloadId,
  }) {
    if (nodeCount != expectedNodes) return false;
    if (expectedWorkloadId != null &&
        workloadId.isNotEmpty &&
        workloadId != expectedWorkloadId) {
      return false;
    }
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
class MultiSampleRecord({
  required final int samplesCount,
  required final bool isPipelined,
  required final BenchmarkMetrics fps,
  required final BenchmarkMetrics buildTime,
  required final BenchmarkMetrics rasterTime,
  required final BenchmarkMetrics totalFrameTime,
  required final BenchmarkMetrics jitter,
  required final List<double> rawFps,
  required final List<double> rawBuildMs,
  required final List<double> rawRasterMs,
}) {
  factory fromRecords(List<BenchmarkRecord> records) {
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

class CapabilityRecord({
  required final String userAgent,
  required final bool crossOriginIsolated,
  required final bool invertedProbe,
}) {
  factory parse(dynamic raw) {
    final map = (raw is String ? jsonDecode(raw) : raw) as Map<String, dynamic>;
    return CapabilityRecord(
      userAgent: map['userAgent'] as String? ?? '',
      crossOriginIsolated: map['crossOriginIsolated'] as bool? ?? false,
      invertedProbe: map['invertedProbe'] as bool? ?? false,
    );
  }
}

abstract interface class BrowserDriver() {
  Future<bool> isAvailable();
  Future<void> start({
    required int viewportWidth,
    required int viewportHeight,
    String initialUrl = 'http://localhost:8899/',
  });
  Future<void> navigate(String url);
  Future<dynamic> evaluate(String script);
  Future<void> stop();
}

BrowserDriver _createDriver(BrowserType type) => switch (type) {
  BrowserType.chrome => _ChromeCdpDriver(),
  BrowserType.safari => _SafariWebDriver(),
  BrowserType.firefox => _FirefoxWebDriver(),
};

/// Selects the first CDP page target whose URL starts with `http`.
String? selectCdpPageTargetWsUrl(List<dynamic> targets) {
  for (final t in targets) {
    final targetUrl = (t is Map<String, dynamic>)
        ? (t['url'] as String? ?? '')
        : '';
    if (t is Map<String, dynamic> &&
        t['type'] == 'page' &&
        targetUrl.startsWith('http')) {
      return t['webSocketDebuggerUrl'] as String?;
    }
  }
  return null;
}

/// Drives Chrome via native Chrome DevTools Protocol (CDP) WebSocket.
class _ChromeCdpDriver() implements BrowserDriver {
  Process? _process;
  WebSocket? _ws;
  Directory? _tempDir;
  int _port = 0;
  int _viewportWidth = 1280;
  int _viewportHeight = 720;
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
    String initialUrl = 'http://localhost:8899/',
  }) async {
    _viewportWidth = viewportWidth;
    _viewportHeight = viewportHeight;
    final chromePath = _findChromeBinary()!;
    _port = await _findAvailablePort();
    if (!Platform.isLinux) {
      _tempDir = await Directory.systemTemp.createTemp('chrome_bench_');
    }

    _process = await Process.start(chromePath, [
      if (Platform.isLinux) ...[
        '--headless=new',
        '--no-sandbox',
        '--no-proxy-server',
      ],
      '--remote-debugging-port=$_port',
      if (!Platform.isLinux) '--user-data-dir=${_tempDir!.path}',
      '--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding',
      '--no-first-run',
      '--no-default-browser-check',
      '--window-size=${viewportWidth + 100},${viewportHeight + 100}',
      initialUrl,
    ], mode: ProcessStartMode.normal);

    await _connectToPageTarget();
  }

  Future<void> _connectToPageTarget() async {
    await _wsSub?.cancel();
    await _ws?.close();
    _pendingResponses.clear();

    final wsUrl = await _pollCdpPageTargetWsUrl();
    if (wsUrl == null) {
      throw StateError(
        'Failed to obtain Chrome DevTools WebSocket URL on port $_port',
      );
    }

    _ws = await WebSocket.connect(wsUrl);
    _attachCdpWebSocketListener();
    await _waitForPageReady();

    await _sendCdp('Emulation.setDeviceMetricsOverride', {
      'width': _viewportWidth,
      'height': _viewportHeight,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
  }

  Future<String?> _pollCdpPageTargetWsUrl() async {
    for (var attempt = 0; attempt < 40; attempt++) {
      final wsUrl = await _fetchPageTargetWsUrlOnce();
      if (wsUrl != null) return wsUrl;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<String?> _fetchPageTargetWsUrlOnce() async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('http://127.0.0.1:$_port/json/list');
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final targets = jsonDecode(body) as List<dynamic>;
      return selectCdpPageTargetWsUrl(targets);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  void _attachCdpWebSocketListener() {
    _wsSub = _ws!.listen(
      (message) {
        if (message is! String) return;
        final map = jsonDecode(message) as Map<String, dynamic>;
        final id = map['id'] as int?;
        if (id != null && _pendingResponses.containsKey(id)) {
          _pendingResponses.remove(id)!.complete(map['result']);
        }
      },
      onDone: () {
        for (final c in _pendingResponses.values) {
          if (!c.isCompleted) {
            c.completeError(StateError('WebSocket disconnected'));
          }
        }
        _pendingResponses.clear();
      },
    );
  }

  Future<void> _waitForPageReady() async {
    for (var i = 0; i < 40; i++) {
      try {
        final href = await evaluate('window.location.href');
        if (href is String && href.startsWith('http')) {
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<dynamic> _sendCdp(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (_ws == null || _ws!.readyState != WebSocket.open) {
      await _connectToPageTarget();
    }
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
    await stop();
    await start(
      viewportWidth: _viewportWidth,
      viewportHeight: _viewportHeight,
      initialUrl: url,
    );
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
class _SafariWebDriver() implements BrowserDriver {
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
    String initialUrl = 'http://localhost:8899/',
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
class _FirefoxWebDriver() implements BrowserDriver {
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
    String initialUrl = 'http://localhost:8899/',
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

class BenchmarkArgs({
  required final bool showHelp,
  required final String baseUrl,
  final String workload = 'bouncy',
  required final List<BrowserType> browsers,
  required final List<BenchmarkMode> modes,
  required final List<int> nodeCounts,
  required final int viewportWidth,
  required final int viewportHeight,
  required final int settleSeconds,
  required final int samples,
  final int sampleIntervalMs = 1200,
  required final String? outputPath,
  required final bool jsonOutput,
  required final String? jsonOutputPath,
  required final bool skipCapabilityProbe,
}) {
  static List<int> _defaultNodesForWorkload(String workload, [String? preset]) {
    final isGrid = workload == 'grid';
    switch (preset) {
      case 'light':
        return isGrid ? [100] : [32];
      case 'medium':
        return isGrid ? [1000] : [64];
      case 'heavy' || 'max':
        return isGrid ? [8000] : [128];
      default:
        return isGrid ? [100, 1000, 8000] : [32, 64, 128];
    }
  }

  factory parse(List<String> args) {
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

    final parsed = _MutableBenchmarkArgs();
    for (final arg in args) {
      parsed.applyArg(arg);
    }

    return parsed.toBenchmarkArgs();
  }
}

class _MutableBenchmarkArgs() {
  String baseUrl = 'https://flutter-wasm-compare.web.app/';
  String workload = 'bouncy';
  List<BrowserType> browsers = BrowserType.values.toList();
  List<BenchmarkMode> modes = BenchmarkMode.values.toList();
  List<int>? explicitNodeCounts;
  String? presetVal;
  int viewportWidth = 1280;
  int viewportHeight = 720;
  int settleSeconds = 5;
  int samples = 5;
  int sampleIntervalMs = 1200;
  String? outputPath;
  bool jsonOutput = false;
  String? jsonOutputPath;
  bool skipCapabilityProbe = false;

  void applyArg(String arg) {
    if (arg == '--json') {
      jsonOutput = true;
    } else if (arg == '--skip-capability-probe') {
      skipCapabilityProbe = true;
    } else if (arg.startsWith('--')) {
      _applyKeyValueArg(arg);
    }
  }

  void _applyKeyValueArg(String arg) {
    final eqIdx = arg.indexOf('=');
    if (eqIdx < 0) return;
    final key = arg.substring(0, eqIdx);
    final val = arg.substring(eqIdx + 1);
    switch (key) {
      case '--url':
        baseUrl = val;
      case '--workload':
        workload = val.toLowerCase().trim() == 'grid' ? 'grid' : 'bouncy';
      case '--browser' || '--browsers':
        browsers = _parseBrowsers(val);
      case '--modes':
        modes = _parseModes(val);
      case '--preset':
        presetVal = val.toLowerCase();
      case '--nodes':
        explicitNodeCounts = _parseNodes(val);
      case '--viewport':
        _applyViewport(val);
      case '--settle-seconds':
        settleSeconds = int.tryParse(val) ?? settleSeconds;
      case '--samples':
        samples = int.tryParse(val) ?? samples;
      case '--sample-interval' || '--sample-interval-ms':
        sampleIntervalMs = int.tryParse(val) ?? sampleIntervalMs;
      case '--output':
        outputPath = val;
      case '--json-output':
        jsonOutputPath = val;
    }
  }

  static List<BrowserType> _parseBrowsers(String val) {
    final lower = val.toLowerCase();
    if (lower == 'all') return BrowserType.values.toList();
    final result = <BrowserType>[];
    for (final token in lower.split(',')) {
      switch (token.trim()) {
        case 'chrome':
          result.add(BrowserType.chrome);
        case 'safari':
          result.add(BrowserType.safari);
        case 'firefox':
          result.add(BrowserType.firefox);
      }
    }
    return result;
  }

  static List<BenchmarkMode> _parseModes(String val) {
    final result = <BenchmarkMode>[];
    for (final token in val.toLowerCase().split(',')) {
      switch (token.trim()) {
        case 'wasm_mt' || 'mt':
          result.add(BenchmarkMode.wasmMultithreaded);
        case 'wasm_st' || 'st':
          result.add(BenchmarkMode.wasmSingleThreaded);
        case 'js':
          result.add(BenchmarkMode.jsCanvasKit);
      }
    }
    return result;
  }

  static List<int> _parseNodes(String val) => val
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();

  void _applyViewport(String val) {
    final parts = val.toLowerCase().split('x');
    if (parts.length != 2) return;
    final w = int.tryParse(parts[0].trim());
    final h = int.tryParse(parts[1].trim());
    if (w != null && h != null) {
      viewportWidth = w;
      viewportHeight = h;
    }
  }

  BenchmarkArgs toBenchmarkArgs() {
    final resolvedNodeCounts =
        (explicitNodeCounts != null && explicitNodeCounts!.isNotEmpty)
        ? explicitNodeCounts!
        : BenchmarkArgs._defaultNodesForWorkload(workload, presetVal);

    return BenchmarkArgs(
      showHelp: false,
      baseUrl: baseUrl,
      workload: workload,
      browsers: browsers.isEmpty ? BrowserType.values.toList() : browsers,
      modes: modes.isEmpty ? BenchmarkMode.values.toList() : modes,
      nodeCounts: resolvedNodeCounts,
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
  --workload=<name>        Workload type: bouncy (layout churn) or grid (card grid).
                           Default: bouncy
  --preset=<name>          Convenience workload preset: light, medium, heavy, or all.
                           (bouncy: 32, 64, 128; grid: 100, 1000, 8000)
  --nodes=<counts>         Comma-separated list of stress node counts.
                           Default: 32,64,128 (bouncy) or 100,1000,8000 (grid)
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
  dart tool/benchmark.dart --workload=grid --preset=heavy --browser=chrome
  dart tool/benchmark.dart --browser=safari,firefox --nodes=64 --json-output=results.json
  dart tool/benchmark.dart --url=http://localhost:8080 --output=doc/benchmarks.md
''');
}
