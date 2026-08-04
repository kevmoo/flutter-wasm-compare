import 'package:flutter/material.dart';
import 'package:wasm_compare/src/scene/widget_churn_engine.dart';

class AdaptiveStressScene extends StatelessWidget {
  final StressLevel stressLevel;

  const AdaptiveStressScene({super.key, required this.stressLevel});

  @override
  Widget build(BuildContext context) {
    return WidgetChurnEngine(
      stressLevel: stressLevel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;

          return Container(
            color: Theme.of(context).colorScheme.surface,
            child: isMobile
                ? _buildMobileView(context)
                : _buildDesktopView(context),
          );
        },
      ),
    );
  }

  Widget _buildMobileView(BuildContext context) {
    return ListView.builder(
      itemCount: 50,
      itemBuilder: (context, index) => _buildMockCard(context, index),
    );
  }

  Widget _buildDesktopView(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 1.5,
      ),
      itemCount: 200,
      itemBuilder: (context, index) => _buildMockCard(context, index),
    );
  }

  Widget _buildMockCard(BuildContext context, int index) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 20,
              width: 150,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
