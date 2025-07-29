import 'package:flutter/material.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/screen/add_device.dart';
import 'package:udp_master/visualizer_provider.dart';

class Home extends StatefulWidget {
  final VisualizerProvider visualizerProvider;

  const Home({super.key, required this.visualizerProvider});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late LedEffect _selectedGlobalEffect;
  final List<String> _sortOptions = ['Name', 'IP'];
  String _selectedSortOption = 'Name';

  @override
  void initState() {
    super.initState();
    _selectedGlobalEffect = widget.visualizerProvider.effects.first;
  }

  void _applyGlobalEffect(String effectId) {
    final updatedDevices = widget.visualizerProvider.devices
        .map((d) => d.copyWith(effect: effectId))
        .toList();
    widget.visualizerProvider.deviceActions(
      context,
      updatedDevices,
      DeviceAction.update,
    );
  }

  List<LedDevice> _getSortedDevices() {
    final devices = widget.visualizerProvider.devices;
    if (_selectedSortOption == 'IP') {
      return [...devices]..sort((a, b) => a.ip.compareTo(b.ip));
    }
    return [...devices]..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final devices = _getSortedDevices();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _buildHeaderControls(),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: devices.length,
              itemBuilder: (context, index) =>
                  _buildDeviceCard(context, devices[index]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderControls() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Sort By',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.sort),
            ),
            value: _selectedSortOption,
            items: _sortOptions
                .map((option) => DropdownMenuItem(
                      value: option,
                      child: Text(option),
                    ))
                .toList(),
            onChanged: (newOption) {
              if (newOption != null) {
                setState(() => _selectedSortOption = newOption);
              }
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Select Effect',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.filter_vintage_outlined),
            ),
            value: _selectedGlobalEffect.id,
            items: widget.visualizerProvider.effects
                .map((e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(e.name),
                    ))
                .toList(),
            onChanged: (newEffectId) {
              if (newEffectId != null) {
                setState(() => _selectedGlobalEffect =
                    widget.visualizerProvider.effects
                        .firstWhere((e) => e.id == newEffectId));
                _applyGlobalEffect(newEffectId);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(BuildContext context, LedDevice device) {
    return Dismissible(
      key: ValueKey(device.name + device.ip + device.port.toString()),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, device),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: Colors.redAccent,
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device Info
              Expanded(child: _buildDeviceDetails(context, device)),
              const SizedBox(width: 12),
              _buildDeviceControls(context, device),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceDetails(BuildContext context, LedDevice device) {
    final theme = Theme.of(context).colorScheme;

    Widget infoRow(IconData icon, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.outline),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: theme.outline),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb, size: 16, color: theme.primary),
            const SizedBox(width: 4),
            Text(device.name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        infoRow(Icons.lan, device.ip),
        infoRow(Icons.wifi, 'PORT: ${device.port}'),
        infoRow(Icons.linear_scale, 'LEDs: ${device.ledCount}'),
        infoRow(Icons.category, device.type.displayName),
      ],
    );
  }

  Widget _buildDeviceControls(BuildContext context, LedDevice device) {
    final effects = widget.visualizerProvider.effects;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          height: 44,
          child: DropdownButtonFormField<String>(
            value: device.effect,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            ),
            items: effects
                .map((effect) => DropdownMenuItem(
                      value: effect.id,
                      child: Text(effect.name),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                widget.visualizerProvider.deviceActions(
                  context,
                  [device.copyWith(effect: val)],
                  DeviceAction.update,
                );
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: () {
                showDialog(
                  barrierDismissible: false,
                  useSafeArea: true,
                  context: context,
                  builder: (_) => Dialog(
                    child: AddDevice(
                      visualizerProvider: widget.visualizerProvider,
                      device: device,
                    ),
                  ),
                );
              },
              child: const Icon(Icons.edit_note, size: 26),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                widget.visualizerProvider.deviceActions(
                  context,
                  [
                    device.copyWith(isEnabled: !device.isEnabled),
                  ],
                  DeviceAction.update,
                );
              },
              child: Icon(
                device.isEnabled
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                size: 26,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<bool> _confirmDelete(BuildContext context, LedDevice device) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Device?'),
            content: Text('Are you sure you want to delete "${device.name}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  widget.visualizerProvider.deviceActions(
                    context,
                    [device],
                    DeviceAction.delete,
                  );
                  Navigator.of(context).pop(true);
                },
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }
}
