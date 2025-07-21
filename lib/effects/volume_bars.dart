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

List<int> renderVolumeBars({
  required int ledCount,
  required double volume,
  required double hue,
}) {
  List<int> packet = [0x02, 0x04];
  int active = (volume * ledCount).round().clamp(0, ledCount);

  for (int i = 0; i < ledCount; i++) {
    if (i < active) {
      var rgb = _hsvToRgb(hue, 1.0, 1.0);
      packet.addAll(rgb);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }
  return packet;
}
