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
    return ListView.builder(
      padding: EdgeInsets.all(16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.visualizerProvider.availableEffects.length,
      itemBuilder: (context, index) {
        final effect = widget.visualizerProvider.availableEffects[index];
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 18.0,
              horizontal: 18.0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: Device details, spaced between
                Expanded(
                  child: Column(
                    spacing: 4,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        spacing: 4,
                        children: [
                          Icon(
                            Icons.animation,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          Text(
                            effect.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        spacing: 4,
                        children: [
                          Icon(
                            Icons.lan,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          Text(
                            effect.id,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                      Row(
                        spacing: 4,
                        children: [
                          Icon(
                            Icons.linear_scale,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ],
                      ),
                      Row(
                        spacing: 4,
                        children: [
                          Icon(
                            Icons.category,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Right: Effect selector and enable/disable button, both rectangular and aligned
              ],
            ),
          ),
        );
      },
    );
  }
}
