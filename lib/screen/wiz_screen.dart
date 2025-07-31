import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:udp/udp.dart';
import 'package:udp_master/models.dart'; // Your existing models.dart file
import 'package:udp_master/udp_sender.dart';
import 'dart:async';

const scenes = {
  0: "Warmest",
  1: "Ocean",
  2: "Romance",
  3: "Sunset",
  4: "Party",
  5: "Fireplace",
  6: "Cozy",
  7: "Forest",
  8: "Pastel colors",
  9: "Wake-up",
  10: "Bedtime",
  11: "Warm",
  12: "Daylight",
  13: "Cool",
  14: "Night light",
  15: "Focus",
  16: "Relax",
  17: "True colors",
  18: "TV time",
  19: "Plant growth",
  20: "Spring",
  21: "Summer",
  22: "Fall",
  23: "Deep dive",
  24: "Jungle",
  25: "Mojito",
  26: "Club",
  27: "Chrismas",
  28: "Halloween",
  29: "Candlelight",
  30: "Golden white",
  31: "Pulse",
  32: "Steampunk",
  33: "Diwali",
  35: "Alarm",
  36: "Snow sky",
};

class DeviceControlScreen extends StatefulWidget {
  final LedDevice device;

  const DeviceControlScreen({super.key, required this.device});

  @override
  State<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends State<DeviceControlScreen> {
  late LedDevice _device; // Use a local state variable for the device
  final UdpSender _udpSender = UdpSender();

  bool _isOn = false;
  int _brigtness = 100;
  int _kelvin = 4600; // Assuming white balance is same as brightness
  Color _color = Colors.white;
  int _selectedSceneId = 2;

  Timer? _brightnessDebounceTimer;
  Timer? _colorDebounceTimer;

  Future<void> sendUdpCommand(dynamic data, LedDevice device) async {
    final target = Endpoint.unicast(
      InternetAddress(device.ip),
      port: Port(device.port),
    );
    _udpSender.udpInstance?.send(data, target);
  }

  @override
  void initState() {
    super.initState();
    _udpSender.initiateUDPSender().then((_) => {_getDeviceStatus()});
    _device = widget.device; // Initialize with the passed device state
  }

  void _sendOnOffCommand(bool isOn) async {
    final Map<String, dynamic> data = {
      "method": "setPilot",
      "params": {"state": isOn},
    };
    final List<int> message = utf8.encode(jsonEncode(data));
    await sendUdpCommand(message, _device);
    setState(() {
      _isOn = isOn; // Optimistic UI update
    });
  }

  void _sendBrightnessCommand(int brightness) {
    setState(() {
      _brigtness = brightness; // Optimistic UI update
    });
    _brightnessDebounceTimer?.cancel();
    _brightnessDebounceTimer = Timer(
      const Duration(milliseconds: 500),
      () async {
        final Map<String, dynamic> data = {
          "method": "setPilot",
          "params": {"dimming": brightness},
        };
        final List<int> message = utf8.encode(jsonEncode(data));
        await sendUdpCommand(message, _device);
      },
    );
  }

  void _sendTempratureCommand(int kelvin) {
    setState(() {
      _kelvin = kelvin; // Optimistic UI update
    });
    _brightnessDebounceTimer = Timer(
      const Duration(milliseconds: 500),
      () async {
        final Map<String, dynamic> data = {
          "method": "setPilot",
          "params": {"state": true, "temp": kelvin},
        };
        final List<int> message = utf8.encode(jsonEncode(data));
        await sendUdpCommand(message, _device);
      },
    );
  }

  void _sendColorCommand(Color color) {
    setState(() {
      _color = color; // Optimistic UI update
      _isOn = true; // Update the UI state as well
    });
    _colorDebounceTimer?.cancel();
    _colorDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      int r = (color.r * 255.0).round() & 0xff;
      int g = (color.g * 255.0).round() & 0xff;
      int b = (color.b * 255.0).round() & 0xff;

      final Map<String, dynamic> data = {
        "method": "setPilot",
        "params": {
          'state': true, // Ensure the light is on when changing color
          'r': r,
          'g': g,
          'b': b,
        },
      };
      if ((r - g).abs() <= 5 &&
          (g - b).abs() <= 5 &&
          (r - b).abs() <= 5 &&
          r >= 200 &&
          g >= 200 &&
          b >= 200) {
        data['params']['temp'] = 4350; // Near-white color
      }

      final List<int> message = utf8.encode(jsonEncode(data));
      await sendUdpCommand(message, _device);
    });
  }

  void _sendSceneIdCommand(int sceneId) {
    setState(() {
      _selectedSceneId = sceneId; // Optimistic UI update
    });

    final Map<String, dynamic> data = {
      "method": "setPilot",
      "params": {"state": true, "sceneId": sceneId},
    };
    final List<int> message = utf8.encode(jsonEncode(data));
    sendUdpCommand(message, _device);
  }

  Future<void> _getDeviceStatus() async {
    final target = Endpoint.unicast(
      InternetAddress(_device.ip),
      port: Port(_device.port),
    );

    final Map<String, dynamic> request = {"method": "getPilot", "params": {}};

    final List<int> message = utf8.encode(jsonEncode(request));
    _udpSender.udpInstance?.send(message, target);

    // Listen for the response
    _udpSender.udpInstance?.asStream().listen((datagram) {
      if (datagram == null) return;

      try {
        final response = jsonDecode(utf8.decode(datagram.data));
        final result = response["result"];

        if (result != null) {
          setState(() {
            if (result["state"]) {
              _isOn = result["state"];
            }
            if (result["dimming"]) {
              _brigtness = result["dimming"];
            }
            if (result["temp"]) {
              _kelvin = result["temp"];
            }
            if (result.containsKey("r") &&
                result.containsKey("g") &&
                result.containsKey("b")) {
              _color = Color.fromARGB(
                255,
                result["r"] ?? 255,
                result["g"] ?? 255,
                result["b"] ?? 255,
              );
            }
          });
        }
      } catch (e) {
        if (kDebugMode) {
          print("Failed to parse UDP response: $e");
        }
      }
    });
  }

  // --- UI Build Methods ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_device.name} Control'),
        elevation: 0, // Flat design
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // Device Status Card
            _buildDeviceStatusCard(),
            const SizedBox(height: 24),

            // Brightness Control Card
            _buildBrightnessControlCard(),
            const SizedBox(height: 24),

            // Color Control Card
            _buildColorControlCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _device.name,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(_device.ip),
              ],
            ),
            Switch.adaptive(
              // Adaptive switch for platform-specific look
              value: _isOn,
              onChanged: _sendOnOffCommand,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrightnessControlCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          spacing: 8,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Brightness', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Icon(Icons.lightbulb_outline),
                Expanded(
                  child: Slider(
                    value: _brigtness.toDouble(),
                    min: 10, // Wiz min brightness
                    max: 100, // Wiz max brightness
                    divisions: 100,
                    onChanged: (value) {
                      _sendBrightnessCommand(value.round());
                    },
                  ),
                ),
                Text('$_brigtness%'),
              ],
            ),
            Text('Temperature', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Icon(Icons.heat_pump_outlined),
                Expanded(
                  child: Slider(
                    value: _kelvin.toDouble(),
                    min: 2200, // Wiz min brightness
                    max: 6500, // Wiz max brightness
                    divisions: 100,
                    onChanged: (value) {
                      _sendTempratureCommand(value.round());
                    },
                  ),
                ),
                Text('$_kelvin%'),
              ],
            ),
            DropdownButtonFormField<String>(
              value: _selectedSceneId.toString(),
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
              items: scenes.entries
                  .map(
                    (scene) => DropdownMenuItem(
                      value: scene.key.toString(),
                      child: Text(scene.value),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                _sendSceneIdCommand(int.parse(val ?? '0'));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorControlCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ColorPicker(
          paletteType: PaletteType.hsvWithValue,
          pickerColor: _color,
          onColorChanged: (Color color) {
            _sendColorCommand(color);
          },
          enableAlpha: false,
          labelTypes: [],
          pickerAreaBorderRadius: BorderRadius.all(Radius.circular(8)),
          pickerAreaHeightPercent: 0.5,
        ),
      ),
    );
  }
}
