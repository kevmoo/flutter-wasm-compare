import 'dart:convert';

import 'package:bench_press/bench_press.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/benchmark.dart';

void main() {
  group('BenchmarkArgs.parse', () {
    test('parses defaults correctly', () {
      final args = BenchmarkArgs.parse([]);
      expect(args.showHelp, isFalse);
      expect(args.baseUrl, equals('https://flutter-wasm-compare.web.app/'));
      expect(args.browsers, equals(BrowserType.values));
      expect(args.modes, equals(BenchmarkMode.values));
      expect(args.nodeCounts, equals([100, 1000, 8000]));
      expect(args.viewportWidth, equals(1280));
      expect(args.viewportHeight, equals(720));
      expect(args.settleSeconds, equals(5));
      expect(args.samples, equals(5));
      expect(args.sampleIntervalMs, equals(1200));
      expect(args.jsonOutput, isFalse);
      expect(args.outputPath, isNull);
    });

    test('parses preset arguments', () {
      final light = BenchmarkArgs.parse(['--preset=light']);
      expect(light.nodeCounts, equals([100]));

      final medium = BenchmarkArgs.parse(['--preset=medium']);
      expect(medium.nodeCounts, equals([1000]));

      final heavy = BenchmarkArgs.parse(['--preset=heavy']);
      expect(heavy.nodeCounts, equals([8000]));

      final all = BenchmarkArgs.parse(['--preset=all']);
      expect(all.nodeCounts, equals([100, 1000, 8000]));
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
  });

  group('BenchmarkRecord matching & filtering', () {
    test(
      'matches Wasm Multithreaded only when mode is wasm and isPipelined',
      () {
        final recordMT = BenchmarkRecord.fromJson({
          'mode': 'wasm',
          'nodeCount': 1000,
          'isPipelined': true,
          'fps': 50.0,
          'buildTimeMs': 18.0,
          'rasterTimeMs': 17.0,
          'totalFrameTimeMs': 19.0,
          'jitterMs': 1.0,
        });

        expect(recordMT.matches(BenchmarkMode.wasmMultithreaded, 1000), isTrue);
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
        final recordST = BenchmarkRecord.fromJson({
          'mode': 'wasm',
          'nodeCount': 1000,
          'isPipelined': false,
          'fps': 40.0,
          'buildTimeMs': 18.0,
          'rasterTimeMs': 5.0,
          'totalFrameTimeMs': 23.0,
          'jitterMs': 1.0,
        });

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
      final recordJS = BenchmarkRecord.fromJson({
        'mode': 'js',
        'nodeCount': 1000,
        'isPipelined': false,
        'fps': 20.0,
        'buildTimeMs': 40.0,
        'rasterTimeMs': 6.0,
        'totalFrameTimeMs': 46.0,
        'jitterMs': 2.0,
      });

      expect(recordJS.matches(BenchmarkMode.jsCanvasKit, 1000), isTrue);
      expect(recordJS.matches(BenchmarkMode.wasmMultithreaded, 1000), isFalse);
      expect(recordJS.matches(BenchmarkMode.wasmSingleThreaded, 1000), isFalse);
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
