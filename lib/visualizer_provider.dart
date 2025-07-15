import 'dart:collection';
import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
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

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  StreamSubscription? _micSubscription;


  List<LedDevice> _devices = [];
  UnmodifiableListView<LedDevice> get devices => UnmodifiableListView(_devices);


  // --- Device Management ---
  Future<void> loadAndSetInitialDevices() async {
    _devices = await loadDevices(); // Your existing function to load from SharedPreferences/DB
    if (kDebugMode) {
      print("VisualizerService: Loaded ${_devices.length} devices.");
    }
    notifyListeners(); // Notify that devices are loaded/changed
  }

  Future<void> addDevice(LedDevice newDevice) async {
    _devices.add(newDevice);
    await updateDevices(_devices); // Your existing function to save all devices
    if (kDebugMode) {
      print("VisualizerService: Added device '${newDevice.name}'.");
    }
    notifyListeners();
  }

  Future<void> updateDevice(LedDevice updatedDevice) async {
    int index = _devices.indexWhere((d) => d.ip == updatedDevice.ip); // Assuming LedDevice has a unique 'id'
    if (index != -1) {
      _devices[index] = updatedDevice;
      await updateDevices(_devices);
      if (kDebugMode) {
        print("VisualizerService: Updated device '${updatedDevice.name}'.");
      }
      notifyListeners();
    }
  }

  Future<void> removeDevice(String ip) async { // Remove by ID
    _devices.removeWhere((d) => d.ip == ip);
    await updateDevices(_devices);
    if (kDebugMode) {
      print("VisualizerService: Removed device with ID '$ip'.");
    }
    notifyListeners();
  }

  Future<void> updateAllDeviceEffects(String effect) async {
    _devices = _devices.map((d) => d.copyWith(effect: effect)).toList();
    await updateDevices(_devices);
    notifyListeners();
  }
  // --- End Device Management ---

  Future<bool> _ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
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

    await _startMicPlatform();
    if (_devices.isEmpty) {
      if (kDebugMode) {
        print(
          "VisualizerService: No target devices set. Visualizer will start but not send data yet.",
        );
      }
    }

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

    _isRunning = true;
    notifyListeners(); // Notify UI or other parts of the app
    return true;
  }

  Future<void> stopVisualizer() async {
    if (!_isRunning && _micSubscription == null) return;

    await _micSubscription?.cancel();
    _micSubscription = null;
    await _stopMicPlatform();
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
}
