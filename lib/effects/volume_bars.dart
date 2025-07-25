import 'dart:typed_data';

import 'package:udp_master/models.dart';

double _prevHeight = 0.0; // persistent across frames

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
  const double riseSpeed = 1.0;
  const double decaySpeed = 0.5;

  if (device.ledCount == 0 || fft.isEmpty) {
    return [0x02, 0x04];
  }

  double sum = 0;
  for (final value in fft) {
    sum += value.abs();
  }

  double avg = sum / fft.length;
  double normalized = (avg * gain).clamp(0.0, 1.0);

  // Smooth height transition
  if (normalized > _prevHeight) {
    _prevHeight += (normalized - _prevHeight) * riseSpeed;
  } else {
    _prevHeight += (normalized - _prevHeight) * decaySpeed;
  }

  int activeHeight = (_prevHeight * device.ledCount).round();
  double hue = (1.0 - _prevHeight) * 0.7;

  if (device.type == DeviceType.wiz) {
    // Wiz supports only 1 LED - treat it as intensity-reactive
    final wizColor = _hsvToRgb(hue, saturation, brightness);
    return [...wizColor, (_prevHeight * 100).round()];
  }

  // WLED: construct packet with each LED's color
  final color = _hsvToRgb(hue, saturation, brightness);
  final List<int> packet = [0x02, 0x04];
  for (int i = 0; i < device.ledCount; i++) {
    if (i < activeHeight) {
      packet.addAll(color);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  print(packet);

  return packet;
}
