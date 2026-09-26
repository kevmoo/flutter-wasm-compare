import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:bench_press/bench_press.dart';

/// Automated browser benchmark driver for `flutter-wasm-compare`.
///
/// Supports Chrome, Safari, and Firefox on macOS/Linux with statistical
/// sampling and telemetry powered by `package:bench_press`.
Future<void> main(List<String> rawArgs) async {
  final BenchmarkArgs args;
  try {
    args = BenchmarkArgs.parse(rawArgs);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    _printUsage(stderr);
    exit(2);
  }
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

  final anyRecorded = benchmarkResults.values.any(
    (records) => records.isNotEmpty,
  );
  if (!anyRecorded) {
    print('\nNo benchmark results collected.');
    exitCode = 1;
    return;
  }

  await _emitOutputs(
    args: args,
    capabilityResults: capabilityResults,
    benchmarkResults: benchmarkResults,
  );

  if (hasFailedRuns(benchmarkResults)) {
    exitCode = 1;
  }
}

/// Whether any recorded point errored or contradicted its mode at runtime.
///
/// Either makes the process exit non-zero after the report is written.
bool hasFailedRuns(
  Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>> results,
) => results.values.any(
  (records) => records.entries.any(
    (entry) => entry.value.failureReason(entry.key.mode) != null,
  ),
);

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
  final driver = _createDriver(browserType, args);
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
      if (mode == BenchmarkMode.jsWebParagraph &&
          browserType != BrowserType.chrome) {
        print(
          '  ⚠️ Skipping ${mode.label} on ${browserType.label} '
          '(requires Chrome with experimental TextCluster API).',
        );
        continue;
      }
      for (final nodes in args.nodeCounts) {
        try {
          browserMap[BenchmarkKey(
            mode,
            nodes,
          )] = await _runWorkloadForModeAndNodes(
            driver: driver,
            args: args,
            mode: mode,
            nodes: nodes,
          );
        } catch (e) {
          print('    ❌ Workload failed: $e');
          browserMap[BenchmarkKey(mode, nodes)] = MultiSampleRecord.error(
            e.toString(),
          );
        }
      }
    }
    return browserMap;
  } catch (e, st) {
    print('❌ Error running ${browserType.label}: $e\n$st');
    exitCode = 1;
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

Future<MultiSampleRecord> _runWorkloadForModeAndNodes({
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

  try {
    await driver.evaluate('''
      (() => {
        try {
          localStorage.removeItem('${mode.storageKey}');
          localStorage.removeItem('${mode.storageKey}_${args.workload}');
          localStorage.removeItem('wasm_compare_active_node_count');
          localStorage.removeItem('wasm_compare_active_node_count_${args.workload}');
          localStorage.removeItem('wasm_compare_active_workload_id');
        } catch (_) {}
      })()
    ''');
  } catch (e) {
    print('  ⚠️  localStorage clear failed: $e');
  }

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
  final runtime = RuntimeRecord.parse(
    await driver.evaluate(_runtimeProbeScript),
  );
  stdout.write(' done.\r');

  final multi = summarizeSamples(
    collected,
    requestedSamples: args.samples,
    runtime: runtime,
  );
  _printWorkloadSummary(mode, nodes, multi, runtime);
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
  final maxAttempts = maxSampleAttempts(
    samples: args.samples,
    sampleIntervalMs: args.sampleIntervalMs,
  );
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

/// Maximum `localStorage` poll attempts for [samples] at [sampleIntervalMs].
///
/// The app throttles `localStorage` publishes to once per 1000ms, so when
/// [sampleIntervalMs] is set below the default 1200ms, the attempt count is
/// scaled up to preserve at least `(samples * 3 + 5) * 1200ms` of wall-clock
/// budget.
int maxSampleAttempts({required int samples, required int sampleIntervalMs}) {
  final baseAttempts = samples * 3 + 5;
  if (sampleIntervalMs <= 0 || sampleIntervalMs >= 1200) {
    return baseAttempts;
  }
  return (baseAttempts * 1200 + sampleIntervalMs - 1) ~/ sampleIntervalMs;
}

/// Aggregates the samples collected for one point, failing closed.
///
/// Returns an error record when no sample arrived, or when sampling timed out
/// before [requestedSamples] distinct samples were read: a stalled renderer
/// keeps republishing the same frame stats, so a short run is a freeze, not a
/// measurement. Error records keep the sample count and [runtime] for triage.
MultiSampleRecord summarizeSamples(
  List<BenchmarkRecord> collected, {
  required int requestedSamples,
  RuntimeRecord? runtime,
}) {
  final counts = '${collected.length} of $requestedSamples requested samples';
  if (collected.isEmpty) {
    return MultiSampleRecord.error(
      'No metrics found in localStorage ($counts)',
      runtime: runtime,
    );
  }
  if (collected.length < requestedSamples) {
    return MultiSampleRecord.error(
      'Incomplete sample count ($counts)',
      samplesCount: collected.length,
      runtime: runtime,
    );
  }
  return MultiSampleRecord.fromRecords(collected, runtime: runtime);
}

void _printWorkloadSummary(
  BenchmarkMode mode,
  int nodes,
  MultiSampleRecord multi,
  RuntimeRecord runtime,
) {
  final label = mode.label.padRight(15);
  final nodeStr = nodes.toString().padLeft(4);
  final invalidReason = runtime.invalidReason(mode);
  final invalidTag = invalidReason == null ? '' : ' [INVALID: $invalidReason]';
  if (multi.errorMessage case final error?) {
    print('  ✗ [$label] @ $nodeStr nodes -> $error.$invalidTag');
    return;
  }

  final fpsStr = multi.fps.medianNs.toStringAsFixed(1);
  final p95Fps = multi.fps.p95Ns.toStringAsFixed(1);
  final buildStr = (multi.buildTime.medianNs / 1e6).toStringAsFixed(2);
  final buildMad = (multi.buildTime.madNs / 1e6).toStringAsFixed(2);
  final rasterStr = (multi.rasterTime.medianNs / 1e6).toStringAsFixed(2);
  final rasterMad = (multi.rasterTime.madNs / 1e6).toStringAsFixed(2);
  final stabilityTag = multi.buildTime.isRobustStable ? 'STABLE' : 'UNSTABLE';
  final marker = invalidReason == null ? '✓' : '✗';

  print(
    '  $marker [$label] @ $nodeStr nodes -> '
    '$fpsStr FPS (p95: $p95Fps) | '
    'Build: ${buildStr}ms (MAD: ${buildMad}ms) | '
    'Raster: ${rasterStr}ms (MAD: ${rasterMad}ms) '
    '[$stabilityTag]$invalidTag',
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

  final jsonResult = generateJsonReport(
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
    case BenchmarkMode.wimpMultithreaded:
      query['mode'] = 'wimp';
      query['optin'] = 'true';
      query['st'] = '0';
    case BenchmarkMode.wimpSingleThreaded:
      query['mode'] = 'wimp';
      query['optin'] = 'true';
      query['st'] = '1';
    case BenchmarkMode.jsCanvasKit:
      query['mode'] = 'js';
      query.remove('optin');
      query.remove('st');
    case BenchmarkMode.jsWebParagraph:
      query['mode'] = 'webparagraph';
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
  _writeMarkdownRuntime(buffer, results);
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

void _writeMarkdownRuntime(
  StringBuffer buffer,
  Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>> results,
) {
  final rows = [
    for (final MapEntry(key: browser, value: records) in results.entries)
      for (final MapEntry(:key, value: multi) in records.entries)
        if (multi.runtime case final runtime?) (browser, key, multi, runtime),
  ];
  if (rows.isEmpty) return;
  buffer.writeln('## 🔎 Runtime Verification');
  buffer.writeln();
  buffer.writeln(
    '| Browser | Mode | Nodes | WIMP Active | Engine MT | '
    'Cross-Origin Isolated | WebGL Renderer | WebGL Vendor | Status |',
  );
  buffer.writeln(
    '| :--- | :--- | ---: | :---: | :---: | :---: | :--- | :--- | :--- |',
  );
  for (final (browser, key, multi, runtime) in rows) {
    final status = switch ((
      runtime.invalidReason(key.mode),
      multi.errorMessage,
    )) {
      (final reason?, _) => '⚠️ INVALID: $reason',
      (null, final error?) => '⚠️ ERROR: $error',
      (null, null) => '✅ valid',
    };
    buffer.writeln(
      '| ${browser.label} | ${key.mode.label} | ${key.nodes} | '
      '${runtime.isWimp ?? 'n/a'} | ${runtime.isMultiThreaded ?? 'n/a'} | '
      '${runtime.crossOriginIsolated} | `${runtime.webglRenderer ?? 'n/a'}` | '
      '`${runtime.webglVendor ?? 'n/a'}` | $status |',
    );
  }
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
        if (rec.errorMessage != null) {
          buffer.write(' ⚠️ ERROR |');
        } else {
          final fpsStr = rec.fps.medianNs.toStringAsFixed(1);
          final buildStr = (rec.buildTime.medianNs / 1e6).toStringAsFixed(2);
          final rasterStr = (rec.rasterTime.medianNs / 1e6).toStringAsFixed(2);
          final invalid = rec.runtime?.invalidReason(col.mode) != null;
          final flag = invalid ? '⚠️ INVALID ' : '';
          buffer.write(
            ' $flag**$fpsStr FPS** / ${buildStr}ms / ${rasterStr}ms |',
          );
        }
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
    for (final nodes in _matchingNodeCounts(args.nodeCounts, browserResults)) {
      _writeNodeTakeaways(takeaways, browser, nodes, browserResults);
    }
  }

  if (takeaways.isNotEmpty) {
    buffer.writeln('### Key Takeaways (Fieller 95% Confidence Intervals)');
    buffer.write(takeaways.toString());
  }
}

/// Node counts with a successful record for every mode the takeaways compare.
///
/// Error records carry no usable samples, and INVALID runs measured a
/// different renderer than their label, so both are excluded rather than
/// compared.
Iterable<int> _matchingNodeCounts(
  List<int> nodeCounts,
  Map<BenchmarkKey, MultiSampleRecord> browserResults,
) {
  bool succeeded(BenchmarkMode mode, int nodes) {
    final record = browserResults[BenchmarkKey(mode, nodes)];
    return record != null && record.failureReason(mode) == null;
  }

  return nodeCounts.where(
    (int n) =>
        succeeded(BenchmarkMode.wasmMultithreaded, n) &&
        succeeded(BenchmarkMode.wasmSingleThreaded, n) &&
        succeeded(BenchmarkMode.jsCanvasKit, n),
  );
}

({
  FiellerInterval rasterOverhead,
  FiellerInterval fpsPipeliningWin,
  FiellerInterval vsJsFpsSpeedup,
  FiellerInterval vsJsBuildSpeedup,
})
_computeNodeFiellerIntervals(
  MultiSampleRecord mt,
  MultiSampleRecord st,
  MultiSampleRecord js,
) {
  return (
    rasterOverhead: FiellerInterval.compute(
      sampleA: mt.rawRasterMs,
      sampleB: st.rawRasterMs,
    ),
    fpsPipeliningWin: FiellerInterval.compute(
      sampleA: mt.rawFps,
      sampleB: st.rawFps,
    ),
    vsJsFpsSpeedup: FiellerInterval.compute(
      sampleA: mt.rawFps,
      sampleB: js.rawFps,
    ),
    vsJsBuildSpeedup: FiellerInterval.compute(
      sampleA: js.rawBuildMs,
      sampleB: mt.rawBuildMs,
    ),
  );
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

  final intervals = _computeNodeFiellerIntervals(mt, st, js);

  final mtRasterMed = (mt.rasterTime.medianNs / 1e6).toStringAsFixed(2);
  final stRasterMed = (st.rasterTime.medianNs / 1e6).toStringAsFixed(2);
  final mtFpsMed = mt.fps.medianNs.toStringAsFixed(1);
  final stFpsMed = st.fps.medianNs.toStringAsFixed(1);
  final mtBuildMed = (mt.buildTime.medianNs / 1e6).toStringAsFixed(2);
  final jsBuildMed = (js.buildTime.medianNs / 1e6).toStringAsFixed(2);

  takeaways.writeln('* **${browser.label} (at $nodes nodes)**:');
  takeaways.writeln(
    '  * Worker Raster Overhead: `st=0` is '
    '**${formatFieller(intervals.rasterOverhead)}** that of `st=1` '
    '(${mtRasterMed}ms vs ${stRasterMed}ms).',
  );
  takeaways.writeln(
    '  * Pipelining Throughput Win: `st=0` delivers '
    '**${formatFieller(intervals.fpsPipeliningWin)} higher FPS** than `st=1` '
    '($mtFpsMed vs $stFpsMed FPS).',
  );
  takeaways.writeln(
    '  * Dart2Wasm vs Dart2JS: Wasm delivers '
    '**${formatFieller(intervals.vsJsFpsSpeedup)} higher FPS** and '
    '**${formatFieller(intervals.vsJsBuildSpeedup)} faster UI build** '
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

/// Builds the JSON telemetry report. Failed points are kept as entries with an
/// `error` field, their collected `samples` count, and the `runtime` probe.
Map<String, Object?> generateJsonReport({
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

      if (multi.errorMessage != null) {
        benchmarksList.add({
          'browser': browser.label.toLowerCase(),
          'mode': key.mode.name,
          'mode_label': key.mode.label,
          'workload': args.workload,
          'nodes': key.nodes,
          'error': multi.errorMessage,
          'samples': multi.samplesCount,
          'runtime': multi.runtime?.toJson(key.mode),
        });
      } else {
        benchmarksList.add({
          'browser': browser.label.toLowerCase(),
          'mode': key.mode.name,
          'mode_label': key.mode.label,
          'workload': args.workload,
          'nodes': key.nodes,
          'samples': multi.samplesCount,
          'is_pipelined': multi.isPipelined,
          'fps': statsToJson(multi.fps, isMs: false),
          'build_time_ms': statsToJson(multi.buildTime, isMs: true),
          'raster_time_ms': statsToJson(multi.rasterTime, isMs: true),
          'total_frame_time_ms': statsToJson(multi.totalFrameTime, isMs: true),
          'jitter_ms': statsToJson(multi.jitter, isMs: true),
          'runtime': multi.runtime?.toJson(key.mode),
        });
      }
    }

    // Generate comparison ratios for matching node counts
    final browserName = browser.label.toLowerCase();
    for (final nodes in _matchingNodeCounts(args.nodeCounts, browserResults)) {
      final mt =
          browserResults[BenchmarkKey(BenchmarkMode.wasmMultithreaded, nodes)]!;
      final st =
          browserResults[BenchmarkKey(
            BenchmarkMode.wasmSingleThreaded,
            nodes,
          )]!;
      final js =
          browserResults[BenchmarkKey(BenchmarkMode.jsCanvasKit, nodes)]!;

      final intervals = _computeNodeFiellerIntervals(mt, st, js);
      final entries = [
        ('wasm_mt_vs_wasm_st_raster_overhead', intervals.rasterOverhead),
        ('wasm_mt_vs_wasm_st_fps_pipelining_win', intervals.fpsPipeliningWin),
        ('wasm_mt_vs_js_fps_speedup', intervals.vsJsFpsSpeedup),
        ('wasm_mt_vs_js_build_speedup', intervals.vsJsBuildSpeedup),
      ];
      for (final (name, fieller) in entries) {
        comparisonsList.add(
          fiellerToJson(
            browser: browserName,
            nodes: nodes,
            name: name,
            fieller: fieller,
          ),
        );
      }
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

/// Reads the live engine flags (skwasm/WIMP exports) so every run can prove it
/// exercised the renderer it is labelled with.
///
/// The WebGL renderer and vendor come from a throwaway main-thread WebGL2
/// context, so they identify the page's GPU backend (e.g. SwiftShader vs. a
/// hardware GPU), not the context the engine renders with.
const _runtimeProbeScript = '''(() => {
  const inst = window._flutter_skwasmInstance;
  const flag = (name) => {
    if (!inst) return null;
    const fn = inst["_" + name] || (inst.wasmExports && inst.wasmExports[name]);
    if (typeof fn !== "function") return null;
    try { return Number(fn()) === 1; } catch (e) { return null; }
  };
  let renderer = null;
  let vendor = null;
  try {
    const gl = document.createElement("canvas").getContext("webgl2");
    if (gl) {
      const info = gl.getExtension("WEBGL_debug_renderer_info");
      if (info) {
        renderer = gl.getParameter(info.UNMASKED_RENDERER_WEBGL);
        vendor = gl.getParameter(info.UNMASKED_VENDOR_WEBGL);
      }
      const lose = gl.getExtension("WEBGL_lose_context");
      if (lose) lose.loseContext();
    }
  } catch (e) {}
  return JSON.stringify({
    isWimp: flag("skwasm_isWimp"),
    isMultiThreaded: flag("skwasm_isMultiThreaded"),
    crossOriginIsolated: window.crossOriginIsolated === true,
    webglRenderer: renderer,
    webglVendor: vendor
  });
})()''';

enum BrowserType(final String label) {
  chrome('Chrome'),
  safari('Safari'),
  firefox('Firefox'),
}

enum BenchmarkMode(
  final String label,
  final String shortLabel,
  final String storageKey,
) {
  wasmMultithreaded('Wasm MT (st=0)', 'Wasm MT', 'wasm_compare_last_wasm_run'),
  wasmSingleThreaded('Wasm ST (st=1)', 'Wasm ST', 'wasm_compare_last_wasm_run'),
  wimpMultithreaded('WIMP MT (st=0)', 'WIMP MT', 'wasm_compare_last_wimp_run'),
  wimpSingleThreaded('WIMP ST (st=1)', 'WIMP ST', 'wasm_compare_last_wimp_run'),
  jsCanvasKit('JS CanvasKit', 'JS', 'wasm_compare_last_js_run'),
  jsWebParagraph(
    'JS WebParagraph',
    'JS WP',
    'wasm_compare_last_webparagraph_run',
  ),
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
      case BenchmarkMode.wimpMultithreaded || BenchmarkMode.wimpSingleThreaded:
        // The app reports every WIMP run as `isPipelined: false`, so WIMP
        // threading is verified from engine exports via [RuntimeRecord].
        return normMode == 'wimp';
      case BenchmarkMode.jsCanvasKit:
        return normMode == 'js';
      case BenchmarkMode.jsWebParagraph:
        return normMode == 'webparagraph' ||
            normMode == 'js-webparagraph' ||
            normMode == 'canvaskit-webparagraph';
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
  final RuntimeRecord? runtime,
  final String? errorMessage,
}) {
  factory error(String error, {int samplesCount = 0, RuntimeRecord? runtime}) {
    final empty = BenchmarkMetrics.fromSamples([0]);
    return MultiSampleRecord(
      samplesCount: samplesCount,
      isPipelined: false,
      fps: empty,
      buildTime: empty,
      rasterTime: empty,
      totalFrameTime: empty,
      jitter: empty,
      rawFps: const [],
      rawBuildMs: const [],
      rawRasterMs: const [],
      runtime: runtime,
      errorMessage: error,
    );
  }

  /// Why this point does not count as a measurement of [mode]: its sampling or
  /// driver error, else its runtime-validation failure, else `null`.
  String? failureReason(BenchmarkMode mode) =>
      errorMessage ?? runtime?.invalidReason(mode);

  factory fromRecords(List<BenchmarkRecord> records, {RuntimeRecord? runtime}) {
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
      runtime: runtime,
    );
  }
}

/// Engine and renderer state read from the page after sampling, used to prove
/// that a run exercised the renderer its [BenchmarkMode] claims.
class RuntimeRecord({
  required final bool? isWimp,
  required final bool? isMultiThreaded,
  required final bool crossOriginIsolated,
  final String? webglRenderer,
  final String? webglVendor,
}) {
  /// Parses the result of `_runtimeProbeScript`. Unreadable input yields
  /// `null` engine flags, which makes every Wasm mode fail validation.
  factory parse(dynamic raw) {
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        decoded = null;
      }
    }
    final map = decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
    return RuntimeRecord(
      isWimp: map['isWimp'] as bool?,
      isMultiThreaded: map['isMultiThreaded'] as bool?,
      crossOriginIsolated: map['crossOriginIsolated'] as bool? ?? false,
      webglRenderer: map['webglRenderer'] as String?,
      webglVendor: map['webglVendor'] as String?,
    );
  }

  /// Returns why this runtime state contradicts [mode], or `null` if the run
  /// is valid.
  String? invalidReason(BenchmarkMode mode) {
    final expected = switch (mode) {
      BenchmarkMode.wasmMultithreaded => (wimp: false, mt: true),
      BenchmarkMode.wasmSingleThreaded => (wimp: false, mt: false),
      BenchmarkMode.wimpMultithreaded => (wimp: true, mt: true),
      BenchmarkMode.wimpSingleThreaded => (wimp: true, mt: false),
      BenchmarkMode.jsCanvasKit || BenchmarkMode.jsWebParagraph => null,
    };
    if (expected == null) {
      return isWimp == null ? null : 'skwasm engine loaded on a JS run';
    }
    if (isWimp != expected.wimp) {
      if (isWimp == null) return 'no engine loaded (isWimp=null)';
      return expected.wimp
          ? 'WIMP not active (isWimp=$isWimp)'
          : 'skwasm run with isWimp=$isWimp';
    }
    if (isMultiThreaded != expected.mt) {
      return 'isMultiThreaded=$isMultiThreaded, expected ${expected.mt}';
    }
    if (expected.mt && !crossOriginIsolated) {
      return 'multi-threaded run without crossOriginIsolated';
    }
    return null;
  }

  Map<String, Object?> toJson(BenchmarkMode mode) {
    final reason = invalidReason(mode);
    return {
      'is_wimp': isWimp,
      'is_multi_threaded': isMultiThreaded,
      'cross_origin_isolated': crossOriginIsolated,
      'webgl_renderer': webglRenderer,
      'webgl_vendor': webglVendor,
      'valid': reason == null,
      'invalid_reason': reason,
    };
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

BrowserDriver _createDriver(BrowserType type, BenchmarkArgs args) =>
    switch (type) {
      BrowserType.chrome => _ChromeCdpDriver(
        customBinary: args.chromeBinary,
        customFlags: args.chromeFlags,
        headed: args.headed,
      ),
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

/// Whether [env] provides an X11 or Wayland display server on Linux.
bool hasLinuxDisplay(Map<String, String> env) =>
    (env['DISPLAY']?.trim().isNotEmpty ?? false) ||
    (env['WAYLAND_DISPLAY']?.trim().isNotEmpty ?? false);

/// Builds the command line for the Chrome CDP driver.
///
/// [extraFlags] (from repeated `--chrome-flag=` arguments) are appended after
/// the built-in defaults; [initialUrl] is always the last argument.
List<String> buildChromeArgs({
  required bool isLinux,
  required int debugPort,
  required int viewportWidth,
  required int viewportHeight,
  required String? userDataDir,
  required List<String> extraFlags,
  required String initialUrl,
  bool headed = false,
}) => [
  if (isLinux && !headed) ...['--headless=new', '--no-sandbox'],
  if (isLinux) '--no-proxy-server',
  '--enable-experimental-web-platform-features',
  '--remote-debugging-port=$debugPort',
  if (userDataDir != null) '--user-data-dir=$userDataDir',
  '--disable-background-timer-throttling',
  '--disable-backgrounding-occluded-windows',
  '--disable-renderer-backgrounding',
  '--no-first-run',
  '--no-default-browser-check',
  '--window-size=${viewportWidth + 100},${viewportHeight + 100}',
  ...extraFlags,
  initialUrl,
];

/// Drives Chrome via native Chrome DevTools Protocol (CDP) WebSocket.
class _ChromeCdpDriver({
  final String? customBinary,
  final List<String> customFlags = const [],
  final bool headed = false,
}) implements BrowserDriver {
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
    final chromePath = _chromePath;
    return chromePath != null && File(chromePath).existsSync();
  }

  String? get _chromePath => customBinary ?? _findChromeBinary();

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
    if (Platform.isLinux && headed && !hasLinuxDisplay(Platform.environment)) {
      throw StateError(
        'Cannot launch Chrome with --headed on Linux: '
        'neither DISPLAY nor WAYLAND_DISPLAY is set.',
      );
    }
    _viewportWidth = viewportWidth;
    _viewportHeight = viewportHeight;
    final chromePath = _chromePath!;
    _port = await _findAvailablePort();
    if (!Platform.isLinux || headed) {
      _tempDir = await Directory.systemTemp.createTemp('chrome_bench_');
    }

    _process = await Process.start(
      chromePath,
      buildChromeArgs(
        isLinux: Platform.isLinux,
        headed: headed,
        debugPort: _port,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        userDataDir: _tempDir?.path,
        extraFlags: customFlags,
        initialUrl: initialUrl,
      ),
      mode: ProcessStartMode.normal,
    );

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

/// Base W3C WebDriver HTTP API driver shared by Safari and Firefox.
abstract class _W3cWebDriver() implements BrowserDriver {
  Process? _driverProcess;
  int? _port;
  String? _sessionId;
  final HttpClient _client = HttpClient();

  String get driverName;
  String get executablePath;
  Map<String, dynamic> buildCapabilities();

  @override
  Future<void> start({
    required int viewportWidth,
    required int viewportHeight,
    String initialUrl = 'http://localhost:8899/',
  }) async {
    _port = await _findAvailablePort();
    _driverProcess = await Process.start(executablePath, [
      '-p',
      '$_port',
    ], mode: ProcessStartMode.normal);

    await Future<void>.delayed(const Duration(milliseconds: 1000));

    final res = await _wdRequest('POST', '/session', buildCapabilities());
    final val = res['value'];
    if (val is Map<String, dynamic>) {
      _sessionId = val['sessionId'] as String?;
    }
    _sessionId ??= res['sessionId'] as String?;
    if (_sessionId == null) {
      throw StateError('Failed to create $driverName WebDriver session');
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
    _client.close(force: true);
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
    if (resp.statusCode >= 400) {
      throw StateError('WebDriver HTTP ${resp.statusCode}: $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json.containsKey('value') && json['value'] is Map) {
      final val = json['value'] as Map<String, dynamic>;
      if (val['error'] != null) {
        throw StateError(
          'WebDriver error: ${val['error']} - ${val['message']}',
        );
      }
    }
    return json;
  }
}

/// Drives Safari via `/usr/bin/safaridriver` (W3C WebDriver HTTP API).
class _SafariWebDriver() extends _W3cWebDriver {
  @override
  String get driverName => 'Safari';

  @override
  String get executablePath => '/usr/bin/safaridriver';

  @override
  Future<bool> isAvailable() async {
    return Platform.isMacOS && File('/usr/bin/safaridriver').existsSync();
  }

  @override
  Map<String, dynamic> buildCapabilities() => {
    'capabilities': {
      'alwaysMatch': {'browserName': 'safari'},
    },
  };
}

/// Drives Firefox via `geckodriver` (W3C WebDriver HTTP API) with
/// unthrottled prefs.
class _FirefoxWebDriver() extends _W3cWebDriver {
  @override
  String get driverName => 'Firefox';

  @override
  String get executablePath => 'geckodriver';

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
  Map<String, dynamic> buildCapabilities() {
    final binary = _resolveFirefoxBinary() ?? 'firefox';
    return {
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
  final bool headed = false,
  required final List<String> chromeFlags,
  required final String? chromeBinary,
}) {
  static const List<BenchmarkMode> _defaultModes = [
    BenchmarkMode.wasmMultithreaded,
    BenchmarkMode.wasmSingleThreaded,
    BenchmarkMode.jsCanvasKit,
  ];

  static ArgParser buildParser() => ArgParser()
    ..addOption(
      'browser',
      defaultsTo: 'all',
      valueHelp: 'name',
      help:
          'Browsers to test: chrome, safari, firefox, or all '
          '(comma-separated).',
    )
    ..addOption(
      'url',
      defaultsTo: 'https://flutter-wasm-compare.web.app/',
      valueHelp: 'url',
      help: 'Target app base URL.',
    )
    ..addOption(
      'workload',
      defaultsTo: 'bouncy',
      valueHelp: 'name',
      help: 'Workload type: bouncy (layout churn) or grid (card grid).',
    )
    ..addOption(
      'preset',
      valueHelp: 'name',
      help:
          'Convenience workload preset: light, medium, heavy, or all.\n'
          '(bouncy: 32, 64, 128; grid: 100, 1000, 5000)',
    )
    ..addOption(
      'nodes',
      valueHelp: 'counts',
      help:
          'Comma-separated list of stress node counts.\n'
          'Default: 32,64,128 (bouncy) or 100,1000,5000 (grid)',
    )
    ..addOption(
      'modes',
      valueHelp: 'modes',
      help:
          'Comma-separated list of engine modes: wasm_mt, wasm_st, wimp_mt,\n'
          'wimp_st, js, webparagraph (or all). Default: wasm_mt,wasm_st,js',
    )
    ..addOption(
      'viewport',
      defaultsTo: '1280x720',
      valueHelp: 'WxH',
      help: 'Enforced inner viewport size in pixels across all browsers.',
    )
    ..addOption(
      'settle-seconds',
      defaultsTo: '5',
      valueHelp: 'sec',
      help: 'Seconds to wait after navigation before sampling.',
    )
    ..addOption(
      'samples',
      defaultsTo: '5',
      valueHelp: 'count',
      help: 'Number of trial samples to record per workload.',
    )
    ..addOption(
      'sample-interval',
      defaultsTo: '1200',
      valueHelp: 'ms',
      help:
          'Milliseconds to wait between successive samples.\n'
          "(Exceeds app's 1000ms HUD throttle)",
    )
    ..addOption(
      'output',
      valueHelp: 'file',
      help: 'Optional file path to save the generated Markdown report.',
    )
    ..addFlag(
      'json',
      negatable: false,
      help: 'Print formatted JSON telemetry results to stdout.',
    )
    ..addOption(
      'json-output',
      valueHelp: 'file',
      help: 'Optional file path to save the JSON telemetry results.',
    )
    ..addFlag(
      'skip-capability-probe',
      negatable: false,
      help: 'Skip the initial Wasm JS-string capability probe.',
    )
    ..addFlag(
      'headed',
      negatable: false,
      help:
          'Launch Chrome in a visible window on Linux instead of '
          '--headless=new.',
    )
    ..addMultiOption(
      'chrome-flag',
      splitCommas: false,
      valueHelp: 'flag',
      help:
          'Extra Chrome flag, appended after the built-in defaults.\n'
          'Repeatable, e.g. --chrome-flag=--disable-gpu-vsync',
    )
    ..addOption(
      'chrome-binary',
      valueHelp: 'path',
      help:
          'Chrome executable to launch.\n'
          'Default: /usr/bin/google-chrome (Linux) or '
          'Google Chrome.app (macOS)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    );

  static List<int> _defaultNodesForWorkload(String workload, [String? preset]) {
    final isGrid = workload == 'grid';
    return switch (preset) {
      'light' => isGrid ? [100] : [32],
      'medium' => isGrid ? [1000] : [64],
      'heavy' => isGrid ? [5000] : [128],
      _ => isGrid ? [100, 1000, 5000] : [32, 64, 128],
    };
  }

  factory parse(List<String> args) {
    final ArgResults results;
    try {
      results = buildParser().parse(args);
    } on ArgParserException catch (e) {
      if (e.message.contains('"browsers"') ||
          e.message.contains('"--browsers"')) {
        throw const FormatException(
          'Flag "--browsers" was renamed; use "--browser" instead.',
        );
      }
      if (e.message.contains('"sample-interval-ms"') ||
          e.message.contains('"--sample-interval-ms"')) {
        throw const FormatException(
          'Flag "--sample-interval-ms" was renamed; '
          'use "--sample-interval" instead.',
        );
      }
      throw FormatException(e.message);
    }

    if (results.rest.isNotEmpty) {
      throw FormatException(
        'Unexpected positional arguments: ${results.rest.join(' ')}',
      );
    }

    if (results.flag('help')) {
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
        outputPath: null,
        jsonOutput: false,
        jsonOutputPath: null,
        skipCapabilityProbe: false,
        chromeFlags: const [],
        chromeBinary: null,
      );
    }

    final baseUrl = results.option('url')!.trim();
    if (baseUrl.isEmpty) {
      throw const FormatException('Invalid --url value: URL cannot be empty.');
    }
    final workload = _parseWorkload(results.option('workload')!);
    final preset = _parsePreset(results.option('preset'));
    final browsers = _parseBrowsers(results.option('browser')!);
    final modes = _parseModes(results.option('modes'));
    final rawNodes = results.option('nodes');
    final nodeCounts = rawNodes != null
        ? _parseNodes(rawNodes)
        : _defaultNodesForWorkload(workload, preset);
    final (viewportWidth, viewportHeight) = _parseViewport(
      results.option('viewport')!,
    );
    final settleSeconds = _parseNonNegativeInt(
      results.option('settle-seconds')!,
      'settle-seconds',
    );
    final samples = _parsePositiveInt(results.option('samples')!, 'samples');
    final sampleIntervalMs = _parsePositiveInt(
      results.option('sample-interval')!,
      'sample-interval',
    );
    final outputPath = _parseOptionalPath(results.option('output'), 'output');
    final jsonOutputPath = _parseOptionalPath(
      results.option('json-output'),
      'json-output',
    );
    final chromeFlags = <String>[];
    for (final rawFlag in results.multiOption('chrome-flag')) {
      final trimmed = rawFlag.trim();
      if (trimmed.isEmpty) {
        throw const FormatException(
          'Invalid --chrome-flag value: flag cannot be empty.',
        );
      }
      chromeFlags.add(trimmed);
    }
    final chromeBinary = _parseOptionalPath(
      results.option('chrome-binary'),
      'chrome-binary',
    );

    return BenchmarkArgs(
      showHelp: false,
      baseUrl: baseUrl,
      workload: workload,
      browsers: browsers,
      modes: modes,
      nodeCounts: nodeCounts,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      settleSeconds: settleSeconds,
      samples: samples,
      sampleIntervalMs: sampleIntervalMs,
      outputPath: outputPath,
      jsonOutput: results.flag('json'),
      jsonOutputPath: jsonOutputPath,
      skipCapabilityProbe: results.flag('skip-capability-probe'),
      headed: results.flag('headed'),
      chromeFlags: chromeFlags,
      chromeBinary: chromeBinary,
    );
  }

  static String _parseWorkload(String raw) {
    final normalized = raw.trim().toLowerCase();
    return switch (normalized) {
      'bouncy' || 'grid' => normalized,
      _ => throw FormatException(
        'Invalid --workload value "$raw" (allowed: bouncy, grid).',
      ),
    };
  }

  static String? _parsePreset(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    return switch (normalized) {
      'light' || 'medium' || 'heavy' || 'all' => normalized,
      'max' => throw const FormatException(
        'Preset "max" was removed; use "heavy" instead.',
      ),
      _ => throw FormatException(
        'Invalid --preset value "$raw" (allowed: light, medium, heavy, all).',
      ),
    };
  }

  static List<BrowserType> _parseBrowsers(String raw) {
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) {
      throw const FormatException(
        'Invalid --browser value "": expected chrome, safari, firefox, or all.',
      );
    }
    if (trimmed == 'all') return BrowserType.values.toList();
    final result = <BrowserType>[];
    for (final part in raw.split(',')) {
      final token = part.trim().toLowerCase();
      switch (token) {
        case 'chrome':
          result.add(BrowserType.chrome);
        case 'safari':
          result.add(BrowserType.safari);
        case 'firefox':
          result.add(BrowserType.firefox);
        default:
          throw FormatException(
            'Invalid --browser value "$part" '
            '(allowed: chrome, safari, firefox, all).',
          );
      }
    }
    return result;
  }

  static List<BenchmarkMode> _parseModes(String? raw) {
    if (raw == null) return _defaultModes.toList();
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) {
      throw const FormatException(
        'Invalid --modes value "": expected wasm_mt, wasm_st, wimp_mt, '
        'wimp_st, js, webparagraph, or all.',
      );
    }
    if (trimmed == 'all') return BenchmarkMode.values.toList();
    final result = <BenchmarkMode>[];
    for (final part in raw.split(',')) {
      final token = part.trim().toLowerCase();
      switch (token) {
        case 'wasm_mt':
          result.add(BenchmarkMode.wasmMultithreaded);
        case 'wasm_st':
          result.add(BenchmarkMode.wasmSingleThreaded);
        case 'wimp_mt':
          result.add(BenchmarkMode.wimpMultithreaded);
        case 'wimp_st':
          result.add(BenchmarkMode.wimpSingleThreaded);
        case 'js':
          result.add(BenchmarkMode.jsCanvasKit);
        case 'webparagraph':
          result.add(BenchmarkMode.jsWebParagraph);
        case 'mt':
          throw const FormatException(
            'Mode "mt" was renamed; use "wasm_mt" instead.',
          );
        case 'st':
          throw const FormatException(
            'Mode "st" was renamed; use "wasm_st" instead.',
          );
        case 'wp' || 'js_wp':
          throw FormatException(
            'Mode "$token" was renamed; use "webparagraph" instead.',
          );
        default:
          throw FormatException(
            'Invalid --modes value "$part" (allowed: wasm_mt, wasm_st, '
            'wimp_mt, wimp_st, js, webparagraph, all).',
          );
      }
    }
    return result;
  }

  static List<int> _parseNodes(String raw) {
    if (raw.trim().isEmpty) {
      throw const FormatException(
        'Invalid --nodes value "": expected comma-separated positive integers.',
      );
    }
    final result = <int>[];
    for (final part in raw.split(',')) {
      final parsed = int.tryParse(part.trim());
      if (parsed == null || parsed <= 0) {
        throw FormatException(
          'Invalid --nodes value "$part": expected a positive integer.',
        );
      }
      result.add(parsed);
    }
    return result;
  }

  static (int, int) _parseViewport(String raw) {
    final parts = raw.trim().toLowerCase().split('x');
    if (parts.length != 2) {
      throw FormatException(
        'Invalid --viewport value "$raw": '
        'expected <width>x<height> in positive pixels (e.g. 1280x720).',
      );
    }
    final w = int.tryParse(parts[0].trim());
    final h = int.tryParse(parts[1].trim());
    if (w == null || h == null || w <= 0 || h <= 0) {
      throw FormatException(
        'Invalid --viewport value "$raw": '
        'expected <width>x<height> in positive pixels (e.g. 1280x720).',
      );
    }
    return (w, h);
  }

  static int _parsePositiveInt(String raw, String flagName) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) {
      throw FormatException(
        'Invalid --$flagName value "$raw": expected a positive integer (> 0).',
      );
    }
    return parsed;
  }

  static int _parseNonNegativeInt(String raw, String flagName) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0) {
      throw FormatException(
        'Invalid --$flagName value "$raw": '
        'expected a non-negative integer (>= 0).',
      );
    }
    return parsed;
  }

  static String? _parseOptionalPath(String? raw, String flagName) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Invalid --$flagName value: path cannot be empty.');
    }
    return trimmed;
  }
}

void _printUsage([IOSink? out]) {
  final sink = out ?? stdout;
  sink.writeln(
    '''
Usage: dart tool/benchmark.dart [options]

Automated empirical browser benchmark runner for flutter-wasm-compare.

Options:
${BenchmarkArgs.buildParser().usage}

Examples:
  dart tool/benchmark.dart --browser=chrome --json
  dart tool/benchmark.dart --workload=grid --preset=heavy --browser=chrome
  dart tool/benchmark.dart --browser=safari,firefox --nodes=64 --json-output=results.json
  dart tool/benchmark.dart --url=http://localhost:8080 --output=doc/benchmarks.md''',
  );
}
