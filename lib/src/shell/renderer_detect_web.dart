import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('window._flutter_skwasmInstance')
external _SkwasmInstance? get _skwasmInstance;

extension type _SkwasmInstance(JSObject _) implements JSObject {
  external _WasmExports? get wasmExports;
}

extension type _WasmExports(JSObject _) implements JSObject {
  @JS('skwasm_isWimp')
  external JSNumber? isWimp();
}

bool get isWimpActive {
  try {
    final exports = _skwasmInstance?.wasmExports;
    if (exports != null) {
      final res = exports.isWimp();
      if (res != null) return res.toDartInt == 1;
    }
  } catch (_) {}
  final modeParam = Uri.base.queryParameters['mode']?.toLowerCase();
  return modeParam == 'wimp' || modeParam == 'impeller';
}

bool get isChromiumBrowser {
  try {
    final vendor = web.window.navigator.vendor;
    final ua = web.window.navigator.userAgent;
    return vendor == 'Google Inc.' || ua.contains('Edg/');
  } catch (_) {
    return false;
  }
}

bool get isSafariBrowser {
  try {
    final ua = web.window.navigator.userAgent;
    return RegExp(
      r'^((?!chrome|android).)*safari',
      caseSensitive: false,
    ).hasMatch(ua);
  } catch (_) {
    return false;
  }
}

bool get isFirefoxBrowser {
  try {
    return web.window.navigator.userAgent.toLowerCase().contains('firefox');
  } catch (_) {
    return false;
  }
}

bool get isWimpSupportedInBrowser => isChromiumBrowser;
