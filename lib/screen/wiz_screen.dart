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

class _DeviceControlScreenState extends State<DeviceControlScreen>
    with WidgetsBindingObserver {
  late LedDevice _device;
  final UdpSender _udpSender = UdpSender();

  bool _isOn = false;
  int _brigtness = 100;
  int _kelvin = 4600;
  Color _color = Colors.white;
  int _selectedSceneId = 2;
  bool _isConnected = false;

  // Timers for debouncing and periodic updates
  Timer? _brightnessDebounceTimer;
  Timer? _colorDebounceTimer;
  Timer? _temperatureDebounceTimer;
  Timer? _statusUpdateTimer;
  Timer? _reconnectTimer;

  // Stream subscription for UDP responses
  StreamSubscription<Datagram?>? _udpSubscription;

  // Track if user is actively interacting to avoid conflicts
  bool _userInteracting = false;
  DateTime _lastUserInteraction = DateTime.now();

  // Connection retry configuration
  static const Duration _statusUpdateInterval = Duration(seconds: 5);
  static const Duration _reconnectInterval = Duration(seconds: 10);

  Future<void> sendUdpCommand(dynamic data, LedDevice device) async {
    try {
      final target = Endpoint.unicast(
        InternetAddress(device.ip),
        port: Port(device.port),
      );
      await _udpSender.udpInstance?.send(data, target);
    } catch (e) {
      if (kDebugMode) {
        print("Failed to send UDP command: $e");
      }
      _handleConnectionError();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _device = widget.device;
    _initializeConnection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupTimers();
    _udpSubscription?.cancel();
    _udpSender.udpInstance?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _initializeConnection();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _pauseUpdates();
        break;
      case AppLifecycleState.detached:
        _cleanupTimers();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _cleanupTimers() {
    _brightnessDebounceTimer?.cancel();
    _colorDebounceTimer?.cancel();
    _temperatureDebounceTimer?.cancel();
    _statusUpdateTimer?.cancel();
    _reconnectTimer?.cancel();
  }

  void _pauseUpdates() {
    _statusUpdateTimer?.cancel();
  }

  Future<void> _initializeConnection() async {
    try {
      await _udpSender.initiateUDPSender();
      _setupUdpListener();
      await _getDeviceStatus();
      _startPeriodicStatusUpdates();
      setState(() {
        _isConnected = true;
      });
    } catch (e) {
      if (kDebugMode) {
        print("Failed to initialize connection: $e");
      }
      _handleConnectionError();
    }
  }

  void _setupUdpListener() {
    _udpSubscription?.cancel();
    _udpSubscription = _udpSender.udpInstance?.asStream().listen(
      (datagram) => _handleUdpResponse(datagram),
      onError: (error) {
        if (kDebugMode) {
          print("UDP stream error: $error");
        }
        _handleConnectionError();
      },
    );
  }

  void _handleConnectionError() {
    setState(() {
      _isConnected = false;
    });

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectInterval, () {
      if (mounted) {
        _initializeConnection();
      }
    });
  }

  void _startPeriodicStatusUpdates() {
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = Timer.periodic(_statusUpdateInterval, (timer) {
      if (mounted && _isConnected && !_isUserCurrentlyInteracting()) {
        _getDeviceStatus();
      }
    });
  }

  bool _isUserCurrentlyInteracting() {
    return _userInteracting ||
        DateTime.now().difference(_lastUserInteraction).inSeconds < 2;
  }

  void _markUserInteraction() {
    _userInteracting = true;
    _lastUserInteraction = DateTime.now();
    Timer(const Duration(milliseconds: 500), () {
      _userInteracting = false;
    });
  }

  void _sendOnOffCommand(bool isOn) async {
    _markUserInteraction();
    final Map<String, dynamic> data = {
      "method": "setPilot",
      "params": {"state": isOn},
    };
    final List<int> message = utf8.encode(jsonEncode(data));
    await sendUdpCommand(message, _device);

    // Optimistic UI update
    if (mounted) {
      setState(() {
        _isOn = isOn;
      });
    }
  }

  void _sendBrightnessCommand(int brightness) {
    _markUserInteraction();
    if (mounted) {
      setState(() {
        _brigtness = brightness;
      });
    }

    _brightnessDebounceTimer?.cancel();
    _brightnessDebounceTimer = Timer(
      const Duration(
        milliseconds: 300,
      ), // Reduced debounce time for better responsiveness
      () async {
        if (!mounted) return;
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
    _markUserInteraction();
    if (mounted) {
      setState(() {
        _kelvin = kelvin;
      });
    }

    _temperatureDebounceTimer?.cancel();
    _temperatureDebounceTimer = Timer(
      const Duration(milliseconds: 300),
      () async {
        if (!mounted) return;
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
    _markUserInteraction();
    if (mounted) {
      setState(() {
        _color = color;
        _isOn = true;
      });
    }

    _colorDebounceTimer?.cancel();
    _colorDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      int r = (color.r * 255.0).round() & 0xff;
      int g = (color.g * 255.0).round() & 0xff;
      int b = (color.b * 255.0).round() & 0xff;

      final Map<String, dynamic> data = {
        "method": "setPilot",
        "params": {'state': true, 'r': r, 'g': g, 'b': b},
      };

      // Smart white detection with improved logic
      if (_isNearWhite(r, g, b)) {
        data['params']['temp'] = _calculateColorTemperature(r, g, b);
      }

      final List<int> message = utf8.encode(jsonEncode(data));
      await sendUdpCommand(message, _device);
    });
  }

  bool _isNearWhite(int r, int g, int b) {
    const int threshold = 10;
    const int minBrightness = 180;

    return (r - g).abs() <= threshold &&
        (g - b).abs() <= threshold &&
        (r - b).abs() <= threshold &&
        r >= minBrightness &&
        g >= minBrightness &&
        b >= minBrightness;
  }

  int _calculateColorTemperature(int r, int g, int b) {
    // Simple heuristic for color temperature based on RGB values
    double avg = (r + g + b) / 3.0;
    if (avg > 240) return 6500; // Cool white
    if (avg > 220) return 5000; // Neutral white
    if (avg > 200) return 4000; // Warm white
    return 2700; // Very warm white
  }

  void _sendSceneIdCommand(int sceneId) {
    _markUserInteraction();
    if (mounted) {
      setState(() {
        _selectedSceneId = sceneId;
        _isOn = true; // Scenes automatically turn on the light
      });
    }

    final Map<String, dynamic> data = {
      "method": "setPilot",
      "params": {"state": true, "sceneId": sceneId},
    };
    final List<int> message = utf8.encode(jsonEncode(data));
    sendUdpCommand(message, _device);
  }

  Future<void> _getDeviceStatus() async {
    if (!_isConnected) return;

    try {
      final target = Endpoint.unicast(
        InternetAddress(_device.ip),
        port: Port(_device.port),
      );

      final Map<String, dynamic> request = {"method": "getPilot", "params": {}};
      final List<int> message = utf8.encode(jsonEncode(request));
      await _udpSender.udpInstance?.send(message, target);
    } catch (e) {
      if (kDebugMode) {
        print("Failed to request device status: $e");
      }
      _handleConnectionError();
    }
  }

  void _handleUdpResponse(Datagram? datagram) {
    if (datagram == null || !mounted || _isUserCurrentlyInteracting()) return;

    try {
      final response = jsonDecode(utf8.decode(datagram.data));
      final result = response["result"];

      if (result != null) {
        setState(() {
          // Update state only if not currently interacting
          if (result.containsKey("state")) {
            _isOn = result["state"] ?? false;
          }
          if (result.containsKey("dimming")) {
            _brigtness = result["dimming"] ?? 100;
          }
          if (result.containsKey("temp")) {
            _kelvin = result["temp"] ?? 4600;
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
          if (result.containsKey("sceneId")) {
            _selectedSceneId = result["sceneId"] ?? 2;
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("Failed to parse UDP response: $e");
      }
    }
  }

  // --- UI Build Methods ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_device.name} Control'),
        elevation: 0,
        actions: [
          // Connection status indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Icon(
              _isConnected ? Icons.wifi : Icons.wifi_off,
              color: _isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _getDeviceStatus,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _device.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _device.ip,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _isConnected ? Icons.circle : Icons.circle_outlined,
                        size: 12,
                        color: _isConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isConnected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isConnected ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: _isOn,
              onChanged: _isConnected ? _sendOnOffCommand : null,
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
            const Text(
              'Brightness',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                const Icon(Icons.lightbulb_outline),
                Expanded(
                  child: Slider(
                    value: _brigtness.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 90,
                    label: '$_brigtness%',
                    onChanged: _isConnected
                        ? (value) {
                            _sendBrightnessCommand(value.round());
                          }
                        : null,
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text('$_brigtness%', textAlign: TextAlign.end),
                ),
              ],
            ),
            const Text(
              'Temperature',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                const Icon(Icons.thermostat_outlined),
                Expanded(
                  child: Slider(
                    value: _kelvin.toDouble(),
                    min: 2200,
                    max: 6500,
                    divisions: 43,
                    label: '${_kelvin}K',
                    onChanged: _isConnected
                        ? (value) {
                            _sendTempratureCommand(value.round());
                          }
                        : null,
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text('${_kelvin}K', textAlign: TextAlign.end),
                ),
              ],
            ),
            const Text('Scenes', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButtonFormField<String>(
              value: scenes.containsKey(_selectedSceneId)
                  ? _selectedSceneId.toString()
                  : '2',
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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
              onChanged: _isConnected
                  ? (val) {
                      if (val != null) {
                        _sendSceneIdCommand(int.parse(val));
                      }
                    }
                  : null,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Color', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ColorPicker(
              paletteType: PaletteType.hsvWithValue,
              pickerColor: _color,
              onColorChanged: (Color color) {
                _sendColorCommand(color);
              },
              enableAlpha: false,
              labelTypes: const [],
              pickerAreaBorderRadius: const BorderRadius.all(
                Radius.circular(8),
              ),
              pickerAreaHeightPercent: 0.5,
            ),
          ],
        ),
      ),
    );
  }
}
