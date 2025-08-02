import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:udp_master/models.dart';

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

class WizLight {
  final String ip;
  final int port;
  final String? mac;

  WizLight({required this.ip, required this.port, this.mac});
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

Future<List<DiscoveredDevice>> _discoverLights({
  String broadcastSpace = "255.255.255.255",
  int waitTime = defaultWaitTime,
  required DeviceType deviceType,
}) async {
  final BroadcastProtocol broadcastProtocol = BroadcastProtocol(
    broadcastSpace,
    waitTime,
    deviceType,
  );

  await broadcastProtocol.broadcastRegistration();

  return broadcastProtocol.discoveryBulbs;
}

Future<List<WizLight>> findWizlights({
  String broadcastSpace = "255.255.255.255",
  int waitTime = defaultWaitTime,
  required DeviceType deviceType,
}) async {
  final List<DiscoveredDevice> discoveredIPs = await _discoverLights(
    broadcastSpace: broadcastSpace,
    waitTime: waitTime,
    deviceType: deviceType,
  );

  return discoveredIPs
      .map((e) => WizLight(ip: e.ip, port: deviceType.port, mac: e.mac))
      .toList();
}

class WizBulbDiscoveryPage extends StatefulWidget {
  const WizBulbDiscoveryPage({super.key});

  @override
  State<WizBulbDiscoveryPage> createState() => _WizBulbDiscoveryPageState();
}

class _WizBulbDiscoveryPageState extends State<WizBulbDiscoveryPage> {
  List<WizLight> discoveredDevices = [];
  bool isScanning = false;
  String? errorMessage;
  String broadcastAddress = "255.255.255.255";
  int waitTime = 5;
  DeviceType deviceType = DeviceType.wled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan devices')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          spacing: 16,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: DeviceType.wled.name,
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
                  deviceType = DeviceType.values.firstWhere(
                    (deviceType) => deviceType.name == val,
                  );
                }
              },
            ),
            // Scan Button
            ElevatedButton.icon(
              onPressed: isScanning ? null : _scanForBulbs,
              icon: isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(isScanning ? 'Scanning...' : 'Scan for devices'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),

            // Status/Error Message
            if (errorMessage != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
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

            // Results Header
            if (discoveredDevices.isNotEmpty) ...[
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
            ],

            // Discovered Bulbs List
            Expanded(
              child: discoveredDevices.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      itemCount: discoveredDevices.length,
                      itemBuilder: (context, index) {
                        final bulb = discoveredDevices[index];
                        return _buildBulbCard(bulb, index);
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

  Widget _buildBulbCard(WizLight bulb, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor,
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          'Device ${index + 1}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('IP: ${bulb.ip}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildDetailRow('IP Address', bulb.ip, Icons.language),
                _buildDetailRow(
                  'Port',
                  bulb.port.toString(),
                  Icons.settings_ethernet,
                ),
                _buildDetailRow(
                  'MAC Address',
                  bulb.mac ?? 'Unknown',
                  Icons.device_hub,
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {},
                    child: Text("Add Device"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Future<void> _scanForBulbs() async {
    setState(() {
      isScanning = true;
      errorMessage = null;
      discoveredDevices.clear();
    });

    try {
      final bulbs = await findWizlights(
        broadcastSpace: broadcastAddress,
        waitTime: waitTime,
        deviceType: deviceType,
      );

      setState(() {
        discoveredDevices = bulbs;
        isScanning = false;
      });

      if (bulbs.isEmpty) {
        setState(() {
          errorMessage =
              'No device found on the network. Make sure they are powered on and connected to the same network.';
        });
      } else {
        _showSnackBar(
          'Found ${bulbs.length} devices${bulbs.length == 1 ? '' : 's'}!',
        );
      }
    } catch (e) {
      setState(() {
        isScanning = false;
        errorMessage = 'Error during discovery: ${e.toString()}';
      });
    }
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
