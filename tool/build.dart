import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final isDeploy = args.contains('--deploy');
  final extraArgs = args.where((arg) => arg != '--deploy').toList();

  final success = await buildWeb(isDeploy: isDeploy, extraArgs: extraArgs);
  if (!success) {
    exitCode = 1;
  }
}

Future<bool> buildWeb({
  bool isDeploy = false,
  List<String> extraArgs = const [],
}) async {
  if (isDeploy) {
    if (!_isWorkingTreeClean()) {
      stderr.writeln(
        '❌ Deploy build failed: Working tree is dirty. '
        'Commit all changes before deploying.',
      );
      return false;
    }

    final branch = _runGit(['branch', '--show-current']);
    if (branch != 'main') {
      stderr.writeln(
        '❌ Deploy build failed: Current branch is "$branch" '
        '(expected "main").',
      );
      return false;
    }
  }

  final isClean = _isWorkingTreeClean();
  final gitSha = _runGit(['rev-parse', 'HEAD']);
  final dartVersion = Platform.version.split(' ').first;
  final flutterVersion = _getFlutterVersion();

  print('🔨 Building Flutter Web (Wasm + JS fallback)...');
  if (gitSha.isNotEmpty) {
    final shortSha = gitSha.length >= 7 ? gitSha.substring(0, 7) : gitSha;
    print('   Git Commit: $shortSha (clean: $isClean)');
  }
  if (dartVersion.isNotEmpty) {
    print('   Dart SDK:   $dartVersion');
  }
  if (flutterVersion.isNotEmpty) {
    print('   Flutter:    $flutterVersion');
  }
  final stopwatch = Stopwatch()..start();

  final fvmFlutter = File('.fvm/flutter_sdk/bin/flutter');
  final executable = fvmFlutter.existsSync() ? fvmFlutter.path : 'flutter';

  final buildArgs = [
    'build',
    'web',
    '--wasm',
    if (gitSha.isNotEmpty) '--dart-define=GIT_SHA=$gitSha',
    if (dartVersion.isNotEmpty) '--dart-define=DART_VERSION=$dartVersion',
    if (flutterVersion.isNotEmpty)
      '--dart-define=FLUTTER_SDK_VERSION=$flutterVersion',
    '--dart-define=IS_CLEAN_BUILD=$isClean',
    ...extraArgs,
  ];

  final process = await Process.start(
    executable,
    buildArgs,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );

  final exit = await process.exitCode;
  stopwatch.stop();

  if (exit == 0) {
    print('✅ Build complete in ${stopwatch.elapsed.inSeconds}s.\n');
    return true;
  } else {
    print('❌ Build failed with exit code $exit.\n');
    return false;
  }
}

String _runGit(List<String> args) {
  try {
    final result = Process.runSync('git', args);
    if (result.exitCode != 0) {
      return '';
    }
    return (result.stdout as String).trim();
  } catch (_) {
    return '';
  }
}

bool _isWorkingTreeClean() => _runGit(['status', '--porcelain']).isEmpty;

String _getFlutterVersion() {
  final fvmrc = File('.fvmrc');
  if (fvmrc.existsSync()) {
    try {
      final json = jsonDecode(fvmrc.readAsStringSync()) as Map<String, dynamic>;
      if (json['flutter'] != null) {
        return json['flutter'] as String;
      }
    } catch (_) {}
  }
  return '3.47.0';
}
