import 'package:flutter/foundation.dart';

bool isCurrentlyWasm() {
  if (kIsWeb) {
    final mode = Uri.base.queryParameters['mode'];
    if (mode == 'js' || mode == 'canvaskit') return false;
    if (mode == 'wasm' || mode == 'skwasm') return true;
    return kIsWasm;
  }
  return true;
}
