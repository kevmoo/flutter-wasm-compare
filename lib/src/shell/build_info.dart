import 'package:flutter/material.dart';

import 'engine_mode.dart';
import 'url_helper.dart';

class BuildInfo {
  static const gitSha = String.fromEnvironment('GIT_SHA', defaultValue: '');
  static const dartVersion = String.fromEnvironment(
    'DART_VERSION',
    defaultValue: '',
  );
  static const flutterVersion = String.fromEnvironment(
    'FLUTTER_SDK_VERSION',
    defaultValue: '',
  );
  static const isCleanBuild = bool.fromEnvironment(
    'IS_CLEAN_BUILD',
    defaultValue: false,
  );

  static bool get hasGitInfo => gitSha.isNotEmpty;
  static String get shortSha {
    if (gitSha.isEmpty) return 'local-dev';
    final base = gitSha.length >= 7 ? gitSha.substring(0, 7) : gitSha;
    return isCleanBuild ? base : '$base (dirty)';
  }

  static String get commitUrl =>
      'https://github.com/kevmoo/flutter-wasm-compare/commit/$gitSha';
  static const repoUrl = 'https://github.com/kevmoo/flutter-wasm-compare';
}

class BuildInfoButton extends StatelessWidget {
  final bool isCompact;

  const BuildInfoButton({super.key, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 20),
      tooltip: 'About & Build Info',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => const BuildInfoDialog(),
      ),
    );
  }
}

class BuildInfoDialog extends StatelessWidget {
  const BuildInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final isWasm = isCurrentlyWasm();
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.info_outline, size: 22, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text('About & Build Info', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Flutter Wasm vs JS Performance Comparison Benchmark',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),
            _BuildInfoRow(
              label: 'Commit',
              child: BuildInfo.hasGitInfo
                  ? InkWell(
                      onTap: () => openExternalUrl(BuildInfo.commitUrl),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              BuildInfo.shortSha,
                              style: const TextStyle(
                                color: Colors.lightBlueAccent,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.open_in_new,
                              size: 13,
                              color: Colors.lightBlueAccent,
                            ),
                          ],
                        ),
                      ),
                    )
                  : const Text(
                      'local-dev',
                      style: TextStyle(
                        color: Colors.white54,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
            ),
            if (BuildInfo.dartVersion.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _BuildInfoRow(
                label: 'Dart SDK',
                child: Text(
                  BuildInfo.dartVersion,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ],
            if (BuildInfo.flutterVersion.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _BuildInfoRow(
                label: 'Flutter SDK',
                child: Text(
                  BuildInfo.flutterVersion,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _BuildInfoRow(
              label: 'Active Engine',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isWasm ? '⚡ WASM (Skwasm)' : '📜 JS (CanvasKit)',
                    style: TextStyle(
                      color: isWasm
                          ? Colors.lightBlueAccent
                          : const Color(0xFFF1E05A),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _BuildInfoRow(
              label: 'Repository',
              child: InkWell(
                onTap: () => openExternalUrl(BuildInfo.repoUrl),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GitHub',
                        style: TextStyle(
                          color: Colors.lightBlueAccent,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new,
                        size: 13,
                        color: Colors.lightBlueAccent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _BuildInfoRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _BuildInfoRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Align(alignment: Alignment.centerRight, child: child),
        ),
      ],
    );
  }
}
