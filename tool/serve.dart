import 'dart:async';
import 'dart:io';

const _defaultPort = 8080;

final _mimeTypes = <String, String>{
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

Future<void> main(List<String> args) async {
  final noBuild = args.contains('--no-build');
  final portIndex = args.indexOf('--port');
  final port = (portIndex != -1 && portIndex + 1 < args.length)
      ? int.tryParse(args[portIndex + 1]) ?? _defaultPort
      : _defaultPort;

  final webDir = Directory('build/web');

  if (!noBuild || !webDir.existsSync()) {
    final success = await _buildWeb();
    if (!success) {
      exitCode = 1;
      return;
    }
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final url = 'http://localhost:${server.port}';

  print('\n🚀 Serving ${webDir.path} at $url');
  print('   Headers: COOP & COEP enabled for WebAssembly multithreading');
  print('   Commands: [r] Rebuild  [o] Open browser  [q] Quit\n');

  _handleRequests(server, webDir);
  _handleTerminalInput(url);
}

Future<bool> _buildWeb() async {
  print('🔨 Building Flutter Web (Wasm + JS fallback)...');
  final stopwatch = Stopwatch()..start();

  final process = await Process.start(
    'flutter',
    ['build', 'web', '--wasm'],
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );

  final exit = await process.exitCode;
  stopwatch.stop();

  if (exit == 0) {
    print('✅ Build complete in ${stopwatch.elapsed.inSeconds}s.\n');
    return true;
  } else {
    print('❌ Build failed with exit code $exit.\n');
    return false;
  }
}

void _handleRequests(HttpServer server, Directory webDir) {
  server.listen((HttpRequest request) async {
    final response = request.response;

    response.headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    response.headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
    response.headers.set(
      'Cache-Control',
      'no-cache, no-store, must-revalidate',
    );

    final file = await _resolveFile(webDir, request.uri.path);
    if (file == null) {
      response.statusCode = HttpStatus.notFound;
      response.write('404 Not Found');
      await response.close();
      return;
    }

    final ext = file.path.contains('.')
        ? '.${file.path.split('.').last.toLowerCase()}'
        : '';
    final mimeType = _mimeTypes[ext] ?? 'application/octet-stream';
    response.headers.set('Content-Type', mimeType);

    await response.addStream(file.openRead());
    await response.close();
  });
}

Future<File?> _resolveFile(Directory webDir, String uriPath) async {
  final decoded = Uri.decodeComponent(uriPath);
  final relativePath = decoded == '/' ? 'index.html' : decoded.substring(1);
  final directFile = File('${webDir.path}/$relativePath');

  if (await directFile.exists()) {
    return directFile;
  }

  // SPA fallback
  final indexFile = File('${webDir.path}/index.html');
  if (await indexFile.exists()) {
    return indexFile;
  }

  return null;
}

void _handleTerminalInput(String url) {
  if (!stdin.hasTerminal) return;

  try {
    stdin.lineMode = false;
    stdin.echoMode = false;
  } catch (_) {
    return;
  }

  var isBuilding = false;
  stdin.listen((List<int> bytes) async {
    for (final char in bytes) {
      isBuilding = await _processKey(char, url, isBuilding);
    }
  });
}

Future<bool> _processKey(int char, String url, bool isBuilding) async {
  final key = String.fromCharCode(char).toLowerCase();
  switch (key) {
    case 'r':
      if (isBuilding) {
        print('⏳ Build already in progress...');
        return true;
      }
      await _buildWeb();
      return false;
    case 'o':
      _openBrowser(url);
      return isBuilding;
    case 'q' || _ when char == 3:
      print('\n👋 Exiting serve.');
      exit(0);
    default:
      return isBuilding;
  }
}

void _openBrowser(String url) {
  print('🌐 Opening $url');
  final (command, args) = switch (Platform.operatingSystem) {
    'macos' => ('open', [url]),
    'linux' => ('xdg-open', [url]),
    'windows' => ('cmd', ['/c', 'start', url]),
    _ => (null, <String>[]),
  };

  if (command != null) {
    unawaited(Process.run(command, args));
  }
}
