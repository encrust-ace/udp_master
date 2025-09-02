import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/screen/led_strip_simulator.dart';
import 'package:udp_master/services/visualizer_provider.dart';

class SimulatorPage extends StatefulWidget {
  const SimulatorPage({super.key});

  @override
  State<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends State<SimulatorPage> {
  String? _selectedGlobalEffectId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only set this once
    _selectedGlobalEffectId ??=
        context.read<VisualizerProvider>().globalEffectId;
  }

  void _applyGlobalEffect(String effectId) {
    context.read<VisualizerProvider>().setGlobalEffect(effectId);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VisualizerProvider>();

    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final stripCount = (width / 50).floor();
    final ledsPerStrip = (height / 10).floor();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // Dropdown for selecting effect
          SizedBox(
            height: 50,
            child: DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Select Effect',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.filter_vintage_outlined),
              ),
              initialValue: _selectedGlobalEffectId,
              items: provider.effects
                  .map((e) => DropdownMenuItem(value: e.id, child: Text(e.name)))
                  .toList(),
              onChanged: (newEffectId) {
                if (newEffectId != null) {
                  setState(() => _selectedGlobalEffectId = newEffectId);
                  _applyGlobalEffect(newEffectId);
                }
              },
            ),
          ),

          const SizedBox(height: 16),

          // LED Strip Simulation
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(stripCount, (index) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: LedStripSimulator(
                      ledCount: ledsPerStrip,
                      packet: provider.simulatorPackets,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
