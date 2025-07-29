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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ledCountController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '21324');

  DeviceType _selectedDeviceType = DeviceType.wled;

  @override
  void initState() {
    super.initState();
    final d = widget.device;
    if (d != null) {
      _nameController.text = d.name;
      _ipController.text = d.ip;
      _ledCountController.text = d.ledCount.toString();
      _portController.text = d.port.toString();
      _selectedDeviceType = d.type;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ledCountController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final device = LedDevice(
      name: _nameController.text.trim(),
      ip: _ipController.text.trim(),
      ledCount: int.parse(_ledCountController.text.trim()),
      effect: widget.visualizerProvider.effects.first.id,
      isEnabled: true,
      type: _selectedDeviceType,
      port: int.parse(_portController.text.trim()),
    );

    final success = await widget.visualizerProvider.deviceActions(
      context,
      [device],
      widget.device == null ? DeviceAction.add : DeviceAction.update,
    );

    if (success) Navigator.of(context).pop();
  }

  InputDecoration _inputDecoration(String label, IconData icon,
      [String? hint]) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Import/Export buttons
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => widget.visualizerProvider.importDevicesFromJsonFile(context),
                  child: const Text("Import Devices"),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => widget.visualizerProvider.exportDevicesToJsonFile(context),
                  child: const Text("Export Devices"),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Name & LED count
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _nameController,
                    decoration: _inputDecoration("Name", Icons.label, "Staircase"),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _ledCountController,
                    decoration: _inputDecoration("LEDs", Icons.light, "90"),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final n = int.tryParse(value ?? '');
                      if (n == null || n <= 0) return 'Enter valid count';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // IP & Port
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _ipController,
                    decoration: _inputDecoration("IP Address", Icons.computer, "192.168.1.100"),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _portController,
                    decoration: _inputDecoration("Port", Icons.settings_ethernet),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final n = int.tryParse(value ?? '');
                      if (n == null || n <= 0) return 'Invalid port';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Device Type
            DropdownButtonFormField<DeviceType>(
              decoration: _inputDecoration("Device Type", Icons.merge_type),
              value: _selectedDeviceType,
              items: DeviceType.values
                  .map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.displayName),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedDeviceType = val);
              },
              validator: (value) => value == null ? 'Select device type' : null,
            ),

            const SizedBox(height: 32),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _submit,
                  child: Text(widget.device == null ? "Add Device" : "Update Device"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
