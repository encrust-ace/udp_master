import 'dart:math';
import 'dart:typed_data';

class AudioFeatures {
  final double sub;
  final double bass;
  final double mid;
  final double high;
  final double overall;
  AudioFeatures({
    required this.sub,
    required this.bass,
    required this.mid,
    required this.high,
    required this.overall,
  });
}

/// LedFx-style analyzer with filterbanks, smoothing & decay
class AudioAnalyzer {
  final int sampleRate;
  final int fftSize;

  // smoothing parameters
  final double smoothing;
  final double decay;

  // persistent state
  double _sub = 0, _bass = 0, _mid = 0, _high = 0;

  AudioAnalyzer({
    this.sampleRate = 44100,
    this.fftSize = 1024,
    this.smoothing = 0.5,
    this.decay = 0.02,
  });

  AudioFeatures analyze(Float32List fft) {
    int n = fft.length;
    double binHz = sampleRate / (2 * n);

    double subNow = 0, bassNow = 0, midNow = 0, highNow = 0;

    for (int i = 0; i < n; i++) {
      double f = i * binHz;
      double mag = fft[i].abs();

      if (f < 60) {
        subNow += mag;
      } else if (f < 250) {
        bassNow += mag;
      } else if (f < 2000) {
        midNow += mag;
      } else {
        highNow += mag;
      }
    }

    // exponential smoothing + decay
    _sub = _smoothAndDecay(_sub, subNow);
    _bass = _smoothAndDecay(_bass, bassNow);
    _mid = _smoothAndDecay(_mid, midNow);
    _high = _smoothAndDecay(_high, highNow);

    double overall = _sub + _bass + _mid + _high;

    return AudioFeatures(
      sub: _sub,
      bass: _bass,
      mid: _mid,
      high: _high,
      overall: overall,
    );
  }

  double _smoothAndDecay(double prev, double current) {
    double decayed = prev * (1 - decay);
    return max(current, decayed) * smoothing + current * (1 - smoothing);
  }
}
