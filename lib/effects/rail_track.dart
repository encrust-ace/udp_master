import 'dart:typed_data';
import 'package:udp_master/models.dart';
import 'dart:math';

class FallingDrop {
  double position; // 0.0 (top) to 1.0 (bottom)
  double hue;
  double speed;
  FallingDrop({required this.position, required this.hue, required this.speed});
}

final List<FallingDrop> _activeDrops = [];
double _lastBass = 0.0;
final Random _rand = Random();

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
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    case 5: r = v; g = p; b = q; break;
    default: r = g = b = 0;
  }
  return [(r * 255).round(), (g * 255).round(), (b * 255).round()];
}

List<int> renderRailTrack({
  required LedDevice device,
  required Float32List fft,
  required double gain,
  required double brightness,
  required double saturation,
  double dt = 0.05, // delta time ~frame interval (e.g., 50ms)
}) {
  final int count = device.ledCount;
  if (count == 0 || fft.isEmpty) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];

  // 1. Detect bass energy
  int bassCount = (fft.length * 0.15).floor().clamp(1, fft.length);
  double bassAvg = 0.0;
  for (int i = 0; i < bassCount; i++) {
    bassAvg += fft[i].abs();
  }
  bassAvg /= bassCount;
  double energy = (bassAvg * gain).clamp(0.0, 1.0);

  // 2. Create new drop if energy spikes
  if (energy > 0.2 && (_lastBass < 0.2)) {
    _activeDrops.add(FallingDrop(
      position: 0.0,
      hue: _rand.nextDouble(), // random hue
      speed: 0.4 + _rand.nextDouble() * 0.3, // fall speed
    ));
  }
  _lastBass = energy;

  // 3. Update drop positions
  for (final drop in _activeDrops) {
    drop.position += drop.speed * dt;
  }

  // 4. Remove drops that are out of view
  _activeDrops.removeWhere((d) => d.position > 1.0);

  // 5. Render LEDs
  for (int i = 0; i < count; i++) {
    double ledPos = (i + 0.5) / count;
    double v = 0.0;
    double hue = 0.0;

    for (final drop in _activeDrops) {
      double dist = (ledPos - drop.position).abs();
      if (dist < 0.1) {
        double localV = (1.0 - dist / 0.1) * brightness;
        if (localV > v) {
          v = localV;
          hue = drop.hue;
        }
      }
    }

    if (v > 0.0) {
      final rgb = _hsvToRgb(hue, saturation, v);
      packet.addAll(rgb);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
}
