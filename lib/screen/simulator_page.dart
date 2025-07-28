import 'package:flutter/material.dart';
import 'package:udp_master/screen/led_strip_simulator.dart';
import 'package:udp_master/visualizer_provider.dart';

class SimulatorPaage extends StatefulWidget {
  final VisualizerProvider visualizerProvider;

  const SimulatorPaage({super.key, required this.visualizerProvider});

  @override
  State<SimulatorPaage> createState() => _SimulatorPaageState();
}

class _SimulatorPaageState extends State<SimulatorPaage> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          (MediaQuery.of(context).size.width / 50).floor(), // Dynamic number based on width
          (index) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0), // Add some spacing
              child: LedStripSimulator(
                ledCount: (MediaQuery.of(context).size.height / 10)
                    .floor(), // Calculate based on height
                packet: widget.visualizerProvider.packets,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
