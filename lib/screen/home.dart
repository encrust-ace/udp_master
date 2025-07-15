import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:udp_master/device.dart';
import 'package:udp_master/effect_processor.dart';
import 'package:udp_master/main.dart';
import 'package:udp_master/udp_sender.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool isRunning = false;
  List<LedDevice> devices = [];
  String selectedEffect = 'linear-fill';
  final List<String> effects = ['linear-fill', 'center-pulse', 'wave-pulse'];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final savedDevices = await loadDevices();
    setState(() {
      devices = savedDevices;
    });
  }

  Future<void> startMic() async {
    await platform.invokeMethod("startMic");
  }

  Future<void> stopMic() async {
    await platform.invokeMethod("stopMic");
  }

  Future<bool> ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    return status.isGranted;
  }

  StreamSubscription? micSubscription;

  void toggleVisualizer() async {
    if (!isRunning) {
      bool granted = await ensureMicPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required')),
          );
        }
        return;
      }
    }

    setState(() => isRunning = !isRunning);

    if (isRunning) {
      await startMic();
      micSubscription = micStream.receiveBroadcastStream().listen((samples) {
        double volume = calculateVolume((samples as List).cast<double>());
        sendUdpPacketsToDevices(
          devices.where((d) => d.isEnabled).toList(),
          volume,
        );
      });
    } else {
      await stopMic();
      await micSubscription?.cancel();
      micSubscription = null;
    }
  }

  void _setGlobalEffect(String effect) {
    selectedEffect = effect;
    for (var d in devices) {
      d.currentEffect = effect;
    }
    setState(() {
      updateDevices(devices);
    });
  }

  void _updateDeviceEffect(int index, String effect) {
    devices[index].currentEffect = effect;
    setState(() {
      updateDevices(devices);
    });
  }

  @override
  void dispose() {
    micSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          spacing: 20.0,
          crossAxisAlignment:
              CrossAxisAlignment.stretch, // Make children take full width
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Select Effect',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.filter_vintage_outlined),
              ),
              value: selectedEffect,
              items: effects
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  _setGlobalEffect(val);
                }
              },
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
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
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
                  onDismissed: (direction) {
                    setState(() {
                      devices.removeAt(index);
                    });
                    updateDevices(devices);
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
                                      device.ip,
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
                                width: 150,
                                height: 44,
                                child: DropdownButtonFormField<String>(
                                  value: device.currentEffect,
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
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(
                                        () => _updateDeviceEffect(index, val),
                                      );
                                    }
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 150,
                                height: 44,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    backgroundColor: device.isEnabled
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                    foregroundColor: device.isEnabled
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                  ),
                                  icon: Icon(
                                    device.isEnabled
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_fill,
                                    size: 26,
                                  ),
                                  label: Text(
                                    device.isEnabled ? "Enabled" : "Disabled",
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: device.isEnabled
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.onPrimary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      devices[index].isEnabled =
                                          !devices[index].isEnabled;
                                    });
                                    updateDevices(devices);
                                  },
                                ),
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
            SwitchListTile(
              title: const Text(
                "Start Visualizer",
                style: TextStyle(fontSize: 16),
              ),
              value: isRunning,
              onChanged: (_) => toggleVisualizer(),
              secondary: Icon(isRunning ? Icons.mic : Icons.mic_off),
              activeColor: Theme.of(context).colorScheme.secondary,
            ),
          ],
        ),
      ),
    );
  }
}
