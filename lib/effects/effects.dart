import 'dart:math' as math;
import 'dart:typed_data';

import '../services/audio_analyzer.dart';

/// Parameter types for effect configuration
enum EffectParameterType { number, option, color, boolean }

/// Parameter definition for effect configuration
class EffectParameter {
  final String name;
  final EffectParameterType type;
  final dynamic value;
  final dynamic defaultValue;

  // For number type
  final double? min;
  final double? max;
  final int? steps;

  // For option type
  final List<String>? options;

  // For color type
  final bool? hasAlpha;

  const EffectParameter({
    required this.name,
    required this.type,
    required this.value,
    required this.defaultValue,
    this.min,
    this.max,
    this.steps,
    this.options,
    this.hasAlpha,
  });

  EffectParameter copyWith({
    String? name,
    EffectParameterType? type,
    dynamic value,
    dynamic defaultValue,
    double? min,
    double? max,
    int? steps,
    List<String>? options,
    bool? hasAlpha,
  }) {
    return EffectParameter(
      name: name ?? this.name,
      type: type ?? this.type,
      value: value ?? this.value,
      defaultValue: defaultValue ?? this.defaultValue,
      min: min ?? this.min,
      max: max ?? this.max,
      steps: steps ?? this.steps,
      options: options ?? this.options,
      hasAlpha: hasAlpha ?? this.hasAlpha,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    'value': value,
    'defaultValue': defaultValue,
    // serialize numeric fields consistently
    'min': min,
    'max': max,
    'steps': steps,
    'options': options,
    'hasAlpha': hasAlpha,
  };

  factory EffectParameter.fromJson(Map<String, dynamic> json) {
    // Convert numeric-like values safely
    double? _asDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    int? _asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    List<String>? _asStringList(dynamic v) {
      if (v == null) return null;
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
      return null;
    }

    final typeString = (json['type'] as String?) ?? EffectParameterType.number.name;
    final type = EffectParameterType.values.firstWhere(
          (t) => t.name == typeString,
      orElse: () => EffectParameterType.number,
    );

    return EffectParameter(
      name: json['name'] as String? ?? '',
      type: type,
      value: json['value'],
      defaultValue: json['defaultValue'],
      min: _asDouble(json['min']),
      max: _asDouble(json['max']),
      steps: _asInt(json['steps']),
      options: _asStringList(json['options']),
      hasAlpha: json['hasAlpha'] as bool?,
    );
  }
}

/// LED Effect definition with metadata and parameters
class LedEffect {
  final String id;
  final String name;
  final Map<String, EffectParameter> parameters;

  const LedEffect({
    required this.id,
    required this.name,
    required this.parameters,
  });

  LedEffect copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    Map<String, EffectParameter>? parameters,
    bool? isActive,
  }) {
    return LedEffect(
      id: id ?? this.id,
      name: name ?? this.name,
      parameters: parameters ?? this.parameters,
    );
  }

  /// Get parameter value by ID
  T getParameter<T>(String parameterId) {
    final param = parameters[parameterId];
    if (param == null) throw ArgumentError('Parameter $parameterId not found');
    return param.value as T;
  }

  /// Update parameter value
  LedEffect updateParameter(String parameterId, dynamic value) {
    if (!parameters.containsKey(parameterId)) {
      throw ArgumentError('Parameter $parameterId not found');
    }

    final updatedParams = Map<String, EffectParameter>.from(parameters);
    updatedParams[parameterId] = parameters[parameterId]!.copyWith(
      value: value,
    );

    return copyWith(parameters: updatedParams);
  }

  /// Reset all parameters to defaults
  LedEffect resetToDefaults() {
    final resetParams = <String, EffectParameter>{};
    parameters.forEach((key, param) {
      resetParams[key] = param.copyWith(value: param.defaultValue);
    });
    return copyWith(parameters: resetParams);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parameters': parameters.map((key, value) => MapEntry(key, value.toJson())),
  };

  factory LedEffect.fromJson(Map<String, dynamic> json) {
    final paramsRaw = json['parameters'];

    final Map<String, EffectParameter> parsedParams = {};

    if (paramsRaw is Map<String, dynamic>) {
      // Normal expected shape: { "paramId": { ... param json ... }, ... }
      paramsRaw.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final param = EffectParameter.fromJson(value);
          parsedParams[key] = param;
        } else {
          // fallback: if value isn't a map, skip or try to handle
        }
      });
    } else if (paramsRaw is List) {
      // Fallback shape: [ { "name": "paramId", ... }, { ... } ]
      for (final item in paramsRaw) {
        if (item is Map<String, dynamic>) {
          final param = EffectParameter.fromJson(item);
          parsedParams[param.name] = param;
        }
      }
    } else {
      // no parameters or unexpected shape -> leave empty
    }

    return LedEffect(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      parameters: parsedParams,
    );
  }
}

/// Color representation for LED effects
class LEDColor {
  final double r, g, b, a;

  const LEDColor(this.r, this.g, this.b, [this.a = 1.0]);

  factory LEDColor.fromRGB(int r, int g, int b, [int a = 255]) {
    return LEDColor(r.toDouble(), g.toDouble(), b.toDouble(), a / 255.0);
  }

  factory LEDColor.fromHex(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';

    final value = int.parse(hex, radix: 16);
    return LEDColor(
      ((value >> 16) & 0xFF).toDouble(),
      ((value >> 8) & 0xFF).toDouble(),
      (value & 0xFF).toDouble(),
      ((value >> 24) & 0xFF) / 255.0,
    );
  }

  factory LEDColor.fromHSV(double h, double s, double v, [double a = 1.0]) {
    final c = v * s;
    final x = c * (1 - (((h / 60) % 2) - 1).abs());
    final m = v - c;

    double r = 0, g = 0, b = 0;
    if (h < 60) {
      r = c;
      g = x;
      b = 0;
    } else if (h < 120) {
      r = x;
      g = c;
      b = 0;
    } else if (h < 180) {
      r = 0;
      g = c;
      b = x;
    } else if (h < 240) {
      r = 0;
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      g = 0;
      b = c;
    } else {
      r = c;
      g = 0;
      b = x;
    }

    return LEDColor((r + m) * 255, (g + m) * 255, (b + m) * 255, a);
  }

  LEDColor operator +(LEDColor other) {
    return LEDColor(r + other.r, g + other.g, b + other.b, a);
  }

  LEDColor operator *(double factor) {
    return LEDColor(r * factor, g * factor, b * factor, a);
  }

  LEDColor clamp([double min = 0.0, double max = 255.0]) {
    return LEDColor(
      r.clamp(min, max),
      g.clamp(min, max),
      b.clamp(min, max),
      a.clamp(0.0, 1.0),
    );
  }

  String toHex() {
    final rHex = r.round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final gHex = g.round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final bHex = b.round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final aHex = (a * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    return '#$aHex$rHex$gHex$bHex';
  }

  static const LEDColor black = LEDColor(0, 0, 0);
  static const LEDColor red = LEDColor(255, 0, 0);
  static const LEDColor green = LEDColor(0, 255, 0);
  static const LEDColor blue = LEDColor(0, 0, 255);
  static const LEDColor yellow = LEDColor(255, 255, 0);
  static const LEDColor cyan = LEDColor(0, 255, 255);
  static const LEDColor magenta = LEDColor(255, 0, 255);
  static const LEDColor white = LEDColor(255, 255, 255);
}

/// Base renderer interface for effects
abstract class EffectRenderer {
  Uint8List render(LedEffect effect, AudioFeatures features, int ledCount);
}

/// VU Meter effect renderer
class VUMeterRenderer extends EffectRenderer {
  final List<LEDColor> _pixels = [];
  final List<LEDColor> _prevPixels = [];
  int _peakPosition = 0;
  double _peakHoldTime = 0;

  @override
  Uint8List render(LedEffect effect, AudioFeatures features, int ledCount) {
    _ensurePixelBuffers(ledCount);

    final gain = effect.getParameter<double>('gain');
    final brightness = effect.getParameter<double>('brightness');
    final sensitivity = effect.getParameter<double>('sensitivity');
    final showPeak = effect.getParameter<bool>('show_peak');
    final peakHold = effect.getParameter<double>('peak_hold');
    final lowColor = LEDColor.fromHex(effect.getParameter<String>('low_color'));
    final midColor = LEDColor.fromHex(effect.getParameter<String>('mid_color'));
    final highColor = LEDColor.fromHex(
      effect.getParameter<String>('high_color'),
    );
    final peakColor = LEDColor.fromHex(
      effect.getParameter<String>('peak_color'),
    );
    final blur = effect.getParameter<double>('blur');
    final mirror = effect.getParameter<bool>('mirror');

    // Clear pixels
    for (int i = 0; i < ledCount; i++) {
      _pixels[i] = LEDColor.black;
    }

    // Calculate active LEDs
    final adjustedVolume = (features.volume * gain).clamp(0.0, 1.0);
    final activeLeds = (adjustedVolume * sensitivity * ledCount).round();

    // Fill VU meter with color transitions
    for (int i = 0; i < activeLeds && i < ledCount; i++) {
      final position = i / ledCount;
      LEDColor color;

      if (position < 0.3) {
        color = lowColor;
      } else if (position < 0.7) {
        color = _interpolateColor(lowColor, midColor, (position - 0.3) / 0.4);
      } else if (position < 0.9) {
        color = _interpolateColor(midColor, highColor, (position - 0.7) / 0.2);
      } else {
        color = highColor;
      }

      _pixels[i] = color;
    }

    // Peak hold logic
    if (showPeak && activeLeds > 0) {
      if (activeLeds > _peakPosition) {
        _peakPosition = activeLeds;
        _peakHoldTime = 0;
      } else {
        _peakHoldTime += 1.0 / 60.0;
        if (_peakHoldTime > peakHold) {
          _peakPosition = math.max(0, _peakPosition - 1);
          _peakHoldTime = 0;
        }
      }

      if (_peakPosition < ledCount) {
        _pixels[_peakPosition] = peakColor;
      }
    }

    return _generateOutput(ledCount, brightness, blur, mirror);
  }

  void _ensurePixelBuffers(int ledCount) {
    if (_pixels.length != ledCount) {
      _pixels.clear();
      _pixels.addAll(List.filled(ledCount, LEDColor.black));
      _prevPixels.clear();
      _prevPixels.addAll(List.filled(ledCount, LEDColor.black));
    }
  }

  LEDColor _interpolateColor(LEDColor a, LEDColor b, double t) {
    t = t.clamp(0.0, 1.0);
    return LEDColor(
      a.r + (b.r - a.r) * t,
      a.g + (b.g - a.g) * t,
      a.b + (b.b - a.b) * t,
    );
  }

  Uint8List _generateOutput(
      int ledCount,
      double brightness,
      double blur,
      bool mirror,
      ) {
    // Apply blur if needed
    if (blur > 0) {
      _applyBlur(blur, ledCount);
    }

    final outputCount = mirror ? ledCount * 2 : ledCount;
    final output = Uint8List(outputCount * 3);

    for (int i = 0; i < outputCount; i++) {
      final sourceIndex = mirror && i >= ledCount
          ? (ledCount * 2 - 1 - i)
          : math.min(i, ledCount - 1);

      if (sourceIndex >= 0 && sourceIndex < _pixels.length) {
        final pixel = (_pixels[sourceIndex] * brightness).clamp();
        final baseIndex = i * 3;
        output[baseIndex] = pixel.r.round();
        output[baseIndex + 1] = pixel.g.round();
        output[baseIndex + 2] = pixel.b.round();
      }
    }

    return output;
  }

  void _applyBlur(double blur, int ledCount) {
    if (blur <= 0 || ledCount == 0) return;

    final blurRadius = (blur * 2).round().clamp(1, ledCount ~/ 4);
    final temp = List<LEDColor>.from(_pixels);

    for (int i = 0; i < ledCount; i++) {
      double rSum = 0, gSum = 0, bSum = 0;
      int count = 0;

      for (
      int j = math.max(0, i - blurRadius);
      j <= math.min(ledCount - 1, i + blurRadius);
      j++
      ) {
        rSum += temp[j].r;
        gSum += temp[j].g;
        bSum += temp[j].b;
        count++;
      }

      if (count > 0) {
        _pixels[i] = LEDColor(rSum / count, gSum / count, bSum / count);
      }
    }
  }
}

/// Energy effect renderer
class EnergyRenderer extends EffectRenderer {
  final List<LEDColor> _pixels = [];
  final math.Random _random = math.Random();
  int _colorCycleIndex = 0;

  @override
  Uint8List render(LedEffect effect, AudioFeatures features, int ledCount) {
    _ensurePixelBuffers(ledCount);

    final gain = effect.getParameter<double>('gain');
    final brightness = effect.getParameter<double>('brightness');
    final sensitivity = effect.getParameter<double>('sensitivity');
    final position = effect.getParameter<String>('position');
    final colorCycle = effect.getParameter<bool>('color_cycle');
    final reactToBeat = effect.getParameter<bool>('react_to_beat');

    final bassColor = LEDColor.fromHex(
      effect.getParameter<String>('bass_color'),
    );
    final midColor = LEDColor.fromHex(effect.getParameter<String>('mid_color'));
    final trebleColor = LEDColor.fromHex(
      effect.getParameter<String>('treble_color'),
    );
    final subBassColor = LEDColor.fromHex(
      effect.getParameter<String>('subbass_color'),
    );

    final blur = effect.getParameter<double>('blur');
    final mirror = effect.getParameter<bool>('mirror');

    // Clear pixels
    for (int i = 0; i < ledCount; i++) {
      _pixels[i] = LEDColor.black;
    }

    // Color cycling on beat
    if (colorCycle &&
        reactToBeat &&
        (features.volumeBeat || features.onsetBeat)) {
      _cycleColors();
    }

    // Apply gain to frequency bands
    final adjustedBass = (features.basspower * gain).clamp(0.0, 1.0);
    final adjustedMid = (features.midPower * gain).clamp(0.0, 1.0);
    final adjustedTreble = (features.treblePower * gain).clamp(0.0, 1.0);
    final adjustedSubBass = (features.subBass * gain).clamp(0.0, 1.0);

    // Fill bands based on position
    switch (position) {
      case 'bottom':
        _fillBottomPosition(
          ledCount,
          sensitivity,
          adjustedSubBass,
          adjustedBass,
          adjustedMid,
          adjustedTreble,
          subBassColor,
          bassColor,
          midColor,
          trebleColor,
        );
        break;
      case 'mid':
        _fillMidPosition(
          ledCount,
          sensitivity,
          adjustedSubBass,
          adjustedBass,
          adjustedMid,
          adjustedTreble,
          subBassColor,
          bassColor,
          midColor,
          trebleColor,
        );
        break;
      case 'edge':
        _fillEdgePosition(
          ledCount,
          sensitivity,
          adjustedSubBass,
          adjustedBass,
          adjustedMid,
          adjustedTreble,
          subBassColor,
          bassColor,
          midColor,
          trebleColor,
        );
        break;
    }

    return _generateOutput(ledCount, brightness, blur, mirror);
  }

  void _fillBottomPosition(
      int ledCount,
      double sensitivity,
      double subBass,
      double bass,
      double mid,
      double treble,
      LEDColor subBassColor,
      LEDColor bassColor,
      LEDColor midColor,
      LEDColor trebleColor,
      ) {
    final bandSize = ledCount ~/ 4;

    // Fill from bottom up
    _fillBand(0, bandSize, subBass * sensitivity, subBassColor);
    _fillBand(bandSize, bandSize, bass * sensitivity, bassColor);
    _fillBand(bandSize * 2, bandSize, mid * sensitivity, midColor);
    _fillBand(
      bandSize * 3,
      ledCount - (bandSize * 3),
      treble * sensitivity,
      trebleColor,
    );
  }

  void _fillMidPosition(
      int ledCount,
      double sensitivity,
      double subBass,
      double bass,
      double mid,
      double treble,
      LEDColor subBassColor,
      LEDColor bassColor,
      LEDColor midColor,
      LEDColor trebleColor,
      ) {
    final center = ledCount ~/ 2;
    final bandSize = ledCount ~/ 8;

    // Fill from center outward
    _fillBandCentered(
      center,
      (subBass * sensitivity * bandSize).round(),
      subBassColor,
    );
    _fillBandCentered(
      center,
      (bass * sensitivity * bandSize * 1.5).round(),
      bassColor,
    );
    _fillBandCentered(
      center,
      (mid * sensitivity * bandSize * 2).round(),
      midColor,
    );
    _fillBandCentered(
      center,
      (treble * sensitivity * bandSize * 3).round(),
      trebleColor,
    );
  }

  void _fillEdgePosition(
      int ledCount,
      double sensitivity,
      double subBass,
      double bass,
      double mid,
      double treble,
      LEDColor subBassColor,
      LEDColor bassColor,
      LEDColor midColor,
      LEDColor trebleColor,
      ) {
    final quarterSize = ledCount ~/ 4;

    // Fill from edges inward
    _fillBand(
      0,
      (subBass * sensitivity * quarterSize).round(),
      1.0,
      subBassColor,
    );
    _fillBand(
      ledCount - (bass * sensitivity * quarterSize).round(),
      (bass * sensitivity * quarterSize).round(),
      1.0,
      bassColor,
    );

    final midStart = (ledCount * 0.25).round();
    _fillBand(
      midStart,
      (mid * sensitivity * quarterSize).round(),
      1.0,
      midColor,
    );

    final trebleStart =
        (ledCount * 0.75).round() -
            (treble * sensitivity * quarterSize).round();
    _fillBand(
      trebleStart,
      (treble * sensitivity * quarterSize).round(),
      1.0,
      trebleColor,
    );
  }

  void _fillBand(int startLed, int bandSize, double intensity, LEDColor color) {
    if (bandSize <= 0) return;

    final activeLeds = (intensity * bandSize).round();

    for (int i = 0; i < activeLeds && i < bandSize; i++) {
      final ledIndex = startLed + i;
      if (ledIndex >= 0 && ledIndex < _pixels.length) {
        final fadeIntensity = 1.0 - (i / bandSize) * 0.3;
        _pixels[ledIndex] = _pixels[ledIndex] + (color * fadeIntensity);
      }
    }
  }

  void _fillBandCentered(int center, int spread, LEDColor color) {
    for (int i = 0; i < spread; i++) {
      final leftIndex = center - i;
      final rightIndex = center + i;

      final fadeIntensity = 1.0 - (i / spread) * 0.5;

      if (leftIndex >= 0 && leftIndex < _pixels.length) {
        _pixels[leftIndex] = _pixels[leftIndex] + (color * fadeIntensity);
      }
      if (rightIndex >= 0 && rightIndex < _pixels.length) {
        _pixels[rightIndex] = _pixels[rightIndex] + (color * fadeIntensity);
      }
    }
  }

  void _cycleColors() {
    // Implementation for color cycling
    _colorCycleIndex = (_colorCycleIndex + 1) % 4;
  }

  void _ensurePixelBuffers(int ledCount) {
    if (_pixels.length != ledCount) {
      _pixels.clear();
      _pixels.addAll(List.filled(ledCount, LEDColor.black));
    }
  }

  Uint8List _generateOutput(
      int ledCount,
      double brightness,
      double blur,
      bool mirror,
      ) {
    // Apply blur if needed
    if (blur > 0) {
      _applyBlur(blur, ledCount);
    }

    final outputCount = mirror ? ledCount * 2 : ledCount;
    final output = Uint8List(outputCount * 3);

    for (int i = 0; i < outputCount; i++) {
      final sourceIndex = mirror && i >= ledCount
          ? (ledCount * 2 - 1 - i)
          : math.min(i, ledCount - 1);

      if (sourceIndex >= 0 && sourceIndex < _pixels.length) {
        final pixel = (_pixels[sourceIndex] * brightness).clamp();
        final baseIndex = i * 3;
        output[baseIndex] = pixel.r.round();
        output[baseIndex + 1] = pixel.g.round();
        output[baseIndex + 2] = pixel.b.round();
      }
    }

    return output;
  }

  void _applyBlur(double blur, int ledCount) {
    if (blur <= 0 || ledCount == 0) return;

    final blurRadius = (blur * 2).round().clamp(1, ledCount ~/ 4);
    final temp = List<LEDColor>.from(_pixels);

    for (int i = 0; i < ledCount; i++) {
      double rSum = 0, gSum = 0, bSum = 0;
      int count = 0;

      for (
      int j = math.max(0, i - blurRadius);
      j <= math.min(ledCount - 1, i + blurRadius);
      j++
      ) {
        rSum += temp[j].r;
        gSum += temp[j].g;
        bSum += temp[j].b;
        count++;
      }

      if (count > 0) {
        _pixels[i] = LEDColor(rSum / count, gSum / count, bSum / count);
      }
    }
  }
}

/// Spectrum Analyzer renderer
class SpectrumRenderer extends EffectRenderer {
  final List<LEDColor> _pixels = [];

  @override
  Uint8List render(LedEffect effect, AudioFeatures features, int ledCount) {
    _ensurePixelBuffers(ledCount);

    final gain = effect.getParameter<double>('gain');
    final brightness = effect.getParameter<double>('brightness');
    final logarithmic = effect.getParameter<bool>('logarithmic');
    final rainbow = effect.getParameter<bool>('rainbow');
    final baseColor = LEDColor.fromHex(
      effect.getParameter<String>('base_color'),
    );
    final blur = effect.getParameter<double>('blur');
    final mirror = effect.getParameter<bool>('mirror');

    // Clear pixels
    for (int i = 0; i < ledCount; i++) {
      _pixels[i] = LEDColor.black;
    }

    final melbank = features.melbank;
    if (melbank.isNotEmpty) {
      for (int i = 0; i < ledCount; i++) {
        // Map LED position to mel band
        final melIndex = logarithmic
            ? _logScale(i, ledCount, melbank.length)
            : (i * melbank.length / ledCount).floor();

        if (melIndex >= 0 && melIndex < melbank.length) {
          final intensity = (melbank[melIndex] * gain).clamp(0.0, 1.0);

          LEDColor color;
          if (rainbow) {
            final hue = (i / ledCount) * 360;
            color = LEDColor.fromHSV(hue, 1.0, intensity);
          } else {
            color = baseColor * intensity;
          }

          _pixels[i] = color;
        }
      }
    }

    return _generateOutput(ledCount, brightness, blur, mirror);
  }

  int _logScale(int position, int maxPosition, int maxOutput) {
    if (maxPosition <= 1) return 0;
    final logPos = math.log(position + 1) / math.log(maxPosition);
    return (logPos * maxOutput).floor().clamp(0, maxOutput - 1);
  }

  void _ensurePixelBuffers(int ledCount) {
    if (_pixels.length != ledCount) {
      _pixels.clear();
      _pixels.addAll(List.filled(ledCount, LEDColor.black));
    }
  }

  Uint8List _generateOutput(
      int ledCount,
      double brightness,
      double blur,
      bool mirror,
      ) {
    // Apply blur if needed
    if (blur > 0) {
      _applyBlur(blur, ledCount);
    }

    final outputCount = mirror ? ledCount * 2 : ledCount;
    final output = Uint8List(outputCount * 3);

    for (int i = 0; i < outputCount; i++) {
      final sourceIndex = mirror && i >= ledCount
          ? (ledCount * 2 - 1 - i)
          : math.min(i, ledCount - 1);

      if (sourceIndex >= 0 && sourceIndex < _pixels.length) {
        final pixel = (_pixels[sourceIndex] * brightness).clamp();
        final baseIndex = i * 3;
        output[baseIndex] = pixel.r.round();
        output[baseIndex + 1] = pixel.g.round();
        output[baseIndex + 2] = pixel.b.round();
      }
    }

    return output;
  }

  void _applyBlur(double blur, int ledCount) {
    if (blur <= 0 || ledCount == 0) return;

    final blurRadius = (blur * 2).round().clamp(1, ledCount ~/ 4);
    final temp = List<LEDColor>.from(_pixels);

    for (int i = 0; i < ledCount; i++) {
      double rSum = 0, gSum = 0, bSum = 0;
      int count = 0;

      for (
      int j = math.max(0, i - blurRadius);
      j <= math.min(ledCount - 1, i + blurRadius);
      j++
      ) {
        rSum += temp[j].r;
        gSum += temp[j].g;
        bSum += temp[j].b;
        count++;
      }

      if (count > 0) {
        _pixels[i] = LEDColor(rSum / count, gSum / count, bSum / count);
      }
    }
  }
}
