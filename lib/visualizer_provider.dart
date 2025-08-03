import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udp/udp.dart';
import 'package:udp_master/effects/center_pulse.dart';
import 'package:udp_master/effects/music_rhythm.dart';
import 'package:udp_master/effects/volume_bars.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/services/audio_analyzer.dart';
import 'package:udp_master/udp_sender.dart';

typedef EffectRenderFunction =
    List<int> Function({
      required int ledCount,
      required Float32List fft,
      double gain,
      // required double hue,
    });

const MethodChannel _platform = MethodChannel("mic_channel");
const EventChannel _micStreamChannel = EventChannel('mic_stream');

class VisualizerProvider with ChangeNotifier {
  static final VisualizerProvider _instance = VisualizerProvider._internal();
  final UdpSender _udpSender = UdpSender();
  factory VisualizerProvider() {
    return _instance;
  }

  VisualizerProvider._internal();

  final AudioAnalyzer _audioAnalyzer = AudioAnalyzer();
  CastMode _castMode = CastMode.audio;
  CastMode get castMode => _castMode;
  set castMode(CastMode value) {
    _castMode = value;
    notifyListeners();
  }

  final Recorder _recorder = Recorder.instance;
  // For Linux

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // Packets for internal simulation/debugging display, not for driving hardware directly.
  // This variable's update is decoupled from the main UDP send loop for performance.
  List<int> packets = [];

  int _currentSelectedTab = 0;
  int get currentSelectedTab => _currentSelectedTab;

  Future<void> setCurrentSelectedTab(int value) async {
    _currentSelectedTab = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('currentSelectedTab', value);
    notifyListeners();
  }

  StreamSubscription? _micSubscription;

  List<LedDevice> _devices = [];
  UnmodifiableListView<LedDevice> get devices => UnmodifiableListView(_devices);

  // --- Effect Management ---

  // --- Effect List ---
  List<LedEffect> _effects = [
    LedEffect(
      id: 'volume-bars',
      name: 'Volume Bars',
      parameters: {
        'gain': {'min': 1.0, 'max': 5.0, 'value': 1.0, 'steps': 8},
        'brightness': {'min': 0.0, 'max': 1.0, 'value': 1.0, 'steps': 10},
        'saturation': {'min': 0.0, 'max': 1.0, 'value': 1.0, 'steps': 10},
      },
    ),
    LedEffect(
      id: 'center-pulse',
      name: 'Center Pulse',
      parameters: {
        'gain': {'min': 1.0, 'max': 5.0, 'value': 1.0, 'steps': 8},
      },
    ),
    LedEffect(
      id: 'music-rhythm',
      name: 'Music Rhythm',
      parameters: {
        'gain': {'min': 1.0, 'max': 5.0, 'value': 1.0, 'steps': 8},
        'brightness': {'min': 0.0, 'max': 1.0, 'value': 1.0, 'steps': 10},
        'saturation': {'min': 0.0, 'max': 1.0, 'value': 1.0, 'steps': 10},
        'raiseSpeed': {'min': 5.0, 'max': 30.0, 'value': 12.5, 'steps': 10},
        'decaySpeed': {'min': 0.3, 'max': 1.0, 'value': 0.5, 'steps': 7},
        'dropSpeed': {'min': 0.1, 'max': 1.0, 'value': 0.5, 'steps': 9},
      },
    ),
  ];

  UnmodifiableListView<LedEffect> get effects => UnmodifiableListView(_effects);

  LedEffect getEffectById(String id) {
    try {
      return _effects.firstWhere(
        (effect) => effect.id == id,
        orElse: () => _effects.first,
      );
    } catch (_) {
      // Should ideally not happen if _effects is never empty and first is valid
      return _effects.first;
    }
  }

  Future<bool> updateEffect(
    LedEffect effect,
    String key,
    Map<String, dynamic> parameter,
  ) async {
    List<LedEffect> existingEffects = _effects;
    int index = existingEffects.indexWhere((e) => e.id == effect.id);
    if (index == -1) {
      return false;
    }
    existingEffects[index] = effect.copyWith(
      parameters: {...effect.parameters, key: parameter},
    );
    final prefs = await SharedPreferences.getInstance();
    final effectList = existingEffects
        .map((e) => json.encode(e.toJson()))
        .toList();
    await prefs.setStringList('effects', effectList);
    notifyListeners();
    _effects = existingEffects;
    return true;
  }

  Future<void> sendUdpToDevices({
    required List<LedDevice> targetDevices,
    required Float32List fft,
  }) async {
    if (_udpSender.udpInstance == null) {
      if (kDebugMode) {
        print("VisualizerService: UDP sender not initialized.");
      }
      return;
    }

    for (var device in targetDevices) {
      final target = Endpoint.unicast(
        InternetAddress(device.ip),
        port: Port(device.port),
      );

      try {
        if (device.type == DeviceType.wled ||
            device.type == DeviceType.esphome) {
          LedEffect effect = getEffectById(device.effect);
          late List<int> packetData;
          switch (effect.id) {
            case 'volume-bars':
              packetData = renderVerticalBars(
                device: device,
                fft: fft,
                gain: effect.parameters["gain"]?["value"] ?? 2.0,
                brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
                saturation: effect.parameters["saturation"]?["value"] ?? 1.0, 
                analyzer: _audioAnalyzer,
              );
              break;
            case 'center-pulse':
              packetData = renderCenterPulsePacket(
                device: device,
                fft: fft,
                gain: effect.parameters["gain"]?["value"] ?? 2.0,
              );
              break;
            case 'music-rhythm':
              packetData = renderBeatDropEffect(
                device: device,
                fft: fft,
                gain: effect.parameters["gain"]?["value"] ?? 2.0,
                brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
                saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
                raiseSpeed: effect.parameters["raiseSpeed"]?["value"] ?? 10.0,
                decaySpeed: effect.parameters["decaySpeed"]?["value"] ?? 1.0,
                dropSpeed: effect.parameters["dropSpeed"]?["value"] ?? 0.5,
              );
              break;
            default:
              continue;
          }
          if (packetData.isNotEmpty) {
            _udpSender.udpInstance?.send(packetData, target);
          }
        } else if (device.type == DeviceType.wiz) {
          LedEffect effect = getEffectById(device.effect);
          late List<int> packetData;
          switch (effect.id) {
            case 'volume-bars':
              packetData = renderVerticalBars(
                device: device,
                fft: fft,
                gain: effect.parameters["gain"]?["value"] ?? 2.0,
                brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
                saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
                analyzer: _audioAnalyzer,
              );
              break;
            default:
              continue;
          }

          final r = packetData.first > 0 ? packetData[0] : 0;
          final g = packetData.length > 1 ? packetData[1] : 0;
          final b = packetData.length > 2 ? packetData[2] : 0;
          final brightness = packetData.length > 3 ? packetData[3] : 0;

          final data = {
            "method": "setPilot",
            "params": {
              "state": brightness > 10,
              "r": r.clamp(0, 255),
              "g": g.clamp(0, 255),
              "b": b.clamp(0, 255),
              "dimming": brightness,
            },
          };

          final message = utf8.encode(jsonEncode(data));
          _udpSender.udpInstance?.send(message, target);
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error sending to ${device.ip}: $e");
        }
      }
    }
  }

  Future<void> simulatorPageData(LedDevice device, Float32List fft) async {
    // For simulators - update the 'packets' variable
    LedEffect effect = getEffectById(device.effect);
    late List<int> packetData;
    switch (effect.id) {
      case 'volume-bars':
        packetData = renderVerticalBars(
          device: device,
          fft: fft,
          gain: effect.parameters["gain"]?["value"] ?? 2.0,
          brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
          saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
          analyzer: _audioAnalyzer,
        );
        break;
      case 'center-pulse':
        packetData = renderCenterPulsePacket(
          device: device,
          fft: fft,
          gain: effect.parameters["gain"]?["value"] ?? 2.0,
        );
        break;
      case 'music-rhythm':
        packetData = renderBeatDropEffect(
          device: device,
          fft: fft,
          gain: effect.parameters["gain"]?["value"] ?? 2.0,
          brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
          saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
          raiseSpeed: effect.parameters["raiseSpeed"]?["value"] ?? 10.0,
          decaySpeed: effect.parameters["decaySpeed"]?["value"] ?? 1.0,
          dropSpeed: effect.parameters["dropSpeed"]?["value"] ?? 0.5,
        );
        break;
      default:
        packetData = []; // Or some default empty/error state
    }
    packets = packetData;
    notifyListeners(); // Notify listeners to update UI or other parts
  }

  // --- Device Management ---

  Future<void> initiateTheAppData() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceList = prefs.getStringList('devices') ?? [];
    _devices = deviceList
        .map((e) => LedDevice.fromJson(json.decode(e)))
        .toList();
    final currectSelectedTab = prefs.getInt('currentSelectedTab') ?? 0;
    _currentSelectedTab = currectSelectedTab;
    _udpSender.initiateUDPSender();
    notifyListeners();
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceList = _devices.map((device) => json.encode(device.toJson())).toList();
    await prefs.setStringList('devices', deviceList);
    notifyListeners(); // Only notify when device list actually changes
  }

  Future<String> deviceActions(LedDevice device, DeviceAction action) async {
    try {
      switch (action) {
        case DeviceAction.add:
          // Check for duplicate (by name or IP)
          final int index = _devices.indexWhere((d) => d.ip == device.ip);
          if (index != -1) {
            _devices[index] = device;
            return "Device already exists";
          } else {
            _devices.add(device);
            await _saveDevices();
            return "Device added successfully";
          }
        case DeviceAction.update:
          final int index = _devices.indexWhere((d) => d.id == device.id);
          if (index != -1) {
            _devices[index] = device;
            await _saveDevices();
            return "Device updated successfully";
          } else {
            return "Device not found, cannot update";
          }
        case DeviceAction.delete:
          _devices.removeWhere((d) => d.id == device.id);
          await _saveDevices();
          return "Device deleted successfully";
      }
    } catch (e) {
      return "Error: $e";
    }
  }

  // Export saved devices
  Future<File?> exportDevicesToJsonFile(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceList = prefs.getStringList('devices') ?? [];

      if (deviceList.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No devices to export.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return null;
      }

      final decodedDevices = deviceList.map((e) => json.decode(e)).toList();
      final jsonString = jsonEncode(decodedDevices);
      final jsonBytes = utf8.encode(jsonString);

      final outputPath = await FilePicker.platform.saveFile(
        fileName: 'devices.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: jsonBytes,
      );

      if (outputPath == null) {
        return null; // User canceled
      }

      // Only needed if you're on desktop and want to write again manually
      final file = File(outputPath);
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await file.writeAsBytes(
          jsonBytes,
        ); // optional — bytes were already written
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Devices exported successfully!')),
        );
      }

      return file;
    } catch (e) {
      if (kDebugMode) {
        print("VisualizerService: Failed to export devices to JSON: $e");
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export devices: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return null;
    }
  }

  Future<String> importDevicesFromJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: "Select Devices JSON File",
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true, // Read file content into memory
    );

    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null) {
      return "File selection canceled or no data found.";
    } else {
      final bytes = result.files.single.bytes!;
      final jsonString = utf8.decode(bytes);
      final List<dynamic> decodedList = jsonDecode(
        jsonString,
      ); // This is List<dynamic>
      final List<LedDevice> importedDevices = decodedList
          .map((e) => LedDevice.fromJson(e))
          .toList();

      final List<LedDevice> finalList = _devices;
      for (var device in importedDevices) {
        final existingIndex = _devices.indexWhere((d) => d.ip == device.ip);
        if (existingIndex != -1) {
          // Update existing device
          _devices[existingIndex] = device;
        } else {
          // Add new device
          finalList.add(device);
        }
      }
      await _saveDevices();
      return "Devices imported successfully!";
    }
  }

  // --- End Device Management ---

  Future<bool> _ensureMicPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    var status = await Permission.microphone.status;
    if (!status.isGranted) status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> startVisualizer() async {
    if (_isRunning) return true;

    bool granted = await _ensureMicPermission();
    if (!granted) {
      if (kDebugMode) {
        print("VisualizerService: Microphone permission not granted.");
      }
      return false;
    }

    if (Platform.isLinux) {
      await _startMicLinux();
    } else {
      await _startMicAndroid(); // Await for _startMicAndroid as well
    }

    _isRunning = true;
    notifyListeners(); // Notify UI or other parts of the app
    return true;
  }

  Future<void> _stopVisualizer() async {
    if (!_isRunning &&
        _micSubscription == null &&
        _udpSender.udpInstance == null) {
      return;
    }

    if (Platform.isLinux) {
      _recorder.stopStreamingData();
      _recorder.deinit();
    } else {
      await _micSubscription?.cancel();
      _micSubscription = null;
      await _platform.invokeMethod("stopMic");
    }

    _isRunning = false;
    notifyListeners();
  }

  Future<void> toggleVisualizer() async {
    if (_isRunning) {
      await _stopVisualizer();
    } else {
      await startVisualizer();
    }
  }

  Future<void> _startMicAndroid() async {
    await _platform.invokeMethod("startMic");
    _micSubscription = _micStreamChannel.receiveBroadcastStream().listen(
      (samples) {
        if (!_isRunning || _devices.isEmpty) return; // Guard clause

        // Ensure samples is List<double>
        List<double> doubleSamples;
        if (samples is List<dynamic>) {
          doubleSamples = samples.map((s) => (s as num).toDouble()).toList();
        } else {
          if (kDebugMode) {
            print(
              "VisualizerService: Received unexpected sample type: ${samples.runtimeType}",
            );
          }
          return;
        }
        sendUdpToDevices(
          targetDevices: _devices
              .where((d) => d.isEffectEnabled == true)
              .toList(),
          fft: Float32List.fromList(doubleSamples),
        );
        if (_currentSelectedTab == 2) {
          simulatorPageData(_devices[0], Float32List.fromList(doubleSamples));
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print("VisualizerService: Error on mic stream: $error");
        }
        _stopVisualizer();
      },
      onDone: () {
        if (kDebugMode) {
          print("VisualizerService: Mic stream done.");
        }
        if (_isRunning) {
          _stopVisualizer();
        }
      },
    );
  }

  Future<void> _startMicLinux() async {
    try {
      await _recorder.init(
        format: PCMFormat.f32le,
        sampleRate: 44100,
        channels: RecorderChannels.mono,
      );
      _recorder.setFftSmoothing(0.1);

      _recorder.start();
      _recorder.startStreamingData();

      _micSubscription = _recorder.uint8ListStream.listen((_) {
        if (!_isRunning || _devices.isEmpty) return;

        final Float32List fft = _recorder.getFft();

        sendUdpToDevices(
          targetDevices: _devices.where((d) => d.isEffectEnabled).toList(),
          fft: fft,
        );
        if (_currentSelectedTab == 2) {
          simulatorPageData(_devices[0], fft);
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print("VisualizerService (Linux): Error starting mic: $e");
      }
    }
  }
}
