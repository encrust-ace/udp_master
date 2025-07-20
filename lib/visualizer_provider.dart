import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/led_effects.dart';

double calculateVolume(List<double> samples) {
  if (samples.isEmpty) return 0;
  double sum = 0;
  for (var sample in samples) {
    sum += sample * sample;
  }
  return sqrt(sum / samples.length); // use sqrt() from dart:math
}

RawDatagramSocket? _socket;

Future<void> _ensureSocketInitialized() async {
  if (_socket == null) {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (e) {
      if (kDebugMode) {
        // Minimal print for error
        // print("Socket init error: $e");
      }
    }
  }
}

Future<void> sendUdpPacketsToDevices(
  List<LedDevice> targetDevices,
  double volume, // Assumed to be normalized 0.0 - 1.0
) async {
  await _ensureSocketInitialized();
  if (_socket == null) {
    return;
  }

  double currentHue = (DateTime.now().millisecondsSinceEpoch % 36000) / 36000.0;

  for (var device in targetDevices) {
    if (!device.isEnabled) continue;

    LedEffect? effect = getEffectById(device.effect);

    if (effect == null) {
      if (availableEffects.isNotEmpty) {
        effect = availableEffects.first;
      } else {
        continue;
      }
    }

    List<int> packetData = effect.renderFunction(
      deviceIpKey: device.ip, // Use device.ip as the key for stateful effects
      ledCount: device.ledCount,
      volume: volume,
      hue: currentHue,
      // Optional parameters like peakHueOffset, peakDecayMillis, etc.,
      // will be passed as null if not explicitly provided here.
      // The render functions or the lambdas in availableEffects
      // should handle their defaults.
    );

    if (packetData.isNotEmpty && packetData[0] != 0x00) {
      try {
        _socket?.send(packetData, InternetAddress(device.ip), device.port);
      } catch (e) {
        if (kDebugMode) {
          // Minimal print for error
          // print("UDP send error to ${device.ip}: $e");
        }
      }
    }
  }
}

void disposeSocket() {
  _socket?.close();
  _socket = null;
}

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

  StreamSubscription? _micSubscription;

  List<LedDevice> _devices = [];
  UnmodifiableListView<LedDevice> get devices => UnmodifiableListView(_devices);

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
    List<LedDevice> existingDevices = await loadDevices();
    switch (action) {
      case DeviceAction.add:
        for (LedDevice device in devices) {
          // Check for duplicate (by name or IP)
          final alreadyExists = existingDevices.any(
            (d) =>
                d.name.toLowerCase() == device.name.toLowerCase() ||
                d.ip == device.ip,
          );

          if (context.mounted && alreadyExists) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Device with same name or IP already exists!'),
                backgroundColor: Colors.redAccent,
              ),
            );
            return false;
          }
          existingDevices.addAll(devices);
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
        SnackBar(
          content: Text('Device ${action}ed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
    _devices = existingDevices;
    return true;
  }

  // Export saved devices
  Future<File?> exportDevicesToJsonFile(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceList = prefs.getStringList('devices') ?? [];

      // Decode each stringified device to proper Map
      final decodedDevices = deviceList.map((e) => json.decode(e)).toList();

      final jsonString = jsonEncode(decodedDevices);

      final directory = await getDownloadsDirectory();
      final file = File('${directory?.path}/devices.json');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Device saved in! ${directory?.path}/devices.json'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return await file.writeAsString(jsonString);
    } catch (e) {
      if (kDebugMode) {
        print("VisualizerService: Failed to export devices to JSON: $e");
      }
      return null;
    }
  }

  Future<bool> importDevicesFromJsonFile(BuildContext context) async {
    try {
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
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      final bytes = result.files.single.bytes!;
      final jsonString = utf8.decode(bytes);
      final List<dynamic> decodedList = jsonDecode(jsonString);

      final List<LedDevice> devicesToAdd = [];
      for (final device in decodedList) {
        final alreadyExists = _devices.any(
          (d) =>
              d.name.toLowerCase() == device.name.toLowerCase() ||
              d.ip == device.ip,
        );
        if (!alreadyExists) {
          devicesToAdd.add(device);
        }
      }

      devicesToAdd.addAll(_devices);

      final List<String> encodedDevices = devicesToAdd
          .map((e) => jsonEncode(e))
          .toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('devices', encodedDevices);
      _devices = devicesToAdd;
      notifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Devices imported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (kDebugMode) {
        print("Imported ${encodedDevices.length} devices successfully.");
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print("Error importing devices from file picker: $e");
      }
      return false;
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

        double volume = calculateVolume(doubleSamples);
        sendUdpPacketsToDevices(
          _devices.where((d) => d.isEnabled).toList(),
          volume,
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
        sampleRate: 22050,
        channels: RecorderChannels.mono,
      );
      _recorder.start();
      _recorder.startStreamingData();

      _micSubscription = _recorder.uint8ListStream.listen((data) {
        if (!_isRunning || _devices.isEmpty) return;

        final floatSamples = data.toF32List(from: PCMFormat.f32le);
        final List<double> samples = floatSamples.toList();

        double volume = calculateVolume(samples);
        sendUdpPacketsToDevices(
          _devices.where((d) => d.isEnabled).toList(),
          volume,
        );
      });
    } catch (e) {
      if (kDebugMode) {
        print("VisualizerService (Linux): Error starting mic: $e");
      }
    }
  }
}
