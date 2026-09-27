import 'dart:js_interop';

import 'build_info.dart';

@JS('window._flutterWasmCompareBuildInfo')
external set _flutterWasmCompareBuildInfo(JSObject value);

void exposeBuildInfoToWindow() {
  _flutterWasmCompareBuildInfo =
      {
            'gitSha': BuildInfoAccessor.gitSha,
            'flutterVersion': BuildInfoAccessor.flutterVersion,
            'dartVersion': BuildInfoAccessor.dartVersion,
            'isCleanBuild': BuildInfoAccessor.isCleanBuild,
          }.jsify()
          as JSObject;
}
