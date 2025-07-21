typedef EffectRenderFunction =
    List<int> Function({
      required int ledCount,
      required double volume,
      required double hue,
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

// --- HSV to RGB ---
List<int> hsvToRgb(double h, double s, double v) {
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

List<int> renderCenterPulsePacket({
  required int ledCount,
  required double volume,
  required double hue,
}) {
  List<int> packet = [0x02, 0x02];
  double reactiveVolume = (volume).clamp(0.0, 1.0);
  double half = ledCount / 2;
  double spread = reactiveVolume * half;

  for (int i = 0; i < ledCount; i++) {
    double dist = (i - half + 0.5).abs(); // for even counts
    if (dist < spread) {
      double intensity = (1.0 - (dist / spread)).clamp(0.0, 1.0);
      var rgb = hsvToRgb(hue, 1.0, intensity);
      packet.addAll(rgb);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }
  return packet;
}

List<int> renderVolumeBars({
  required int ledCount,
  required double volume,
  required double hue,
}) {
  List<int> packet = [0x02, 0x04];
  int active = (volume * ledCount).round().clamp(
    0,
    ledCount,
  );

  for (int i = 0; i < ledCount; i++) {
    if (i < active) {
      var rgb = hsvToRgb(hue, 1.0, 1.0);
      packet.addAll(rgb);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }
  return packet;
}

List<int> renderRainbowFlow({
  required int ledCount,
  required double volume,
  required double hue,
}) {
  List<int> packet = [0x02, 0x05];
  for (int i = 0; i < ledCount; i++) {
    double offsetHue = (hue + i / ledCount) % 1.0;
    double brightness = volume.clamp(0.2, 1.0);
    final rgb = hsvToRgb(offsetHue, 1.0, brightness);
    packet.addAll(rgb);
  }
  return packet;
}

// --- Effect List ---
final List<LedEffect> availableEffects = [
  LedEffect(
    id: 'volume-bars',
    name: 'Volume Bars',
    renderFunction: renderVolumeBars,
  ),
  LedEffect(
    id: 'center-pulse',
    name: 'Center Pulse',
    renderFunction: renderCenterPulsePacket,
  ),
  LedEffect(
    id: 'rainbow-flow',
    name: 'Rainbow Flow',
    renderFunction: renderRainbowFlow,
  ),
];

LedEffect? getEffectById(String id) {
  try {
    return availableEffects.firstWhere((effect) => effect.id == id);
  } catch (_) {
    return null;
  }
}
