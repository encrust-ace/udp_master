import 'dart:typed_data';

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

List<int> renderCenterPulsePacket({
  required int ledCount,
  required Float32List fft,
  required double gain,
}) {
  List<int> packet = [0x02, 0x02];
  double sum = 0;
  for (final value in fft) {
    sum += value.abs();
  }

  double avg = sum / fft.length;
  double normalized = (avg * gain).clamp(0.0, 1.0);
  double half = ledCount / 2;
  double spread = normalized * half;
  double hue = (1.0 - spread) * 0.7; // high intensity = red
  for (int i = 0; i < ledCount; i++) {
    double dist = (i - half + 0.5).abs(); // for even counts
    if (dist < spread) {
      double intensity = (1.0 - (dist / spread)).clamp(0.0, 1.0);
      var rgb = _hsvToRgb(hue, 1.0, intensity);
      packet.addAll(rgb);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }
  return packet;
}
