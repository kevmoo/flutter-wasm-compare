# Flutter WebAssembly vs JavaScript Comparison

An interactive, responsive performance benchmark comparing Flutter compiled to
**WebAssembly** against **JavaScript**.

**Live Demo**: [https://flutter-wasm-compare.web.app](https://flutter-wasm-compare.web.app)

---

## Features

- **Side-by-Side Performance HUD**: Dedicated dual mini-cards displaying
  real-time metrics (FPS, Total Frame, Build Time, and Raster Time) comparing
  Wasm (left) against JS (right).
- **Adaptive Stress Scenes**: Configurable UI load (from 0 to 4,000 animated
  churn nodes) testing widget tree rebuilding, layout recalculation, and raster
  costs.
- **Dynamic Auto-Tuning**: Automatically ramps workload to pinpoint the exact
  threshold where framerate drops below the target refresh rate (60 Hz / 120 Hz).
- **Responsive Layout**: Adapts between compact single-column mobile viewports
  and wide desktop multi-column grids.
- **Persisted State**: Engine benchmarks and HUD expand/collapse states persist
  across runtime engine reloads.

---

## Requirements for WebAssembly

Flutter WebAssembly multi-threading requires `SharedArrayBuffer` support.
Web servers hosting the application must set the following HTTP response
headers:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

---

## Development

### Run Locally

Use the local Dart development server to serve the build with required
COOP/COEP headers:

```bash
# Build WASM and serve locally on port 8088
dart run tool/serve.dart --port 8088
```

### Build for Production

```bash
flutter build web --wasm --source-maps --dump-info
```

### Deploy to Firebase Hosting

```bash
firebase deploy --only hosting
```
