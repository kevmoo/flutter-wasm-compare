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
        '--browsers=chrome,firefox',
        '--modes=mt,js',
        '--viewport=1920x1080',
        '--settle-seconds=2',
        '--output=doc/bench.md',
        '--json-output=doc/bench.json',
        '--skip-capability-probe',
      ]);
      expect(full.showHelp, isFalse);
      expect(full.baseUrl, equals('http://localhost:8080/'));
      expect(full.browsers, equals([BrowserType.chrome, BrowserType.firefox]));
      expect(
        full.modes,
        equals([BenchmarkMode.wasmMultithreaded, BenchmarkMode.jsCanvasKit]),
      );
      expect(full.viewportWidth, equals(1920));
      expect(full.viewportHeight, equals(1080));
      expect(full.settleSeconds, equals(2));
      expect(full.outputPath, equals('doc/bench.md'));
      expect(full.jsonOutputPath, equals('doc/bench.json'));
      expect(full.skipCapabilityProbe, isTrue);
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

  group('formatMarkdownReport', () {
    test('generates structured Markdown tables and speedup metrics', () {
      final args = BenchmarkArgs.parse([
        '--browsers=chrome',
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
        '--browsers=chrome',
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
          equals('WIMP not active (isWimp=null)'),
        );
        expect(
          parsed.invalidReason(BenchmarkMode.wasmSingleThreaded),
          equals('skwasm run with isWimp=null'),
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
