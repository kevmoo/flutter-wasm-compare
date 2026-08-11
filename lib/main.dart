import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/metrics/frame_timing_service.dart';
import 'src/scene/adaptive_stress_scene.dart';
import 'src/scene/widget_churn_engine.dart';
import 'src/shell/compatibility_shield.dart';
import 'src/shell/performance_hud.dart';
import 'src/shell/runtime_selector.dart';
import 'src/shell/url_helper.dart';

void main() {
  runApp(const WasmCompareApp());
}

class WasmCompareApp extends StatelessWidget {
  const WasmCompareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => FrameTimingService())],
      child: MaterialApp(
        title: 'Wasm vs JS Compare',
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueAccent,
            brightness: Brightness.dark,
          ),
        ),
        home: const CompatibilityShield(child: DemoDashboard()),
      ),
    );
  }
}

class DemoDashboard extends StatefulWidget {
  const DemoDashboard({super.key});

  @override
  State<DemoDashboard> createState() => _DemoDashboardState();
}

class _DemoDashboardState extends State<DemoDashboard> {
  late StressLevel _stressLevel;

  @override
  void initState() {
    super.initState();
    _stressLevel = _parseInitialStressLevel();
  }

  static StressLevel _parseInitialStressLevel() {
    final query = Uri.base.queryParameters['stress'];
    if (query != null) {
      for (final level in StressLevel.values) {
        if (level.name.toLowerCase() == query.toLowerCase()) {
          return level;
        }
      }
    }
    return StressLevel.medium;
  }

  void _onStressChanged(StressLevel? val) {
    if (val != null && val != _stressLevel) {
      setState(() => _stressLevel = val);
      updateUrlQueryParam('stress', val.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wasm vs JS Performance'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButton<StressLevel>(
              value: _stressLevel,
              onChanged: _onStressChanged,
              items: StressLevel.values.map((level) {
                return DropdownMenuItem(
                  value: level,
                  child: Text('Stress: ${level.name}'),
                );
              }).toList(),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AdaptiveStressScene(stressLevel: _stressLevel),
          ),
          Positioned(
            top: 20,
            left: 20,
            child: PerformanceHud(currentStressLevel: _stressLevel.name),
          ),
          const Positioned(top: 20, right: 20, child: RuntimeSelector()),
        ],
      ),
    );
  }
}
