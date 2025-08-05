import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/services/visualizer_provider.dart';

class EffectsPage extends StatelessWidget {
  const EffectsPage({super.key});

  void resetEffect(BuildContext context, LedEffect effect) {
    final provider = context.read<VisualizerProvider>();
    provider.resetEffect(effect);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VisualizerProvider>();
    final effects = provider.effects;

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: effects.length,
      itemBuilder: (context, effectIndex) {
        final effect = effects[effectIndex];

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with name and reset button
                Row(
                  children: [
                    Icon(
                      Icons.animation,
                      size: 28,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        effect.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => resetEffect(context, effect),
                      icon: const Icon(Icons.restore),
                      tooltip: 'Reset to default',
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Sliders for each parameter
                ...effect.parameters.entries.map((entry) {
                  final key = entry.key;
                  final param = entry.value;

                  final double min = (param["min"] ?? 0.0).toDouble();
                  final double max = (param["max"] ?? 1.0).toDouble();
                  final double currentValue = (param["value"] ?? 0.0).toDouble();
                  final double defaultValue = (param["default"] ?? 0.0).toDouble();
                  final int steps = (param["steps"] ?? 20).toInt();

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 100, child: Text(key)),
                        Text(currentValue.toStringAsFixed(2)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            value: currentValue,
                            min: min,
                            max: max,
                            divisions: steps,
                            onChanged: (val) {
                              context.read<VisualizerProvider>().updateEffect(
                                    effect,
                                    key,
                                    {
                                      "min": min,
                                      "max": max,
                                      "value": val,
                                      "steps": steps,
                                      "default": defaultValue,
                                    },
                                  );
                            },
                          ),
                        ),
                        Text(max.toStringAsFixed(1)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
