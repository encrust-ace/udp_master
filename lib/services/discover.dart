import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:udp_master/models.dart';
import 'package:udp_master/screen/add_device.dart';
import 'package:udp_master/services/visualizer_provider.dart';

// Your discovery code - include these classes/functions
const defaultWaitTime = 5;
const registerMessage =
    '{"method":"registration","params":{"phoneMac":"AAAAAAAAAAAA","register":false,"phoneIp":"1.2.3.4","id":"1"}}';

class DiscoveredDevice {
  final String ip;
  final String mac;

  DiscoveredDevice(this.ip, this.mac);
}

class DeviceRegistry {
  final List<DiscoveredDevice> _devices = [];

  void register(DiscoveredDevice bulb) {
    _devices.add(bulb);
  }

  List<DiscoveredDevice> bulbs() => _devices;
}

class Device {
  final String? name;
  final String ip;
  final int port;
  final String? mac;
  final int ledCount;

  Device({
    this.name,
    required this.ip,
    required this.port,
    this.mac,
    required this.ledCount,
  });
}

class BroadcastProtocol {
  BroadcastProtocol(this.broadcastSpace, this.waitTime, this.deviceType);

  final DeviceRegistry _registry = DeviceRegistry();
  late RawDatagramSocket datagramSocket;
  final String broadcastSpace;
  final int waitTime;
  DeviceType deviceType = DeviceType.wled;

  Future<void> broadcastRegistration() async {
    try {
      datagramSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        deviceType.port,
      );
      datagramSocket.broadcastEnabled = true;

      datagramReceived();

      await sendMessage(registerMessage);

      datagramSocket.close();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  List<DiscoveredDevice> get discoveryBulbs => _registry.bulbs();

  Future<void> sendMessage(String message) async {
    int sendResult = datagramSocket.send(
      utf8.encode(message),
      InternetAddress(broadcastSpace),
      deviceType.port,
    );
    debugPrint(
      'Wiz request sent, waiting for response... Did send data successfully: ${sendResult > 0}\n',
    );
    await Future.delayed(Duration(seconds: waitTime));
  }

  void datagramReceived() {
    datagramSocket.listen(
      (RawSocketEvent evt) {
        if (evt == RawSocketEvent.read) {
          Datagram? packet = datagramSocket.receive();

          if (packet != null) {
            try {
              final Map resp = json.decode(utf8.decode(packet.data));
              debugPrint(resp.toString());

              if (resp.keys.contains('result')) {
                final String mac = resp['result']['mac'];
                _registry.register(
                  DiscoveredDevice(packet.address.address, mac),
                );
              }
            } catch (e) {
              debugPrint('Error parsing response: $e');
            }
          }
        }
      },
      onDone: () {
        debugPrint("Socket closed successfully!");
      },
    );
  }
}

class DeviceScanPage extends StatefulWidget {
  final VisualizerProvider visualizerProvider;

  const DeviceScanPage({super.key, required this.visualizerProvider});

  @override
  State<DeviceScanPage> createState() => _DeviceScanPageState();
}

class _DeviceScanPageState extends State<DeviceScanPage> {
  List<Device> discoveredDevices = [];
  bool isScanning = false;
  String? errorMessage;
  String broadcastAddress = "255.255.255.255";
  int waitTime = defaultWaitTime;
  DeviceType deviceType = DeviceType.wled;

  @override
  void initState() {
    super.initState();
    widget.visualizerProvider.addListener(_onVisualizerProviderUpdate);
  }

  @override
  void dispose() {
    widget.visualizerProvider.removeListener(_onVisualizerProviderUpdate);
    super.dispose();
  }

  void _onVisualizerProviderUpdate() => setState(() {});

  Future<List<Device>> _discoverDevices() async {
    switch (deviceType) {
      case DeviceType.wled:
      case DeviceType.esphome:
        return _discoverBonsoirDevices();
      case DeviceType.wiz:
        return _discoverWizDevices();
    }
  }

  Future<List<Device>> _discoverBonsoirDevices() async {
    final List<Device> foundDevices = [];
    final discovery = BonsoirDiscovery(
      type: deviceType == DeviceType.wled ? "_wled._tcp" : "_esphomelib._tcp",
    );

    await discovery.initialize();
    await discovery.start();

    final completer = Completer<List<Device>>();
    final timer = Timer(Duration(seconds: waitTime), () {
      if (!completer.isCompleted) completer.complete(foundDevices);
    });

    discovery.eventStream!.listen((event) {
      final service = event.service;
      if (service == null) return;

      if (service.host != null) {
        final alreadyExists = foundDevices.any((d) => d.ip == service.host);
        if (!alreadyExists) {
          foundDevices.add(
            Device(
              name: service.name,
              ip: service.host!,
              port: deviceType.port,
              mac: service.attributes['mac'],
              ledCount: 1,
            ),
          );
        }
      } else {
        service.resolve(discovery.serviceResolver);
      }
    });

    final results = await completer.future;
    timer.cancel();
    await discovery.stop();
    return results;
  }

  Future<List<Device>> _discoverWizDevices() async {
    final protocol = BroadcastProtocol(broadcastAddress, waitTime, deviceType);
    await protocol.broadcastRegistration();
    return protocol.discoveryBulbs
        .map(
          (d) =>
              Device(ip: d.ip, port: deviceType.port, mac: d.mac, ledCount: 1),
        )
        .toList();
  }

  Future<void> _scanForDevices() async {
    setState(() {
      isScanning = true;
      errorMessage = null;
      discoveredDevices.clear();
    });

    try {
      final devices = await _discoverDevices();

      setState(() {
        discoveredDevices = devices;
        isScanning = false;
      });

      if (devices.isEmpty) {
        errorMessage = 'No ${deviceType.name} devices found.';
      } else {
        _showSnackBar('Found ${devices.length} device(s).');
      }
    } catch (e) {
      setState(() {
        isScanning = false;
        errorMessage = 'Discovery failed: ${e.toString()}';
      });
    }
  }

  Future<Device?> _fetchWledDetails(Device device) async {
    final String url = 'http://${device.ip}/json/info';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data.containsKey('leds')) {
          final int ledCount = data['leds']['count'];
          final String? name = data['name'] ?? device.name;
          return Device(
            name: name,
            ip: device.ip,
            port: device.port,
            mac: device.mac,
            ledCount: ledCount,
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to get WLED details for ${device.ip}: $e');
    }

    return null;
  }

  void _showAddDeviceDialog(Device device) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: AddDevice(
          device: LedDevice(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: device.name ?? 'Unknown',
            ip: device.ip,
            port: device.port,
            ledCount: device.ledCount,
            isEffectEnabled: true,
            type: deviceType,
            segments: [
              Segment(
                id: 'segment_1',
                startIndex: 0,
                endIndex: device.ledCount,
              ),
            ],
          ),
          action: DeviceAction.add,
        ),
      ),
    );
  }

  void _clearResults() {
    setState(() {
      discoveredDevices.clear();
      errorMessage = null;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Devices')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: deviceType.name,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    items: DeviceType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type.name,
                            child: Text(type.name),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          deviceType = DeviceType.values.firstWhere(
                            (d) => d.name == val,
                          );
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: isScanning ? null : _scanForDevices,
                  style: ElevatedButton.styleFrom(
                    fixedSize: const Size(44, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: isScanning
                      ? const SizedBox(
                          height: 12,
                          width: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (errorMessage != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (discoveredDevices.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Found ${discoveredDevices.length} device${discoveredDevices.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _clearResults,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
                ],
              ),

            const SizedBox(height: 8),

            Expanded(
              child: discoveredDevices.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      itemCount: discoveredDevices.length,
                      itemBuilder: (_, index) {
                        final device = discoveredDevices[index];
                        final alreadyAdded = widget.visualizerProvider.devices
                            .any((d) => d.ip == device.ip);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              child: const Icon(Icons.light),
                            ),
                            title: Text(
                              device.name ?? 'Unknown',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text('IP: ${device.ip}'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    _buildDetailRow(
                                      'IP Address',
                                      device.ip,
                                      Icons.language,
                                    ),
                                    _buildDetailRow(
                                      'Port',
                                      device.port.toString(),
                                      Icons.dns,
                                    ),
                                    _buildDetailRow(
                                      'MAC Address',
                                      device.mac ?? 'Unknown',
                                      Icons.memory,
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: alreadyAdded
                                            ? null
                                            : () async {
                                                if (deviceType ==
                                                    DeviceType.wled) {
                                                  Device? newDevice =
                                                      await _fetchWledDetails(
                                                        device,
                                                      );

                                                  if (newDevice != null) {
                                                    _showAddDeviceDialog(
                                                      newDevice,
                                                    );
                                                  } else {
                                                    _showAddDeviceDialog(
                                                      device,
                                                    );
                                                  }
                                                } else {
                                                  _showAddDeviceDialog(device);
                                                }
                                              },

                                        child: Text(
                                          alreadyAdded
                                              ? 'Already added'
                                              : 'Add Device',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lightbulb_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No devices discovered',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
