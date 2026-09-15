import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('window._flutter_skwasmInstance')
external _SkwasmInstance? get _skwasmInstance;

@JS('window.TextCluster')
external JSAny? get _textClusterConstructor;

@JS('window.flutterCanvasKit')
external _CanvasKitInstance? get _canvasKitInstance;

extension type _SkwasmInstance(JSObject _) implements JSObject {
  external _WasmExports? get wasmExports;
}

extension type _WasmExports(JSObject _) implements JSObject {
  @JS('skwasm_isWimp')
  external JSNumber? isWimp();
}

extension type _CanvasKitInstance(JSObject _) implements JSObject {
  @JS('Bidi')
  external JSAny? get bidi;
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

bool get isWebParagraphActive {
  try {
    return _canvasKitInstance?.bidi != null;
  } catch (_) {}
  return false;
}

bool get isWebParagraphSupportedInBrowser {
  try {
    return isChromiumBrowser && _textClusterConstructor != null;
  } catch (_) {
    return false;
  }
}
