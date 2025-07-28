import 'dart:typed_data';

import 'package:udp_master/models.dart'; // Assuming this provides LedDevice

// Enum for frequency band selection (unchanged)
enum BeatFrequencyBand { bass, mids, highs }

// Helper function to convert HSV to RGB (unchanged)
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

// --- Global state variables for the effect ---
double _currentRisingLedsCount = 0.0;

// Drop animation state
// We'll manage this so it effectively cycles, representing both falling and rising
double _currentDropLogicalPos = 0.0;

// Beat detection state
int _lastBeatDetectedTime = 0;
List<double> _energyHistory = [];
final int _historyLength = 30;

// Automatic Gain Control (AGC) state
double _currentGain = 1.0;
final double _gainAttack = 0.005;
final double _gainDecay = 0.001;
final double _targetLoudness = 0.1;

// Aesthetic state
double _rainbowHueOffset = 0.0;
final double _rainbowSpeed = 0.005;

List<int> renderBeatDropEffect({
  required LedDevice device,
  required Float32List fft,
  required double gain,
  required double brightness,
  required double saturation,
  required double raiseSpeed,
  required double decaySpeed,
  required double dropSpeed,
}) {
  final int count = device.ledCount;
  BeatFrequencyBand beatFrequencyBand = BeatFrequencyBand.bass;
  final double beatThreshold = 0.1;
  final int retriggerDelayMs = 150;
  final double squelch = 0.1;
  if (count == 0 || fft.isEmpty) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];
  final int now = DateTime.now().millisecondsSinceEpoch;

  // --- FFT Band Energy Calculation (unchanged) ---
  final int fftLen = fft.length;
  final int bassEnd = (fftLen * 0.1).floor();
  final int midsEnd = (fftLen * 0.4).floor();

  double bassAvg = 0.0, midAvg = 0.0, highAvg = 0.0;

  if (bassEnd > 0) {
    for (int i = 0; i < bassEnd; i++) {
      bassAvg += fft[i].abs();
    }
    bassAvg /= bassEnd;
  }
  if (midsEnd > bassEnd) {
    for (int i = bassEnd; i < midsEnd; i++) {
      midAvg += fft[i].abs();
    }
    midAvg /= (midsEnd - bassEnd);
  }
  if (fftLen > midsEnd) {
    for (int i = midsEnd; i < fftLen; i++) {
      highAvg += fft[i].abs();
    }
    highAvg /= (fftLen - midsEnd);
  }

  double rawBeatEnergy;
  switch (beatFrequencyBand) {
    case BeatFrequencyBand.bass:
      rawBeatEnergy = bassAvg;
      break;
    case BeatFrequencyBand.mids:
      rawBeatEnergy = midAvg;
      break;
    case BeatFrequencyBand.highs:
      rawBeatEnergy = highAvg;
      break;
  }

  double processedEnergy = rawBeatEnergy * gain;

  // --- Automatic Gain Control (AGC) (unchanged) ---
  if (processedEnergy > _targetLoudness) {
    _currentGain -= _gainAttack * (processedEnergy - _targetLoudness);
  } else if (processedEnergy < _targetLoudness / 2) {
    _currentGain += _gainDecay * (_targetLoudness - processedEnergy);
  } else {
    _currentGain -= _gainDecay * 0.1;
  }
  _currentGain = _currentGain.clamp(0.5, 5.0);

  double currentEnergy = rawBeatEnergy * _currentGain;

  if (currentEnergy < squelch) {
    currentEnergy = 0.0;
  }

  _energyHistory.add(currentEnergy);
  if (_energyHistory.length > _historyLength) _energyHistory.removeAt(0);

  double avgHistoryEnergy = _energyHistory.isEmpty
      ? 0.0
      : _energyHistory.reduce((a, b) => a + b) / _energyHistory.length;

  final double dynamicThreshold = avgHistoryEnergy * (1.0 + beatThreshold) + 0.005;
  final bool beatDetectedThisFrame = currentEnergy > dynamicThreshold;

  // --- Animation State Update ---
  if (beatDetectedThisFrame && (now - _lastBeatDetectedTime > retriggerDelayMs)) {
    // Beat detected: Grow the bar and reset the drop to the top.
    _currentRisingLedsCount += raiseSpeed;
    _currentDropLogicalPos = 0.0; // Always reset to the logical top on beat
    _lastBeatDetectedTime = now;
  } else {
    // No beat: Decay the bar.
    _currentRisingLedsCount -= decaySpeed;
  }

  _currentRisingLedsCount = _currentRisingLedsCount.clamp(0.0, count.toDouble());

  // --- Drop LED Animation Logic (MODIFIED to use raiseSpeed for return) ---
  // The drop continuously moves.
  // If _currentDropLogicalPos is less than 'count', it's falling.
  // If _currentDropLogicalPos is 'count' or more, it has "hit the bottom" and is
  // now conceptually moving upwards or resetting.

  if (_currentDropLogicalPos < count) {
    // Drop is currently falling
    _currentDropLogicalPos += dropSpeed;
  } else {
    // Drop has passed the bottom, now "move" it back to the top quickly
    // by decrementing from its current 'off-screen' position.
    // This makes it visually reappear at the top quickly.
    _currentDropLogicalPos += raiseSpeed; // Use raiseSpeed to move it upwards

    // If it has moved "off the top" (become very large due to successive raiseSpeeds without reset)
    // or if we simply want it to always cycle through the visible range after hitting the bottom.
    // The modulo operation helps keep it within bounds while simulating a wrap-around
    // or a fast ascent from below the screen.
    // We want it to be 0 when it should be at the top after its fast ascent.
    // Let's ensure it stays within a manageable range for rendering.
    if (_currentDropLogicalPos >= count + count * 0.5) { // If it's well past bottom, snap it back
        _currentDropLogicalPos = 0.0; // Or ( _currentDropLogicalPos % count ); for looping
    }

    // A simpler way: if it hits bottom, reset it to a negative value corresponding to
    // its effective starting point for the fast ascent.
    // On beat, _currentDropLogicalPos is 0.0.
    // It increases by dropSpeed.
    // When _currentDropLogicalPos >= count, it hit the bottom.
    // To make it rise fast from the bottom, it should go from `count` back to `0`.
    // We can simulate this by making the "effective" position from `count` to `0` using `raiseSpeed`.
    // This is probably best done by resetting and then adding raiseSpeed *after* hitting the bottom.

    // Let's refine the logic to make it clearer for "fast ascent":
    // The `_currentDropLogicalPos` should always represent the position from 0 (top) to count (bottom).
    // When it goes past `count`, it means it's "off screen at the bottom".
    // We now want it to animate from this "off screen bottom" to "on screen top".
    // A more explicit state-based system makes this cleaner without extra variables:
    // This current approach of just continually incrementing will make the drop appear to
    // accelerate off screen then slowly return.

    // Reverting to the logic that makes it behave like a "fast teleport to top" when it hits the bottom.
    // This is done by checking if it exceeded `count`.
    if (_currentDropLogicalPos >= count) {
        // If it goes off the bottom, immediately set it to "off the top, ready to rise".
        // The value `-(count - 1)` means it's just off the top by the full strip length.
        // Then, the next `+ raiseSpeed` will bring it onto the screen.
        _currentDropLogicalPos = -(count - 1).toDouble(); // Set to effectively "off screen top"
    }
  }

  // Always update rainbow hue offset for continuous color shift
  _rainbowHueOffset = (_rainbowHueOffset + _rainbowSpeed) % 1.0;

  // --- Render LEDs ---
  final int risingBottomLeds = _currentRisingLedsCount.round();
  // Ensure dropLedPosition is always a valid index or logically handled
  // We need to map _currentDropLogicalPos (which can be negative) to a visible LED index [0, count-1]
  int dropLedPosition = _currentDropLogicalPos.floor();

  for (int i = 0; i < count; i++) {
    List<int> ledColor = [0, 0, 0]; // Default to OFF

    // Render the growing/decaying bar.
    if (i < risingBottomLeds) {
      double hue = (_rainbowHueOffset + (i / count)).remainder(1.0);
      ledColor = _hsvToRgb(hue, saturation, brightness);
    }

    // Always keep the first LED (index 0) on with a rainbow color (if desired)
    if (i == 0) {
      double hue = _rainbowHueOffset;
      ledColor = _hsvToRgb(hue, saturation, brightness);
    }

    // Overlay the drop LED
    // `actualDropLedIndex` maps logical position (0=top, count-1=bottom) to physical index.
    // If _currentDropLogicalPos is 0 (top), actualDropLedIndex is count-1.
    // If _currentDropLogicalPos is count-1 (bottom), actualDropLedIndex is 0.
    int actualDropLedIndex = count - 1 - dropLedPosition;

    // Only render the drop if its logical position is within the visible range [0, count-1]
    if (dropLedPosition >= 0 && dropLedPosition < count && i == actualDropLedIndex) {
      double dropHue = (_rainbowHueOffset + (actualDropLedIndex / count)).remainder(1.0);
      ledColor = _hsvToRgb(dropHue, saturation, brightness);
    }
    packet.addAll(ledColor);
  }

  return packet;
}