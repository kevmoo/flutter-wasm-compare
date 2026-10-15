import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

class FrameEntry(
  final double timestamp,
  final String filePath,
  final String phase,
);

class CaptureConfig({
  required final bool showHelp,
  required final bool dryRun,
  required final String baseUrl,
  required final String outDir,
  final String workload = 'bouncy',
  required final int nodes,
  required final int width,
  required final int height,
  required final int dpr,
  required final int screencastDpr,
  required final int fps,
  required final int hz,
  required final double phaseSeconds,
  required final double warmupSeconds,
  required final int quality,
  required final String chromeBinary,
  required final String ffmpegBinary,
}) {
  static ArgParser buildParser() => ArgParser()
    ..addOption(
      'base-url',
      defaultsTo: 'http://localhost:8088',
      valueHelp: 'url',
      help: 'Base URL of the running flutter-wasm-compare server.',
    )
    ..addOption(
      'out-dir',
      defaultsTo: '.',
      valueHelp: 'path',
      help: 'Output directory for MP4s, PNGs, and capture_metadata.json.',
    )
    ..addOption(
      'workload',
      defaultsTo: 'bouncy',
      allowed: const ['bouncy', 'grid'],
      valueHelp: 'id',
      help: 'Benchmark workload to record (bouncy or grid).',
    )
    ..addOption(
      'nodes',
      valueHelp: 'count',
      help:
          'Widget/card node count (default: 128 on macOS / 64 on Linux for '
          'bouncy, 1000 for grid).',
    )
    ..addOption(
      'width',
      defaultsTo: '1280',
      valueHelp: 'px',
      help: 'Logical viewport width in CSS pixels.',
    )
    ..addOption(
      'height',
      defaultsTo: '720',
      valueHelp: 'px',
      help: 'Logical viewport height in CSS pixels.',
    )
    ..addOption(
      'dpr',
      valueHelp: 'ratio',
      help:
          'Device pixel ratio for rendering (default: 2 on macOS, 1 on Linux).',
    )
    ..addOption(
      'screencast-dpr',
      valueHelp: 'ratio',
      help:
          'Scale factor for CDP screencast maxWidth/maxHeight '
          '(default: 2 on macOS, 1 on Linux).',
    )
    ..addOption(
      'fps',
      defaultsTo: '60',
      valueHelp: 'rate',
      help: 'Target output MP4 framerate.',
    )
    ..addOption(
      'hz',
      valueHelp: 'rate',
      help:
          'HUD target refresh rate query parameter ?hz= '
          '(default: 120 on macOS, 60 on Linux).',
    )
    ..addOption(
      'phase-seconds',
      defaultsTo: '8.0',
      valueHelp: 'sec',
      help: 'Recording duration per phase in seconds.',
    )
    ..addOption(
      'warmup-seconds',
      defaultsTo: '4.0',
      valueHelp: 'sec',
      help: 'Pre-screencast localStorage warmup duration per mode in seconds.',
    )
    ..addOption(
      'quality',
      defaultsTo: '88',
      valueHelp: '1-100',
      help: 'CDP screencast JPEG quality (1..100).',
    )
    ..addOption(
      'chrome-binary',
      valueHelp: 'path',
      help: 'Override Chrome executable path.',
    )
    ..addOption(
      'ffmpeg-binary',
      valueHelp: 'path',
      help: 'Override ffmpeg executable path.',
    )
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'Print resolved configuration and exit without launching Chrome.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this usage message and exit.',
    );

  static String get usage =>
      'Usage: dart run tool/record_video.dart [options]\n\n'
      'Records standalone 16:9 MP4 videos (JavaScript vs. WebAssembly) plus a\n'
      'combined MP4 and keyframe PNG screenshots of flutter-wasm-compare via\n'
      'Chrome DevTools Protocol (CDP) Page.startScreencast + ffmpeg. Pre-warms\n'
      'both modes in localStorage so both side-by-side HUD comparison cards\n'
      'are populated in each standalone video.\n\n'
      '${buildParser().usage}\n';

  factory parse(List<String> rawArgs, {bool? isMacOS}) {
    final mac = isMacOS ?? Platform.isMacOS;
    final results = buildParser().parse(rawArgs);
    if (results.rest.isNotEmpty) {
      throw FormatException(
        'Unexpected positional arguments: ${results.rest.join(' ')}',
      );
    }

    if (results.flag('help')) {
      return CaptureConfig(
        showHelp: true,
        dryRun: false,
        baseUrl: '',
        outDir: '.',
        nodes: 0,
        width: 0,
        height: 0,
        dpr: 1,
        screencastDpr: 1,
        fps: 60,
        hz: 60,
        phaseSeconds: 0,
        warmupSeconds: 0,
        quality: 88,
        chromeBinary: '',
        ffmpegBinary: '',
      );
    }

    final baseUrl = _requireNonEmpty(results.option('base-url')!, 'base-url');
    final outDir = _requireNonEmpty(results.option('out-dir')!, 'out-dir');
    final workload = results.option('workload')!;
    final defaultNodes = workload == 'grid' ? 1000 : (mac ? 128 : 64);
    final rawNodes = results.option('nodes');
    final nodes = rawNodes != null
        ? _parsePositiveInt(rawNodes, 'nodes')
        : defaultNodes;
    final width = _parsePositiveInt(results.option('width')!, 'width');
    final height = _parsePositiveInt(results.option('height')!, 'height');
    final dpr = _parseOptionalPositiveInt(
      results.option('dpr'),
      'dpr',
      mac ? 2 : 1,
    );
    final screencastDpr = _parseOptionalPositiveInt(
      results.option('screencast-dpr'),
      'screencast-dpr',
      mac ? 2 : 1,
    );
    final fps = _parsePositiveInt(results.option('fps')!, 'fps');
    final hz = _parseOptionalPositiveInt(
      results.option('hz'),
      'hz',
      mac ? 120 : 60,
    );
    final phaseSeconds = _parsePositiveDouble(
      results.option('phase-seconds')!,
      'phase-seconds',
    );
    final warmupSeconds = _parseNonNegativeDouble(
      results.option('warmup-seconds')!,
      'warmup-seconds',
    );
    final quality = _parseQuality(results.option('quality')!);
    final chromeBinary =
        _parseOptionalNonEmpty(
          results.option('chrome-binary'),
          'chrome-binary',
        ) ??
        _resolveChromeBinary(isMacOS: mac);
    final ffmpegBinary =
        _parseOptionalNonEmpty(
          results.option('ffmpeg-binary'),
          'ffmpeg-binary',
        ) ??
        _resolveFfmpegBinary();

    return CaptureConfig(
      showHelp: false,
      dryRun: results.flag('dry-run'),
      baseUrl: baseUrl,
      outDir: outDir,
      workload: workload,
      nodes: nodes,
      width: width,
      height: height,
      dpr: dpr,
      screencastDpr: screencastDpr,
      fps: fps,
      hz: hz,
      phaseSeconds: phaseSeconds,
      warmupSeconds: warmupSeconds,
      quality: quality,
      chromeBinary: chromeBinary,
      ffmpegBinary: ffmpegBinary,
    );
  }

  String get normalizedBaseUrl => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  String get jsUrl =>
      '$normalizedBaseUrl/?workload=$workload&stress=manual&nodes=$nodes&mode=js&hz=$hz';

  String get wasmUrl =>
      '$normalizedBaseUrl/?workload=$workload&stress=manual&nodes=$nodes&mode=wasm&optin=true&st=0&hz=$hz';

  String get jsMp4Path => '$outDir/flutter_wasm_compare_${workload}_js.mp4';

  String get wasmMp4Path => '$outDir/flutter_wasm_compare_${workload}_wasm.mp4';

  String get combinedMp4Path =>
      '$outDir/flutter_wasm_compare_${workload}_combined.mp4';

  String get jsPngPath => '$outDir/flutter_wasm_compare_${workload}_js.png';

  String get wasmPngPath => '$outDir/flutter_wasm_compare_${workload}_wasm.png';

  List<String> buildChromeArgs(int port, String userDataDir, {bool? isMacOS}) {
    final mac = isMacOS ?? Platform.isMacOS;
    final common = <String>[
      '--user-data-dir=$userDataDir',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding',
      '--disable-backgrounding-occluded-windows',
      '--remote-allow-origins=*',
      '--window-size=$width,${height + 88}',
      '--remote-debugging-port=$port',
    ];
    if (mac) {
      return <String>[...common, jsUrl];
    }
    return <String>[
      '--headless=new',
      '--no-sandbox',
      '--no-proxy-server',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
      '--disable-gpu-sandbox',
      ...common,
      jsUrl,
    ];
  }

  static String _requireNonEmpty(String raw, String flagName) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Invalid --$flagName value: cannot be empty.');
    }
    return trimmed;
  }

  static String? _parseOptionalNonEmpty(String? raw, String flagName) {
    if (raw == null) return null;
    return _requireNonEmpty(raw, flagName);
  }

  static int _parsePositiveInt(String raw, String flagName) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) {
      throw FormatException(
        'Invalid --$flagName value "$raw": expected a positive integer.',
      );
    }
    return parsed;
  }

  static int _parseOptionalPositiveInt(
    String? raw,
    String flagName,
    int fallback,
  ) {
    if (raw == null) return fallback;
    return _parsePositiveInt(raw, flagName);
  }

  static double _parsePositiveDouble(String raw, String flagName) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      throw FormatException(
        'Invalid --$flagName value "$raw": expected a positive number.',
      );
    }
    return parsed;
  }

  static double _parseNonNegativeDouble(String raw, String flagName) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      throw FormatException(
        'Invalid --$flagName value "$raw": expected a non-negative number.',
      );
    }
    return parsed;
  }

  static int _parseQuality(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 1 || parsed > 100) {
      throw FormatException(
        'Invalid --quality value "$raw": expected an integer between 1 and 100.',
      );
    }
    return parsed;
  }

  static String _resolveChromeBinary({required bool isMacOS}) {
    if (isMacOS) {
      const macPath =
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
      if (File(macPath).existsSync()) return macPath;
    }
    const cftPath =
        '/tmp/puppeteer_chrome/chrome/linux-154.0.8037.92/chrome-linux64/chrome';
    if (File(cftPath).existsSync()) return cftPath;
    final home = Platform.environment['HOME'] ?? '';
    final pwPath =
        '$home/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome';
    if (File(pwPath).existsSync()) return pwPath;
    return '/usr/bin/google-chrome';
  }

  static String _resolveFfmpegBinary() {
    for (final candidate in [
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
      '/usr/bin/ffmpeg',
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return 'ffmpeg';
  }
}

String formatFfconcatManifest(List<FrameEntry> entries) {
  if (entries.length < 2) {
    throw StateError('Too few screencast frames (${entries.length})');
  }
  final buf = StringBuffer('ffconcat version 1.0\n');
  for (var i = 0; i < entries.length; i++) {
    buf.writeln("file '${entries[i].filePath}'");
    if (i + 1 < entries.length) {
      final rawDur = entries[i + 1].timestamp - entries[i].timestamp;
      final dur = rawDur.clamp(0.008, 0.500);
      buf.writeln('duration ${dur.toStringAsFixed(4)}');
    } else {
      buf.writeln('duration 0.0333');
    }
  }
  buf.writeln("file '${entries.last.filePath}'");
  return buf.toString();
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  try {
    return socket.port;
  } finally {
    await socket.close();
  }
}

Future<String?> _probeCdpTargets(HttpClient client, int port) async {
  try {
    final req = await client
        .getUrl(Uri.parse('http://127.0.0.1:$port/json/list'))
        .timeout(const Duration(seconds: 1));
    final resp = await req.close().timeout(const Duration(seconds: 1));
    final body = await resp.transform(utf8.decoder).join();
    final targets = jsonDecode(body) as List<dynamic>;
    for (final target in targets) {
      if (target is Map<String, dynamic> &&
          target['type'] == 'page' &&
          target['webSocketDebuggerUrl'] is String) {
        return target['webSocketDebuggerUrl'] as String;
      }
    }
  } on Object {
    // Retry while Chrome starts up.
  }
  return null;
}

Future<String> _waitForCdpWebSocketUrl(int port) async {
  final client = HttpClient();
  try {
    for (var i = 0; i < 60; i++) {
      final wsUrl = await _probeCdpTargets(client, port);
      if (wsUrl != null) return wsUrl;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } finally {
    client.close(force: true);
  }
  throw StateError('Timed out waiting for Chrome CDP on port $port');
}

class _CdpSession {
  _CdpSession(this._ws, this._framesDir) {
    _sub = _ws.listen(_onMessage);
  }

  final WebSocket _ws;
  final Directory _framesDir;
  late final StreamSubscription<dynamic> _sub;
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final List<FrameEntry> frames = [];
  String currentPhase = 'warmup';
  bool recordFrames = false;

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    final method = msg['method'] as String?;
    if (method == 'Page.screencastFrame') {
      _handleScreencastFrame(msg['params'] as Map<String, dynamic>);
      return;
    }
    final id = msg['id'] as int?;
    if (id != null && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(msg);
    }
  }

  void _handleScreencastFrame(Map<String, dynamic> params) {
    final sessionId = params['sessionId'] as int;
    if (recordFrames) {
      final dataB64 = params['data'] as String;
      final metadata = params['metadata'] as Map<String, dynamic>?;
      final ts =
          (metadata?['timestamp'] as num?)?.toDouble() ??
          DateTime.now().millisecondsSinceEpoch / 1000.0;
      final idx = frames.length;
      final framePath =
          '${_framesDir.path}/frame_${idx.toString().padLeft(5, '0')}.jpg';
      File(framePath).writeAsBytesSync(base64Decode(dataB64));
      frames.add(FrameEntry(ts, framePath, currentPhase));
    }
    unawaited(send('Page.screencastFrameAck', {'sessionId': sessionId}));
  }

  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _ws.add(
      jsonEncode({
        'id': id,
        'method': method,
        'params': params ?? <String, dynamic>{},
      }),
    );
    return completer.future.timeout(const Duration(seconds: 15));
  }

  Future<void> saveScreenshot(String path) async {
    final res = await send('Page.captureScreenshot', {'format': 'png'});
    final result = res['result'] as Map<String, dynamic>?;
    final data = result?['data'] as String?;
    if (data != null) {
      File(path).writeAsBytesSync(base64Decode(data));
      stdout.writeln('Saved screenshot: $path');
    }
  }

  Future<dynamic> evalJs(String expression) async {
    final res = await send('Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
    });
    final result = res['result'] as Map<String, dynamic>?;
    final inner = result?['result'] as Map<String, dynamic>?;
    return inner?['value'];
  }

  Future<void> close() async {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(<String, dynamic>{});
    }
    _pending.clear();
    await _sub.cancel();
    await _ws.close();
  }
}

Future<void> _encodeMp4({
  required String ffmpegBinary,
  required List<FrameEntry> entries,
  required String concatPath,
  required String outputMp4Path,
  required int targetFps,
}) async {
  File(concatPath).writeAsStringSync(formatFfconcatManifest(entries));

  final res = await Process.run(ffmpegBinary, [
    '-y',
    '-f',
    'concat',
    '-safe',
    '0',
    '-i',
    concatPath,
    '-vf',
    'fps=$targetFps,scale=trunc(iw/2)*2:trunc(ih/2)*2',
    '-c:v',
    'libx264',
    '-preset',
    'medium',
    '-crf',
    '22',
    '-pix_fmt',
    'yuv420p',
    '-movflags',
    '+faststart',
    outputMp4Path,
  ]);
  if (res.exitCode != 0) {
    throw StateError('ffmpeg failed on $outputMp4Path:\n${res.stderr}');
  }
  final sizeKb = File(outputMp4Path).lengthSync() / 1024.0;
  final totalDur = entries.last.timestamp - entries.first.timestamp;
  final effFps = entries.length / (totalDur > 0.1 ? totalDur : 0.1);
  stdout.writeln(
    'Encoded $outputMp4Path: ${sizeKb.toStringAsFixed(1)} KB '
    '(${entries.length} frames over ${totalDur.toStringAsFixed(2)}s = '
    '${effFps.toStringAsFixed(1)} effective screencast FPS)',
  );
}

void _printDryRun(CaptureConfig cfg) {
  stdout.writeln('Dry-run configuration:');
  stdout.writeln('  Platform:       ${Platform.operatingSystem}');
  stdout.writeln('  Chrome binary:  ${cfg.chromeBinary}');
  stdout.writeln('  ffmpeg binary:  ${cfg.ffmpegBinary}');
  stdout.writeln(
    '  Viewport:       ${cfg.width}x${cfg.height} @ ${cfg.dpr}x DPR '
    '(${cfg.width * cfg.dpr}x${cfg.height * cfg.dpr} physical px, 16:9)',
  );
  stdout.writeln(
    '  Screencast max: ${cfg.width * cfg.screencastDpr}x'
    '${cfg.height * cfg.screencastDpr} (quality ${cfg.quality})',
  );
  stdout.writeln('  HUD Target Hz:  ${cfg.hz} Hz (?hz=${cfg.hz})');
  stdout.writeln('  Target MP4 FPS: ${cfg.fps}');
  stdout.writeln('  Workload:       ${cfg.workload} (${cfg.nodes} nodes)');
  stdout.writeln('  JS URL:         ${cfg.jsUrl}');
  stdout.writeln('  Wasm MT URL:    ${cfg.wasmUrl}');
  stdout.writeln('  JS MP4:         ${cfg.jsMp4Path}');
  stdout.writeln('  Wasm MP4:       ${cfg.wasmMp4Path}');
  stdout.writeln('  Combined MP4:   ${cfg.combinedMp4Path}');
}

Future<void> _runCaptureSession(
  CaptureConfig cfg,
  _CdpSession cdp,
  Directory framesDir,
) async {
  await cdp.send('Page.enable');
  await cdp.send('Runtime.enable');
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    'width': cfg.width,
    'height': cfg.height,
    'deviceScaleFactor': cfg.dpr,
    'mobile': false,
  });

  final warmupDuration = Duration(
    milliseconds: (cfg.warmupSeconds * 1000).round(),
  );
  final phaseDuration = Duration(
    milliseconds: (cfg.phaseSeconds * 1000).round(),
  );

  stdout.writeln(
    'Warmup 1/2: Pre-populating localStorage for JS @ ${cfg.nodes} nodes '
    '(${cfg.warmupSeconds}s)...',
  );
  await Future<void>.delayed(warmupDuration);

  final renderer = await cdp.evalJs('''
(() => {
  try {
    const c = document.createElement('canvas');
    const gl = c.getContext('webgl2') || c.getContext('webgl');
    if (!gl) return 'no-webgl';
    const ext = gl.getExtension('WEBGL_debug_renderer_info');
    return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
  } catch (e) {
    return 'error: ' + e;
  }
})()
''');
  stdout.writeln('WebGL Renderer: $renderer');

  stdout.writeln(
    'Warmup 2/2: Pre-populating localStorage for Wasm MT @ ${cfg.nodes} nodes '
    '(${cfg.warmupSeconds}s)...',
  );
  await cdp.send('Page.navigate', {'url': cfg.wasmUrl});
  await Future<void>.delayed(warmupDuration);

  await cdp.send('Page.navigate', {'url': cfg.jsUrl});
  await Future<void>.delayed(const Duration(milliseconds: 2500));

  cdp.currentPhase = 'js';
  cdp.recordFrames = true;
  await cdp.send('Page.startScreencast', {
    'format': 'jpeg',
    'quality': cfg.quality,
    'maxWidth': cfg.width * cfg.screencastDpr,
    'maxHeight': cfg.height * cfg.screencastDpr,
    'everyNthFrame': 1,
  });

  stdout.writeln(
    'Recording Phase 1 (JS @ ${cfg.nodes} nodes, ?hz=${cfg.hz}) '
    'for ${cfg.phaseSeconds}s...',
  );
  await Future<void>.delayed(phaseDuration);
  await cdp.saveScreenshot(cfg.jsPngPath);

  cdp.recordFrames = false;
  await cdp.send('Page.navigate', {'url': cfg.wasmUrl});
  await Future<void>.delayed(const Duration(milliseconds: 2000));

  cdp.currentPhase = 'wasm';
  cdp.recordFrames = true;
  stdout.writeln(
    'Recording Phase 2 (Wasm MT @ ${cfg.nodes} nodes, ?hz=${cfg.hz}) '
    'for ${cfg.phaseSeconds}s...',
  );
  await Future<void>.delayed(phaseDuration);
  await cdp.saveScreenshot(cfg.wasmPngPath);

  cdp.recordFrames = false;
  await cdp.send('Page.stopScreencast');

  final runsJson = await cdp.evalJs('''
(() => {
  const wasm = window.localStorage.getItem('wasm_compare_last_wasm_run_${cfg.workload}') ||
               window.localStorage.getItem('wasm_compare_last_wasm_run');
  const js = window.localStorage.getItem('wasm_compare_last_js_run_${cfg.workload}') ||
             window.localStorage.getItem('wasm_compare_last_js_run');
  return JSON.stringify({
    wasm: wasm ? JSON.parse(wasm) : null,
    js: js ? JSON.parse(js) : null,
  });
})()
''');
  stdout.writeln('HUD localStorage (${cfg.workload}): $runsJson');
  await cdp.close();

  final jsFrames = cdp.frames.where((f) => f.phase == 'js').toList();
  final wasmFrames = cdp.frames.where((f) => f.phase == 'wasm').toList();

  await _encodeMp4(
    ffmpegBinary: cfg.ffmpegBinary,
    entries: jsFrames,
    concatPath: '${framesDir.path}/js_frames.ffconcat',
    outputMp4Path: cfg.jsMp4Path,
    targetFps: cfg.fps,
  );
  await _encodeMp4(
    ffmpegBinary: cfg.ffmpegBinary,
    entries: wasmFrames,
    concatPath: '${framesDir.path}/wasm_frames.ffconcat',
    outputMp4Path: cfg.wasmMp4Path,
    targetFps: cfg.fps,
  );
  await _encodeMp4(
    ffmpegBinary: cfg.ffmpegBinary,
    entries: cdp.frames,
    concatPath: '${framesDir.path}/combined_frames.ffconcat',
    outputMp4Path: cfg.combinedMp4Path,
    targetFps: cfg.fps,
  );

  final metaFile = File('${cfg.outDir}/capture_metadata.json');
  metaFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'platform': Platform.operatingSystem,
      'webgl_renderer': renderer,
      'viewport_logical': '${cfg.width}x${cfg.height}',
      'dpr': cfg.dpr,
      'screencast_dpr': cfg.screencastDpr,
      'hud_target_hz': cfg.hz,
      'target_mp4_fps': cfg.fps,
      'workload': cfg.workload,
      'nodes': cfg.nodes,
      'js_frames': jsFrames.length,
      'wasm_frames': wasmFrames.length,
      'total_frames': cdp.frames.length,
      'runs': runsJson != null ? jsonDecode(runsJson.toString()) : null,
    }),
  );
  stdout.writeln('Saved metadata: ${metaFile.path}');
}

Future<void> main(List<String> rawArgs) async {
  late final CaptureConfig cfg;
  try {
    cfg = CaptureConfig.parse(rawArgs);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    stderr.write(CaptureConfig.usage);
    exit(2);
  }

  if (cfg.showHelp) {
    stdout.write(CaptureConfig.usage);
    return;
  }

  if (cfg.dryRun) {
    _printDryRun(cfg);
    return;
  }

  Directory(cfg.outDir).createSync(recursive: true);
  final framesDir = Directory.systemTemp.createTempSync('wasm_compare_frames_');
  final userDataDir = Directory.systemTemp.createTempSync(
    'wasm_compare_chrome_',
  );
  final port = await _findFreePort();
  final chromeArgs = cfg.buildChromeArgs(port, userDataDir.path);

  stdout.writeln('Launching ${cfg.chromeBinary} on CDP port $port...');
  final proc = await Process.start(
    cfg.chromeBinary,
    chromeArgs,
    environment: {...Platform.environment, 'GSETTINGS_BACKEND': 'memory'},
  );

  try {
    final wsUrl = await _waitForCdpWebSocketUrl(port);
    stdout.writeln('Connected to CDP: $wsUrl');
    final ws = await WebSocket.connect(wsUrl);
    final cdp = _CdpSession(ws, framesDir);
    await _runCaptureSession(cfg, cdp, framesDir);
  } finally {
    proc.kill();
    try {
      framesDir.deleteSync(recursive: true);
    } on Object {
      // Ignore cleanup errors.
    }
    try {
      userDataDir.deleteSync(recursive: true);
    } on Object {
      // Ignore cleanup errors.
    }
  }
}
