import 'dart:js_interop';

@JS('window._flutter')
external _Flutter? get _flutter;

extension type _Flutter(JSObject _) implements JSObject {
  external _BuildConfig? get buildConfig;
}

extension type _BuildConfig(JSObject _) implements JSObject {
  external JSArray<_BuildDescription>? get builds;
}

extension type _BuildDescription(JSObject _) implements JSObject {
  external String? get compileTarget;
}

Set<String> get availableTargets {
  final builds = _flutter?.buildConfig?.builds?.toDart;
  if (builds == null) return const {};
  return builds.map((b) => b.compileTarget).whereType<String>().toSet();
}
