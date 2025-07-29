import 'dart:typed_data';

import 'package:udp_master/models.dart';

// Enum to define which frequency band (bass, mids, highs) we are listening for beats.
enum BeatFrequencyBand { bass, mids, highs }

// Helper function to convert HSV (Hue, Saturation, Value) color to RGB (Red, Green, Blue).
// This allows for creating smooth color gradients and vibrant effects.
List<int> _hsvToRgb(double h, double s, double v) {
  h = h.clamp(0.0, 1.0); // Ensure hue is between 0 and 1
  s = s.clamp(0.0, 1.0); // Ensure saturation is between 0 and 1
  v = v.clamp(0.0, 1.0); // Ensure value (brightness) is between 0 and 1
  int i = (h * 6).floor(); // Which "sextant" of the color wheel we are in
  double f = h * 6 - i; // Fractional part for interpolation
  double p = v * (1 - s);
  double q = v * (1 - f * s);
  double t = v * (1 - (1 - f) * s);
  double r, g, b; // Red, Green, Blue components

  // Convert based on the sextant
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
  // Convert 0-1 values to 0-255 and return as a list of integers
  return [(r * 255).round(), (g * 255).round(), (b * 255).round()];
}

// Variables to track the state of the beat drop effect over time.
double _currentRisingLedsCount = 0.0; // How many LEDs are currently "lit up" from the bottom.
double _currentDropLogicalPos = 0.0; // The logical position of the "falling" beat drop element.
int _lastBeatDetectedTime = 0; // Timestamp of the last detected beat to prevent rapid re-triggering.
List<double> _energyHistory = []; // Stores recent audio energy levels to calculate a dynamic threshold.
final int _historyLength = 0; // How many past energy samples to keep in history.

// Variables for dynamic gain adjustment and rainbow effect.
double _currentGain = 1.0; // Current amplification of the audio signal.
final double _gainAttack = 0.005; // How quickly the gain reduces when loudness is high.
final double _gainDecay = 0.001; // How quickly the gain increases when loudness is low.
final double _targetLoudness = 0.1; // The desired average loudness level.
double _rainbowHueOffset = 0.0; // Current position in the rainbow color cycle.
final double _rainbowSpeed = 0.005; // How fast the rainbow colors cycle.

// Main function to render the beat drop effect for a given LED device.
List<int> renderBeatDropEffect({
  required LedDevice device, // The LED device configuration (e.g., number of LEDs).
  required Float32List fft, // Fast Fourier Transform data, representing audio frequencies.
  required double gain, // User-defined gain for the effect sensitivity.
  required double brightness, // User-defined brightness for the effect.
  required double saturation, // User-defined color saturation for the effect.
  required double raiseSpeed, // How fast LEDs rise from the bottom on a beat.
  required double decaySpeed, // How fast LEDs fade/decay after rising.
  required double dropSpeed, // How fast the "dropping" beat indicator moves.
}) {
  final int count = device.ledCount; // Total number of LEDs on the device.
  BeatFrequencyBand beatFrequencyBand = BeatFrequencyBand.bass; // Which part of the sound spectrum to focus on for beats.
  final double beatThreshold = 0.1; // How much louder a sound needs to be than average to be considered a beat.
  final int retriggerDelayMs = 0; // Minimum time between detected beats to prevent flickering.
  final double squelch = 0.1; // A minimum energy level below which sound is ignored (noise gate).

  // If no LEDs or no audio data, return a default empty packet.
  if (count == 0 || fft.isEmpty) return [0x02, 0x04];

  // Initialize the packet with WLED specific header (0x02 for '2D' or 'DRGB' mode, 0x04 for refresh rate).
  final List<int> packet = [0x02, 0x04];
  final int now = DateTime.now().millisecondsSinceEpoch; // Current time for beat re-triggering.
  final int fftLen = fft.length; // Total length of the FFT data.

  // Define frequency band boundaries within the FFT data.
  final int bassEnd = (fftLen * 0.1).floor(); // First 10% of FFT is bass.
  final int midsEnd = (fftLen * 0.4).floor(); // Next 30% is mids (up to 40% of total).

  // Calculate average energy for bass, mids, and highs.
  double bassAvg = 0.0, midAvg = 0.0, highAvg = 0.0;

  if (bassEnd > 0) {
    for (int i = 0; i < bassEnd; i++) {
      bassAvg += fft[i].abs(); // Sum absolute values of bass frequencies.
    }
    bassAvg /= bassEnd; // Average bass energy.
  }
  if (midsEnd > bassEnd) {
    for (int i = bassEnd; i < midsEnd; i++) {
      midAvg += fft[i].abs(); // Sum absolute values of mid frequencies.
    }
    midAvg /= (midsEnd - bassEnd); // Average mid energy.
  }
  if (fftLen > midsEnd) {
    for (int i = midsEnd; i < fftLen; i++) {
      highAvg += fft[i].abs(); // Sum absolute values of high frequencies.
    }
    highAvg /= (fftLen - midsEnd); // Average high energy.
  }

  // Determine the raw beat energy based on the selected frequency band.
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

  // --- Dynamic Gain Adjustment (Automatic Volume Control) ---
  // This helps the effect respond consistently regardless of input volume.
  double processedEnergy = rawBeatEnergy * gain; // Apply user-defined gain to raw energy.
  if (processedEnergy > _targetLoudness) {
    _currentGain -= _gainAttack * (processedEnergy - _targetLoudness); // Reduce gain if too loud.
  } else if (processedEnergy < _targetLoudness / 2) {
    _currentGain += _gainDecay * (_targetLoudness - processedEnergy); // Increase gain if too quiet.
  } else {
    _currentGain -= _gainDecay * 0.1; // Slowly decay gain even when near target.
  }
  _currentGain = _currentGain.clamp(0.5, 5.0); // Keep gain within a reasonable range.

  // Calculate current energy with the adjusted dynamic gain.
  double currentEnergy = rawBeatEnergy * _currentGain;

  // Apply squelch: if energy is below this, set to zero to filter out background noise.
  if (currentEnergy < squelch) {
    currentEnergy = 0.0;
  }

  // Update energy history for dynamic threshold calculation.
  _energyHistory.add(currentEnergy);
  if (_energyHistory.length > _historyLength) _energyHistory.removeAt(0); // Keep history length fixed.

  // Calculate the average energy from the history.
  double avgHistoryEnergy = _energyHistory.isEmpty
      ? 0.0
      : _energyHistory.reduce((a, b) => a + b) / _energyHistory.length;

  // Calculate a dynamic threshold for beat detection: average history + a beat sensitivity margin.
  final double dynamicThreshold = avgHistoryEnergy * (1.0 + beatThreshold) + 0.005;
  final bool beatDetectedThisFrame = currentEnergy > dynamicThreshold; // Is the current energy above the threshold?

  // --- Beat Triggering Logic ---
  // If a beat is detected AND enough time has passed since the last beat:
  if (beatDetectedThisFrame && (now - _lastBeatDetectedTime > retriggerDelayMs)) {
    _currentRisingLedsCount += raiseSpeed; // Make more LEDs rise from the bottom.
    _currentDropLogicalPos = 0.0; // Reset the dropping element to the top.
    _lastBeatDetectedTime = now; // Update last beat time.
  } else {
    _currentRisingLedsCount -= decaySpeed; // Otherwise, LEDs decay from the bottom.
  }

  // Clamp the rising LEDs count to prevent it from going out of bounds.
  _currentRisingLedsCount = _currentRisingLedsCount.clamp(0.0, count.toDouble());

  // --- Dropping Effect Logic ---
  // If the dropping element hasn't reached the bottom yet, keep it moving.
  if (_currentDropLogicalPos < count) {
    _currentDropLogicalPos += dropSpeed;
  } else {
    // Once it reaches the bottom, reset it to the top or slightly above the top
    // to create a continuous falling effect. The logic here creates a "wrap-around"
    // or continuous falling visual.
    _currentDropLogicalPos += raiseSpeed; // A small boost to ensure it moves past 'count'
    if (_currentDropLogicalPos >= count + count * 0.5) { // If it goes too far past, reset
        _currentDropLogicalPos = 0.0;
    }
    // This condition seems to reset the drop position slightly differently,
    // potentially making it appear from the very top (`count - 1`) again.
    // It's a bit of a tricky logic for a continuous loop.
    if (_currentDropLogicalPos >= count) {
        _currentDropLogicalPos = -(count - 1).toDouble();
    }
  }

  // Update the rainbow color offset for the next frame.
  _rainbowHueOffset = (_rainbowHueOffset + _rainbowSpeed) % 1.0;

  // --- Render LEDs (Determine Color for Each LED) ---
  final int risingBottomLeds = _currentRisingLedsCount.round(); // Number of LEDs to light from the bottom.
  int dropLedPosition = _currentDropLogicalPos.floor(); // Current integer position of the dropping LED.

  // Loop through each LED to determine its color.
  for (int i = 0; i < count; i++) {
    List<int> ledColor = [0, 0, 0]; // Default color is off (black).

    // LEDs at the bottom (rising from a beat) get a rainbow color.
    if (i < risingBottomLeds) {
      double hue = (_rainbowHueOffset + (i / count)).remainder(1.0); // Calculate hue based on position and global offset.
      ledColor = _hsvToRgb(hue, saturation, brightness); // Convert to RGB.
    }

    // The very first LED (bottom-most) always gets a special rainbow color if active.
    // This might be redundant with the `i < risingBottomLeds` if `risingBottomLeds` can be 0.
    // Or it ensures the first pixel always shows the current global rainbow hue.
    if (i == 0) {
      double hue = _rainbowHueOffset;
      ledColor = _hsvToRgb(hue, saturation, brightness);
    }

    // Calculate the actual index for the "dropping" LED (from top to bottom).
    int actualDropLedIndex = count - 1 - dropLedPosition;
    // If the current LED is the dropping LED, give it a rainbow color.
    if (dropLedPosition >= 0 && dropLedPosition < count && i == actualDropLedIndex) {
      double dropHue = (_rainbowHueOffset + (actualDropLedIndex / count)).remainder(1.0);
      ledColor = _hsvToRgb(dropHue, saturation, brightness);
    }
    packet.addAll(ledColor); // Add the RGB color of the current LED to the packet.
  }

  return packet; // Return the final LED packet data.
}