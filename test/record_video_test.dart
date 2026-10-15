import 'package:flutter_test/flutter_test.dart';

import '../tool/record_video.dart';

void main() {
  group('CaptureConfig.parse', () {
    test('parses macOS defaults for bouncy workload', () {
      final cfg = CaptureConfig.parse(const [], isMacOS: true);
      expect(cfg.showHelp, isFalse);
      expect(cfg.dryRun, isFalse);
      expect(cfg.baseUrl, equals('http://localhost:8088'));
      expect(cfg.outDir, equals('.'));
      expect(cfg.workload, equals('bouncy'));
      expect(cfg.nodes, equals(128));
      expect(cfg.width, equals(1280));
      expect(cfg.height, equals(720));
      expect(cfg.dpr, equals(2));
      expect(cfg.screencastDpr, equals(2));
      expect(cfg.fps, equals(60));
      expect(cfg.hz, equals(120));
      expect(cfg.phaseSeconds, equals(8.0));
      expect(cfg.warmupSeconds, equals(4.0));
      expect(cfg.quality, equals(88));
      expect(
        cfg.jsUrl,
        equals(
          'http://localhost:8088/?workload=bouncy&stress=manual&nodes=128&mode=js&hz=120',
        ),
      );
      expect(
        cfg.wasmUrl,
        equals(
          'http://localhost:8088/?workload=bouncy&stress=manual&nodes=128&mode=wasm&optin=true&st=0&hz=120',
        ),
      );
      expect(cfg.jsMp4Path, equals('./flutter_wasm_compare_bouncy_js.mp4'));
      expect(cfg.wasmMp4Path, equals('./flutter_wasm_compare_bouncy_wasm.mp4'));
      expect(
        cfg.combinedMp4Path,
        equals('./flutter_wasm_compare_bouncy_combined.mp4'),
      );
    });

    test('parses Linux defaults and grid workload default nodes', () {
      final linuxBouncy = CaptureConfig.parse(const [], isMacOS: false);
      expect(linuxBouncy.nodes, equals(64));
      expect(linuxBouncy.dpr, equals(1));
      expect(linuxBouncy.screencastDpr, equals(1));
      expect(linuxBouncy.hz, equals(60));

      final gridCfg = CaptureConfig.parse(const [
        '--workload=grid',
        '--base-url=http://127.0.0.1:8088/',
      ], isMacOS: true);
      expect(gridCfg.workload, equals('grid'));
      expect(gridCfg.nodes, equals(1000));
      expect(gridCfg.normalizedBaseUrl, equals('http://127.0.0.1:8088'));
      expect(gridCfg.jsMp4Path, equals('./flutter_wasm_compare_grid_js.mp4'));
    });

    test('parses custom CLI flags and --help / --dry-run', () {
      final helpCfg = CaptureConfig.parse(const ['--help']);
      expect(helpCfg.showHelp, isTrue);

      final custom = CaptureConfig.parse(const [
        '--dry-run',
        '--base-url=http://127.0.0.1:8088',
        '--out-dir=/tmp/out',
        '--workload=bouncy',
        '--nodes=96',
        '--width=1920',
        '--height=1080',
        '--dpr=2',
        '--screencast-dpr=1',
        '--fps=60',
        '--hz=120',
        '--phase-seconds=6.5',
        '--warmup-seconds=2.5',
        '--quality=90',
        '--chrome-binary=/custom/chrome',
        '--ffmpeg-binary=/custom/ffmpeg',
      ]);
      expect(custom.dryRun, isTrue);
      expect(custom.nodes, equals(96));
      expect(custom.width, equals(1920));
      expect(custom.height, equals(1080));
      expect(custom.dpr, equals(2));
      expect(custom.screencastDpr, equals(1));
      expect(custom.phaseSeconds, equals(6.5));
      expect(custom.warmupSeconds, equals(2.5));
      expect(custom.quality, equals(90));
      expect(custom.chromeBinary, equals('/custom/chrome'));
      expect(custom.ffmpegBinary, equals('/custom/ffmpeg'));
    });

    test('rejects invalid options and out-of-range values', () {
      expect(
        () => CaptureConfig.parse(const ['positional']),
        throwsFormatException,
      );
      expect(
        () => CaptureConfig.parse(const ['--nodes=0']),
        throwsFormatException,
      );
      expect(
        () => CaptureConfig.parse(const ['--quality=0']),
        throwsFormatException,
      );
      expect(
        () => CaptureConfig.parse(const ['--quality=101']),
        throwsFormatException,
      );
      expect(
        () => CaptureConfig.parse(const ['--phase-seconds=0']),
        throwsFormatException,
      );
      expect(
        () => CaptureConfig.parse(const ['--warmup-seconds=-1']),
        throwsFormatException,
      );
      expect(
        () => CaptureConfig.parse(const ['--base-url=   ']),
        throwsFormatException,
      );
    });

    test(
      'buildChromeArgs includes headless SwiftShader flags only on Linux',
      () {
        final cfg = CaptureConfig.parse(const ['--nodes=96'], isMacOS: true);
        final macArgs = cfg.buildChromeArgs(9222, '/tmp/prof', isMacOS: true);
        expect(macArgs, isNot(contains('--headless=new')));
        expect(macArgs.last, equals(cfg.jsUrl));

        final linuxArgs = cfg.buildChromeArgs(
          9222,
          '/tmp/prof',
          isMacOS: false,
        );
        expect(linuxArgs, contains('--headless=new'));
        expect(linuxArgs, contains('--use-angle=swiftshader'));
        expect(linuxArgs.last, equals(cfg.jsUrl));
      },
    );
  });

  group('formatFfconcatManifest', () {
    test('formats frame durations clamped between 8ms and 500ms', () {
      final entries = [
        FrameEntry(10.000, '/tmp/f0.jpg', 'js'),
        FrameEntry(10.002, '/tmp/f1.jpg', 'js'),
        FrameEntry(11.000, '/tmp/f2.jpg', 'js'),
      ];
      final manifest = formatFfconcatManifest(entries);
      expect(
        manifest,
        equals(
          'ffconcat version 1.0\n'
          "file '/tmp/f0.jpg'\n"
          'duration 0.0080\n'
          "file '/tmp/f1.jpg'\n"
          'duration 0.5000\n'
          "file '/tmp/f2.jpg'\n"
          'duration 0.0333\n'
          "file '/tmp/f2.jpg'\n",
        ),
      );
    });

    test('throws StateError when fewer than 2 frames are provided', () {
      expect(
        () => formatFfconcatManifest([FrameEntry(1.0, '/tmp/f0.jpg', 'js')]),
        throwsStateError,
      );
    });
  });
}
