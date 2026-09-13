{{flutter_js}}
{{flutter_build_config}}

const searchParams = new URLSearchParams(window.location.search);
const modeParam = searchParams.get("mode");
let mode = modeParam;
if (!mode) {
  try {
    mode = localStorage.getItem("wasm_compare_engine_mode") || "auto";
  } catch (_) {
    mode = "auto";
  }
} else {
  try {
    localStorage.setItem("wasm_compare_engine_mode", mode);
  } catch (_) {}
}

const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);
const isFirefox = /firefox/i.test(navigator.userAgent);
const isExperimentalWasm = isSafari || isFirefox;
const optin = searchParams.get("optin") === "true";

let forceCanvasKit = false;

if ((mode === "wasm" || mode === "skwasm" || mode === "wimp" || mode === "impeller" || mode === "auto") && isExperimentalWasm && !optin) {
  forceCanvasKit = true;
  window.experimentallyBlocked = true;
}

if (mode === "js" || mode === "canvaskit") {
  forceCanvasKit = true;
}

const stParam = searchParams.get("st") || searchParams.get("single_threaded");
const isExplicitSt = stParam === "1" || stParam === "true" || mode === "skwasm-st";
const isExplicitMt = stParam === "0" || stParam === "false" || mode === "skwasm-mt";
let isSingleThreaded = false;

try {
  if (isExplicitSt) {
    isSingleThreaded = true;
    localStorage.setItem("wasm_compare_single_threaded", "true");
  } else if (isExplicitMt) {
    isSingleThreaded = false;
    localStorage.setItem("wasm_compare_single_threaded", "false");
  } else {
    isSingleThreaded = localStorage.getItem("wasm_compare_single_threaded") === "true";
  }
} catch (_) {
  isSingleThreaded = isExplicitSt;
}

const userConfig = {'wasmAllowList': {'gecko': true, 'webkit': true}};
if (forceCanvasKit) {
  userConfig.renderer = "canvaskit";
} else {
  if (isSingleThreaded || mode === "skwasm-st") {
    userConfig.forceSingleThreadedSkwasm = true;
  }
  if (mode === "wimp" || mode === "impeller") {
    userConfig.enableWimp = true;
  }
}

_flutter.loader.load({
  config: userConfig,
  serviceWorkerSettings: null,
});



