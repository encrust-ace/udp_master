import 'package:flutter/material.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/visualizer_provider.dart';

class AddDevice extends StatefulWidget {
  final VisualizerProvider visualizerProvider;
  final LedDevice? device;

  const AddDevice({super.key, required this.visualizerProvider, this.device});

  @override
  State<AddDevice> createState() => _AddDeviceState();
}

class _AddDeviceState extends State<AddDevice> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _numberOfLEDs = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '21324',
  );
  DeviceType _selectedDeviceType = DeviceType.wled;
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
    final effects = widget.visualizerProvider.effects;

    final device = LedDevice(
      name: name,
      ip: ip,
      ledCount: ledCount,
      effect: effects.first.id,
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
      _selectedDeviceType = DeviceType.wled; // Reset to default
    });
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    if (widget.device != null) {
      _nameController.text = widget.device!.name;
      _ipController.text = widget.device!.ip;
      _numberOfLEDs.text = widget.device!.ledCount.toString();
      _portController.text = widget.device!.port.toString();
      _selectedDeviceType = widget.device!.type;
    }
    super.initState();
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
              spacing: 16,
              children: [
                ElevatedButton(
                  onPressed: () {
                    widget.visualizerProvider.importDevicesFromJsonFile(
                      context,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text("Import Devices"),
                ),
                ElevatedButton(
                  onPressed: () {
                    widget.visualizerProvider.exportDevicesToJsonFile(context);
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text("Export Devices"),
                ),
                SizedBox(width: 8),
                // Text(
                //   _visualizerProvider.castMode == CastMode.video
                //       ? "Video"
                //       : "Audio",
                // ),
                // Switch(
                //   padding: EdgeInsets.only(right: 50),
                //   value: _visualizerProvider.castMode == CastMode.video,
                //   thumbColor: const WidgetStatePropertyAll<Color>(Colors.black),
                //   onChanged: (bool value) {
                //     if (value) {
                //       _visualizerProvider.castMode = CastMode.video;
                //     } else {
                //       _visualizerProvider.castMode = CastMode.audio;
                //     }
                //   },
                // ),
              ],
            ),

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
                    enabled: true,
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
            SizedBox(height: 60),
            Row(
              spacing: 16,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
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
                  child: const Text("Cancel"),
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
                  child: Text(
                    widget.device == null ? "Add Device" : "Update Device",
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
