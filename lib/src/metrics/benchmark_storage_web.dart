import 'dart:convert';

import 'package:web/web.dart' as web;

import 'benchmark_run.dart';

class BenchmarkStoragePersistence() {
  static const String _activeNodesKey = 'wasm_compare_active_node_count';
  static const String _activeWorkloadKey = 'wasm_compare_active_workload_id';
  static const String _wasmRunKey = 'wasm_compare_last_wasm_run';
  static const String _wimpRunKey = 'wasm_compare_last_wimp_run';
  static const String _jsRunKey = 'wasm_compare_last_js_run';
  static const String _webParagraphRunKey =
      'wasm_compare_last_webparagraph_run';

  static String _nodesKeyFor(String workloadId) =>
      '${_activeNodesKey}_$workloadId';
  static String _runKeyFor(String baseKey, String workloadId) =>
      '${baseKey}_$workloadId';

  static void loadAll(
    Map<String, int> nodesByWorkload,
    Map<String, BenchmarkRun> wasmRuns,
    Map<String, BenchmarkRun> wimpRuns,
    Map<String, BenchmarkRun> jsRuns,
    Map<String, BenchmarkRun> webParagraphRuns,
    BenchmarkRun? Function(Map<String, dynamic>) parseRun,
  ) {
    try {
      final storage = web.window.localStorage;
      for (final workloadId in const ['bouncy', 'grid']) {
        final nodesStr = storage.getItem(_nodesKeyFor(workloadId));
        final nodes = nodesStr != null ? int.tryParse(nodesStr) : null;
        if (nodes != null) {
          nodesByWorkload[workloadId] = nodes;
        }
        _loadCachedRun(storage, _wasmRunKey, workloadId, wasmRuns, parseRun);
        _loadCachedRun(storage, _wimpRunKey, workloadId, wimpRuns, parseRun);
        _loadCachedRun(storage, _jsRunKey, workloadId, jsRuns, parseRun);
        _loadCachedRun(
          storage,
          _webParagraphRunKey,
          workloadId,
          webParagraphRuns,
          parseRun,
        );
      }
    } catch (_) {
      // Ignore
    }
  }

  static void _loadCachedRun(
    web.Storage storage,
    String baseKey,
    String workloadId,
    Map<String, BenchmarkRun> targetCache,
    BenchmarkRun? Function(Map<String, dynamic>) parseRun,
  ) {
    final rawStr = storage.getItem(_runKeyFor(baseKey, workloadId));
    if (rawStr == null || rawStr.isEmpty) return;
    final parsed = parseRun(jsonDecode(rawStr) as Map<String, dynamic>);
    if (parsed != null) {
      targetCache[workloadId] = parsed;
    }
  }

  static void clearWorkload(String workloadId) {
    try {
      final storage = web.window.localStorage;
      storage.removeItem(_nodesKeyFor(workloadId));
      for (final key in const [
        _wasmRunKey,
        _wimpRunKey,
        _jsRunKey,
        _webParagraphRunKey,
      ]) {
        storage.removeItem(_runKeyFor(key, workloadId));
      }
    } catch (_) {
      // Ignore
    }
  }

  static void clearAll() {
    try {
      final storage = web.window.localStorage;
      storage.removeItem(_activeNodesKey);
      storage.removeItem(_activeWorkloadKey);
      for (final key in const [
        _wasmRunKey,
        _wimpRunKey,
        _jsRunKey,
        _webParagraphRunKey,
      ]) {
        storage.removeItem(key);
      }
      for (final id in const ['bouncy', 'grid']) {
        clearWorkload(id);
      }
    } catch (_) {
      // Ignore
    }
  }

  static void saveRun({
    required String baseKey,
    required String workloadId,
    required int nodeCount,
    required String jsonStr,
  }) {
    try {
      final storage = web.window.localStorage;
      storage.setItem(_activeNodesKey, '$nodeCount');
      storage.setItem(_nodesKeyFor(workloadId), '$nodeCount');
      storage.setItem(_activeWorkloadKey, workloadId);
      storage.setItem(baseKey, jsonStr);
      storage.setItem(_runKeyFor(baseKey, workloadId), jsonStr);
    } catch (_) {
      // Ignore
    }
  }
}
