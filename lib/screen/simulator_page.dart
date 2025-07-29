import 'package:flutter/material.dart';
import 'package:udp_master/screen/led_strip_simulator.dart';
import 'package:udp_master/visualizer_provider.dart';

class SimulatorPage extends StatelessWidget {
  final VisualizerProvider visualizerProvider;

  const SimulatorPage({super.key, required this.visualizerProvider});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final stripCount = (width / 50).floor();
    final ledsPerStrip = (height / 10).floor();

    return AnimatedBuilder(
      animation: visualizerProvider,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(stripCount, (index) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: LedStripSimulator(
                    ledCount: ledsPerStrip,
                    packet: visualizerProvider.packets,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
