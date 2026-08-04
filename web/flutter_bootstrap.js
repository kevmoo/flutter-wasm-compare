{{flutter_js}}
const searchParams = new URLSearchParams(window.location.search);
let mode = searchParams.get("mode") || "auto";

const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);
const isFirefox = /firefox/i.test(navigator.userAgent);
const isExperimentalWasm = isSafari || isFirefox;
const optin = searchParams.get("optin") === "true";

let forceCanvasKit = false;

if ((mode === "wasm" || mode === "skwasm" || mode === "auto") && isExperimentalWasm && !optin) {
  forceCanvasKit = true;
  // Expose blocked state to Dart side
  window.experimentallyBlocked = true;
}

if (mode === "js" || mode === "canvaskit") {
  forceCanvasKit = true;
}

const config = {};
if (forceCanvasKit) {
  // Try to force canvaskit. 
} 

_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    const runConfig = forceCanvasKit ? { renderer: "canvaskit" } : {};
    const appRunner = await engineInitializer.initializeEngine(runConfig);
    await appRunner.runApp();
  }
});
