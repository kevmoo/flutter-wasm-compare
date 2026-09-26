import 'dart:convert';

import 'package:bench_press/bench_press.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/benchmark.dart';

void main() {
  group('BenchmarkArgs.parse', () {
    test('parses defaults correctly (bouncy workload)', () {
      final args = BenchmarkArgs.parse([]);
      expect(args.showHelp, isFalse);
      expect(args.baseUrl, equals('https://flutter-wasm-compare.web.app/'));
      expect(args.workload, equals('bouncy'));
      expect(args.browsers, equals(BrowserType.values));
      expect(
        args.modes,
        equals([
          BenchmarkMode.wasmMultithreaded,
          BenchmarkMode.wasmSingleThreaded,
          BenchmarkMode.jsCanvasKit,
        ]),
      );
      expect(args.nodeCounts, equals([32, 64, 128]));
      expect(args.viewportWidth, equals(1280));
      expect(args.viewportHeight, equals(720));
      expect(args.settleSeconds, equals(5));
      expect(args.samples, equals(5));
      expect(args.sampleIntervalMs, equals(1200));
      expect(args.jsonOutput, isFalse);
      expect(args.outputPath, isNull);
    });

    test('parses preset arguments for bouncy and grid workloads', () {
      final light = BenchmarkArgs.parse(['--preset=light']);
      expect(light.workload, equals('bouncy'));
      expect(light.nodeCounts, equals([32]));

      final medium = BenchmarkArgs.parse(['--preset=medium']);
      expect(medium.nodeCounts, equals([64]));

      final heavy = BenchmarkArgs.parse(['--preset=heavy']);
      expect(heavy.nodeCounts, equals([128]));

      final all = BenchmarkArgs.parse(['--preset=all']);
      expect(all.nodeCounts, equals([32, 64, 128]));

      final gridHeavy = BenchmarkArgs.parse([
        '--workload=grid',
        '--preset=heavy',
      ]);
      expect(gridHeavy.workload, equals('grid'));
      expect(gridHeavy.nodeCounts, equals([5000]));

      final gridDefault = BenchmarkArgs.parse(['--workload=grid']);
      expect(gridDefault.nodeCounts, equals([100, 1000, 5000]));
    });

    test('parses custom sample interval and nodes', () {
      final args = BenchmarkArgs.parse([
        '--sample-interval=1500',
        '--nodes=500,2000',
        '--samples=8',
        '--json',
      ]);
      expect(args.sampleIntervalMs, equals(1500));
      expect(args.nodeCounts, equals([500, 2000]));
      expect(args.samples, equals(8));
      expect(args.jsonOutput, isTrue);
    });

    test('parses all remaining CLI flags and help options', () {
      final helpArgs = BenchmarkArgs.parse(['--help']);
      expect(helpArgs.showHelp, isTrue);

      final shortHelp = BenchmarkArgs.parse(['-h']);
      expect(shortHelp.showHelp, isTrue);

      final full = BenchmarkArgs.parse([
        '--url=http://localhost:8080/',
        '--browser=chrome,firefox',
        '--modes=wasm_mt,js,webparagraph',
        '--viewport=1920x1080',
        '--settle-seconds=2',
        '--output=doc/bench.md',
        '--json-output=doc/bench.json',
        '--skip-capability-probe',
        '--headed',
      ]);
      expect(full.showHelp, isFalse);
      expect(full.baseUrl, equals('http://localhost:8080/'));
      expect(full.browsers, equals([BrowserType.chrome, BrowserType.firefox]));
      expect(
        full.modes,
        equals([
          BenchmarkMode.wasmMultithreaded,
          BenchmarkMode.jsCanvasKit,
          BenchmarkMode.jsWebParagraph,
        ]),
      );
      expect(full.viewportWidth, equals(1920));
      expect(full.viewportHeight, equals(1080));
      expect(full.settleSeconds, equals(2));
      expect(full.outputPath, equals('doc/bench.md'));
      expect(full.jsonOutputPath, equals('doc/bench.json'));
      expect(full.skipCapabilityProbe, isTrue);
      expect(full.headed, isTrue);
    });

    test('parses WIMP mode tokens', () {
      final args = BenchmarkArgs.parse(['--modes=wimp_mt,wimp_st,wasm_mt']);
      expect(
        args.modes,
        equals([
          BenchmarkMode.wimpMultithreaded,
          BenchmarkMode.wimpSingleThreaded,
          BenchmarkMode.wasmMultithreaded,
        ]),
      );
    });

    test('parses repeated --chrome-flag and --chrome-binary', () {
      final defaults = BenchmarkArgs.parse([]);
      expect(defaults.chromeFlags, isEmpty);
      expect(defaults.chromeBinary, isNull);
      expect(defaults.headed, isFalse);

      final args = BenchmarkArgs.parse([
        '--chrome-flag=--disable-gpu-vsync',
        '--chrome-flag=--disable-frame-rate-limit',
        '--chrome-flag=--enable-features=Foo,Bar',
        '--chrome-binary=/opt/chrome/chrome',
      ]);
      expect(
        args.chromeFlags,
        equals([
          '--disable-gpu-vsync',
          '--disable-frame-rate-limit',
          '--enable-features=Foo,Bar',
        ]),
      );
      expect(args.chromeBinary, equals('/opt/chrome/chrome'));
    });

    test('buildParser.usage documents --headed and canonical flags', () {
      final usage = BenchmarkArgs.buildParser().usage;
      expect(usage, contains('--headed'));
      expect(usage, contains('--browser'));
      expect(usage, contains('--sample-interval'));
      expect(usage, isNot(contains('--browsers')));
      expect(usage, isNot(contains('--sample-interval-ms')));
    });

    test('throws FormatException on unknown flags or positional args', () {
      for (final badArgs in [
        ['--unknown'],
        ['--browsers=chrome'],
        ['--sample-interval-ms=1000'],
        ['--mode=wasm_mt'],
        ['--node=64'],
        ['-x'],
        ['bouncy'],
        ['--browser=chrome', 'extra'],
      ]) {
        expect(
          () => BenchmarkArgs.parse(badArgs),
          throwsFormatException,
          reason: 'Expected FormatException for $badArgs',
        );
      }
    });

    test('throws FormatException on invalid option values', () {
      for (final badArgs in [
        ['--workload=foo'],
        ['--workload='],
        ['--preset=ultra'],
        ['--preset=max'],
        ['--preset='],
        ['--browser=ie'],
        ['--browser=chrome,'],
        ['--browser='],
        ['--modes=foo'],
        ['--modes=mt'],
        ['--modes=st'],
        ['--modes=wp'],
        ['--modes=js_wp'],
        ['--modes=wasm_mt,foo'],
        ['--modes='],
        ['--viewport=100'],
        ['--viewport=0x720'],
        ['--viewport=1280x-10'],
        ['--viewport=axb'],
        ['--nodes=abc'],
        ['--nodes=0'],
        ['--nodes=64,-1'],
        ['--nodes='],
        ['--samples=0'],
        ['--samples=-1'],
        ['--samples=abc'],
        ['--sample-interval=0'],
        ['--sample-interval=-100'],
        ['--settle-seconds=-1'],
        ['--settle-seconds=abc'],
        ['--url='],
        ['--output='],
        ['--json-output='],
        ['--chrome-binary='],
        ['--chrome-flag='],
      ]) {
        expect(
          () => BenchmarkArgs.parse(badArgs),
          throwsFormatException,
          reason: 'Expected FormatException for $badArgs',
        );
      }

      // --settle-seconds=0 is valid (non-negative).
      expect(
        BenchmarkArgs.parse(['--settle-seconds=0']).settleSeconds,
        equals(0),
      );
    });
  });

  group('buildBenchmarkUrl & selectCdpPageTargetWsUrl', () {
    test('buildBenchmarkUrl constructs query params per mode and workload', () {
      final mtUrl = buildBenchmarkUrl(
        'https://example.com/',
        BenchmarkMode.wasmMultithreaded,
        64,
        workload: 'bouncy',
      );
      expect(
        mtUrl,
        equals(
          'https://example.com/?workload=bouncy&stress=manual&nodes=64&mode=wasm&optin=true&st=0',
        ),
      );

      final stUrl = buildBenchmarkUrl(
        'https://example.com/',
        BenchmarkMode.wasmSingleThreaded,
        128,
        workload: 'bouncy',
      );
      expect(
        stUrl,
        equals(
          'https://example.com/?workload=bouncy&stress=manual&nodes=128&mode=wasm&optin=true&st=1',
        ),
      );

      final jsUrl = buildBenchmarkUrl(
        'https://example.com/?optin=true&st=1',
        BenchmarkMode.jsCanvasKit,
        500,
        workload: 'grid',
      );
      expect(
        jsUrl,
        equals(
          'https://example.com/?workload=grid&stress=manual&nodes=500&mode=js',
        ),
      );

      final wpUrl = buildBenchmarkUrl(
        'https://example.com/?optin=true&st=1',
        BenchmarkMode.jsWebParagraph,
        500,
        workload: 'bouncy',
      );
      expect(
        wpUrl,
        equals(
          'https://example.com/?workload=bouncy&stress=manual&nodes=500&mode=webparagraph',
        ),
      );
    });

    test('buildBenchmarkUrl selects the WIMP renderer for WIMP modes', () {
      expect(
        buildBenchmarkUrl(
          'https://example.com/',
          BenchmarkMode.wimpMultithreaded,
          128,
        ),
        equals(
          'https://example.com/?workload=bouncy&stress=manual&nodes=128&mode=wimp&optin=true&st=0',
        ),
      );
      expect(
        buildBenchmarkUrl(
          'https://example.com/',
          BenchmarkMode.wimpSingleThreaded,
          1000,
          workload: 'grid',
        ),
        equals(
          'https://example.com/?workload=grid&stress=manual&nodes=1000&mode=wimp&optin=true&st=1',
        ),
      );
    });

    test('selectCdpPageTargetWsUrl filters CDP /json/list targets', () {
      final targets = <dynamic>[
        {
          'type': 'background_page',
          'url': 'chrome-extension://abcdef/bg.html',
          'webSocketDebuggerUrl': 'ws://127.0.0.1:9222/devtools/page/ext',
        },
        {
          'type': 'page',
          'url': 'about:blank',
          'webSocketDebuggerUrl': 'ws://127.0.0.1:9222/devtools/page/blank',
        },
        {
          'type': 'page',
          'url': 'http://localhost:8899/?mode=wasm',
          'webSocketDebuggerUrl': 'ws://127.0.0.1:9222/devtools/page/app',
        },
      ];

      expect(
        selectCdpPageTargetWsUrl(targets),
        equals('ws://127.0.0.1:9222/devtools/page/app'),
      );
      expect(selectCdpPageTargetWsUrl(const []), isNull);
    });
  });

  group('buildChromeArgs', () {
    const url = 'http://127.0.0.1:8899/';

    List<String> build({
      required bool isLinux,
      String? userDataDir,
      List<String> extraFlags = const [],
      bool headed = false,
    }) => buildChromeArgs(
      isLinux: isLinux,
      debugPort: 9222,
      viewportWidth: 1280,
      viewportHeight: 720,
      userDataDir: userDataDir,
      extraFlags: extraFlags,
      initialUrl: url,
      headed: headed,
    );

    test('keeps the default Linux launch line', () {
      expect(
        build(isLinux: true),
        equals([
          '--headless=new',
          '--no-sandbox',
          '--no-proxy-server',
          '--enable-experimental-web-platform-features',
          '--remote-debugging-port=9222',
          '--disable-background-timer-throttling',
          '--disable-backgrounding-occluded-windows',
          '--disable-renderer-backgrounding',
          '--no-first-run',
          '--no-default-browser-check',
          '--window-size=1380,820',
          url,
        ]),
      );
    });

    test('omits --headless=new and --no-sandbox when headed on Linux', () {
      final args = build(
        isLinux: true,
        headed: true,
        userDataDir: '/tmp/chrome_bench_headed',
      );
      expect(args, isNot(contains('--headless=new')));
      expect(args, isNot(contains('--no-sandbox')));
      expect(args, contains('--no-proxy-server'));
      expect(args, contains('--user-data-dir=/tmp/chrome_bench_headed'));
      expect(args.last, equals(url));
    });

    test('hasLinuxDisplay checks DISPLAY and WAYLAND_DISPLAY', () {
      expect(hasLinuxDisplay(const {}), isFalse);
      expect(
        hasLinuxDisplay(const {'DISPLAY': '  ', 'WAYLAND_DISPLAY': ''}),
        isFalse,
      );
      expect(hasLinuxDisplay(const {'DISPLAY': ':0'}), isTrue);
      expect(hasLinuxDisplay(const {'WAYLAND_DISPLAY': 'wayland-0'}), isTrue);
    });

    test('appends extra flags after the defaults, before the URL', () {
      final defaults = build(isLinux: true);
      expect(
        build(
          isLinux: true,
          extraFlags: ['--disable-gpu-vsync', '--disable-frame-rate-limit'],
        ),
        equals([
          ...defaults.sublist(0, defaults.length - 1),
          '--disable-gpu-vsync',
          '--disable-frame-rate-limit',
          url,
        ]),
      );
    });

    test('uses a profile dir instead of Linux-only flags elsewhere', () {
      final args = build(isLinux: false, userDataDir: '/tmp/chrome_bench_x');
      expect(args, isNot(contains('--headless=new')));
      expect(args, isNot(contains('--no-sandbox')));
      expect(args, contains('--user-data-dir=/tmp/chrome_bench_x'));
      expect(args.last, equals(url));
    });
  });

  group('formatMarkdownReport', () {
    test('generates structured Markdown tables and speedup metrics', () {
      final args = BenchmarkArgs.parse([
        '--browser=chrome',
        '--modes=wasm_mt,wasm_st,js',
        '--nodes=64',
        '--samples=2',
      ]);

      final capabilities = {
        BrowserType.chrome: CapabilityRecord(
          userAgent: 'HeadlessChrome/153.0',
          crossOriginIsolated: true,
          invertedProbe: true,
        ),
      };

      BenchmarkRecord rec({
        required String mode,
        required bool pipelined,
        required double fps,
        required double buildMs,
        required double rasterMs,
      }) => BenchmarkRecord(
        fps: fps,
        buildTimeMs: buildMs,
        rasterTimeMs: rasterMs,
        totalFrameTimeMs: pipelined
            ? (buildMs > rasterMs ? buildMs : rasterMs)
            : (buildMs + rasterMs),
        jitterMs: 0.5,
        isPipelined: pipelined,
        nodeCount: 64,
        mode: mode,
        workloadId: 'bouncy',
      );

      MultiSampleRecord multiPair({
        required String mode,
        required bool pipelined,
        required double fpsA,
        required double buildA,
        required double rasterA,
        required double fpsB,
        required double buildB,
        required double rasterB,
      }) => MultiSampleRecord.fromRecords([
        rec(
          mode: mode,
          pipelined: pipelined,
          fps: fpsA,
          buildMs: buildA,
          rasterMs: rasterA,
        ),
        rec(
          mode: mode,
          pipelined: pipelined,
          fps: fpsB,
          buildMs: buildB,
          rasterMs: rasterB,
        ),
      ]);

      final mtMulti = multiPair(
        mode: 'wasm',
        pipelined: true,
        fpsA: 58.0,
        buildA: 11.0,
        rasterA: 2.0,
        fpsB: 57.5,
        buildB: 11.5,
        rasterB: 2.2,
      );
      final stMulti = multiPair(
        mode: 'wasm',
        pipelined: false,
        fpsA: 38.0,
        buildA: 12.0,
        rasterA: 2.1,
        fpsB: 37.5,
        buildB: 12.2,
        rasterB: 2.3,
      );
      final jsMulti = multiPair(
        mode: 'js',
        pipelined: false,
        fpsA: 16.0,
        buildA: 38.0,
        rasterA: 4.0,
        fpsB: 15.5,
        buildB: 39.0,
        rasterB: 4.2,
      );

      final results = {
        BrowserType.chrome: {
          const BenchmarkKey(BenchmarkMode.wasmMultithreaded, 64): mtMulti,
          const BenchmarkKey(BenchmarkMode.wasmSingleThreaded, 64): stMulti,
          const BenchmarkKey(BenchmarkMode.jsCanvasKit, 64): jsMulti,
        },
      };

      final markdown = formatMarkdownReport(
        args: args,
        capabilities: capabilities,
        results: results,
      );

      expect(
        markdown,
        contains(
          '# Browser WebAssembly Benchmark Report (`flutter-wasm-compare`)',
        ),
      );
      expect(markdown, contains('## 🧪 Capability & Streaming Probes'));
      expect(
        markdown,
        contains('| Chrome | true | **PASS** | `HeadlessChrome/153.0` |'),
      );
      expect(
        markdown,
        contains('## 📊 Performance Comparison Matrix (Median Values)'),
      );
      expect(
        markdown,
        contains('### Key Takeaways (Fieller 95% Confidence Intervals)'),
      );
      expect(markdown, contains('Worker Raster Overhead:'));
      expect(markdown, contains('Pipelining Throughput Win:'));
      expect(markdown, contains('Dart2Wasm vs Dart2JS:'));
      expect(markdown, isNot(contains('## 🔎 Runtime Verification')));
    });

    test('flags runs whose runtime contradicts their mode label', () {
      final args = BenchmarkArgs.parse([
        '--browser=chrome',
        '--modes=wasm_mt,wimp_mt',
        '--nodes=128',
      ]);
      const renderer = 'ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device))';

      MultiSampleRecord multi(String mode, RuntimeRecord runtime) =>
          MultiSampleRecord.fromRecords([
            BenchmarkRecord(
              fps: 30.0,
              buildTimeMs: 25.0,
              rasterTimeMs: 30.0,
              totalFrameTimeMs: 55.0,
              jitterMs: 1.0,
              isPipelined: mode == 'wasm',
              nodeCount: 128,
              mode: mode,
            ),
          ], runtime: runtime);

      final results = {
        BrowserType.chrome: {
          const BenchmarkKey(BenchmarkMode.wasmMultithreaded, 128): multi(
            'wasm',
            RuntimeRecord(
              isWimp: false,
              isMultiThreaded: true,
              crossOriginIsolated: true,
              webglRenderer: renderer,
              webglVendor: 'Google Inc. (Google)',
            ),
          ),
          const BenchmarkKey(BenchmarkMode.wimpMultithreaded, 128): multi(
            'wimp',
            RuntimeRecord(
              isWimp: false,
              isMultiThreaded: true,
              crossOriginIsolated: true,
              webglRenderer: renderer,
            ),
          ),
        },
      };

      final markdown = formatMarkdownReport(
        args: args,
        capabilities: const {},
        results: results,
      );

      expect(markdown, contains('## 🔎 Runtime Verification'));
      expect(
        markdown,
        contains(
          '| Chrome | Wasm MT (st=0) | 128 | false | true | true | '
          '`$renderer` | `Google Inc. (Google)` | ✅ valid |',
        ),
      );
      expect(
        markdown,
        contains(
          '| Chrome | WIMP MT (st=0) | 128 | false | true | true | '
          '`$renderer` | `n/a` | ⚠️ INVALID: WIMP not active (isWimp=false) |',
        ),
      );
      expect(markdown, contains('| Chrome WIMP MT |'));
      expect(
        markdown,
        contains(
          '| **Nodes (128)** | **30.0 FPS** / 25.00ms / 30.00ms | '
          '⚠️ INVALID **30.0 FPS** / 25.00ms / 30.00ms |',
        ),
      );
    });

    test('omits takeaways for node counts with an errored mode', () {
      final args = BenchmarkArgs.parse([
        '--browser=chrome',
        '--modes=wasm_mt,wasm_st,js',
        '--nodes=64',
      ]);

      MultiSampleRecord multi(String mode, {required bool pipelined}) =>
          MultiSampleRecord.fromRecords([
            for (final fps in [30.0, 31.0])
              BenchmarkRecord(
                fps: fps,
                buildTimeMs: 10.0,
                rasterTimeMs: 5.0,
                totalFrameTimeMs: 15.0,
                jitterMs: 0.5,
                isPipelined: pipelined,
                nodeCount: 64,
                mode: mode,
              ),
          ]);

      String report(MultiSampleRecord mt) => formatMarkdownReport(
        args: args,
        capabilities: const {},
        results: {
          BrowserType.chrome: {
            const BenchmarkKey(BenchmarkMode.wasmMultithreaded, 64): mt,
            const BenchmarkKey(BenchmarkMode.wasmSingleThreaded, 64): multi(
              'wasm',
              pipelined: false,
            ),
            const BenchmarkKey(BenchmarkMode.jsCanvasKit, 64): multi(
              'js',
              pipelined: false,
            ),
          },
        },
      );

      expect(
        report(multi('wasm', pipelined: true)),
        contains('* **Chrome (at 64 nodes)**:'),
      );

      final markdown = report(MultiSampleRecord.error('page crashed'));
      expect(markdown, contains('⚠️ ERROR |'));
      expect(markdown, isNot(contains('Key Takeaways')));
      expect(markdown, isNot(contains('(at 64 nodes)')));
    });
  });

  group('fail-closed point results', () {
    final validMt = RuntimeRecord(
      isWimp: false,
      isMultiThreaded: true,
      crossOriginIsolated: true,
    );

    BenchmarkRecord sample(
      double fps, {
      String mode = 'wasm',
      bool pipelined = true,
    }) => BenchmarkRecord(
      fps: fps,
      buildTimeMs: 10.0,
      rasterTimeMs: 5.0,
      totalFrameTimeMs: 1000 / fps,
      jitterMs: 0.5,
      isPipelined: pipelined,
      nodeCount: 64,
      mode: mode,
    );

    test('summarizeSamples errors when no sample arrived', () {
      final multi = summarizeSamples(
        const [],
        requestedSamples: 5,
        runtime: validMt,
      );
      expect(
        multi.errorMessage,
        equals('No metrics found in localStorage (0 of 5 requested samples)'),
      );
      expect(multi.samplesCount, equals(0));
      expect(multi.runtime, same(validMt));
    });

    test('summarizeSamples errors on a short sample count', () {
      final multi = summarizeSamples(
        [sample(30.0)],
        requestedSamples: 5,
        runtime: validMt,
      );
      expect(
        multi.errorMessage,
        equals('Incomplete sample count (1 of 5 requested samples)'),
      );
      expect(multi.samplesCount, equals(1));
      expect(multi.runtime, same(validMt));
      expect(
        multi.failureReason(BenchmarkMode.wasmMultithreaded),
        equals(multi.errorMessage),
      );
    });

    test('summarizeSamples aggregates a complete run', () {
      final multi = summarizeSamples(
        [sample(30.0), sample(31.0), sample(32.0)],
        requestedSamples: 3,
        runtime: validMt,
      );
      expect(multi.errorMessage, isNull);
      expect(multi.samplesCount, equals(3));
      expect(multi.failureReason(BenchmarkMode.wasmMultithreaded), isNull);
    });

    test('hasFailedRuns counts errors and INVALID runtimes', () {
      final measured = summarizeSamples(
        [sample(30.0), sample(31.0)],
        requestedSamples: 2,
        runtime: validMt,
      );
      Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>> results(
        BenchmarkMode mode,
        MultiSampleRecord multi,
      ) => {
        BrowserType.chrome: {BenchmarkKey(mode, 64): multi},
      };

      expect(
        hasFailedRuns(results(BenchmarkMode.wasmMultithreaded, measured)),
        isFalse,
      );
      // The same skwasm runtime contradicts a WIMP label.
      expect(
        measured.failureReason(BenchmarkMode.wimpMultithreaded),
        equals('WIMP not active (isWimp=false)'),
      );
      expect(
        hasFailedRuns(results(BenchmarkMode.wimpMultithreaded, measured)),
        isTrue,
      );
      expect(
        hasFailedRuns(
          results(BenchmarkMode.jsCanvasKit, MultiSampleRecord.error('crash')),
        ),
        isTrue,
      );
    });

    test('JSON keeps failed points with error, sample count, and runtime', () {
      final args = BenchmarkArgs.parse([
        '--browser=chrome',
        '--modes=wasm_mt',
        '--nodes=64',
      ]);
      final report = generateJsonReport(
        args: args,
        capabilities: const {},
        results: {
          BrowserType.chrome: {
            const BenchmarkKey(
              BenchmarkMode.wasmMultithreaded,
              64,
            ): summarizeSamples(
              [sample(30.0)],
              requestedSamples: 5,
              runtime: validMt,
            ),
          },
        },
      );

      final decoded = jsonDecode(jsonEncode(report)) as Map<String, dynamic>;
      final benchmarks = decoded['benchmarks'] as List<dynamic>;
      expect(benchmarks, hasLength(1));
      final entry = benchmarks.single as Map<String, dynamic>;
      expect(entry['mode'], equals('wasmMultithreaded'));
      expect(entry['nodes'], equals(64));
      expect(
        entry['error'],
        equals('Incomplete sample count (1 of 5 requested samples)'),
      );
      expect(entry['samples'], equals(1));
      final runtime = entry['runtime'] as Map<String, dynamic>;
      expect(runtime['valid'], isTrue);
      expect(runtime['is_multi_threaded'], isTrue);
    });

    test('INVALID runs are excluded from Fieller comparisons', () {
      final args = BenchmarkArgs.parse([
        '--browser=chrome',
        '--modes=wasm_mt,wasm_st,js',
        '--nodes=64',
      ]);
      Map<BrowserType, Map<BenchmarkKey, MultiSampleRecord>> results(
        RuntimeRecord mtRuntime,
      ) => {
        BrowserType.chrome: {
          const BenchmarkKey(
            BenchmarkMode.wasmMultithreaded,
            64,
          ): MultiSampleRecord.fromRecords([
            sample(58.0),
            sample(57.0),
          ], runtime: mtRuntime),
          const BenchmarkKey(
            BenchmarkMode.wasmSingleThreaded,
            64,
          ): MultiSampleRecord.fromRecords([
            sample(38.0, pipelined: false),
            sample(37.0, pipelined: false),
          ]),
          const BenchmarkKey(
            BenchmarkMode.jsCanvasKit,
            64,
          ): MultiSampleRecord.fromRecords([
            sample(16.0, mode: 'js', pipelined: false),
            sample(15.0, mode: 'js', pipelined: false),
          ]),
        },
      };

      String markdown(RuntimeRecord mtRuntime) => formatMarkdownReport(
        args: args,
        capabilities: const {},
        results: results(mtRuntime),
      );
      List<dynamic> comparisons(RuntimeRecord mtRuntime) =>
          generateJsonReport(
                args: args,
                capabilities: const {},
                results: results(mtRuntime),
              )['comparisons']
              as List<dynamic>;

      expect(markdown(validMt), contains('* **Chrome (at 64 nodes)**:'));
      expect(comparisons(validMt), isNotEmpty);

      // A wasm_mt point that actually ran single-threaded.
      final stRuntime = RuntimeRecord(
        isWimp: false,
        isMultiThreaded: false,
        crossOriginIsolated: true,
      );
      expect(markdown(stRuntime), contains('⚠️ INVALID'));
      expect(markdown(stRuntime), isNot(contains('Key Takeaways')));
      expect(comparisons(stRuntime), isEmpty);
    });

    test('Runtime Verification shows ⚠️ ERROR on sampling failure', () {
      final args = BenchmarkArgs.parse([
        '--browser=chrome',
        '--modes=wasm_mt',
        '--nodes=64',
      ]);
      final markdown = formatMarkdownReport(
        args: args,
        capabilities: const {},
        results: {
          BrowserType.chrome: {
            const BenchmarkKey(
              BenchmarkMode.wasmMultithreaded,
              64,
            ): summarizeSamples(
              [sample(30.0)],
              requestedSamples: 5,
              runtime: validMt,
            ),
          },
        },
      );

      expect(
        markdown,
        contains(
          '⚠️ ERROR: Incomplete sample count (1 of 5 requested samples)',
        ),
      );
      expect(markdown, isNot(contains('✅ valid')));
      expect(markdown, contains('| **Nodes (64)** | ⚠️ ERROR |'));
    });

    test('maxSampleAttempts scales budget for sub-throttle intervals', () {
      expect(maxSampleAttempts(samples: 5, sampleIntervalMs: 1200), equals(20));
      expect(maxSampleAttempts(samples: 5, sampleIntervalMs: 2000), equals(20));
      expect(maxSampleAttempts(samples: 5, sampleIntervalMs: 200), equals(120));
    });
  });

  group('BenchmarkRecord matching & filtering', () {
    BenchmarkRecord makeRecord({
      required String mode,
      int nodeCount = 1000,
      String workloadId = 'bouncy',
      required bool isPipelined,
      required double fps,
      required double buildTimeMs,
      required double rasterTimeMs,
      required double totalFrameTimeMs,
      double jitterMs = 1.0,
    }) => BenchmarkRecord.fromJson({
      'mode': mode,
      'nodeCount': nodeCount,
      'workloadId': workloadId,
      'isPipelined': isPipelined,
      'fps': fps,
      'buildTimeMs': buildTimeMs,
      'rasterTimeMs': rasterTimeMs,
      'totalFrameTimeMs': totalFrameTimeMs,
      'jitterMs': jitterMs,
    });

    test(
      'matches Wasm Multithreaded only when mode is wasm and isPipelined',
      () {
        final recordMT = makeRecord(
          mode: 'wasm',
          workloadId: 'grid',
          isPipelined: true,
          fps: 50.0,
          buildTimeMs: 18.0,
          rasterTimeMs: 17.0,
          totalFrameTimeMs: 19.0,
        );

        expect(
          recordMT.matches(
            BenchmarkMode.wasmMultithreaded,
            1000,
            expectedWorkloadId: 'grid',
          ),
          isTrue,
        );
        expect(
          recordMT.matches(
            BenchmarkMode.wasmMultithreaded,
            1000,
            expectedWorkloadId: 'bouncy',
          ),
          isFalse,
        );
        expect(
          recordMT.matches(BenchmarkMode.wasmSingleThreaded, 1000),
          isFalse,
        );
        expect(recordMT.matches(BenchmarkMode.jsCanvasKit, 1000), isFalse);
        expect(recordMT.matches(BenchmarkMode.wasmMultithreaded, 500), isFalse);
      },
    );

    test(
      'matches Wasm Single-Threaded only when mode is wasm and !isPipelined',
      () {
        final recordST = makeRecord(
          mode: 'wasm',
          isPipelined: false,
          fps: 40.0,
          buildTimeMs: 18.0,
          rasterTimeMs: 5.0,
          totalFrameTimeMs: 23.0,
        );

        expect(
          recordST.matches(BenchmarkMode.wasmSingleThreaded, 1000),
          isTrue,
        );
        expect(
          recordST.matches(BenchmarkMode.wasmMultithreaded, 1000),
          isFalse,
        );
        expect(recordST.matches(BenchmarkMode.jsCanvasKit, 1000), isFalse);
      },
    );

    test('matches JS CanvasKit when mode is js', () {
      final recordJS = makeRecord(
        mode: 'js',
        isPipelined: false,
        fps: 20.0,
        buildTimeMs: 40.0,
        rasterTimeMs: 6.0,
        totalFrameTimeMs: 46.0,
        jitterMs: 2.0,
      );

      expect(recordJS.matches(BenchmarkMode.jsCanvasKit, 1000), isTrue);
      expect(recordJS.matches(BenchmarkMode.wasmMultithreaded, 1000), isFalse);
      expect(recordJS.matches(BenchmarkMode.wasmSingleThreaded, 1000), isFalse);
    });

    test('matches JS WebParagraph when mode is webparagraph', () {
      final recordWP = makeRecord(
        mode: 'webparagraph',
        isPipelined: false,
        fps: 52.0,
        buildTimeMs: 11.0,
        rasterTimeMs: 2.0,
        totalFrameTimeMs: 13.0,
        jitterMs: 0.8,
      );

      expect(recordWP.matches(BenchmarkMode.jsWebParagraph, 1000), isTrue);
      expect(recordWP.matches(BenchmarkMode.jsCanvasKit, 1000), isFalse);
      expect(recordWP.matches(BenchmarkMode.wasmMultithreaded, 1000), isFalse);
      expect(recordWP.matches(BenchmarkMode.wasmSingleThreaded, 1000), isFalse);
    });

    test('matches WIMP modes on mode wimp regardless of isPipelined', () {
      for (final isPipelined in [false, true]) {
        final recordWimp = makeRecord(
          mode: 'wimp',
          isPipelined: isPipelined,
          fps: 24.0,
          buildTimeMs: 30.0,
          rasterTimeMs: 39.0,
          totalFrameTimeMs: 70.0,
        );

        expect(
          recordWimp.matches(BenchmarkMode.wimpMultithreaded, 1000),
          isTrue,
        );
        expect(
          recordWimp.matches(BenchmarkMode.wimpSingleThreaded, 1000),
          isTrue,
        );
        expect(
          recordWimp.matches(BenchmarkMode.wasmMultithreaded, 1000),
          isFalse,
        );
        expect(
          recordWimp.matches(BenchmarkMode.wasmSingleThreaded, 1000),
          isFalse,
        );
        expect(recordWimp.matches(BenchmarkMode.jsCanvasKit, 1000), isFalse);
      }

      final recordWasm = makeRecord(
        mode: 'wasm',
        isPipelined: true,
        fps: 36.0,
        buildTimeMs: 26.0,
        rasterTimeMs: 26.0,
        totalFrameTimeMs: 27.0,
      );
      expect(
        recordWasm.matches(BenchmarkMode.wimpMultithreaded, 1000),
        isFalse,
      );
    });
  });

  group('RuntimeRecord', () {
    RuntimeRecord runtime({
      bool? isWimp,
      bool? isMultiThreaded,
      bool crossOriginIsolated = true,
    }) => RuntimeRecord(
      isWimp: isWimp,
      isMultiThreaded: isMultiThreaded,
      crossOriginIsolated: crossOriginIsolated,
    );

    test('parses the probe JSON payload', () {
      final parsed = RuntimeRecord.parse(
        jsonEncode({
          'isWimp': true,
          'isMultiThreaded': true,
          'crossOriginIsolated': true,
          'webglRenderer': 'ANGLE (SwiftShader)',
          'webglVendor': 'Google Inc. (Google)',
        }),
      );
      expect(parsed.isWimp, isTrue);
      expect(parsed.isMultiThreaded, isTrue);
      expect(parsed.crossOriginIsolated, isTrue);
      expect(parsed.webglRenderer, equals('ANGLE (SwiftShader)'));
      expect(parsed.webglVendor, equals('Google Inc. (Google)'));
      expect(parsed.invalidReason(BenchmarkMode.wimpMultithreaded), isNull);
    });

    test('accepts runtimes that match their mode', () {
      expect(
        runtime(
          isWimp: false,
          isMultiThreaded: true,
        ).invalidReason(BenchmarkMode.wasmMultithreaded),
        isNull,
      );
      expect(
        runtime(
          isWimp: false,
          isMultiThreaded: false,
        ).invalidReason(BenchmarkMode.wasmSingleThreaded),
        isNull,
      );
      expect(
        runtime(
          isWimp: true,
          isMultiThreaded: false,
        ).invalidReason(BenchmarkMode.wimpSingleThreaded),
        isNull,
      );
      expect(runtime().invalidReason(BenchmarkMode.jsCanvasKit), isNull);
    });

    test('flags WIMP-labelled runs where WIMP is not active', () {
      expect(
        runtime(
          isWimp: false,
          isMultiThreaded: true,
        ).invalidReason(BenchmarkMode.wimpMultithreaded),
        equals('WIMP not active (isWimp=false)'),
      );
      expect(
        runtime(
          isWimp: true,
          isMultiThreaded: true,
        ).invalidReason(BenchmarkMode.wasmMultithreaded),
        equals('skwasm run with isWimp=true'),
      );
    });

    test('flags threading and isolation mismatches', () {
      expect(
        runtime(
          isWimp: true,
          isMultiThreaded: false,
        ).invalidReason(BenchmarkMode.wimpMultithreaded),
        equals('isMultiThreaded=false, expected true'),
      );
      expect(
        runtime(
          isWimp: false,
          isMultiThreaded: true,
          crossOriginIsolated: false,
        ).invalidReason(BenchmarkMode.wasmMultithreaded),
        equals('multi-threaded run without crossOriginIsolated'),
      );
      expect(
        runtime(
          isWimp: false,
          isMultiThreaded: false,
        ).invalidReason(BenchmarkMode.jsCanvasKit),
        equals('skwasm engine loaded on a JS run'),
      );
    });

    test('fails closed when the probe result is unreadable', () {
      for (final raw in [null, '', 'not json', 42]) {
        final parsed = RuntimeRecord.parse(raw);
        expect(parsed.crossOriginIsolated, isFalse);
        expect(
          parsed.invalidReason(BenchmarkMode.wimpMultithreaded),
          equals('no engine loaded (isWimp=null)'),
        );
        expect(
          parsed.invalidReason(BenchmarkMode.wasmSingleThreaded),
          equals('no engine loaded (isWimp=null)'),
        );
      }
    });

    test('toJson reports validity alongside the raw fields', () {
      final invalid = runtime(
        isWimp: false,
        isMultiThreaded: true,
      ).toJson(BenchmarkMode.wimpMultithreaded);
      expect(() => jsonEncode(invalid), returnsNormally);
      expect(invalid['valid'], isFalse);
      expect(
        invalid['invalid_reason'],
        equals('WIMP not active (isWimp=false)'),
      );
      expect(invalid['is_wimp'], isFalse);
      expect(invalid['cross_origin_isolated'], isTrue);

      final valid = runtime(
        isWimp: true,
        isMultiThreaded: true,
      ).toJson(BenchmarkMode.wimpMultithreaded);
      expect(valid['valid'], isTrue);
      expect(valid['invalid_reason'], isNull);
    });
  });

  group('JSON Sanitization & Serialization', () {
    test('statsToJson serializes valid metrics to RFC 8259 JSON', () {
      final metrics = BenchmarkMetrics.fromSamples([
        1000000.0,
        2000000.0,
        3000000.0,
      ]);
      final jsonMap = statsToJson(metrics, isMs: true);
      expect(() => jsonEncode(jsonMap), returnsNormally);
      expect(jsonMap['mean'], equals(2.0));
      expect(jsonMap['is_stable'], isA<bool>());
    });

    test('fiellerToJson sanitizes unbounded Infinity to null', () {
      const unbounded = FiellerInterval(
        ratio: 2.5,
        lowerBound: double.negativeInfinity,
        upperBound: double.infinity,
        g: 1.5,
        confidenceLevel: 0.95,
        isValid: false,
      );

      final jsonMap = fiellerToJson(
        browser: 'chrome',
        nodes: 1000,
        name: 'test_comparison',
        fieller: unbounded,
      );

      expect(() => jsonEncode(jsonMap), returnsNormally);
      final encoded = jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>;
      final ci = encoded['confidence_interval'] as Map<String, dynamic>;
      expect(ci['lower'], isNull);
      expect(ci['upper'], isNull);
      expect(ci['is_valid'], isFalse);
      expect(encoded['ratio'], equals(2.5));
    });

    test('fiellerToJson sanitizes NaN ratio to null', () {
      const nanFieller = FiellerInterval(
        ratio: double.nan,
        lowerBound: double.nan,
        upperBound: double.nan,
        g: double.nan,
        confidenceLevel: 0.95,
        isValid: false,
      );

      final jsonMap = fiellerToJson(
        browser: 'chrome',
        nodes: 1000,
        name: 'test_nan',
        fieller: nanFieller,
      );

      expect(() => jsonEncode(jsonMap), returnsNormally);
      final encoded = jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>;
      expect(encoded['ratio'], isNull);
    });

    test('formatFieller handles edge cases gracefully', () {
      const valid = FiellerInterval(
        ratio: 2.5,
        lowerBound: 2.1,
        upperBound: 2.9,
        g: 0.05,
        confidenceLevel: 0.95,
        isValid: true,
      );
      expect(formatFieller(valid), equals('2.50x [2.10x, 2.90x] (95% CI)'));

      const unbounded = FiellerInterval(
        ratio: 2.5,
        lowerBound: double.negativeInfinity,
        upperBound: double.infinity,
        g: 1.2,
        confidenceLevel: 0.95,
        isValid: false,
      );
      expect(formatFieller(unbounded), equals('2.50x'));

      const nanInterval = FiellerInterval(
        ratio: double.nan,
        lowerBound: double.nan,
        upperBound: double.nan,
        g: double.nan,
        confidenceLevel: 0.95,
        isValid: false,
      );
      expect(formatFieller(nanInterval), equals('N/A'));
    });
  });
}
