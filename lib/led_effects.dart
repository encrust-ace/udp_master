import 'dart:math';

typedef EffectRenderFunction =
    List<int> Function({
      required int ledCount,
      required double volume,
      required double
      hue, // You can add more parameters if other effects need them
      // e.g., double speed, Color customColor, etc.
    });

class LedEffect {
  final String id;
  final String name;
  final EffectRenderFunction renderFunction;

  LedEffect({
    required this.id,
    required this.name,
    required this.renderFunction,
  });
}

List<int> hsvToRgb(double h, double s, double v) {
  /* ... (same hsvToRgb function) ... */
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
  return [(r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt()];
}

List<int> renderLinearFillPacket({
  required int ledCount,
  required double volume,
  required double hue,
}) {
  List<int> packet = [0x02, 0x01]; // Header

  int lit = (volume * ledCount).clamp(0, ledCount).toInt();

  for (int i = 0; i < ledCount; i++) {
    if (i < lit) {
      var rgb = hsvToRgb((hue + i / ledCount) % 1.0, 1.0, 1.0);
      packet.addAll(rgb);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }
  return packet;
}

// --- Placeholder for your other effect functions ---
List<int> renderCenterPulsePacket({
  required int ledCount,
  required double volume,
  required double hue,
}) {
  // This is just a placeholder example, similar to linear fill for now
  List<int> packet = [
    0x02,
    0x02,
  ]; // Different header maybe? Or handle in UDP sender
  int center = ledCount ~/ 2;
  int spread = (volume * (ledCount / 2.0)).clamp(0, ledCount / 2.0).toInt();

  for (int i = 0; i < ledCount; i++) {
    double distanceFromCenter = (i - center).abs().toDouble();
    if (distanceFromCenter <= spread) {
      // Intensity can fall off with distance from center within the spread
      double intensity = 1.0 - (distanceFromCenter / spread);
      var rgb = hsvToRgb(hue, 1.0, intensity.clamp(0.0, 1.0));
      packet.addAll(rgb);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }
  return packet;
}

List<int> renderWavePulsePacket({
  required int ledCount,
  required double volume,
  required double hue,
}) {
  List<int> packet = [0x02, 0x03]; // Different header

  // Your existing hsvToRgb function if it's not already top-level or imported
  List<int> hsvToRgb(double h, double s, double v) {
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
    return [(r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt()];
  }

  for (int i = 0; i < ledCount; i++) {
    double timeWave = sin(
      DateTime.now().millisecondsSinceEpoch / 500.0 +
          (i / (ledCount / (2 * pi))),
    );
    double intensity =
        (0.5 + 0.5 * timeWave) * volume; // Scale the 0-1 wave by volume

    intensity = intensity.clamp(0.0, 1.0);

    var rgb = hsvToRgb(
      (hue + (i / (ledCount * 0.3))) % 1.0,
      1.0,
      intensity,
    );
    packet.addAll(rgb);
  }
  return packet;
}

final List<LedEffect> availableEffects = [
  LedEffect(
    id: 'linear-fill',
    name: 'Linear Fill',
    renderFunction: renderLinearFillPacket,
  ),
  LedEffect(
    id: 'center-pulse',
    name: 'Center Pulse',
    renderFunction: renderCenterPulsePacket,
  ),
  LedEffect(
    id: 'wave-pulse',
    name: 'Wave Pulse',
    renderFunction: renderWavePulsePacket,
  ),
  // Add more effects here as you create their render functions
];

LedEffect? getEffectById(String id) {
  try {
    return availableEffects.firstWhere((effect) => effect.id == id);
  } catch (e) {
    return null; // Not found
  }
}
