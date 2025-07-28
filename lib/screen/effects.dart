import 'package:flutter/material.dart';
import 'package:udp_master/visualizer_provider.dart';

class EffectsPage extends StatefulWidget {
  final VisualizerProvider visualizerProvider;
  const EffectsPage({super.key, required this.visualizerProvider});

  @override
  State<EffectsPage> createState() => _EffectsPageState();
}

class _EffectsPageState extends State<EffectsPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.visualizerProvider.effects.length,
        itemBuilder: (context, index) {
          final effect = widget.visualizerProvider.effects[index];
          return Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 18.0,
                horizontal: 18.0,
              ),
              child: Column(
                spacing: 4,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    spacing: 16,
                    children: [
                      Icon(
                        Icons.animation,
                        size: 28,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      Text(
                        effect.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: effect.parameters.length,
                    itemBuilder: (context, index) {
                      final parameter = effect.parameters.entries.elementAt(
                        index,
                      );
                      final key = parameter.key;
                      final value = parameter.value;
                      final min = value["min"];
                      final max = value["max"];
                      final steps = value["steps"] ?? 20;
                      final currentValue = value["value"];
                      return Row(
                        spacing: 8,
                        children: [
                          SizedBox(width: 100, child: Text(key)),
                          Text(currentValue.toStringAsFixed(2)),
                          Expanded(
                            child: Slider(
                              divisions: steps,
                              value: currentValue,
                              min: min,
                              max: max,
                              onChanged: (val) {
                                widget.visualizerProvider
                                    .updateEffect(effect, key, {
                                      "min": value["min"],
                                      "max": value["max"],
                                      "value": val,
                                      "steps": value["steps"],
                                    });
                              },
                            ),
                          ),
                          Text(max.toString()),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
