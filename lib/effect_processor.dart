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

// These would typically be defined in your main.dart or a config file
const MethodChannel _platform = MethodChannel("mic_channel");
const EventChannel _micStreamChannel = EventChannel('mic_stream');

class VisualizerService with ChangeNotifier {
  // Or use ValueNotifier for simpler cases
  static final VisualizerService _instance = VisualizerService._internal();

  factory VisualizerService() {
    return _instance;
  }

  VisualizerService._internal();

  bool _isRunning = false;
  StreamSubscription? _micSubscription;
  List<LedDevice> _devices = []; // Keep a copy of devices to send data to

  bool get isRunning => _isRunning;
  List<LedDevice> get devices => _devices;

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

  void setTargetDevices(List<LedDevice> devices) {
    _devices = devices;
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
    notifyListeners(); // Notify UI
    print("VisualizerService: Visualizer stopped.");
  }

  Future<void> toggleVisualizer() async {
    if (_isRunning) {
      await stopVisualizer();
    } else {
      await startVisualizer();
      // Handle the boolean result of startVisualizer if needed (e.g., show error)
    }
  }
}
