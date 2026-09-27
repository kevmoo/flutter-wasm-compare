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
  if (isDeploy && !_validateDeployPrerequisites()) {
    return false;
  }

  final isClean = _isWorkingTreeClean();
  final gitSha = _runGit(['rev-parse', 'HEAD']);

  final fvmFlutter = File('.fvm/flutter_sdk/bin/flutter');
  final executable = fvmFlutter.existsSync() ? fvmFlutter.path : 'flutter';

  final sdkInfo = await _resolveSdkVersions(executable);
  final dartVersion = sdkInfo.dartSdkVersion;
  final flutterVersion = sdkInfo.formattedFrameworkVersion;

  _printBuildHeader(
    gitSha: gitSha,
    isClean: isClean,
    dartVersion: dartVersion,
    flutterVersion: flutterVersion,
  );

  final stopwatch = Stopwatch()..start();

  final buildArgs = [
    'build',
    'web',
    '--wasm',
    '--no-web-resources-cdn',
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

bool _validateDeployPrerequisites({bool allowBranch = false}) {
  if (!_isWorkingTreeClean()) {
    stderr.writeln(
      '❌ Deploy build failed: Working tree is dirty. '
      'Commit all changes before deploying.',
    );
    return false;
  }

  final branch = _runGit(['branch', '--show-current']);
  final envAllowBranch = Platform.environment['ALLOW_BRANCH'] == '1';
  if (branch != 'main' && !allowBranch && !envAllowBranch) {
    stderr.writeln(
      '❌ Deploy build failed: Current branch is "$branch" '
      '(expected "main", or pass ALLOW_BRANCH=1 for preview channels).',
    );
    return false;
  }

  return true;
}

void _printBuildHeader({
  required String gitSha,
  required bool isClean,
  required String dartVersion,
  required String flutterVersion,
}) {
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

String? _readJsonField(String path, String key) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json[key] as String?;
  } catch (_) {
    return null;
  }
}

class const FlutterVersionInfo({
  required final String frameworkVersion,
  required final String frameworkRevision,
  required final String engineRevision,
  required final String dartSdkVersion,
}) {
  factory fromJson(Map<String, dynamic> json) {
    return FlutterVersionInfo(
      frameworkVersion: json['frameworkVersion'] as String? ?? '',
      frameworkRevision: json['frameworkRevision'] as String? ?? '',
      engineRevision: json['engineRevision'] as String? ?? '',
      dartSdkVersion: (json['dartSdkVersion'] as String? ?? '')
          .split(' ')
          .first,
    );
  }

  String get formattedFrameworkVersion {
    if (frameworkVersion.isEmpty || frameworkRevision.isEmpty) {
      return frameworkVersion;
    }
    final shortRev = frameworkRevision.length >= 7
        ? frameworkRevision.substring(0, 7)
        : frameworkRevision;
    return '$frameworkVersion ($shortRev)';
  }

  static Future<FlutterVersionInfo?> runFlutterVersionMachine(
    String executable,
  ) async {
    try {
      final result = await Process.run(executable, ['--version', '--machine']);
      if (result.exitCode == 0) {
        final json =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        final info = FlutterVersionInfo.fromJson(json);
        if (info.frameworkVersion.isNotEmpty &&
            info.dartSdkVersion.isNotEmpty) {
          return info;
        }
      }
    } catch (_) {}
    return null;
  }
}

Future<FlutterVersionInfo> _resolveSdkVersions(String executable) async {
  final info = await FlutterVersionInfo.runFlutterVersionMachine(executable);
  if (info != null) {
    return info;
  }

  final flutter =
      _readJsonField(
        '.fvm/flutter_sdk/bin/cache/flutter.version.json',
        'flutterVersion',
      ) ??
      _readJsonField('.fvmrc', 'flutter') ??
      '3.47.0';

  var dart = '';
  final dartJson = _readJsonField(
    '.fvm/flutter_sdk/bin/cache/flutter.version.json',
    'dartSdkVersion',
  );
  if (dartJson != null) dart = dartJson.split(' ').first;

  if (dart.isEmpty) {
    final fvmDartSdk = File('.fvm/flutter_sdk/bin/cache/dart-sdk/version');
    if (fvmDartSdk.existsSync()) {
      try {
        dart = fvmDartSdk.readAsStringSync().trim().split(' ').first;
      } catch (_) {}
    }
  }

  if (dart.isEmpty) dart = Platform.version.split(' ').first;

  return FlutterVersionInfo(
    frameworkVersion: flutter,
    frameworkRevision: '',
    engineRevision: '',
    dartSdkVersion: dart,
  );
}
