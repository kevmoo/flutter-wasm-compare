import 'package:flutter/material.dart';

import 'widget_churn_engine.dart';

const double largeScreenMinWidth = 600.0;

class AdaptiveStressScene extends StatelessWidget {
  final int nodeCount;

  const AdaptiveStressScene({super.key, required this.nodeCount});

  @override
  Widget build(BuildContext context) {
    return WidgetChurnEngine(
      nodeCount: nodeCount,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLarge = constraints.maxWidth >= largeScreenMinWidth;

          return Container(
            color: Theme.of(context).colorScheme.surface,
            child: isLarge
                ? _buildDesktopView(context)
                : _buildMobileView(context),
          );
        },
      ),
    );
  }

  Widget _buildMobileView(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeScreenMinWidth),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          itemCount: 50,
          itemBuilder: _buildMockCard,
        ),
      ),
    );
  }

  Widget _buildDesktopView(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 200,
      itemBuilder: _buildMockCard,
    );
  }

  Widget _buildMockCard(BuildContext context, int index) {
    return SizedBox(
      height: 120,
      child: Card(
        margin: const EdgeInsets.all(4.0),
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
      ),
    );
  }
}
