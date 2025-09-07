// visualizer_provider.dart

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udp_master/effects/effects.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/services/audio_analyzer.dart';
import 'package:udp_master/services/udp_sender.dart';

// Method and Event channels for platform-specific communication
const MethodChannel _platform = MethodChannel("mic_channel");

class VisualizerProvider with ChangeNotifier {
  // Singleton instance
  static final VisualizerProvider _instance = VisualizerProvider._internal();

  factory VisualizerProvider() => _instance;

  VisualizerProvider._internal();

  // --- Core Services & State ---
  final UdpSender _udpSender = UdpSender();
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  int _currentSelectedTab = 0;
  int get currentSelectedTab => _currentSelectedTab;

  List<int> simulatorPackets = []; // For internal simulation/debugging display
  StreamSubscription? _micSubscription;

  // --- Device & Display Side Management ---
  List<LedDevice> _devices = [];
  UnmodifiableListView<LedDevice> get devices => UnmodifiableListView(_devices);

  // --- Effect Management ---
  String _globalEffectId = 'vu-meter';
  String get globalEffectId => _globalEffectId;

  // Using a map for faster effect lookup by ID
  final Map<String, LedEffect> _effects = {
    'energy': LedEffect(
      id: 'energy',
      name: 'Energy',
      parameters: {
        'gain': EffectParameter(
          name: 'Gain',
          type: EffectParameterType.number,
          value: 1.0,
          defaultValue: 1.0,
          min: 0.0,
          max: 5.0,
          steps: 10,
        ),
        'brightness': EffectParameter(
          name: 'Brightness',
          type: EffectParameterType.number,
          value: 1.0,
          defaultValue: 1.0,
          min: 0.0,
          max: 1.0,
          steps: 10,
        ),
        'sensitivity': EffectParameter(
          name: 'Sensitivity',
          type: EffectParameterType.number,
          value: 1.0,
          defaultValue: 1.0,
          min: 0.0,
          max: 1.0,
          steps: 10,
        ),
        'blur': EffectParameter(
          name: 'Blur',
          type: EffectParameterType.number,
          value: 1.0,
          defaultValue: 1.0,
          min: 0.0,
          max: 1.0,
          steps: 10,
        ),
        'show_peak': EffectParameter(
          name: 'Show peak',
          type: EffectParameterType.boolean,
          value: true,
          defaultValue: true,
        ),
        'mirror': EffectParameter(
          name: 'Mirror',
          type: EffectParameterType.boolean,
          value: false,
          defaultValue: false,
        ),
        'peak_hold': EffectParameter(
          name: 'Peak hold',
          type: EffectParameterType.number,
          value: 0.0,
          defaultValue: 0.0,
          min: 0.0,
          max: 1.0,
          steps: 10,
        ),
        'low_color': EffectParameter(
          name: 'low_color',
          type: EffectParameterType.color,
          value: '#FF00FF00',
          defaultValue: '',
        ),
        'mid_color': EffectParameter(
          name: 'mid_color',
          type: EffectParameterType.color,
          value: '#FFFFFF00',
          defaultValue: '',
        ),
        'high_color': EffectParameter(
          name: 'high_color',
          type: EffectParameterType.color,
          value: '#FFFF0000',
          defaultValue: '',
        ),
        'peak_color': EffectParameter(
          name: 'peak_color',
          type: EffectParameterType.color,
          value: '#FFFFFFFF',
          defaultValue: '',
        ),
      },
    ),
    'vu-meter': LedEffect(
      id: 'vu-meter',
      name: 'VU meter',
      parameters: {
        'gain': EffectParameter(
          name: 'Gain',
          type: EffectParameterType.number,
          value: 1.0,
          defaultValue: 1.0,
          min: 0.0,
          max: 5.0,
          steps: 10,
        ),
        'brightness': EffectParameter(
          name: 'Brightness',
          type: EffectParameterType.number,
          value: 1.0,
          defaultValue: 1.0,
          min: 0.0,
          max: 1.0,
          steps: 10,
        ),
        'sensitivity': EffectParameter(
          name: 'Sensitivity',
          type: EffectParameterType.number,
          value: 1.0,
          defaultValue: 1.0,
          min: 0.0,
          max: 1.0,
          steps: 10,
        ),
        'blur': EffectParameter(
          name: 'Blur',
          type: EffectParameterType.number,
          value: 1.0,
          defaultValue: 1.0,
          min: 0.0,
          max: 1.0,
          steps: 10,
        ),
        'show_peak': EffectParameter(
          name: 'Show peak',
          type: EffectParameterType.boolean,
          value: true,
          defaultValue: true,
        ),
        'mirror': EffectParameter(
          name: 'Mirror',
          type: EffectParameterType.boolean,
          value: false,
          defaultValue: false,
        ),
        'peak_hold': EffectParameter(
          name: 'Peak hold',
          type: EffectParameterType.number,
          value: 0.0,
          defaultValue: 0.0,
          min: 0.0,
          max: 1.0,
          steps: 10,
        ),
        'low_color': EffectParameter(
          name: 'low_color',
          type: EffectParameterType.color,
          value: '#FF00FF00',
          defaultValue: '',
        ),
        'mid_color': EffectParameter(
          name: 'mid_color',
          type: EffectParameterType.color,
          value: '#FFFFFF00',
          defaultValue: '',
        ),
        'high_color': EffectParameter(
          name: 'high_color',
          type: EffectParameterType.color,
          value: '#FFFF0000',
          defaultValue: '',
        ),
        'peak_color': EffectParameter(
          name: 'peak_color',
          type: EffectParameterType.color,
          value: '#FFFFFFFF',
          defaultValue: '',
        ),

      },
    ),
  };

  UnmodifiableListView<LedEffect> get effects =>
      UnmodifiableListView(_effects.values.toList());

  LedEffect getEffectById(String id) => _effects[id] ?? _effects.values.first;

  // ----------------------------------------------------------------------
  // --- Public Methods ---
  // ----------------------------------------------------------------------

  Future<void> initiateTheAppData() async {
    final prefs = await SharedPreferences.getInstance();

    // Restore data from SharedPreferences
    await _restoreDevices(prefs);
    await _restoreEffects(prefs);

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

  Future<void> _restoreEffects(SharedPreferences prefs) async {
    final effectList = prefs.getStringList('effects') ?? [];
    for (var effectJson in effectList) {
      try {
        final savedEffect = LedEffect.fromJson(json.decode(effectJson));

        if (_effects.containsKey(savedEffect.id)) {
          final currentEffect = _effects[savedEffect.id]!;

          // Merge parameters: keep saved values, but use current definitions
          final mergedParameters = <String, EffectParameter>{};
          currentEffect.parameters.forEach((key, currentParam) {
            if (savedEffect.parameters.containsKey(key)) {
              final savedParam = savedEffect.parameters[key]!;
              // Replace only the value, keep definition from current
              mergedParameters[key] = currentParam.copyWith(
                value: savedParam.value,
              );
            } else {
              mergedParameters[key] = currentParam;
            }
          });

          // Update the effect in _effects
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

  /// --- Effect Actions ---
  Future<bool> updateEffect(
    LedEffect effect,
    String key,
    EffectParameter parameter,
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
    final resetEffect = effect.resetToDefaults();
    _effects[effect.id] = resetEffect;
    await _saveEffects();
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
    await _startMicCapture();
    _isRunning = true;
    notifyListeners();
    return true;
  }

  Future<void> _stopVisualizer() async {
    if (!_isRunning) return;
    if (Platform.isAndroid) {
      await _micSubscription?.cancel();
      _micSubscription = null;
      await _platform.invokeMethod("stopMic");
    } else {
      _recorder.stop();
      _recorder.cancel();
    }
    simulatorPackets = [];
    _isRunning = false;
    notifyListeners();
  }

  Future<void> _startMicCapture() async {
    try {
      const config = AudioConfig(
        micRate: 44100,
        analysisRate: 60,
        fftSize: 1024,
        minVolume: 50,
        melBands: 64,
      );
      final visualizer = AudioVisualizer(config);

      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits),
      );
      stream.listen((Uint8List chunk) {
        final audioFeatures = visualizer.processAudio(chunk, isFloat32: false);
        _processAudioData(audioFeatures);
      });
    } catch (e) {
      if (kDebugMode) print("Linux mic error: $e");
    }
  }

  void _processAudioData(AudioFeatures audioFeatures) {
    // Filter out only active devices once to avoid re-filtering in the loop
    final activeDevices = _devices.where((d) => d.isEffectEnabled).toList();
    final effect = _effects[_globalEffectId]!;
    for (final device in activeDevices) {
      List<int> packetData = _getPakcetData(device, effect, audioFeatures);
      if (packetData.isNotEmpty) {
        _udpSender.send(device, packetData);
      }
    }

    if (_currentSelectedTab == 2) {
      _updateSimulatorData(audioFeatures, effect);
    }
  }

  List<int> _getPakcetData(
    LedDevice device,
    LedEffect effect,
    AudioFeatures audioFeatures,
  ) {
    List<int> packetData = [0x02, 0x04];

    for (Segment segment in device.segments) {
      List<int> segmentPacketData = [];
      final int segmentLedCount = (segment.endIndex - segment.startIndex) + 1;
      switch (effect.id) {
        case 'vu-meter':
          final effectRenderer = VUMeterRenderer();
          segmentPacketData = effectRenderer.render(
            effect,
            audioFeatures,
            segmentLedCount,
          );
      }
      if (segmentPacketData.isNotEmpty) {
        packetData.addAll(segmentPacketData);
      }
    }
    return packetData;
  }

  void _updateSimulatorData(AudioFeatures audioFeatures, LedEffect effect) {
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

    List<int> packetData = _getPakcetData(
      simulatedDevice,
      effect,
      audioFeatures,
    );

    // print(packetData);

    if (packetData.isNotEmpty) {
      simulatorPackets = packetData;
      notifyListeners();
    }
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

  Future<void> _restoreDevices(SharedPreferences prefs) async {
    final deviceList = prefs.getStringList('devices') ?? [];
    _devices = deviceList
        .map((e) => LedDevice.fromJson(json.decode(e)))
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
