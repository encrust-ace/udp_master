import 'package:flutter/material.dart';
import 'package:udp_master/device.dart';
import 'package:udp_master/visualizer_provider.dart';

class AddDevice extends StatefulWidget {
  final VisualizerProvider visualizerProvider;

  const AddDevice({super.key, required this.visualizerProvider});

  @override
  State<AddDevice> createState() => _AddDeviceState();
}

class _AddDeviceState extends State<AddDevice> {
  String selectedEffect = 'linear-fill';
  final List<String> effects = ['linear-fill', 'center-pulse', 'wave-pulse'];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _numberOfLEDs = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '5568',
  );
  DeviceType _selectedDeviceType = DeviceType.strip;
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ipController.dispose();
    _numberOfLEDs.dispose();
    super.dispose();
  }

  void _addDevice() async {
    final ledCount = int.tryParse(_numberOfLEDs.text.trim()) ?? 0;
    final name = _nameController.text.trim();
    final ip = _ipController.text.trim();

    final device = LedDevice(
      name: name,
      ip: ip,
      ledCount: ledCount,
      effect: selectedEffect,
      isEnabled: true,
      type: _selectedDeviceType,
      port: int.parse(_portController.text),
    );
    final resp = await widget.visualizerProvider.deviceActions(context, [
      device,
    ], DeviceAction.add);

    if (!resp) return;
    // Clear all fields except port and device type
    setState(() {
      _nameController.clear();
      _ipController.clear();
      _numberOfLEDs.clear();
      // _portController remains unchanged
      _selectedDeviceType = DeviceType.strip; // Reset to default
      selectedEffect = 'linear-fill'; // Optionally reset effect
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          spacing: 20.0,
          crossAxisAlignment:
              CrossAxisAlignment.stretch, // Make children take full width
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8.0,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: 'Starcase',
                      prefixIcon: const Icon(Icons.label),
                      border: OutlineInputBorder(
                        borderSide: const BorderSide(),
                      ),
                    ),
                    keyboardType: TextInputType.text,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Required'
                        : null,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _numberOfLEDs,
                    decoration: InputDecoration(
                      labelText: 'LEDs',
                      hintText: '90',
                      prefixIcon: const Icon(Icons.light),
                      border: OutlineInputBorder(
                        borderSide: const BorderSide(),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      final n = int.tryParse(value.trim());
                      if (n == null || n <= 0) return 'Enter a valid number';
                      return null;
                    },
                  ),
                ),
              ],
            ),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8.0,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      labelText: 'IP Address',
                      hintText: '192.168.1.100',
                      prefixIcon: const Icon(Icons.computer),
                      border: OutlineInputBorder(
                        borderSide: const BorderSide(),
                      ),
                    ),

                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Required'
                        : null,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _portController,
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'PORT',
                      hintText: _portController.text,
                      prefixIcon: const Icon(Icons.settings_ethernet),
                      border: OutlineInputBorder(
                        borderSide: const BorderSide(),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      final n = int.tryParse(value.trim());
                      if (n == null || n <= 0) return 'Enter a valid port';
                      return null;
                    },
                  ),
                ),
              ],
            ),

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<DeviceType>(
                    decoration: const InputDecoration(
                      labelText: 'Device Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.merge_type),
                    ),
                    value: _selectedDeviceType,
                    items: DeviceType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedDeviceType = val);
                      }
                    },
                    validator: (value) =>
                        value == null ? 'Select device type' : null,
                  ),
                ),
              ],
            ),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState?.validate() ?? false) {
                  _addDevice();
                }
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6.0),
                  side: const BorderSide(),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 18.0,
                  horizontal: 18.0,
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: const Text("Add Device"),
            ),
          ],
        ),
      ),
    );
  }
}
