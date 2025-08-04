import 'package:flutter/material.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/screen/led_strip_simulator.dart';
import 'package:udp_master/services/visualizer_provider.dart';

class SimulatorPage extends StatefulWidget {
  final VisualizerProvider visualizerProvider;

  const SimulatorPage({super.key, required this.visualizerProvider});

  @override
  State<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends State<SimulatorPage> {
  late LedEffect _selectedGlobalEffect;

  @override
  void initState() {
    super.initState();
    _selectedGlobalEffect = widget.visualizerProvider.effects.first;
  }

  void _applyGlobalEffect(String effectId) {
    final updatedDevices = widget.visualizerProvider.devices
        .map((d) => d.copyWith(effect: effectId))
        .toList();

    for (var device in updatedDevices) {
      widget.visualizerProvider.deviceActions(device, DeviceAction.update);
    }
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
                  value: _selectedGlobalEffect.id,
                  items: widget.visualizerProvider.effects
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e.id, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (newEffectId) {
                    if (newEffectId != null) {
                      setState(
                        () => _selectedGlobalEffect = widget
                            .visualizerProvider
                            .effects
                            .firstWhere((e) => e.id == newEffectId),
                      );
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
