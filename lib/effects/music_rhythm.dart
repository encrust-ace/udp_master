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
final double _targetLoudness = 0.1; // The desired average loudness level.
double _rainbowHueOffset = 0.0; // Current position in the rainbow color cycle.
final double _rainbowSpeed = 0.005; // How fast the rainbow colors cycle.

List<int> renderBeatDropEffect({
  required int ledCount,
  required AudioFeatures features,
  required double gain,
  required double brightness,
  required double saturation,
  required double raiseSpeed,
  required double decaySpeed,
  required double dropSpeed,
}) {
  final List<int> packet = [0x02, 0x04];
  final int now = DateTime.now().millisecondsSinceEpoch;

  double rawEnergy = features.bassEnergy;

  final double userOrAutoGain = gain == 0
      ? _beatDropAgc.computeGain(rawEnergy)
      : gain;

  double processedEnergy = rawEnergy * userOrAutoGain;

  // Faster dynamic gain adjustment
  if (processedEnergy > _targetLoudness) {
    _currentGain -= 0.015 * (processedEnergy - _targetLoudness);
  } else {
    _currentGain += 0.004 * (_targetLoudness - processedEnergy);
  }
  _currentGain = _currentGain.clamp(1.0, 6.0);

  double currentEnergy = rawEnergy * _currentGain;

  // Squelch
  if (currentEnergy < 0.05) currentEnergy = 0.0;

  _energyHistory.add(currentEnergy);
  if (_energyHistory.length > _historyLength) {
    _energyHistory.removeAt(0);
  }

  double avgEnergy = _energyHistory.isEmpty
      ? 0.0
      : _energyHistory.reduce((a, b) => a + b) / _energyHistory.length;

  // Make beat threshold a bit more aggressive
  final double dynamicThreshold = avgEnergy * 1.05 + 0.002;
  final bool beatDetected = currentEnergy > dynamicThreshold;

  if (beatDetected && (now - _lastBeatDetectedTime > 120)) {
    // Increase rising LEDs more forcefully
    _currentRisingLedsCount += raiseSpeed + 2;
    _currentDropLogicalPos = 0.0;
    _lastBeatDetectedTime = now;
  } else {
    _currentRisingLedsCount -= decaySpeed;
  }

  _rainbowHueOffset = (_rainbowHueOffset + _rainbowSpeed) % 1.0;

  final int risingBottomLeds = _currentRisingLedsCount.round();
  final int dropLedPosition = _currentDropLogicalPos.floor();

  _currentRisingLedsCount = _currentRisingLedsCount.clamp(
    0.0,
    ledCount.toDouble(),
  );

  if (_currentDropLogicalPos < ledCount) {
    _currentDropLogicalPos += dropSpeed;
  } else {
    _currentDropLogicalPos += raiseSpeed;
    if (_currentDropLogicalPos >= ledCount + ledCount * 0.5) {
      _currentDropLogicalPos = 0.0;
    }
    if (_currentDropLogicalPos >= ledCount) {
      _currentDropLogicalPos = -(ledCount - 1).toDouble();
    }
  }
  for (int i = 0; i < ledCount; i++) {
    List<int> ledColor = [0, 0, 0];

    if (i < risingBottomLeds) {
      double hue = (_rainbowHueOffset + (i / ledCount)) % 1.0;
      ledColor = hsvToRgb(hue, saturation, brightness);
    }

    if (i == 0) {
      double hue = _rainbowHueOffset;
      ledColor = hsvToRgb(hue, saturation, brightness);
    }

    int actualDropLedIndex = ledCount - 1 - dropLedPosition;
    if (dropLedPosition >= 0 &&
        dropLedPosition < ledCount &&
        i == actualDropLedIndex) {
      double dropHue =
          (_rainbowHueOffset + (actualDropLedIndex / ledCount)) % 1.0;
      ledColor = hsvToRgb(dropHue, saturation, brightness);
    }

    packet.addAll(ledColor);
  }

  return packet;
}
