import 'benchmark_run.dart';

class BenchmarkStoragePersistence() {
  static void loadAll(
    Map<String, int> nodesByWorkload,
    Map<String, Map<String, BenchmarkRun>> runsByKey,
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
