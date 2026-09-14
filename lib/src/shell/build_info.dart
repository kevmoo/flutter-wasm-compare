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
  final bool? isWasmOverride;
  final bool? isWimpOverride;
  final bool? isSingleThreadedOverride;
  final bool? hasGitInfoOverride;

  const BuildInfoDialog({
    super.key,
    this.isWasmOverride,
    this.isWimpOverride,
    this.isSingleThreadedOverride,
    this.hasGitInfoOverride,
  });

  @override
  Widget build(BuildContext context) {
    final isWasm = isWasmOverride ?? isCurrentlyWasm();
    final isWimp = isWimpOverride ?? isCurrentlyWimp();
    final isSingleThreaded =
        isSingleThreadedOverride ?? isCurrentlySingleThreaded();
    final hasGitInfo = hasGitInfoOverride ?? BuildInfo.hasGitInfo;
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
              child: _buildCommitValue(hasGitInfo),
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
              child: Text(
                _activeEngineLabel(
                  isWasm: isWasm,
                  isWimp: isWimp,
                  isSingleThreaded: isSingleThreaded,
                ),
                style: TextStyle(
                  color: isWasm
                      ? Colors.lightBlueAccent
                      : const Color(0xFFF1E05A),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            if (isWasm) ...[
              const SizedBox(height: 8),
              _BuildInfoRow(
                label: 'Renderer',
                child: Text(
                  isWimp
                      ? 'Impeller (wimp.wasm) • Experimental'
                      : 'Skia (skwasm.wasm)',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              _BuildInfoRow(
                label: 'Threading',
                child: _buildThreadingValue(
                  context,
                  isWimp: isWimp,
                  isSingleThreaded: isSingleThreaded,
                ),
              ),
            ],
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

  static String _activeEngineLabel({
    required bool isWasm,
    required bool isWimp,
    required bool isSingleThreaded,
  }) => switch ((isWasm, isWimp, isSingleThreaded)) {
    (false, _, _) => '📜 JS (CanvasKit)',
    (true, true, true) => '⚡ WASM + Impeller (Exp, ST)',
    (true, true, false) => '⚡ WASM + Impeller (Exp)',
    (true, false, true) => '⚡ WASM + Skia (ST)',
    (true, false, false) => '⚡ WASM + Skia',
  };

  Widget _buildCommitValue(bool hasGitInfo) {
    if (!hasGitInfo) {
      return const Text(
        'local-dev',
        style: TextStyle(
          color: Colors.white54,
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      );
    }
    return InkWell(
      onTap: () => openExternalUrl(BuildInfo.commitUrl),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              BuildInfo.shortSha.isEmpty ? '4867f6c' : BuildInfo.shortSha,
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
    );
  }

  Widget _buildThreadingValue(
    BuildContext context, {
    required bool isWimp,
    required bool isSingleThreaded,
  }) {
    if (isWimp) {
      return const Text(
        'Single-threaded (forced by engine)',
        style: TextStyle(fontFamily: 'monospace', fontSize: 13),
      );
    }
    return Tooltip(
      message: 'Press Ctrl+Shift+S (or ⌘+Shift+S) to toggle',
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        label: Text(
          isSingleThreaded
              ? 'Single-threaded (Toggle)'
              : 'Multi-threaded (Toggle)',
          style: const TextStyle(fontSize: 11),
        ),
        onPressed: () {
          Navigator.of(context).pop();
          toggleSingleThreadedMode(context);
        },
      ),
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
