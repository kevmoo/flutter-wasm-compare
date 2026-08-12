{{flutter_js}}
{{flutter_build_config}}

const searchParams = new URLSearchParams(window.location.search);
let mode = searchParams.get("mode") || "auto";

const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);
const isFirefox = /firefox/i.test(navigator.userAgent);
const isExperimentalWasm = isSafari || isFirefox;
const optin = searchParams.get("optin") === "true";

let forceCanvasKit = false;

if ((mode === "wasm" || mode === "skwasm" || mode === "auto") && isExperimentalWasm && !optin) {
  forceCanvasKit = true;
  window.experimentallyBlocked = true;
}

if (mode === "js" || mode === "canvaskit") {
  forceCanvasKit = true;
}

const userConfig = {'wasmAllowList': {'gecko': true, 'webkit': true}};
if (forceCanvasKit) {
  userConfig.renderer = "canvaskit";
} else if (mode === "skwasm-st") {
  userConfig.forceSingleThreadedSkwasm = true;
} else if (mode === "wimp") {
  userConfig.enableWimp = true;
}

const tBootstrap = performance.now();
window._flutterTimings = {
  bootstrapStart: tBootstrap,
  entrypointLoaded: 0,
  engineInitialized: 0,
  firstFrame: 0,
};

_flutter.loader.load({
  config: userConfig,
  onEntrypointLoaded: async function(engineInitializer) {
    window._flutterTimings.entrypointLoaded = performance.now();
    const appRunner = await engineInitializer.initializeEngine();
    window._flutterTimings.engineInitialized = performance.now();
    await appRunner.runApp();
  }
});
