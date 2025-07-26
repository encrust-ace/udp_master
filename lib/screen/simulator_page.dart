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
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 50,
        children: [
          SizedBox(
            width: 30,
            child: LedStripSimulator(
              ledCount: 50,
              packet: widget.visualizerProvider.packets,
            ),
          ),
          SizedBox(
            width: 30,
            child: LedStripSimulator(
              ledCount: 50,
              packet: widget.visualizerProvider.packets,
            ),
          ),
        ],
      ),
    );
  }
}
