import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udp_master/effects/center_pulse.dart';
import 'package:udp_master/effects/music_rhythm.dart';
import 'package:udp_master/effects/vertical_bars.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/services/audio_analyzer.dart';
import 'package:udp_master/services/udp_sender.dart';

// Method and Event channels for platform-specific communication
const MethodChannel _platform = MethodChannel("mic_channel");
const EventChannel _micStreamChannel = EventChannel('mic_stream');

class VisualizerProvider with ChangeNotifier {
  // Singleton instance
  static final VisualizerProvider _instance = VisualizerProvider._internal();

  factory VisualizerProvider() => _instance;

  VisualizerProvider._internal();

  // --- Core Services & State ---
  final UdpSender _udpSender = UdpSender();
  final Recorder _recorder = Recorder.instance;
  final AudioAnalyzer _audioAnalyzer = AudioAnalyzer(
    sampleRate: 44100,
    fftSize: 1024,
  );

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  int _currentSelectedTab = 0;
  int get currentSelectedTab => _currentSelectedTab;

  List<int> packets = []; // For internal simulation/debugging display
  StreamSubscription? _micSubscription;

  // --- Device & Display Side Management ---
  List<LedDevice> _devices = [];
  UnmodifiableListView<LedDevice> get devices => UnmodifiableListView(_devices);

  List<DisplaySide> _displaySides = [];
  UnmodifiableListView<DisplaySide> get displaySides =>
      UnmodifiableListView(_displaySides);

  // --- Effect Management ---
  String _globalEffectId = 'vertical-bars';
  String get globalEffectId => _globalEffectId;

  // Using a map for faster effect lookup by ID
  final Map<String, LedEffect> _effects = {
    'vertical-bars': LedEffect(
      id: 'vertical-bars',
      name: 'Vertical Bars',
      parameters: {
        'gain': {
          'min': 0.0,
          'max': 5.0,
          'value': 0.0,
          'steps': 10,
          'default': 0.0,
        },
        'brightness': {
          'min': 0.0,
          'max': 1.0,
          'value': 1.0,
          'steps': 10,
          'default': 1.0,
        },
        'saturation': {
          'min': 0.0,
          'max': 1.0,
          'value': 1.0,
          'steps': 10,
          'default': 1.0,
        },
        'smooth': {
          'min': 0.0,
          'max': 1.0,
          'value': 0.7,
          'steps': 10,
          'default': 0.7,
        },
      },
    ),
    'center-pulse': LedEffect(
      id: 'center-pulse',
      name: 'Center Pulse',
      parameters: {
        'gain': {
          'min': 0.0,
          'max': 5.0,
          'value': 0.0,
          'steps': 10,
          'default': 0.0,
        },
        'brightness': {
          'min': 0.0,
          'max': 1.0,
          'value': 1.0,
          'steps': 10,
          'default': 1.0,
        },
        'saturation': {
          'min': 0.0,
          'max': 1.0,
          'value': 1.0,
          'steps': 10,
          'default': 1.0,
        },
      },
    ),
    'music-rhythm': LedEffect(
      id: 'music-rhythm',
      name: 'Music Rhythm',
      parameters: {
        'gain': {
          'min': 0.0,
          'max': 5.0,
          'value': 0.0,
          'steps': 10,
          'default': 0.0,
        },
        'brightness': {
          'min': 0.0,
          'max': 1.0,
          'value': 1.0,
          'steps': 10,
          'default': 1.0,
        },
        'saturation': {
          'min': 0.0,
          'max': 1.0,
          'value': 1.0,
          'steps': 10,
          'default': 1.0,
        },
        'raiseSpeed': {
          'min': 5.0,
          'max': 30.0,
          'value': 10.0,
          'steps': 10,
          'default': 10.0,
        },
        'decaySpeed': {
          'min': 0.3,
          'max': 1.0,
          'value': 0.5,
          'steps': 7,
          'default': 0.5,
        },
        'dropSpeed': {
          'min': 0.1,
          'max': 1.0,
          'value': 0.5,
          'steps': 9,
          'default': 0.5,
        },
      },
    ),
  };

  UnmodifiableListView<LedEffect> get effects =>
      UnmodifiableListView(_effects.values.toList());

  LedEffect getEffectById(String id) => _effects[id] ?? _effects.values.first;

  // --- Screen Sync Properties ---
  GlobalKey? _videoKey;
  MediaStream? _screenStream;
  Timer? _screenTimer;

  // ----------------------------------------------------------------------
  // --- Public Methods ---
  // ----------------------------------------------------------------------

  Future<void> initiateTheAppData() async {
    final prefs = await SharedPreferences.getInstance();

    // Restore data from SharedPreferences
    await _restoreDevices(prefs);
    await _restoreEffects(prefs);
    await _restoreDisplaySides(prefs);

    _currentSelectedTab = prefs.getInt('currentSelectedTab') ?? 0;
    _globalEffectId = prefs.getString('globalEffect') ?? _effects.keys.first;

    // Initialize UDP sender
    _udpSender.initiateUDPSender();
    notifyListeners();
  }

  Future<bool> setCurrentSelectedTab(int value) async {
    _currentSelectedTab = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('currentSelectedTab', value);
    notifyListeners();
    return true;
  }

  Future<bool> setGlobalEffect(String effectId) async {
    _globalEffectId = effectId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('globalEffect', effectId);
    notifyListeners();
    return true;
  }

  Future<void> toggleVisualizer() async {
    _isRunning ? await _stopVisualizer() : await _startVisualizer();
  }

  Future<bool> startScreenSync(MediaStream stream, GlobalKey key) async {
    if (_isRunning) return false;
    _screenStream = stream;
    _videoKey = key;
    _isRunning = true;
    _screenTimer?.cancel();
    _screenTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      await _processFrameAndSend();
    });
    notifyListeners();
    return true;
  }

  Future<void> stopScreenSync() async {
    if (!_isRunning) return;
    _screenTimer?.cancel();
    _screenTimer = null;
    _isRunning = false;
    await _screenStream?.dispose();
    _screenStream = null;
    notifyListeners();
  }

  // --- Device Actions ---
  Future<String> deviceActions(LedDevice device, DeviceAction action) async {
    try {
      switch (action) {
        case DeviceAction.add:
          if (!_devices.any((d) => d.id == device.id)) {
            _devices.add(device);
          } else {
            return "Device already exists";
          }
          break;
        case DeviceAction.update:
          final index = _devices.indexWhere((d) => d.id == device.id);
          if (index != -1) {
            _devices[index] = device;
          } else {
            return "Device not found, cannot update";
          }
          break;
        case DeviceAction.delete:
          _devices.removeWhere((d) => d.id == device.id);
          break;
      }
      await _saveDevices();
      return "Device updated successfully";
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<File?> exportDevicesToJsonFile(BuildContext context) async {
    // Simplified logic, using a helper function to avoid code duplication
    return _exportDataToJsonFile(
      context,
      'devices',
      'devices.json',
      (e) => LedDevice.fromJson(json.decode(e)),
    );
  }

  Future<String> importDevicesFromJsonFile() async {
    // Simplified logic, using a helper function
    return _importDataFromJsonFile<LedDevice>(
      'devices',
      (e) => LedDevice.fromJson(e),
      (importedDevices) {
        final existingIps = _devices.map((d) => d.ip).toSet();
        for (var device in importedDevices) {
          if (!existingIps.contains(device.ip)) {
            _devices.add(device);
          }
        }
      },
    );
  }

  // --- Effect Actions ---
  Future<bool> updateEffect(
    LedEffect effect,
    String key,
    Map<String, dynamic> parameter,
  ) async {
    final updatedEffect = effect.copyWith(
      parameters: {...effect.parameters, key: parameter},
    );
    _effects[effect.id] = updatedEffect;
    await _saveEffects();
    notifyListeners();
    return true;
  }

  Future<bool> resetEffect(LedEffect effect) async {
    final defaultEffect = _effects[effect.id]!.copyWith(
      parameters: Map.fromEntries(
        effect.parameters.entries.map(
          (e) => MapEntry(e.key, {...e.value, 'value': e.value['default']}),
        ),
      ),
    );
    _effects[effect.id] = defaultEffect;
    await _saveEffects();
    notifyListeners();
    return true;
  }

  // --- Display Side Actions ---
  Future<bool> addOrUpdateDisplaySide(DisplaySide side) async {
    final index = _displaySides.indexWhere((s) => s.position == side.position);
    if (index != -1) {
      _displaySides[index] = side;
    } else {
      _displaySides.add(side);
    }
    await _saveDisplaySides();
    notifyListeners();
    return true;
  }

  // ----------------------------------------------------------------------
  // --- Private Methods ---
  // ----------------------------------------------------------------------

  // --- Visualizer Core Logic ---

  Future<bool> _startVisualizer() async {
    if (_isRunning) return true;
    if (!await _ensureMicPermission()) {
      if (kDebugMode) {
        print("VisualizerService: Microphone permission not granted.");
      }
      return false;
    }

    if (Platform.isLinux) {
      await _startMicLinux();
    } else {
      await _startMicAndroid();
    }

    _isRunning = true;
    notifyListeners();
    return true;
  }

  Future<void> _stopVisualizer() async {
    if (!_isRunning) return;
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

  Future<void> _startMicAndroid() async {
    await _platform.invokeMethod("startMic");
    _micSubscription = _micStreamChannel.receiveBroadcastStream().listen(
      (samples) {
        if (!_isRunning || _devices.isEmpty) return;
        final floatSamples = Float32List.fromList(
          (samples as List).map((s) => (s as num).toDouble()).toList(),
        );
        _processAudioData(_audioAnalyzer.analyze(floatSamples));
      },
      onError: (e) {
        if (kDebugMode) print("Mic stream error: $e");
        _stopVisualizer();
      },
      onDone: () {
        if (kDebugMode) print("Mic stream done.");
        if (_isRunning) _stopVisualizer();
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
      _recorder.setFftSmoothing(0.05);
      _recorder.start();
      _recorder.startStreamingData();
      _micSubscription = _recorder.uint8ListStream.listen((_) {
        if (!_isRunning || _devices.isEmpty) return;
        _processAudioData(_audioAnalyzer.analyze(_recorder.getFft()));
      });
    } catch (e) {
      if (kDebugMode) print("Linux mic error: $e");
    }
  }

  List<int> _getPakcetData(
    LedDevice device,
    LedEffect effect,
    AudioFeatures features,
  ) {
    switch (effect.id) {
      case 'vertical-bars':
        return renderVerticalBars(
          device: device,
          features: features,
          gain: effect.parameters["gain"]!['value'],
          brightness: effect.parameters["brightness"]!['value'],
          saturation: effect.parameters["saturation"]!['value'],
          smooth: effect.parameters["smooth"]!['value'],
        );
      case 'center-pulse':
        return renderCenterPulsePacket(
          device: device,
          features: features,
          gain: effect.parameters["gain"]!['value'],
          brightness: effect.parameters["brightness"]!['value'],
          saturation: effect.parameters["saturation"]!['value'],
        );
      case 'music-rhythm':
        return renderBeatDropEffect(
          device: device,
          features: features,
          gain: effect.parameters["gain"]!['value'],
          brightness: effect.parameters["brightness"]!['value'],
          saturation: effect.parameters["saturation"]!['value'],
          raiseSpeed: effect.parameters["raiseSpeed"]!['value'],
          decaySpeed: effect.parameters["decaySpeed"]!['value'],
          dropSpeed: effect.parameters["dropSpeed"]!['value'],
        );
      default:
        return [];
    }
  }

  void _processAudioData(AudioFeatures features) {
    // Filter out only active devices once to avoid re-filtering in the loop
    final activeDevices = _devices.where((d) => d.isEffectEnabled).toList();

    for (final device in activeDevices) {
      final effect = _effects[_globalEffectId]!;
      List<int> packetData = _getPakcetData(device, effect, features);
      if (packetData.isNotEmpty) {
        _udpSender.send(device, packetData);
      }
    }

    if (_currentSelectedTab == 2) {
      _updateSimulatorData(features, _effects[_globalEffectId]!);
    }
  }

  void _updateSimulatorData(AudioFeatures features, LedEffect effect) {
    // This is a simplified version of the main processing loop for a single device
    LedDevice simulatedDevice = LedDevice(
      id: 'Simulator',
      name: 'Simulator',
      ip: '127.0.0.1',
      port: 60,
      ledCount: 90,
      isEffectEnabled: true,
      type: DeviceType.wled,
      segments: [Segment(id: 'segment_1', startIndex: 0, endIndex: 89)],
    );

    List<int> packetData = _getPakcetData(simulatedDevice, effect, features);

    if (packetData.isNotEmpty) {
      packets = packetData;
      notifyListeners();
    }
  }

  // --- Screen Sync Logic ---

  Future<void> _processFrameAndSend() async {
    if (_videoKey?.currentContext == null || _displaySides.isEmpty) return;

    try {
      final boundary =
          _videoKey!.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return;

      final pixelData = byteData.buffer.asUint8List();
      final width = image.width;
      final height = image.height;

      // Process and send data for all sides in a single loop
      for (final side in _displaySides) {
        final device = side.device;
        if (device == null) continue;

        final packetData = _renderScreenData(
          device: device,
          pixelData: pixelData,
          width: width,
          height: height,
          side: side.position,
          startIndex: side.startIndex,
          endIndex: side.endIndex,
        );
        if (packetData.isNotEmpty) {
          _udpSender.send(device, packetData);
        }
      }
      image.dispose();
    } catch (e) {
      if (kDebugMode) print("Error processing frame: $e");
    }
  }

  List<int> _renderScreenData({
    required LedDevice device,
    required Uint8List pixelData,
    required int width,
    required int height,
    required DisplayPosition side,
    required int startIndex,
    required int endIndex,
  }) {
    final List<int> packet = [0x02, 0x04];
    final int sideLedCount = endIndex - startIndex + 1;
    if (sideLedCount <= 0) return [];

    // Pre-calculate constants outside the loop
    final int sectionThickness =
        (side == DisplayPosition.left || side == DisplayPosition.right)
        ? (width * 0.1).round()
        : (height * 0.1).round();
    final double step = 1.0 / (sideLedCount > 1 ? (sideLedCount - 1) : 1);

    for (int i = 0; i < sideLedCount; i++) {
      double t = i * step;
      int x, y;

      switch (side) {
        case DisplayPosition.left:
          x = sectionThickness ~/ 2;
          y = height - (t * height).round().clamp(0, height - 1);
          break;
        case DisplayPosition.top:
          x = (t * width).round().clamp(0, width - 1);
          y = sectionThickness ~/ 2;
          break;
        case DisplayPosition.right:
          x = width - (sectionThickness ~/ 2);
          y = height - (t * height).round().clamp(0, height - 1);
          break;
        case DisplayPosition.bottom:
          x = (t * width).round().clamp(0, width - 1);
          y = height - (sectionThickness ~/ 2);
          break;
      }

      final int pixelIndex = (y * width + x) * 4;

      if (pixelIndex >= 0 && pixelIndex + 3 < pixelData.length) {
        packet.addAll([
          pixelData[pixelIndex],
          pixelData[pixelIndex + 1],
          pixelData[pixelIndex + 2],
        ]);
      } else {
        packet.addAll([0, 0, 0]);
      }
    }
    return packet;
  }

  // --- Persistence & Permissions ---

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceList = _devices.map((d) => json.encode(d.toJson())).toList();
    await prefs.setStringList('devices', deviceList);
    notifyListeners();
  }

  Future<void> _saveEffects() async {
    final prefs = await SharedPreferences.getInstance();
    final effectList = _effects.values
        .map((e) => json.encode(e.toJson()))
        .toList();
    await prefs.setStringList('effects', effectList);
    notifyListeners();
  }

  Future<void> _saveDisplaySides() async {
    final prefs = await SharedPreferences.getInstance();
    final sideList = _displaySides.map((s) => json.encode(s.toJson())).toList();
    await prefs.setStringList('displaySides', sideList);
    notifyListeners();
  }

  Future<void> _restoreDevices(SharedPreferences prefs) async {
    final deviceList = prefs.getStringList('devices') ?? [];
    _devices = deviceList
        .map((e) => LedDevice.fromJson(json.decode(e)))
        .toList();
  }

  Future<void> _restoreEffects(SharedPreferences prefs) async {
    final effectList = prefs.getStringList('effects') ?? [];
    for (var effectJson in effectList) {
      try {
        final savedEffect = LedEffect.fromJson(json.decode(effectJson));
        if (_effects.containsKey(savedEffect.id)) {
          // Get the current effect from _effects
          final currentEffect = _effects[savedEffect.id]!;

          // Merge parameters: keep saved values, but use current parameter definitions
          final mergedParameters = <String, Map<String, dynamic>>{};
          currentEffect.parameters.forEach((key, currentParam) {
            if (savedEffect.parameters.containsKey(key)) {
              // Use the saved value, but keep the current min/max/steps/default
              mergedParameters[key] = {
                ...currentParam,
                'value': savedEffect.parameters[key]!['value'],
              };
            } else {
              // If the parameter doesn't exist in the saved effect, use the current one
              mergedParameters[key] = currentParam;
            }
          });

          // Update the effect in _effects with merged parameters and current name/id
          _effects[savedEffect.id] = currentEffect.copyWith(
            parameters: mergedParameters,
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error decoding or merging effect: $e");
        }
      }
    }
  }

  Future<void> _restoreDisplaySides(SharedPreferences prefs) async {
    final displaySideList = prefs.getStringList('displaySides') ?? [];
    _displaySides = displaySideList
        .map((e) => DisplaySide.fromJson(json.decode(e)))
        .toList();
  }

  Future<bool> _ensureMicPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // --- Reusable Helper Functions ---

  Future<File?> _exportDataToJsonFile(
    BuildContext context,
    String key,
    String filename,
    Function fromJson,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataList = prefs.getStringList(key) ?? [];
      if (dataList.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No $key to export.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return null;
      }
      final decodedData = dataList.map((e) => json.decode(e)).toList();
      final jsonString = jsonEncode(decodedData);
      final jsonBytes = utf8.encode(jsonString);
      final outputPath = await FilePicker.platform.saveFile(
        fileName: filename,
        bytes: jsonBytes,
      );
      if (outputPath == null) return null;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$key exported successfully!')));
      }
      return File(outputPath);
    } catch (e) {
      if (kDebugMode) print("Failed to export $key to JSON: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export $key: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return null;
    }
  }

  Future<String> _importDataFromJsonFile<T>(
    String key,
    T Function(dynamic) fromJson,
    void Function(List<T>) updateState,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) {
      return "File selection canceled or no data found.";
    }
    try {
      final jsonString = utf8.decode(result.files.single.bytes!);
      final decodedList = jsonDecode(jsonString) as List<dynamic>;
      final importedData = decodedList.map((e) => fromJson(e)).toList();
      updateState(importedData);
      await _saveDevices();
      return "$key imported successfully!";
    } catch (e) {
      if (kDebugMode) print("Failed to import $key: $e");
      return "Failed to import $key: Invalid file format.";
    }
  }
}
