
List<int> renderLinearFillPacket({
  required int ledCount,
  required double volume,
  required double hue,
}) {
  List<int> packet = [0x02, 0x01]; // Header

  int lit = (volume * ledCount).clamp(0, ledCount).toInt();

  List<int> hsvToRgb(double h, double s, double v) {
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
    return [(r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt()];
  }

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