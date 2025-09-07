import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/services/visualizer_provider.dart';

import '../effects/effects.dart';

class EffectsPage extends StatelessWidget {
  const EffectsPage({super.key});

  void resetEffect(BuildContext context, LedEffect effect) {
    context.read<VisualizerProvider>().resetEffect(effect);
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Header row ---
                Row(
                  children: [
                    Icon(Icons.animation,
                        size: 28,
                        color: Theme.of(context).colorScheme.primary),
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
                    IconButton(
                      onPressed: () => resetEffect(context, effect),
                      icon: const Icon(Icons.restore),
                      tooltip: 'Reset to default',
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // --- Parameters ---
                ...effect.parameters.entries.map((entry) {
                  final key = entry.key;
                  final param = entry.value;

                  switch (param.type) {
                    case EffectParameterType.number:
                      final double min = param.min ?? 0.0;
                      final double max = param.max ?? 1.0;
                      final double currentValue = param.value ?? 0.0;
                      final int steps = param.steps ?? 20;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(width: 100, child: Text(param.name)),
                            Text(currentValue.toStringAsFixed(2)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Slider(
                                value: currentValue,
                                min: min,
                                max: max,
                                divisions: steps,
                                onChanged: (val) {
                                  context
                                      .read<VisualizerProvider>()
                                      .updateEffect(
                                    effect,
                                    key,
                                    param.copyWith(value: val),
                                  );
                                },
                              ),
                            ),
                            Text(max.toStringAsFixed(1)),
                          ],
                        ),
                      );

                    case EffectParameterType.option:
                      final List<String> options =
                      List<String>.from(param.options ?? []);
                      final String currentOption =
                          param.value ?? options.first;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(width: 100, child: Text(param.name)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<String>(
                                value: currentOption,
                                isExpanded: true,
                                items: options.map((option) {
                                  return DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    context
                                        .read<VisualizerProvider>()
                                        .updateEffect(
                                      effect,
                                      key,
                                      param.copyWith(value: val),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      );

                    default:
                      return const SizedBox.shrink();
                  }
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
