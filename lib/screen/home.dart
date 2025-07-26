import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    _selectedGlobalEffect = widget.visualizerProvider.effects.first;
    super.initState();
  }

  void _applyGlobalEffect(BuildContext context, String effectId) {
    List<LedDevice> devices = widget.visualizerProvider.devices;
    List<LedDevice> updatedDevices = devices.map((device) {
      return device.copyWith(effect: effectId);
    }).toList();
    widget.visualizerProvider.deviceActions(
      context,
      updatedDevices,
      DeviceAction.update,
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = context.watch<VisualizerProvider>().devices;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          spacing: 20.0,
          crossAxisAlignment:
              CrossAxisAlignment.stretch, // Make children take full width
          children: [
            Row(
              spacing: 16,
              children: [
                Expanded(
                  child: ButtonTheme(
                    alignedDropdown: true,
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Sort By',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.sort),
                      ),
                      value: _selectedSortOption,
                      items: _sortOptions
                          .map(
                            (String option) => DropdownMenuItem(
                              value: option,
                              child: Text(option),
                            ),
                          )
                          .toList(),
                      onChanged: (newOption) {
                        if (newOption != null) {
                          setState(() {
                            _selectedSortOption = newOption;
                          });
                        }
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: ButtonTheme(
                    alignedDropdown: true,
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Select Effect',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.filter_vintage_outlined),
                      ),
                      value: _selectedGlobalEffect.id,
                      items: widget.visualizerProvider.effects
                          .map(
                            (LedEffect effect) => DropdownMenuItem(
                              value: effect.id,
                              child: Text(effect.name),
                            ),
                          )
                          .toList(),
                      onChanged: (newEffectId) {
                        if (newEffectId != null) {
                          _applyGlobalEffect(context, newEffectId);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return Dismissible(
                  key: ValueKey(
                    device.name + device.ip + device.port.toString(),
                  ),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (direction) async {
                    return await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Device?'),
                            content: Text(
                              'Are you sure you want to delete "${device.name}"?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
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
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  },
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    color: Colors.redAccent,
                    child: const Icon(
                      Icons.delete,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),

                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 18.0,
                        horizontal: 18.0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left: Device details, spaced between
                          Expanded(
                            child: Column(
                              spacing: 4,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  spacing: 4,
                                  children: [
                                    Icon(
                                      Icons.lightbulb,
                                      size: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    Text(
                                      device.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                Row(
                                  spacing: 4,
                                  children: [
                                    Icon(
                                      Icons.lan,
                                      size: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                    Text(
                                      '${device.ip}:${device.port}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                                Row(
                                  spacing: 4,
                                  children: [
                                    Icon(
                                      Icons.linear_scale,
                                      size: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                    Text(
                                      'LEDs: ${device.ledCount}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                                Row(
                                  spacing: 4,
                                  children: [
                                    Icon(
                                      Icons.category,
                                      size: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                    Text(
                                      device.type.displayName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Right: Effect selector and enable/disable button, both rectangular and aligned
                          Column(
                            spacing: 4,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 200,
                                height: 44,
                                child: ButtonTheme(
                                  alignedDropdown: true,
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
                                    items: widget.visualizerProvider.effects
                                        .map(
                                          (LedEffect effect) => DropdownMenuItem(
                                            value: effect.id,
                                            child: Text(effect.name),
                                          ),
                                        )
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
                              ),
                              Row(
                                spacing: 16,
                                children: [
                                  FilledButton(
                                    onPressed: () async {
                                      showDialog(
                                        barrierDismissible: false,
                                        useSafeArea: true,
                                        context: context,
                                        builder: (BuildContext context) {
                                          return Dialog(
                                            child: AddDevice(
                                              visualizerProvider:
                                                  widget.visualizerProvider,
                                              device: device,
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    child: Icon(Icons.edit_note, size: 26),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      widget.visualizerProvider
                                          .deviceActions(context, [
                                            device.copyWith(
                                              isEnabled: !device.isEnabled,
                                            ),
                                          ], DeviceAction.update);
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
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
