import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
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
  List<DisplaySide> _displaySides = [];
  List<LedDevice> _devices = [];
  UnmodifiableListView<LedDevice> get devices => UnmodifiableListView(_devices);

  // --- Effect Management ---

  // Updated effects list with new advanced effects
  List<LedEffect> _effects = [
    LedEffect(
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
      },
    ),
    LedEffect(
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
    LedEffect(
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
          'value': 10,
          'steps': 10,
          'default': 10,
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
  ];

  String _globalEffectId = 'vertical-bars';

  String get globalEffectId => _globalEffectId;

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

  Future<bool> resetEffect(LedEffect effect) async {
    int index = _effects.indexWhere((e) => e.id == effect.id);
    if (index == -1) {
      return false;
    }
    effect.parameters.forEach((key, value) {
      value["value"] = value["default"];
    });
    _effects[index] = effect;
    final prefs = await SharedPreferences.getInstance();
    final effectList = _effects.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('effects', effectList);
    notifyListeners();
    return true;
  }

  Future<bool> setGlobalEffect(String effectId) async {
    _globalEffectId = effectId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('globalEffect', json.encode(effectId));
    final updatedDevices = _devices
        .map((d) => d.copyWith(effect: effectId))
        .toList();

    for (var device in updatedDevices) {
      deviceActions(device, DeviceAction.update);
    }
    notifyListeners();
    return true;
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
    _effects = existingEffects;
    notifyListeners();
    return true;
  }

  // Enhanced UDP sending function
  Future<void> sendUdpToDevices({
    required List<LedDevice> targetDevices,
    required AudioFeatures features,
  }) async {
    if (_udpSender.udpSocket == null) {
      if (kDebugMode) {
        print("VisualizerService: UDP sender not initialized.");
      }
      return;
    }

    for (var device in targetDevices) {
      try {
        if (device.type == DeviceType.wled ||
            device.type == DeviceType.esphome) {
          LedEffect effect = getEffectById(device.effect);
          late List<int> packetData;

          // Use enhanced effects for new effect types
          if (effect.id == 'vertical-bars') {
            packetData = renderVerticalBars(
              device: device,
              features: features,
              gain: effect.parameters["gain"]?["value"] ?? 0.0,
              brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
              saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
            );
          } else if (effect.id == 'center-pulse') {
            packetData = renderCenterPulsePacket(
              device: device,
              features: features,
              gain: effect.parameters["gain"]?["value"] ?? 0.0,
              brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
              saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
            );
          } else if (effect.id == 'music-rhythm') {
            packetData = renderBeatDropEffect(
              device: device,
              features: features,
              gain: effect.parameters["gain"]?["value"] ?? 0.0,
              brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
              saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
              raiseSpeed: effect.parameters["raiseSpeed"]?["value"] ?? 12.5,
              decaySpeed: effect.parameters["decaySpeed"]?["value"] ?? 0.5,
              dropSpeed: effect.parameters["dropSpeed"]?["value"] ?? 0.5,
            );
          }

          if (packetData.isNotEmpty) {
            _udpSender.send(device, packetData);
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error sending to ${device.ip}: $e");
        }
      }
    }
  }

  // Enhanced simulator page data
  Future<void> simulatorPageDataEnhanced(
    AudioFeatures features,
    LedEffect effect,
  ) async {
    late List<int> packetData;
    LedDevice simulatedDevice = LedDevice(
      id: 'Simulator',
      name: 'Simulator',
      ip: '127.0.0.1',
      port: 60,
      ledCount: 90,
      effect: effect.id,
      isEffectEnabled: true,
      type: DeviceType.wled,
    );

    // Use enhanced effects for new effect types
    if (effect.id == 'vertical-bars') {
      packetData = renderVerticalBars(
        device: simulatedDevice,
        features: features,
        gain: effect.parameters["gain"]?["value"] ?? 0.0,
        brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
        saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
      );
    } else if (effect.id == 'center-pulse') {
      packetData = renderCenterPulsePacket(
        device: simulatedDevice,
        features: features,
        gain: effect.parameters["gain"]?["value"] ?? 0.0,
        brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
        saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
      );
    } else if (effect.id == 'music-rhythm') {
      packetData = renderBeatDropEffect(
        device: simulatedDevice,
        features: features,
        gain: effect.parameters["gain"]?["value"] ?? 0.0,
        brightness: effect.parameters["brightness"]?["value"] ?? 1.0,
        saturation: effect.parameters["saturation"]?["value"] ?? 1.0,
        raiseSpeed: effect.parameters["raiseSpeed"]?["value"] ?? 12.5,
        decaySpeed: effect.parameters["decaySpeed"]?["value"] ?? 0.5,
        dropSpeed: effect.parameters["dropSpeed"]?["value"] ?? 0.5,
      );
    }

    if (packetData.isNotEmpty) {
      packets = packetData;
      notifyListeners();
    }
  }
  // --- Device Management ---

  Future<void> initiateTheAppData() async {
    final prefs = await SharedPreferences.getInstance();

    // restore devices
    final deviceList = prefs.getStringList('devices') ?? [];
    _devices = deviceList
        .map((e) => LedDevice.fromJson(json.decode(e)))
        .toList();

    // restore last selected tab
    final currectSelectedTab = prefs.getInt('currentSelectedTab') ?? 0;
    _currentSelectedTab = currectSelectedTab;

    // restore effects presets
    final effectList = prefs.getStringList('effects') ?? [];
    List<LedEffect> fetchedEffects = effectList
        .map((e) => LedEffect.fromJson(json.decode(e)))
        .toList();
    for (var effect in fetchedEffects) {
      int index = _effects.indexWhere((e) => e.id == effect.id);
      if (index != -1) {
        _effects[index] = effect;
      }
    }

    // restore global effect
    final globalEffectId = prefs.getString('globalEffect');
    if (globalEffectId != null) {
      _globalEffectId = globalEffectId;
    }

    // restore display sides
    final displaySideList = prefs.getStringList('displaySides') ?? [];
    _displaySides = displaySideList
        .map((e) => DisplaySide.fromJson(json.decode(e)))
        .toList();

    // initialize udp
    _udpSender.initiateUDPSender();
    notifyListeners();
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceList = _devices
        .map((device) => json.encode(device.toJson()))
        .toList();
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
      await _startMicAndroid();
    }

    _isRunning = true;
    notifyListeners();
    return true;
  }

  Future<void> _stopVisualizer() async {
    if (!_isRunning &&
        _micSubscription == null &&
        _udpSender.udpSocket == null) {
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

    final AudioAnalyzer analyzer = AudioAnalyzer(
      sampleRate: 44100,
      fftSize: 1024,
    );

    _micSubscription = _micStreamChannel.receiveBroadcastStream().listen(
      (samples) {
        if (!_isRunning || _devices.isEmpty) return;

        List<double> doubleSamples;
        if (samples is List<dynamic>) {
          doubleSamples = samples.map((s) => (s as num).toDouble()).toList();
        } else {
          if (kDebugMode) {
            print(
              "VisualizerService: Unexpected sample type: ${samples.runtimeType}",
            );
          }
          return;
        }

        final Float32List floatSamples = Float32List.fromList(doubleSamples);

        // Use analyzer to extract FFT and volume features
        final AudioFeatures features = analyzer.analyze(floatSamples);

        // Send to devices
        sendUdpToDevices(
          targetDevices: _devices
              .where((d) => d.isEffectEnabled == true)
              .toList(),
          features: features,
        );

        // Update simulator view if on tab 2
        if (_currentSelectedTab == 2) {
          simulatorPageDataEnhanced(features, getEffectById(_globalEffectId));
        }
      },
      onError: (error) {
        if (kDebugMode) print("VisualizerService: Mic stream error: $error");
        _stopVisualizer();
      },
      onDone: () {
        if (kDebugMode) print("VisualizerService: Mic stream done.");
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

      // Enhanced settings for better FFT quality
      _recorder.setFftSmoothing(0.05); // Less smoothing for more responsiveness
      // _recorder.setFftSize(2048); // Larger FFT for better frequency resolution

      _recorder.start();
      _recorder.startStreamingData();

      final AudioAnalyzer analyzer = AudioAnalyzer(
        sampleRate: 44100,
        fftSize: 1024,
      );

      _micSubscription = _recorder.uint8ListStream.listen((_) {
        if (!_isRunning || _devices.isEmpty) return;

        final Float32List fft = _recorder.getFft();

        final features = analyzer.analyze(fft);

        // Use enhanced audio processing
        sendUdpToDevices(
          targetDevices: _devices.where((d) => d.isEffectEnabled).toList(),
          features: features,
        );

        if (_currentSelectedTab == 2) {
          simulatorPageDataEnhanced(features, getEffectById(_globalEffectId));
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print("VisualizerService (Linux): Error starting mic: $e");
      }
    }
  }

  // --- Screen Sync Methods ---
  GlobalKey? _videoKey;
  MediaStream? _screenStream;
  Timer? _screenTimer;

  UnmodifiableListView<DisplaySide> get displaySides =>
      UnmodifiableListView(_displaySides);

  Future<bool> addOrUpdateDisplaySide(DisplaySide side) async {
    // Check if the side already exists
    int index = _displaySides.indexWhere((s) => s.position == side.position);
    if (index != -1) {
      // Update existing side
      _displaySides[index] = side;
    } else {
      // Add new side
      _displaySides.add(side);
    }
    final prefs = await SharedPreferences.getInstance();
    final sideList = _displaySides.map((s) => json.encode(s.toJson())).toList();
    await prefs.setStringList('displaySides', sideList);
    notifyListeners();
    return true;
  }

  Future<void> startScreenSync(MediaStream stream, GlobalKey key) async {
    _screenStream = stream;
    _videoKey = key;
    _isRunning = true;
    _castMode = CastMode.video;

    _screenTimer?.cancel();

    // Set up a periodic timer to process the stream at ~20 FPS (50ms)
    _screenTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) async {
      await _processFrameAndSend();
    });

    notifyListeners();
  }

  Future<void> stopScreenSync() async {
    _screenTimer?.cancel();
    _screenTimer = null;

    _isRunning = false;
    _screenStream?.dispose();
    _screenStream = null;
    _udpSender.close();
    notifyListeners();
  }

  Future<void> _processFrameAndSend() async {
    // Check if the key and displaySides are valid
    if (_videoKey == null ||
        _videoKey!.currentContext == null ||
        _displaySides.isEmpty) {
      return;
    }

    try {
      RenderRepaintBoundary boundary =
          _videoKey!.currentContext!.findRenderObject()
              as RenderRepaintBoundary;

      ui.Image image = await boundary.toImage();
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      if (byteData == null) return;

      Uint8List pixelData = byteData.buffer.asUint8List();
      final int width = image.width;
      final int height = image.height;

      // Iterate through all configured display sides
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
      if (kDebugMode) {
        print("Error processing frame: $e");
      }
    }
  }

  // Add this to your member variables at the top of the class
  final Map<String, List<Color>> _previousColors = {};

  final double smoothingFactor = 0.2;
  final double saturationBoost = 1.3; // Boost saturation by 30%
  final int darkThreshold =
      20; // Pixels with R,G,B values below this are treated as black
  final double gamma = 2.2; // A common gamma value for sRGB color space

  int getColorValue(Color color, String channel) {
    switch (channel) {
      case 'r':
        return ((color.r * 255.0).round() & 0xff);
      case 'g':
        return ((color.g * 255.0).round() & 0xff);
      case 'b':
        return ((color.b * 255.0).round() & 0xff);
      default:
        return ((color.r * 255.0).round() & 0xff);
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

    _previousColors[device.id] ??= List.generate(
      device.ledCount,
      (_) => const Color(0x00000000),
    );

    final int sectionThickness =
        (side == DisplayPosition.left || side == DisplayPosition.right)
        ? (width * 0.1).round()
        : (height * 0.1).round();

    // A helper function for gamma correction
    int applyGamma(int value) {
      // Normalize the value to a 0.0-1.0 range, apply gamma, then scale back to 0-255
      double normalized = value / 255.0;
      double corrected = pow(normalized, gamma) as double;
      return (corrected * 255).round().clamp(0, 255);
    }

    // A helper function for saturation boost
    Color applySaturationBoost(Color color) {
      double r = double.parse(getColorValue(color, 'r').toString());
      double g = double.parse(getColorValue(color, 'g').toString());
      double b = double.parse(getColorValue(color, 'b').toString());
      double l = 0.3 * r + 0.59 * g + 0.11 * b; // Calculate luminance

      // Blend the color towards its luminance (gray) to increase saturation
      r = l + saturationBoost * (r - l);
      g = l + saturationBoost * (g - l);
      b = l + saturationBoost * (b - l);

      return Color.fromARGB(
        255,
        (r * 255).round().clamp(0, 255),
        (g * 255).round().clamp(0, 255),
        (b * 255).round().clamp(0, 255),
      );
    }

    for (int i = 0; i < device.ledCount; i++) {
      if (i < startIndex || i > endIndex) {
        packet.addAll([0, 0, 0]);
        continue;
      }

      double t =
          (i - startIndex) /
          ((endIndex - startIndex) > 0 ? (endIndex - startIndex) : 1);
      int x = 0, y = 0;

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
        final int newR = pixelData[pixelIndex];
        final int newG = pixelData[pixelIndex + 1];
        final int newB = pixelData[pixelIndex + 2];

        if (newR < darkThreshold &&
            newG < darkThreshold &&
            newB < darkThreshold) {
          packet.addAll([0, 0, 0]);
          _previousColors[device.id]![i] = const Color.fromARGB(255, 0, 0, 0);
          continue;
        }

        Color newColor = Color.fromARGB(255, newR, newG, newB);

        // Apply gamma correction to the sampled color
        final int gammaR = applyGamma(getColorValue(newColor, 'r'));
        final int gammaG = applyGamma(getColorValue(newColor, 'g'));
        final int gammaB = applyGamma(getColorValue(newColor, 'b'));
        newColor = Color.fromARGB(255, gammaR, gammaG, gammaB);

        // Apply a simple saturation boost to the gamma-corrected color
        Color boostedColor = applySaturationBoost(newColor);

        final Color previousColor = _previousColors[device.id]![i];

        final int r =
            ((getColorValue(previousColor, 'r') * (1 - smoothingFactor)) +
                    (getColorValue(boostedColor, 'r') * smoothingFactor))
                .round();
        final int g =
            ((getColorValue(previousColor, 'g') * (1 - smoothingFactor)) +
                    (getColorValue(boostedColor, 'g') * smoothingFactor))
                .round();
        final int b =
            ((getColorValue(previousColor, 'b') * (1 - smoothingFactor)) +
                    (getColorValue(boostedColor, 'b') * smoothingFactor))
                .round();

        packet.addAll([r, g, b]);
        _previousColors[device.id]![i] = Color.fromARGB(255, r, g, b);
      } else {
        packet.addAll([0, 0, 0]);
        _previousColors[device.id]![i] = const Color.fromARGB(255, 0, 0, 0);
      }
    }

    return packet;
  }
}
