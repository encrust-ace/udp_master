import 'dart:math';
import 'dart:typed_data';

class AudioFeatures {
  final double rms;
  final double dominantFrequency;
  final double subEnergy;
  final double bassEnergy;
  final double midEnergy;
  final double highEnergy;
  final double hue;
  final bool isBeat;

  AudioFeatures({
    required this.rms,
    required this.dominantFrequency,
    required this.subEnergy,
    required this.bassEnergy,
    required this.midEnergy,
    required this.highEnergy,
    required this.hue,
    required this.isBeat,
  });
}

class AudioAnalyzer {
  final int sampleRate;
  final int fftSize;
  double _previousEnergy = 0;
  int _beatCooldown = 0;

  AudioAnalyzer({this.sampleRate = 44100, this.fftSize = 1024});

  AudioFeatures analyze(Float32List fft) {
    final int binCount = fft.length;
    final double binFreq = sampleRate / (2 * binCount);

    double maxAmplitude = 0;
    int maxIndex = 0;
    double sumSquares = 0;

    double sub = 0, bass = 0, mid = 0, high = 0;
    double energySum = 0, energyWeightedSum = 0;

    for (int i = 0; i < binCount; i++) {
      double amplitude = fft[i];
      double freq = i * binFreq;
      double square = amplitude * amplitude;

      sumSquares += square;
      energySum += square;
      energyWeightedSum += square * freq;

      if (amplitude > maxAmplitude) {
        maxAmplitude = amplitude;
        maxIndex = i;
      }

      if (freq < 60) {
        sub += square;
      } else if (freq < 250) {
        bass += square;
      } else if (freq < 2000) {
        mid += square;
      } else {
        high += square;
      }
    }

    final double rms = sqrt(sumSquares / binCount);
    final double dominantFrequency = maxIndex * binFreq;

    // Simple beat detection based on energy difference
    final double energy = sumSquares;
    bool isBeat = false;
    if (_beatCooldown <= 0 && energy > (_previousEnergy * 1.5)) {
      isBeat = true;
      _beatCooldown = 6; // prevent false positives (about 60–100 ms)
    } else {
      _beatCooldown = max(0, _beatCooldown - 1);
    }
    _previousEnergy = energy;

    // Hue based on frequency center of energy
    final double centerFreq = energySum == 0
        ? 0
        : energyWeightedSum / energySum;
    final double hue = ((centerFreq / (sampleRate / 2)) * 360) % 360;

    return AudioFeatures(
      rms: rms,
      dominantFrequency: dominantFrequency,
      subEnergy: sub,
      bassEnergy: bass,
      midEnergy: mid,
      highEnergy: high,
      hue: hue,
      isBeat: isBeat,
    );
  }
}

List<int> hsvToRgb(double h, double s, double v) {
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
