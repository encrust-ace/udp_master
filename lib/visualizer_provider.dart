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
import 'package:udp_master/effects/rail_track.dart';
import 'package:udp_master/effects/test2.dart';
import 'package:udp_master/effects/volume_bars.dart';
import 'package:udp_master/models.dart';

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

  factory VisualizerProvider() {
    return _instance;
  }

  VisualizerProvider._internal();

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
  List<int> packets = [];

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
        'gain': {'min': 0.0, 'max': 5.0, 'value': 2.0},
        'brightness': {'min': 0.0, 'max': 1.0, 'value': 1.0},
        'saturation': {'min': 0.0, 'max': 1.0, 'value': 1.0},
      },
    ),
    LedEffect(
      id: 'center-pulse',
      name: 'Center Pulse',
      parameters: {
        'gain': {'min': 0.0, 'max': 5.0, 'value': 2.0},
      },
    ),
    LedEffect(
      id: 'music-rhythm',
      name: 'Music Rhythm',
      parameters: {
        'gain': {'min': 0.0, 'max': 5.0, 'value': 2.0},
        'brightness': {'min': 0.0, 'max': 1.0, 'value': 1.0},
        'saturation': {'min': 0.0, 'max': 1.0, 'value': 1.0},
        'raiseSpeed': {'min': 5.0, 'max': 50.0, 'value': 10.0},
        'decaySpeed': {'min': 1.0, 'max': 10.0, 'value': 1.0},
        'dropSpeed': {'min': 0.1, 'max': 1.0, 'value': 0.5},
      },
    ),
    LedEffect(
      id: 'rail-track',
      name: 'Rail Track',
      parameters: {
        'gain': {'min': 0.0, 'max': 5.0, 'value': 2.0},
        'brightness': {'min': 0.0, 'max': 1.0, 'value': 1.0},
        'saturation': {'min': 0.0, 'max': 1.0, 'value': 1.0},
      },
    ),
  ];

  UnmodifiableListView<LedEffect> get effects => UnmodifiableListView(_effects);

  LedEffect? getEffectById(String id) {
    try {
      return _effects.firstWhere((effect) => effect.id == id);
    } catch (_) {
      return null;
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
    final udp = await UDP.bind(Endpoint.any());

    for (var device in targetDevices) {
      if (!device.isEnabled) continue;

      final target = Endpoint.unicast(
        InternetAddress(device.ip),
        port: Port(device.port),
      );

      try {
        if (device.type == DeviceType.wled) {
          LedEffect? effect = getEffectById(device.effect) ?? _effects.first;
          late List<int> packetData;
          switch (effect.id) {
            case 'volume-bars':
              packetData = renderVerticalBars(
                device: device,
                fft: fft,
                gain: effect.parameters["gain"]?["value"] ?? 2.0,
                brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
                saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
              );
              break;
            case 'center-pulse':
              packetData = renderCenterPulsePacket(
                ledCount: device.ledCount,
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
            case 'rail-track':
              packetData = renderRailTrack(
                device: device,
                fft: fft,
                gain: effect.parameters["gain"]?["value"] ?? 2.0,
                brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
                saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
              );
              break;
            default:
              continue;
          }
          if (packetData.isNotEmpty) {
            udp.send(packetData, target);
          }
        } else if (device.type == DeviceType.wiz) {
          LedEffect? effect = getEffectById(device.effect) ?? _effects.first;
          late List<int> packetData;
          switch (effect.id) {
            case 'volume-bars':
              packetData = renderVerticalBars(
                device: device,
                fft: fft,
                gain: effect.parameters["gain"]?["value"] ?? 2.0,
                brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
                saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
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
              "state": brightness > 20,
              "r": r.clamp(0, 255),
              "g": g.clamp(0, 255),
              "b": b.clamp(0, 255),
              "dimming": brightness,
            },
          };

          final message = utf8.encode(jsonEncode(data));
          udp.send(message, target);
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error sending to ${device.ip}: $e");
        }
      }
    }
    // For simulators
    final device = LedDevice(
      name: "Simulator",
      ip: "127.0.0.1",
      port: 12345,
      ledCount: 50,
      effect: "volume-bars",
      isEnabled: true,
      type: DeviceType.esphome,
    );
    late List<int> packetData;
    packetData = renderBeatDropEffectTest(
      device: device,
      fft: fft,
      gain: 1,
      brightness: 1,
      saturation: 1,
    );
    packets = packetData;
    notifyListeners();
  }

  // --- Device Management ---

  Future<List<LedDevice>> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceList = prefs.getStringList('devices') ?? [];
    _devices = deviceList
        .map((e) => LedDevice.fromJson(json.decode(e)))
        .toList();
    notifyListeners();
    return _devices;
  }

  Future<bool> deviceActions(
    BuildContext context,
    List<LedDevice> devices,
    DeviceAction action,
  ) async {
    try {
      List<LedDevice> existingDevices = await loadDevices();
      switch (action) {
        case DeviceAction.add:
          for (LedDevice device in devices) {
            // Check for duplicate (by name or IP)
            final int index = existingDevices.indexWhere(
              (d) => d.ip == device.ip,
            );
            if (index != -1) {
              existingDevices[index] = device;
              continue;
            } else {
              existingDevices.add(device);
            }
          }
          break;
        case DeviceAction.update:
          for (LedDevice device in devices) {
            int index = existingDevices.indexWhere((d) => d.ip == device.ip);
            if (index != -1) {
              existingDevices[index] = device;
            }
          }
          break;
        case DeviceAction.delete:
          for (LedDevice device in devices) {
            existingDevices.removeWhere((d) => d.ip == device.ip);
          }
          break;
      }
      final prefs = await SharedPreferences.getInstance();
      final deviceList = existingDevices
          .map((e) => json.encode(e.toJson()))
          .toList();
      await prefs.setStringList('devices', deviceList);
      notifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device list updated successfully!')),
        );
      }
      _devices = existingDevices;
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return false;
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

  Future<void> importDevicesFromJsonFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: "Select Devices JSON File",
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true, // Read file content into memory
    );

    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File is incorrect!'),
            backgroundColor: Colors.deepOrange,
          ),
        );
      }
    } else {
      final bytes = result.files.single.bytes!;
      final jsonString = utf8.decode(bytes);
      final List<dynamic> decodedList = jsonDecode(
        jsonString,
      ); // This is List<dynamic>
      final List<LedDevice> importedDevices = decodedList
          .map((e) => LedDevice.fromJson(e))
          .toList();

      deviceActions(context, importedDevices, DeviceAction.add);
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
      _startMicAndroid();
    }

    _isRunning = true;
    notifyListeners(); // Notify UI or other parts of the app
    return true;
  }

  Future<void> _stopVisualizer() async {
    if (!_isRunning && _micSubscription == null) return;

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
          targetDevices: _devices.where((d) => d.isEnabled).toList(),
          fft: Float32List.fromList(doubleSamples),
        );
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
          targetDevices: _devices.where((d) => d.isEnabled).toList(),
          fft: fft,
        );
      });
    } catch (e) {
      if (kDebugMode) {
        print("VisualizerService (Linux): Error starting mic: $e");
      }
    }
  }
}
