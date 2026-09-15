import 'benchmark_run.dart';

class BenchmarkStoragePersistence() {
  static void loadAll(
    Map<String, int> nodesByWorkload,
    Map<String, BenchmarkRun> wasmRuns,
    Map<String, BenchmarkRun> wimpRuns,
    Map<String, BenchmarkRun> jsRuns,
    Map<String, BenchmarkRun> webParagraphRuns,
    BenchmarkRun? Function(Map<String, dynamic>) parseRun,
  ) {}

  static void clearWorkload(String workloadId) {}

  static void clearAll() {}

  static void saveRun({
    required String baseKey,
    required String workloadId,
    required int nodeCount,
    required String jsonStr,
  }) {}
}
