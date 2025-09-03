import 'dart:math';
import '../services/audio_analyzer.dart';

/// Render energy bars similar to LedFx `energy.py`
List<int> renderEnergyEffect({
  required int ledCount,
  required AudioFeatures features,
  double gain = 1.0,
  double brightness = 1.0,
  double saturation = 1.0,
  bool mirror = false,
}) {
  List<int> packet = [];

  // AGC-like normalization
  double total = features.overall > 0 ? features.overall : 1;

  // log scaling for perception
  double bass = log(1 + features.bass * gain) / log(1 + total);
  double mid = log(1 + features.mid * gain) / log(1 + total);
  double high = log(1 + features.high * gain) / log(1 + total);

  int bassCount = (bass * ledCount).clamp(0, ledCount).round();
  int midCount = (mid * ledCount).clamp(0, ledCount).round();
  int highCount = (high * ledCount).clamp(0, ledCount).round();

  // LED buffer [r,g,b] per LED
  List<List<double>> leds =
      List.generate(ledCount, (_) => [0.0, 0.0, 0.0]);

  for (int i = 0; i < bassCount && i < ledCount; i++) {
    leds[i] = [1.0, 0.0, 0.0]; // red
  }
  for (int i = 0; i < midCount && i < ledCount; i++) {
    leds[i] = [0.0, 1.0, 0.0]; // green
  }
  for (int i = 0; i < highCount && i < ledCount; i++) {
    leds[i] = [0.0, 0.0, 1.0]; // blue
  }

  // apply brightness & saturation
  for (var rgb in leds) {
    double r = pow(rgb[0], 0.8) * brightness;
    double g = pow(rgb[1], 0.8) * brightness;
    double b = pow(rgb[2], 0.8) * brightness;
    packet.addAll([
      (r * 255).round().clamp(0, 255),
      (g * 255).round().clamp(0, 255),
      (b * 255).round().clamp(0, 255),
    ]);
  }

  // optional mirror
  if (mirror) {
    packet.addAll(packet.reversed);
  }

  return packet;
}
