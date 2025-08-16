import 'package:udp_master/models.dart';
import 'package:udp_master/services/audio_analyzer.dart';

final AutoGainController agcCenter = AutoGainController();

List<int> renderCenterPulsePacket({
  required LedDevice device,
  required AudioFeatures features,
  required double gain,
  required double saturation,
  required double brightness,
}) {
  final List<int> packet = [0x02, 0x02];

  // Auto-gain: use AGC if gain is 0
  final double effectiveGain = gain == 0.0
      ? agcCenter.computeGain(features.bassEnergy)
      : gain;

  // Use bassEnergy to determine pulse spread
  final double rawStrength = (features.bassEnergy * effectiveGain).clamp(
    0.0,
    1.0,
  );

  final double hue = (features.hue % 360) / 360;
  final double beatBoost = features.isBeat ? 1.2 : 1.0;

  for (Segment segment in device.segments) {
    final int count = segment.endIndex - segment.startIndex + 1;
    final double half = count / 2;
    final double spread = rawStrength * half;

    for (int i = 0; i < count; i++) {
      final double dist = (i - half + 0.5).abs(); // symmetrical from center

      if (dist < spread) {
        final double intensity =
            ((1.0 - (dist / spread)) * beatBoost * brightness).clamp(0.0, 1.0);
        final rgb = hsvToRgb(hue, saturation, intensity);
        packet.addAll(rgb);
      } else {
        packet.addAll([0, 0, 0]);
      }
    }
  }
  return packet;
}
