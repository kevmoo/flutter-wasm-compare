import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'url_helper.dart';

@JS('window.experimentallyBlocked')
external bool? get _experimentallyBlocked;

class CompatibilityShield extends StatelessWidget {
  final Widget child;

  const CompatibilityShield({super.key, required this.child});

  bool get isBlocked {
    return _experimentallyBlocked == true;
  }

  @override
  Widget build(BuildContext context) {
    if (!isBlocked) return child;

    return Stack(
      children: [
        child,
        Container(
          color: Colors.black.withValues(alpha: 0.8),
          alignment: Alignment.center,
          child: AlertDialog(
            title: const Text('Experimental WebAssembly'),
            content: const Text(
              'WebAssembly rendering on Safari/Firefox is experimental. '
              'Click [Test Wasm Now] to reload with Wasm enabled '
              '(may cause visual artifacts or instability).',
            ),
            actions: [
              TextButton(
                onPressed: () => reloadWithQueryParams({'mode': 'js'}),
                child: const Text('Stay on JS (Safe)'),
              ),
              ElevatedButton(
                onPressed: () =>
                    reloadWithQueryParams({'optin': 'true', 'mode': 'wasm'}),
                child: const Text('Test Wasm Now'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
