import 'package:udp_master/models.dart';
import 'package:udp_master/services/audio_analyzer.dart';

// Enum to define which frequency band (bass, mids, highs) we are listening for beats.
enum BeatFrequencyBand { bass, mids, highs }

final AutoGainController _beatDropAgc = AutoGainController();

// Variables to track the state of the beat drop effect over time.
double _currentRisingLedsCount =
    0.0; // How many LEDs are currently "lit up" from the bottom.
double _currentDropLogicalPos =
    0.0; // The logical position of the "falling" beat drop element.
int _lastBeatDetectedTime =
    0; // Timestamp of the last detected beat to prevent rapid re-triggering.
List<double> _energyHistory =
    []; // Stores recent audio energy levels to calculate a dynamic threshold.
final int _historyLength =
    30; // How many past energy samples to keep in history.

// Variables for dynamic gain adjustment and rainbow effect.
double _currentGain = 1.0; // Current amplification of the audio signal.
final double _gainAttack =
    0.005; // How quickly the gain reduces when loudness is high.
final double _gainDecay =
    0.001; // How quickly the gain increases when loudness is low.
final double _targetLoudness = 0.1; // The desired average loudness level.
double _rainbowHueOffset = 0.0; // Current position in the rainbow color cycle.
final double _rainbowSpeed = 0.005; // How fast the rainbow colors cycle.

List<int> renderBeatDropEffect({
  required LedDevice device,
  required AudioFeatures features,
  required double gain,
  required double brightness,
  required double saturation,
  required double raiseSpeed,
  required double decaySpeed,
  required double dropSpeed,
}) {
  final int count = device.ledCount;
  if (count == 0) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];
  final int now = DateTime.now().millisecondsSinceEpoch;

  // Use bass energy from AudioFeatures
  double rawBeatEnergy = features.bassEnergy;

  // Choose gain
  final double userOrAutoGain = gain == 0
      ? _beatDropAgc.computeGain(rawBeatEnergy)
      : gain;

  double processedEnergy = rawBeatEnergy * userOrAutoGain;

  // Apply dynamic gain logic (preserved from original)
  if (processedEnergy > _targetLoudness) {
    _currentGain -= _gainAttack * (processedEnergy - _targetLoudness);
  } else if (processedEnergy < _targetLoudness / 2) {
    _currentGain += _gainDecay * (_targetLoudness - processedEnergy);
  } else {
    _currentGain -= _gainDecay * 0.1;
  }
  _currentGain = _currentGain.clamp(0.5, 5.0);

  double currentEnergy = rawBeatEnergy * _currentGain;

  // Squelch
  if (currentEnergy < 0.1) currentEnergy = 0.0;

  // History tracking
  _energyHistory.add(currentEnergy);
  if (_energyHistory.length > _historyLength) {
    _energyHistory.removeAt(0);
  }

  double avgHistoryEnergy = _energyHistory.isEmpty
      ? 0.0
      : _energyHistory.reduce((a, b) => a + b) / _energyHistory.length;

  final double dynamicThreshold = avgHistoryEnergy * 1.1 + 0.005;

  final bool beatDetectedThisFrame = currentEnergy > dynamicThreshold;

  // Beat trigger
  if (beatDetectedThisFrame && (now - _lastBeatDetectedTime > 150)) {
    _currentRisingLedsCount += raiseSpeed;
    _currentDropLogicalPos = 0.0;
    _lastBeatDetectedTime = now;
  } else {
    _currentRisingLedsCount -= decaySpeed;
  }

  _currentRisingLedsCount = _currentRisingLedsCount.clamp(
    0.0,
    count.toDouble(),
  );

  // Dropping logic
  if (_currentDropLogicalPos < count) {
    _currentDropLogicalPos += dropSpeed;
  } else {
    _currentDropLogicalPos += raiseSpeed;
    if (_currentDropLogicalPos >= count + count * 0.5) {
      _currentDropLogicalPos = 0.0;
    }
    if (_currentDropLogicalPos >= count) {
      _currentDropLogicalPos = -(count - 1).toDouble();
    }
  }

  // Rainbow hue cycle (same logic)
  _rainbowHueOffset = (_rainbowHueOffset + _rainbowSpeed) % 1.0;

  final int risingBottomLeds = _currentRisingLedsCount.round();
  int dropLedPosition = _currentDropLogicalPos.floor();

  for (int i = 0; i < count; i++) {
    List<int> ledColor = [0, 0, 0];

    if (i < risingBottomLeds) {
      double hue = (_rainbowHueOffset + (i / count)) % 1.0;
      ledColor = hsvToRgb(hue, saturation, brightness);
    }

    if (i == 0) {
      double hue = _rainbowHueOffset;
      ledColor = hsvToRgb(hue, saturation, brightness);
    }

    int actualDropLedIndex = count - 1 - dropLedPosition;
    if (dropLedPosition >= 0 &&
        dropLedPosition < count &&
        i == actualDropLedIndex) {
      double dropHue = (_rainbowHueOffset + (actualDropLedIndex / count)) % 1.0;
      ledColor = hsvToRgb(dropHue, saturation, brightness);
    }

    packet.addAll(ledColor);
  }

  return packet;
}
