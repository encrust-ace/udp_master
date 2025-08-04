import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
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

  Device({this.name, required this.ip, required this.port, this.mac});
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

          debugPrint('Received Wiz packet: ${packet != null}');

          if (packet != null) {
            try {
              final Map resp = json.decode(utf8.decode(packet.data));

              if (resp.keys.contains('result')) {
                final String mac = resp['result']['mac'];

                debugPrint(
                  "Found bulb with IP: ${packet.address.address} and MAC: $mac",
                );
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
  int waitTime = 5;
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

  void _onVisualizerProviderUpdate() {
    setState(() {});
  }

  Future<List<dynamic>> _discoverDevices({
    required DeviceType deviceType,
    String broadcastSpace = "255.255.255.255",
    int waitTime = defaultWaitTime,
  }) async {
    if (deviceType == DeviceType.wled || deviceType == DeviceType.esphome) {
      final List<Device> foundDevices = [];
      final BonsoirDiscovery discovery = BonsoirDiscovery(
        type: deviceType == DeviceType.wled ? "_wled._tcp" : "_esphomelib._tcp",
      );

      await discovery.initialize();
      await discovery.start();

      // Use a Completer and a Timer to control the discovery duration
      final completer = Completer<List<Device>>();
      final timer = Timer(Duration(seconds: waitTime), () {
        if (!completer.isCompleted) {
          completer.complete(foundDevices);
        }
      });

      discovery.eventStream!.listen((event) {
        if (event.service == null) {
          return;
        }

        // The event types are defined internally in Bonsoir and are not public enums.
        // We must compare against the internal integer values or rely on service properties.
        // This is a known issue with the bonsoir API, but we can make it work.
        // Based on the bonsoir internal logic, a service with a host and port
        // is a resolved service.
        final service = event.service!;
        if (service.host != null) {
          // This is the most reliable check for a resolved service
          debugPrint('Resolved service found: ${service.toJson()}');
          final isDuplicate = foundDevices.any(
            (device) => device.ip == service.host,
          );
          if (!isDuplicate) {
            foundDevices.add(
              Device(
                name: service.name,
                ip: service.host!,
                port: deviceType.port,
                mac: service.attributes['mac'],
              ),
            );
          }
        } else {
          // A service without host/port is an unresolved service,
          // so we ask bonsoir to resolve it.
          debugPrint(
            'Unresolved service found, resolving: ${service.toJson()}',
          );
          service.resolve(discovery.serviceResolver);
        }
      });

      final result = await completer.future;
      await discovery.stop();
      timer.cancel();
      return result;
    } else if (deviceType == DeviceType.wiz) {
      // Wiz discovery logic
      final BroadcastProtocol broadcastProtocol = BroadcastProtocol(
        broadcastSpace,
        waitTime,
        deviceType,
      );

      await broadcastProtocol.broadcastRegistration();
      return broadcastProtocol.discoveryBulbs;
    }

    return [];
  }

  Future<List<Device>> _findWizLights({
    String broadcastSpace = "255.255.255.255",
    int waitTime = defaultWaitTime,
  }) async {
    final List<DiscoveredDevice> discoveredIPs =
        await _discoverDevices(
              broadcastSpace: broadcastSpace,
              waitTime: waitTime,
              deviceType: deviceType,
            )
            as List<DiscoveredDevice>;

    return discoveredIPs
        .map((e) => Device(ip: e.ip, port: deviceType.port, mac: e.mac))
        .toList();
  }

  Future<List<Device>> _findWledLights({int waitTime = defaultWaitTime}) async {
    final List<dynamic> discoveredDevices = await _discoverDevices(
      waitTime: waitTime,
      deviceType: deviceType,
    );
    return discoveredDevices.cast<Device>(); // Cast the result
  }

  Future<void> _scanForDevices() async {
    setState(() {
      isScanning = true;
      errorMessage = null;
      discoveredDevices.clear();
    });

    try {
      List<dynamic> foundDevices;
      if (deviceType == DeviceType.wled || deviceType == DeviceType.esphome) {
        final wledDevices = await _findWledLights(waitTime: waitTime);
        foundDevices = wledDevices;
      } else if (deviceType == DeviceType.wiz) {
        foundDevices = await _findWizLights(
          broadcastSpace: broadcastAddress,
          waitTime: waitTime,
        );
      } else {
        foundDevices = [];
      }

      setState(() {
        discoveredDevices = foundDevices.map((d) {
          if (d is Device) {
            return Device(name: d.name, ip: d.ip, port: d.port, mac: d.mac);
          }
          return d as Device;
        }).toList();

        isScanning = false;
      });

      if (foundDevices.isEmpty) {
        setState(() {
          errorMessage =
              'No devices of type ${deviceType.name} found on the network.';
        });
      } else {
        _showSnackBar('Found ${foundDevices.length} devices!');
      }
    } catch (e) {
      setState(() {
        isScanning = false;
        errorMessage = 'Error during discovery: ${e.toString()}';
      });
    }
  }

  void _showAddDeviceDialog(BuildContext context, Device device) {
    showDialog(
      barrierDismissible: false,
      useSafeArea: true,
      context: context,
      builder: (_) => Dialog(
        child: AddDevice(
          visualizerProvider: widget.visualizerProvider,
          device: LedDevice(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: device.name ?? 'Unknown',
            ip: device.ip,
            port: device.port,
            ledCount: 0,
            effect: '',
            isEffectEnabled: true,
            type: deviceType,
          ),
          action: DeviceAction.add,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan devices')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          spacing: 16,
          children: [
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: deviceType.name,
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
                    items: DeviceType.values
                        .map(
                          (deviceType) => DropdownMenuItem(
                            value: deviceType.name,
                            child: Text(deviceType.name),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          deviceType = DeviceType.values.firstWhere(
                            (dt) => dt.name == val,
                          );
                        });
                      }
                    },
                  ),
                ),
                ElevatedButton(
                  onPressed: isScanning ? null : _scanForDevices,
                  style: ElevatedButton.styleFrom(
                    fixedSize: Size(44, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: isScanning
                      ? SizedBox(
                          height: 12,
                          width: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ],
            ),

            if (errorMessage != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
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
            // Results Header
            if (discoveredDevices.isNotEmpty) ...[
              Row(
                spacing: 8,
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
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Discovered Bulbs List
            Expanded(
              child: discoveredDevices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No devices discovered',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: discoveredDevices.length,
                      itemBuilder: (context, index) {
                        final device = discoveredDevices[index];
                        final isAlreadyAdded = widget.visualizerProvider.devices
                            .any(
                              (existingDevice) =>
                                  existingDevice.ip == device.ip,
                            );

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).primaryColor,
                              child: Icon(Icons.light),
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
                                padding: const EdgeInsets.only(
                                  left: 26.0,
                                  right: 26,
                                  top: 8,
                                  bottom: 8,
                                ),
                                child: Column(
                                  spacing: 4,
                                  children: [
                                    _buildDetailRow(
                                      'IP Address',
                                      device.ip,
                                      Icons.language,
                                    ),
                                    _buildDetailRow(
                                      'Port',
                                      device.port.toString(),
                                      Icons.settings_ethernet,
                                    ),
                                    _buildDetailRow(
                                      'MAC Address',
                                      device.mac ?? 'Unknown',
                                      Icons.device_hub,
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: isAlreadyAdded
                                            ? null
                                            : () {
                                                _showAddDeviceDialog(
                                                  context,
                                                  device,
                                                );
                                              },
                                        style: ElevatedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              4.0,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          isAlreadyAdded
                                              ? 'Device already added'
                                              : "Add Device",
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

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        spacing: 12,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          Expanded(child: Text(value)),
        ],
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
}
