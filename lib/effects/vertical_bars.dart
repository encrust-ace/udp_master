import 'package:udp_master/models.dart';
import 'package:udp_master/services/audio_analyzer.dart';

double _previousBarStrength = 0.0;
final AutoGainController agc = AutoGainController();

List<int> renderVerticalBars({
  required LedDevice device,
  required AudioFeatures features,
  required double brightness,
  required double saturation,
  double gain = 0.0, // NEW PARAMETER
}) {
  final int count = device.ledCount;
  if (count == 0) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];

  // Use AGC if userGain is 0, otherwise use userGain directly
  final double effectiveGain = gain == 0.0
      ? agc.computeGain(features.bassEnergy)
      : gain;

  final double rawStrength = (features.bassEnergy * effectiveGain).clamp(
    0.0,
    1.0,
  );

  // Smooth the output (EMA)
  const double smoothFactor = 0.2;
  _previousBarStrength =
      (_previousBarStrength * (1 - smoothFactor)) +
      (rawStrength * smoothFactor);

  final double barStrength = _previousBarStrength;

  for (int i = 0; i < count; i++) {
    final double pos = (i + 0.5) / count;
    final double strength = ((barStrength - pos) * count).clamp(0.0, 1.0);

    if (strength > 0) {
      final double hue = (features.hue % 360) / 360;
      final double beatBoost = features.isBeat ? 1.2 : 1.0;

      final fadedColor = hsvToRgb(
        hue,
        saturation,
        (brightness * strength * beatBoost).clamp(0.0, 1.0),
      );
      packet.addAll(fadedColor);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
}
