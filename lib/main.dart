import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wasm_compare/src/metrics/frame_timing_service.dart';
import 'package:wasm_compare/src/scene/adaptive_stress_scene.dart';
import 'package:wasm_compare/src/scene/widget_churn_engine.dart';
import 'package:wasm_compare/src/shell/compatibility_shield.dart';
import 'package:wasm_compare/src/shell/performance_hud.dart';
import 'package:wasm_compare/src/shell/runtime_selector.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => FrameTimingService())],
      child: const WasmCompareApp(),
    ),
  );
}

class WasmCompareApp extends StatelessWidget {
  const WasmCompareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wasm vs JS Compare',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const CompatibilityShield(child: DemoDashboard()),
    );
  }
}

class DemoDashboard extends StatefulWidget {
  const DemoDashboard({super.key});

  @override
  State<DemoDashboard> createState() => _DemoDashboardState();
}

class _DemoDashboardState extends State<DemoDashboard> {
  StressLevel _stressLevel = StressLevel.medium;

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
              onChanged: (val) {
                if (val != null) {
                  setState(() => _stressLevel = val);
                }
              },
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
          const Positioned(top: 20, left: 20, child: PerformanceHud()),
          const Positioned(top: 20, right: 20, child: RuntimeSelector()),
        ],
      ),
    );
  }
}
