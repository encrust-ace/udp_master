import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/services/visualizer_provider.dart';

class AddDevice extends StatefulWidget {
  final LedDevice device;
  final DeviceAction action;

  const AddDevice({
    super.key,
    required this.device,
    required this.action,
  });

  @override
  State<AddDevice> createState() => _AddDeviceState();
}

class _AddDeviceState extends State<AddDevice> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ledCountController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '21324');
  late LedEffect _selectedEffect;

  DeviceType _selectedDeviceType = DeviceType.wled;

  @override
  void initState() {
    super.initState();
    final d = widget.device;

    final provider = Provider.of<VisualizerProvider>(context, listen: false);

    _selectedEffect = d.effect.isNotEmpty
        ? provider.getEffectById(d.effect)
        : provider.effects.first;

    _nameController.text = d.name;
    _ipController.text = d.ip;
    _ledCountController.text = d.ledCount.toString();
    _portController.text = d.port.toString();
    _selectedDeviceType = d.type;
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

    final provider = Provider.of<VisualizerProvider>(context, listen: false);

    final device = LedDevice(
      id: widget.device.id,
      name: _nameController.text.trim(),
      ip: _ipController.text.trim(),
      ledCount: int.parse(_ledCountController.text.trim()),
      effect: _selectedEffect.id,
      isEffectEnabled: widget.device.isEffectEnabled,
      type: _selectedDeviceType,
      port: int.parse(_portController.text.trim()),
    );

    final message = await provider.deviceActions(device, widget.action);

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

    if (message.contains("successful")) {
      Navigator.of(context).pop();
    }
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon, [
    String? hint,
  ]) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VisualizerProvider>(context, listen: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Name & LED count
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _nameController,
                    decoration: _inputDecoration("Name", Icons.label, "Staircase"),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Required' : null,
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
            const SizedBox(height: 24),

            // IP & Port
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _ipController,
                    decoration: _inputDecoration("IP Address", Icons.computer, "192.168.1.100"),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    readOnly: true,
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
            const SizedBox(height: 24),

            // Effect Dropdown
            DropdownButtonFormField<LedEffect>(
              decoration: _inputDecoration("Effect", Icons.style),
              value: _selectedEffect,
              items: provider.effects
                  .map((effect) => DropdownMenuItem(
                        value: effect,
                        child: Text(effect.name),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedEffect = val);
                }
              },
              validator: (value) => value == null ? 'Select effect' : null,
            ),
            const SizedBox(height: 24),

            // Device Type Dropdown
            DropdownButtonFormField<DeviceType>(
              decoration: _inputDecoration("Device Type", Icons.device_hub),
              value: _selectedDeviceType,
              items: DeviceType.values
                  .map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.name),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedDeviceType = val;
                    _portController.text = val.port.toString();
                  });
                }
              },
              validator: (value) => value == null ? 'Select device type' : null,
            ),
            const SizedBox(height: 24),

            // Action Buttons
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
                  child: Text(widget.action == DeviceAction.add
                      ? "Add Device"
                      : "Update Device"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
