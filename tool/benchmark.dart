import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Automated browser benchmark driver for `flutter-wasm-compare`.
///
/// Supports Chrome, Safari, and Firefox on macOS/Linux with zero external
/// dependencies, using standard W3C WebDriver (Safari/Firefox) and Chrome
/// DevTools Protocol (CDP over WebSocket).
Future<void> main(List<String> rawArgs) async {
  final args = _BenchmarkArgs.parse(rawArgs);
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
  print('Settle Duration: ${args.settleSeconds}s per run');
  print('=' * 63);
  print('');

  final benchmarkResults = <BrowserType, Map<BenchmarkKey, BenchmarkRecord>>{};
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

      final browserMap = <BenchmarkKey, BenchmarkRecord>{};
      for (final mode in args.modes) {
        for (final nodes in args.nodeCounts) {
          final url = _buildUrl(args.baseUrl, mode, nodes);
          stdout.write('  • [${mode.label}] @ $nodes nodes: navigating...');
          await driver.navigate(url);

          for (var s = args.settleSeconds; s > 0; s--) {
            stdout.write(' ${s}s');
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          stdout.write(' evaluating...\r');

          final readExpr = "localStorage.getItem('${mode.storageKey}')";
          final rawJson = await driver.evaluate(readExpr);

          if (rawJson is String && rawJson.isNotEmpty) {
            final data = jsonDecode(rawJson) as Map<String, dynamic>;
            final record = BenchmarkRecord.fromJson(data);
            final key = BenchmarkKey(mode, nodes);
            browserMap[key] = record;
            final label = mode.label.padRight(15);
            final nodeStr = nodes.toString().padLeft(4);
            final fpsStr = record.effectiveFps.toStringAsFixed(1);
            final buildStr = record.buildTimeMs.toStringAsFixed(2);
            final rasterStr = record.rasterTimeMs.toStringAsFixed(2);
            print(
              '  ✓ [$label] @ $nodeStr nodes -> '
              '$fpsStr FPS | Build: ${buildStr}ms | Raster: ${rasterStr}ms',
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
    print('\nReport saved to ${file.path}');
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
  required _BenchmarkArgs args,
  required Map<BrowserType, CapabilityRecord> capabilities,
  required Map<BrowserType, Map<BenchmarkKey, BenchmarkRecord>> results,
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
  buffer.writeln('- **Settle Duration**: ${args.settleSeconds} seconds');
  buffer.writeln();

  if (capabilities.isNotEmpty) {
    buffer.writeln('## 🧪 Capability & Streaming Probes');
    buffer.writeln();
    buffer.writeln('<!-- mdformat off -->');
    buffer.writeln(
      '| Browser | Cross-Origin Isolated | Wasm JS-String Supported | User Agent |',
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

  buffer.writeln('## 📊 Performance Comparison Matrix');
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
        final fpsStr = rec.effectiveFps.toStringAsFixed(1);
        final buildStr = rec.buildTimeMs.toStringAsFixed(2);
        final rasterStr = rec.rasterTimeMs.toStringAsFixed(2);
        buffer.write(' **$fpsStr FPS** / ${buildStr}ms / ${rasterStr}ms |');
      } else {
        buffer.write(' N/A |');
      }
    }
    buffer.writeln();
  }
  buffer.writeln('<!-- mdformat on -->');
  buffer.writeln();

  buffer.writeln('### Key Takeaways');
  for (final browser in results.keys) {
    final browserResults = results[browser]!;
    final mt1000 =
        browserResults[const BenchmarkKey(
          BenchmarkMode.wasmMultithreaded,
          1000,
        )];
    final st1000 =
        browserResults[const BenchmarkKey(
          BenchmarkMode.wasmSingleThreaded,
          1000,
        )];
    final js1000 =
        browserResults[const BenchmarkKey(BenchmarkMode.jsCanvasKit, 1000)];

    if (mt1000 != null && st1000 != null && js1000 != null) {
      final rasterOverhead = mt1000.rasterTimeMs / st1000.rasterTimeMs;
      final fpsWin = mt1000.effectiveFps / st1000.effectiveFps;
      final vsJsWin = mt1000.effectiveFps / js1000.effectiveFps;
      final buildSpeedup = js1000.buildTimeMs / mt1000.buildTimeMs;

      buffer.writeln('* **${browser.label} (at 1,000 nodes)**:');
      buffer.writeln(
        '  * Worker Raster Overhead: `st=0` is '
        '**${rasterOverhead.toStringAsFixed(2)}x** that of `st=1` '
        '(${mt1000.rasterTimeMs.toStringAsFixed(2)}ms vs '
        '${st1000.rasterTimeMs.toStringAsFixed(2)}ms).',
      );
      buffer.writeln(
        '  * Pipelining Throughput Win: `st=0` delivers '
        '**${fpsWin.toStringAsFixed(2)}x higher FPS** than `st=1` '
        '(${mt1000.effectiveFps.toStringAsFixed(1)} vs '
        '${st1000.effectiveFps.toStringAsFixed(1)} FPS).',
      );
      buffer.writeln(
        '  * Dart2Wasm vs Dart2JS: Wasm delivers '
        '**${vsJsWin.toStringAsFixed(2)}x higher FPS** and '
        '**${buildSpeedup.toStringAsFixed(2)}x faster UI build** '
        '(${mt1000.buildTimeMs.toStringAsFixed(2)}ms vs '
        '${js1000.buildTimeMs.toStringAsFixed(2)}ms).',
      );
    }
  }

  return buffer.toString();
}

class _ReportColumn {
  final BrowserType browser;
  final BenchmarkMode mode;
  _ReportColumn(this.browser, this.mode);

  String get header => '${browser.label} ${mode.shortLabel}';
}

const _capabilityProbeScript = """(() => {
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
})()""";

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
  final bool isPipelined;

  BenchmarkRecord({
    required this.fps,
    required this.buildTimeMs,
    required this.rasterTimeMs,
    required this.totalFrameTimeMs,
    required this.isPipelined,
  });

  factory BenchmarkRecord.fromJson(Map<String, dynamic> json) {
    return BenchmarkRecord(
      fps: (json['fps'] as num?)?.toDouble() ?? 0.0,
      buildTimeMs: (json['buildTimeMs'] as num?)?.toDouble() ?? 0.0,
      rasterTimeMs: (json['rasterTimeMs'] as num?)?.toDouble() ?? 0.0,
      totalFrameTimeMs: (json['totalFrameTimeMs'] as num?)?.toDouble() ?? 0.0,
      isPipelined: json['isPipelined'] as bool? ?? false,
    );
  }

  /// Calculates true throughput if the HUD's tab-pause filter fallback occurred.
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

/// Drives Firefox via `geckodriver` (W3C WebDriver HTTP API) with unthrottled prefs.
class _FirefoxWebDriver implements BrowserDriver {
  Process? _driverProcess;
  int? _port;
  String? _sessionId;
  final HttpClient _client = HttpClient();

  @override
  Future<bool> isAvailable() async {
    if (!File('/Applications/Firefox.app/Contents/MacOS/firefox')
        .existsSync()) {
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

    final caps = {
      'capabilities': {
        'alwaysMatch': {
          'browserName': 'firefox',
          'moz:firefoxOptions': {
            'binary': '/Applications/Firefox.app/Contents/MacOS/firefox',
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

class _BenchmarkArgs {
  final bool showHelp;
  final String baseUrl;
  final List<BrowserType> browsers;
  final List<BenchmarkMode> modes;
  final List<int> nodeCounts;
  final int viewportWidth;
  final int viewportHeight;
  final int settleSeconds;
  final String? outputPath;
  final bool skipCapabilityProbe;

  _BenchmarkArgs({
    required this.showHelp,
    required this.baseUrl,
    required this.browsers,
    required this.modes,
    required this.nodeCounts,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.settleSeconds,
    required this.outputPath,
    required this.skipCapabilityProbe,
  });

  factory _BenchmarkArgs.parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      return _BenchmarkArgs(
        showHelp: true,
        baseUrl: '',
        browsers: const [],
        modes: const [],
        nodeCounts: const [],
        viewportWidth: 0,
        viewportHeight: 0,
        settleSeconds: 0,
        outputPath: null,
        skipCapabilityProbe: false,
      );
    }

    var baseUrl = 'https://flutter-wasm-compare.web.app/';
    var browsers = BrowserType.values.toList();
    var modes = BenchmarkMode.values.toList();
    var nodeCounts = [100, 1000, 8000];
    var viewportWidth = 1280;
    var viewportHeight = 720;
    var settleSeconds = 7;
    String? outputPath;
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
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg == '--skip-capability-probe') {
        skipCapabilityProbe = true;
      }
    }

    return _BenchmarkArgs(
      showHelp: false,
      baseUrl: baseUrl,
      browsers: browsers.isEmpty ? BrowserType.values.toList() : browsers,
      modes: modes.isEmpty ? BenchmarkMode.values.toList() : modes,
      nodeCounts: nodeCounts.isEmpty ? [100, 1000, 8000] : nodeCounts,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      settleSeconds: settleSeconds,
      outputPath: outputPath,
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
  --nodes=<counts>         Comma-separated list of stress node counts.
                           Default: 100,1000,8000
  --modes=<modes>          Comma-separated list of engine modes: wasm_mt, wasm_st, js.
                           Default: wasm_mt,wasm_st,js
  --viewport=<WxH>         Enforced inner viewport size in pixels across all browsers.
                           Default: 1280x720
  --settle-seconds=<sec>   Seconds to wait after navigation before reading metrics.
                           Default: 7
  --output=<file>          Optional file path to save the generated Markdown report.
  --skip-capability-probe  Skip the initial Wasm JS-string capability probe.
  --help, -h               Show this help message.

Examples:
  dart tool/benchmark.dart --browser=chrome
  dart tool/benchmark.dart --browser=safari,firefox --nodes=1000 --viewport=1280x720
  dart tool/benchmark.dart --url=http://localhost:8080 --output=doc/benchmarks.md
''');
}
