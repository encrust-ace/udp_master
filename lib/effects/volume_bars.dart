import 'dart:typed_data';

import 'package:udp_master/models.dart';

List<int> _hsvToRgb(double h, double s, double v) {
  h = h.clamp(0.0, 1.0);
  s = s.clamp(0.0, 1.0);
  v = v.clamp(0.0, 1.0);
  int i = (h * 6).floor();
  double f = h * 6 - i;
  double p = v * (1 - s);
  double q = v * (1 - f * s);
  double t = v * (1 - (1 - f) * s);
  double r, g, b;
  switch (i % 6) {
    case 0:
      r = v;
      g = t;
      b = p;
      break;
    case 1:
      r = q;
      g = v;
      b = p;
      break;
    case 2:
      r = p;
      g = v;
      b = t;
      break;
    case 3:
      r = p;
      g = q;
      b = v;
      break;
    case 4:
      r = t;
      g = p;
      b = v;
      break;
    case 5:
      r = v;
      g = p;
      b = q;
      break;
    default:
      r = g = b = 0;
  }
  return [(r * 255).round(), (g * 255).round(), (b * 255).round()];
}

List<int> renderVerticalBars({
  required LedDevice device,
  required Float32List fft,
  required double gain,
  required double brightness,
  required double saturation,
}) {
  final int count = device.ledCount;
  if (count == 0 || fft.isEmpty) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];

  // Focus only on the first 15% of the FFT (bass/rhythm)
  int bassBinCount = (fft.length * 0.15).floor().clamp(1, fft.length);
  double bassAvg = 0.0;
  for (int i = 0; i < bassBinCount; i++) {
    bassAvg += fft[i].abs();
  }
  bassAvg /= bassBinCount;

  final double barStrength = (bassAvg * gain).clamp(0.0, 1.0);

  for (int i = 0; i < count; i++) {
    final double pos = (i + 0.5) / count;
    final double strength = ((barStrength - pos) * count).clamp(0.0, 1.0);

    if (strength > 0) {
      final double hue = (1.0 - pos) * 0.7;
      final fadedColor = _hsvToRgb(hue, saturation, brightness * strength);
      packet.addAll(fadedColor);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
}
