import 'package:flutter/material.dart';
import 'package:udp_master/screen/led_strip_simulator.dart';
import 'package:udp_master/services/visualizer_provider.dart';

class SimulatorPage extends StatefulWidget {
  final VisualizerProvider visualizerProvider;

  const SimulatorPage({super.key, required this.visualizerProvider});

  @override
  State<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends State<SimulatorPage> {
  late String _selectedGlobalEffectId;

  @override
  void initState() {
    super.initState();
    _selectedGlobalEffectId = widget.visualizerProvider.globalEffectId;
  }

  void _applyGlobalEffect(String effectId) {
    widget.visualizerProvider.setGlobalEffect(effectId);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final stripCount = (width / 50).floor();
    final ledsPerStrip = (height / 10).floor();

    return AnimatedBuilder(
      animation: widget.visualizerProvider,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            spacing: 16,
            children: [
              SizedBox(
                height: 50,
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Select Effect',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.filter_vintage_outlined),
                  ),
                  value: _selectedGlobalEffectId,
                  items: widget.visualizerProvider.effects
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e.id, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (newEffectId) {
                    if (newEffectId != null) {
                      setState(() => _selectedGlobalEffectId = newEffectId);
                      _applyGlobalEffect(newEffectId);
                    }
                  },
                ),
              ),

              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(stripCount, (index) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: LedStripSimulator(
                          ledCount: ledsPerStrip,
                          packet: widget.visualizerProvider.packets,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
