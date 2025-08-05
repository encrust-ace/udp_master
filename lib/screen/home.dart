import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/screen/add_device.dart';
import 'package:udp_master/screen/device_details.dart';
import 'package:udp_master/screen/wiz_screen.dart';
import 'package:udp_master/services/visualizer_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final List<String> _sortOptions = ['Name', 'IP'];
  String _selectedSortOption = 'Name';
  String? _selectedGlobalEffect;

  Future<void> _launchUrl(LedDevice device) async {
    final Uri uri = Uri.parse('http://${device.ip}');
    if (!await launchUrl(uri)) {
      throw Exception('Could not launch $uri');
    }
  }

  void _applyGlobalEffect(String effectId) {
    final provider = Provider.of<VisualizerProvider>(context, listen: false);
    provider.setGlobalEffect(effectId);
  }

  List<LedDevice> _getSortedDevices(List<LedDevice> devices) {
    if (_selectedSortOption == 'IP') {
      return [...devices]..sort((a, b) => a.ip.compareTo(b.ip));
    }
    return [...devices]..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VisualizerProvider>();
    final devices = _getSortedDevices(provider.devices);

    // Sync selected effect with provider if needed
    _selectedGlobalEffect ??= provider.globalEffectId;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _buildHeaderControls(provider),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: devices.length,
              itemBuilder: (context, index) =>
                  _buildDeviceCard(context, devices[index], provider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderControls(VisualizerProvider provider) {
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
                .map(
                  (option) =>
                      DropdownMenuItem(value: option, child: Text(option)),
                )
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
            value: _selectedGlobalEffect,
            items: provider.effects
                .map((e) => DropdownMenuItem(value: e.id, child: Text(e.name)))
                .toList(),
            onChanged: (newEffectId) {
              if (newEffectId != null) {
                setState(() => _selectedGlobalEffect = newEffectId);
                _applyGlobalEffect(newEffectId);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(
    BuildContext context,
    LedDevice device,
    VisualizerProvider provider,
  ) {
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
      child: GestureDetector(
        onTap: () {
          if (device.type == DeviceType.wiz) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DeviceControlScreen(device: device),
              ),
            );
          } else {
            if (Platform.isAndroid || Platform.isIOS) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DeviceDetails(device: device),
                ),
              );
            } else {
              _launchUrl(device);
            }
          }
        },
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.lightbulb, size: 16),
            title: Text(
              device.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [_buildDeviceDetails(context, device, provider)],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceDetails(
    BuildContext context,
    LedDevice device,
    VisualizerProvider provider,
  ) {
    final theme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8, left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.device_hub, size: 16, color: theme.outline),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  device.ip.toString(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: theme.outline),
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.settings_ethernet, size: 16, color: theme.outline),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  device.port.toString(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: theme.outline),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Icon(Icons.linear_scale, size: 16, color: theme.outline),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  device.ledCount.toString(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: theme.outline),
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.category, size: 16, color: theme.outline),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  device.type.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: theme.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildDeviceControls(context, device, provider),
        ],
      ),
    );
  }

  Widget _buildDeviceControls(
    BuildContext context,
    LedDevice device,
    VisualizerProvider provider,
  ) {
    final effects = provider.effects;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: device.effect,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 12,
              ),
            ),
            items: effects
                .map(
                  (effect) => DropdownMenuItem(
                    value: effect.id,
                    child: Text(effect.name),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) {
                provider.deviceActions(
                  device.copyWith(effect: val),
                  DeviceAction.update,
                );
              }
            },
          ),
        ),
        FilledButton(
          onPressed: () {
            showDialog(
              barrierDismissible: false,
              useSafeArea: true,
              context: context,
              builder: (_) => Dialog(
                child: AddDevice(device: device, action: DeviceAction.update),
              ),
            );
          },
          child: const Icon(Icons.edit_note, size: 26),
        ),
        FilledButton(
          onPressed: () {
            provider.deviceActions(
              device.copyWith(isEffectEnabled: !device.isEffectEnabled),
              DeviceAction.update,
            );
          },
          child: Icon(
            device.isEffectEnabled
                ? Icons.pause_circle_filled
                : Icons.play_circle_fill,
            size: 26,
          ),
        ),
      ],
    );
  }

  Future<bool> _confirmDelete(BuildContext context, LedDevice device) async {
    final provider = Provider.of<VisualizerProvider>(context, listen: false);
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
                  provider.deviceActions(device, DeviceAction.delete);
                  Navigator.of(context).pop(true);
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}
