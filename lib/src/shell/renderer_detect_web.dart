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
  return false;
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

bool get isWimpSupportedInBrowser => isChromiumBrowser;
