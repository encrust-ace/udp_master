import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udp_master/device.dart';
import 'package:udp_master/udp_sender.dart';

double calculateVolume(List<double> samples) {
  if (samples.isEmpty) return 0;
  double sum = 0;
  for (var sample in samples) {
    sum += sample * sample;
  }
  return sqrt(sum / samples.length); // use sqrt() from dart:math
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

  final _record = AudioRecorder(); // For Linux

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  StreamSubscription? _micSubscription;

  List<LedDevice> _devices = [];
  UnmodifiableListView<LedDevice> get devices => UnmodifiableListView(_devices);

  // --- Device Management ---

  Future<List<LedDevice>> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceList = prefs.getStringList('devices') ?? [];
    _devices = deviceList
        .map((e) => LedDevice.fromJson(json.decode(e)))
        .toList();
    return _devices;
  }

  Future<void> _deviceActions(
    List<LedDevice> devices,
    DeviceAction action,
  ) async {
    List<LedDevice> existingDevices = await _loadDevices();
    switch (action) {
      case DeviceAction.add:
        existingDevices.addAll(devices);
        break;
      case DeviceAction.update:
        for (var device in devices) {
          int index = existingDevices.indexWhere((d) => d.ip == device.ip);
          if (index != -1) {
            existingDevices[index] = device;
          }
        }
        break;
      case DeviceAction.delete:
        for (var device in devices) {
          existingDevices.removeWhere((d) => d.ip == device.ip);
        }
        break;
    }
    final prefs = await SharedPreferences.getInstance();
    final deviceList = existingDevices
        .map((e) => json.encode(e.toJson()))
        .toList();
    await prefs.setStringList('devices', deviceList);
  }

  Future<void> loadDevices() async {
    await _loadDevices();
    notifyListeners(); // Notify that devices are loaded/changed
  }

  Future<void> deviceActions(
    List<LedDevice> updatedDevices,
    DeviceAction action,
  ) async {
    await _deviceActions(updatedDevices, action);
    loadDevices();
  }

  // Export saved devices
  Future<File?> exportDevicesToJsonFile(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceList = prefs.getStringList('devices') ?? [];

      // Decode each stringified device to proper Map
      final decodedDevices = deviceList.map((e) => json.decode(e)).toList();

      final jsonString = jsonEncode(decodedDevices);

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/devices.json');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Device saved in! ${directory.path}/devices.json'),
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

  // --- End Device Management ---

  Future<bool> _ensureMicPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    var status = await Permission.microphone.status;
    if (!status.isGranted) status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _startMicPlatform() async {
    try {
      await _platform.invokeMethod("startMic");
    } catch (e) {
      if (kDebugMode) {
        print("VisualizerService: Error starting mic via platform channel: $e");
      }
    }
  }

  Future<void> _stopMicPlatform() async {
    try {
      await _platform.invokeMethod("stopMic");
    } catch (e) {
      if (kDebugMode) {
        print("VisualizerService: Error stopping mic via platform channel: $e");
      }
    }
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
      await _startMicPlatform();
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
          stopVisualizer();
        },
        onDone: () {
          if (kDebugMode) {
            print("VisualizerService: Mic stream done.");
          }
          if (_isRunning) {
            stopVisualizer();
          }
        },
      );
    }

    _isRunning = true;
    notifyListeners(); // Notify UI or other parts of the app
    return true;
  }

  Future<void> stopVisualizer() async {
    if (!_isRunning && _micSubscription == null) return;

    if (Platform.isLinux) {
      await _record.stop();
    } else {
      await _micSubscription?.cancel();
      _micSubscription = null;
      await _stopMicPlatform();
    }

    _isRunning = false;
    notifyListeners();
  }

  Future<void> toggleVisualizer() async {
    if (_isRunning) {
      await stopVisualizer();
    } else {
      await startVisualizer();
    }
  }

  Future<void> _startMicLinux() async {
    if (!(await _record.hasPermission())) {
      if (kDebugMode) print("VisualizerService (Linux): No mic permission.");
      return;
    }

    await _record
        .startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 44100,
            numChannels: 1,
          ),
        )
        .then((stream) {
          _micSubscription = stream.listen((data) {
            if (!_isRunning || _devices.isEmpty) return;

            final int sampleCount = data.length ~/ 2;
            List<double> samples = List.generate(sampleCount, (i) {
              int lsb = data[2 * i];
              int msb = data[2 * i + 1];
              int sample = (msb << 8) | lsb;
              if (sample & 0x8000 != 0) sample -= 0x10000;
              return sample / 32768.0;
            });

            double volume = calculateVolume(samples);
            sendUdpPacketsToDevices(
              _devices.where((d) => d.isEnabled).toList(),
              volume,
            );
          });
        });
  }
}
