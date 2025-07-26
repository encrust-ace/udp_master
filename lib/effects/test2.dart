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

// --- Global state variables for the effect (retained for simplicity within a single function) ---
// Bar height (grows on beat, shrinks on silence)
double _currentRisingLedsCount = 0.0;

// Drop animation state
double _currentDropLogicalPos =
    0.0; // Start at 0.0 so it's always active and falling

// Beat detection state
int _lastBeatDetectedTime = 0;
List<double> _energyHistory = [];
final int _historyLength = 30; // Increased history length for smoother average

// Automatic Gain Control (AGC) state
double _currentGain = 1.0;
final double _gainAttack = 0.005; // How quickly gain increases
final double _gainDecay = 0.001; // How quickly gain decreases
final double _targetLoudness = 0.1; // Target loudness for AGC

// Aesthetic state
double _rainbowHueOffset = 0.0;
final double _rainbowSpeed = 0.005; // Adjusted speed for smoother rainbow shift

List<int> renderBeatDropEffectTest({
  required LedDevice device,
  required Float32List fft,
  required double gain, // This 'gain' now acts as a master sensitivity/pre-amp
  required double brightness,
  required double saturation,
  double raiseSpeed =
      10.0, // Reduced speed as AGC will handle overall responsiveness
  double decaySpeed = 1, // Reduced decay speed for smoother fall
  double dropSpeed = 0.5,
  BeatFrequencyBand beatFrequencyBand =
      BeatFrequencyBand.bass, // Make this configurable
  double beatThreshold = 0.3, // Increased threshold for clearer beat detection
  int retriggerDelayMs =
      150, // Added retrigger delay to avoid multiple detections for one beat
  double squelch = 0.005, // Minimum energy to react to, filters out noise
}) {
  final int count = device.ledCount;
  if (count == 0 || fft.isEmpty) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];
  final int now = DateTime.now().millisecondsSinceEpoch;

  // --- FFT Band Energy Calculation ---
  final int fftLen = fft.length;
  final int bassEnd = (fftLen * 0.1).floor(); // 0-10% for bass
  final int midsEnd = (fftLen * 0.4)
      .floor(); // 10-40% for mids (approx 250Hz - 2kHz for 44.1kHz sample rate, 1024 FFT)

  double bassAvg = 0.0, midAvg = 0.0, highAvg = 0.0;

  // Ensure bands have at least one bin
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

  // Apply master gain (pre-amp)
  double processedEnergy = rawBeatEnergy * gain;

  // --- Automatic Gain Control (AGC) ---
  // Adjust _currentGain based on how close processedEnergy is to _targetLoudness
  if (processedEnergy > _targetLoudness) {
    _currentGain -= _gainAttack * (processedEnergy - _targetLoudness);
  } else if (processedEnergy < _targetLoudness / 2) {
    // Increase gain more aggressively if very quiet
    _currentGain += _gainDecay * (_targetLoudness - processedEnergy);
  } else {
    // Slowly decrease if just slightly below target
    _currentGain -= _gainDecay * 0.1;
  }

  // Clamp _currentGain to a reasonable range
  _currentGain = _currentGain.clamp(
    0.5,
    5.0,
  ); // Allow gain to vary between 0.5x and 5x

  double currentEnergy = rawBeatEnergy * _currentGain; // Apply dynamic gain

  // Apply squelch
  if (currentEnergy < squelch) {
    currentEnergy = 0.0;
  }

  _energyHistory.add(currentEnergy);
  if (_energyHistory.length > _historyLength) _energyHistory.removeAt(0);

  double avgHistoryEnergy = _energyHistory.isEmpty
      ? 0.0
      : _energyHistory.reduce((a, b) => a + b) / _energyHistory.length;

  // Dynamic threshold: relative to historical average + a base offset
  final double dynamicThreshold =
      avgHistoryEnergy * (1.0 + beatThreshold) + 0.005;
  final bool beatDetectedThisFrame = currentEnergy > dynamicThreshold;

  // --- Animation State Update ---
  if (beatDetectedThisFrame &&
      (now - _lastBeatDetectedTime > retriggerDelayMs)) {
    // A beat was detected: Grow the bar and reset the drop to the top.
    _currentRisingLedsCount += raiseSpeed;
    _currentDropLogicalPos = 0.0; // Reset drop to the top on beat
    _lastBeatDetectedTime = now;
  } else {
    // No beat: Decay the bar.
    _currentRisingLedsCount -= decaySpeed;
  }

  // Clamp the bar height between 0 and the total LED count.
  _currentRisingLedsCount = _currentRisingLedsCount.clamp(
    0.0,
    count.toDouble(),
  );

  // Update the drop's position (it continuously falls)
  _currentDropLogicalPos = (_currentDropLogicalPos + dropSpeed);
  // If the drop goes off-screen, loop it back to the top
  if (_currentDropLogicalPos >= count) {
    _currentDropLogicalPos = 0.0;
  }

  // Always update rainbow hue offset for continuous color shift
  _rainbowHueOffset = (_rainbowHueOffset + _rainbowSpeed) % 1.0;

  // --- Render LEDs ---
  final int risingBottomLeds = _currentRisingLedsCount.round();
  final int dropLedPosition = _currentDropLogicalPos.round();

  for (int i = 0; i < count; i++) {
    List<int> ledColor = [0, 0, 0]; // Default to OFF

    // Render the growing/decaying bar.
    if (i < risingBottomLeds) {
      double hue = (_rainbowHueOffset + (i / count)).remainder(1.0);
      ledColor = _hsvToRgb(hue, saturation, brightness);
    }

    // Always keep the first LED (index 0) on with a rainbow color (optional, but in your original code)
    if (i == 0) {
      double hue =
          _rainbowHueOffset; // Use the global offset for a moving rainbow
      ledColor = _hsvToRgb(hue, saturation, brightness);
    }

    // Overlay the drop LED if it's active and at the current position.
    // Its color will now be determined by the rainbow logic based on its position.
    int actualDropLedIndex =
        count -
        1 -
        dropLedPosition; // Assuming LEDs are ordered from bottom (0) to top (count-1)
    if (i == actualDropLedIndex) {
      // Calculate hue for the drop based on its position, similar to the rising bar
      double dropHue = (_rainbowHueOffset + (actualDropLedIndex / count))
          .remainder(1.0);
      ledColor = _hsvToRgb(dropHue, saturation, brightness);
    }
    packet.addAll(ledColor);
  }

  return packet;
}
