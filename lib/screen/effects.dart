import 'package:flutter/material.dart';
import 'package:udp_master/visualizer_provider.dart';

class EffectsPage extends StatelessWidget {
  final VisualizerProvider visualizerProvider;
  const EffectsPage({super.key, required this.visualizerProvider});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: visualizerProvider.effects.length,
      itemBuilder: (context, effectIndex) {
        final effect = visualizerProvider.effects[effectIndex];

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...effect.parameters.entries.map((entry) {
                  final key = entry.key;
                  final value = entry.value;
                  final double min = value["min"];
                  final double max = value["max"];
                  final int steps = value["steps"] ?? 20;
                  final double currentValue = value["value"];

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
                              visualizerProvider.updateEffect(effect, key, {
                                "min": min,
                                "max": max,
                                "value": val,
                                "steps": steps,
                              });
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
