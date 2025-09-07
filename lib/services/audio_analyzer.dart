import 'dart:math' as math;
import 'dart:typed_data';

/// Configuration for audio analysis
class AudioConfig {
  final int micRate;        // Microphone sample rate (e.g., 44100)
  final int analysisRate;   // Analysis frames per second (e.g., 60)
  final int fftSize;        // FFT size, must be power of 2
  final int melBands;       // Number of mel bands per bank
  final double minVolume;   // Volume threshold (0-1)

  // Smoothing parameters
  final double volumeSmoothing;
  final double melSmoothing;
  final double beatSmoothing;

  const AudioConfig({
    this.micRate = 44100,
    this.analysisRate = 60,
    this.fftSize = 1024,
    this.melBands = 64,
    this.minVolume = 0.05,
    this.volumeSmoothing = 0.8,
    this.melSmoothing = 0.85,
    this.beatSmoothing = 0.7,
  });

  int get hopSize => (micRate / analysisRate).round();
}

/// Audio analysis results for visualizers
class AudioFeatures {
  // Core metrics
  final double volume;          // 0-1, smoothed RMS volume
  final double rawVolume;       // 0-1, instantaneous volume
  final bool volumeBeat;        // Beat detected from volume changes
  final bool onsetBeat;         // Beat detected from spectral changes

  // Frequency analysis
  final Float64List melbank;    // Main mel filterbank (0-1)
  final Float64List rawMelbank; // Unsmoothed mel filterbank

  // Frequency power bands
  final double basspower;       // Low frequencies (0-1)
  final double midPower;        // Mid frequencies (0-1)
  final double treblePower;     // High frequencies (0-1)
  final double subBass;         // Sub-bass frequencies (0-1)

  // Beat tracking
  final double beatConfidence;  // How confident we are in beat (0-1)
  final double tempo;          // Estimated BPM
  final double beatPhase;      // Position in beat cycle (0-1)

  // Pitch
  final double pitch;          // Fundamental frequency in Hz
  final double pitchMidi;      // MIDI note number
  final double pitchConfidence; // Pitch detection confidence (0-1)

  const AudioFeatures({
    required this.volume,
    required this.rawVolume,
    required this.volumeBeat,
    required this.onsetBeat,
    required this.melbank,
    required this.rawMelbank,
    required this.basspower,
    required this.midPower,
    required this.treblePower,
    required this.subBass,
    required this.beatConfidence,
    required this.tempo,
    required this.beatPhase,
    required this.pitch,
    required this.pitchMidi,
    required this.pitchConfidence,
  });
}

/// Main audio analysis engine for visualizers
class AudioVisualizer {
  final AudioConfig config;

  // Core components
  late final _FFTProcessor _fft;
  late final _MelFilterBank _melbank;
  late final _BeatDetector _beatDetector;
  late final _OnsetDetector _onsetDetector;
  late final _PitchDetector _pitchDetector;
  late final _TempoTracker _tempoTracker;

  // Smoothing filters
  late final _SmoothingFilter _volumeFilter;
  late final _SmoothingFilter _bassFilter;
  late final _SmoothingFilter _midFilter;
  late final _SmoothingFilter _trebleFilter;
  late final _SmoothingFilter _subBassFilter;
  late final List<_SmoothingFilter> _melFilters;

  AudioVisualizer(this.config) {
    _initializeComponents();
  }

  void _initializeComponents() {
    _fft = _FFTProcessor(config.fftSize);
    _melbank = _MelFilterBank(
      sampleRate: config.micRate,
      fftSize: config.fftSize,
      numBands: config.melBands,
    );

    _beatDetector = _BeatDetector(
      historySize: config.analysisRate, // 1 second history
      threshold: 0.3,
      smoothing: config.beatSmoothing,
    );

    _onsetDetector = _OnsetDetector();
    _pitchDetector = _PitchDetector(config.micRate);
    _tempoTracker = _TempoTracker();

    // Initialize smoothing filters
    _volumeFilter = _SmoothingFilter(config.volumeSmoothing);
    _bassFilter = _SmoothingFilter(config.melSmoothing);
    _midFilter = _SmoothingFilter(config.melSmoothing);
    _trebleFilter = _SmoothingFilter(config.melSmoothing);
    _subBassFilter = _SmoothingFilter(config.melSmoothing);

    _melFilters = List.generate(
      config.melBands,
          (_) => _SmoothingFilter(config.melSmoothing),
    );
  }

  /// Process audio data and return analysis results
  AudioFeatures processAudio(Uint8List audioBytes, {bool isFloat32 = false}) {
    // Convert audio bytes to samples
    final samples = _convertToSamples(audioBytes, isFloat32);

    // Resample to hop size if needed
    final frame = samples.length == config.hopSize
        ? samples
        : _resample(samples, config.hopSize);

    return _analyzeFrame(frame);
  }

  AudioFeatures _analyzeFrame(Float64List frame) {
    // Calculate raw volume
    final rawVol = _calculateVolume(frame);
    final smoothedVol = _volumeFilter.process(rawVol);

    // Apply window and get magnitude spectrum
    final windowed = _applyHannWindow(frame);
    final spectrum = _fft.process(windowed);

    // Get mel filterbank
    final rawMel = _melbank.process(spectrum);
    final smoothedMel = Float64List(rawMel.length);
    for (int i = 0; i < rawMel.length; i++) {
      smoothedMel[i] = _melFilters[i].process(rawMel[i]);
    }

    // Extract frequency bands
    final bands = _extractFrequencyBands(smoothedMel);
    final rawBands = _extractFrequencyBands(rawMel);

    // Beat detection
    final volumeBeat = _beatDetector.detectVolumeBeat(smoothedVol);
    final onsetBeat = _onsetDetector.detectOnset(spectrum);

    // Tempo tracking
    _tempoTracker.update(onsetBeat);

    // Pitch detection
    final pitchResult = _pitchDetector.detect(frame);

    return AudioFeatures(
      volume: smoothedVol,
      rawVolume: rawVol,
      volumeBeat: volumeBeat,
      onsetBeat: onsetBeat,
      melbank: smoothedMel,
      rawMelbank: rawMel,
      basspower: _bassFilter.process(rawBands.bass),
      midPower: _midFilter.process(rawBands.mid),
      treblePower: _trebleFilter.process(rawBands.treble),
      subBass: _subBassFilter.process(rawBands.subBass),
      beatConfidence: _beatDetector.confidence,
      tempo: _tempoTracker.tempo,
      beatPhase: _tempoTracker.beatPhase,
      pitch: pitchResult.frequency,
      pitchMidi: pitchResult.midiNote,
      pitchConfidence: pitchResult.confidence,
    );
  }

  Float64List _convertToSamples(Uint8List bytes, bool isFloat32) {
    if (isFloat32) {
      final floats = bytes.buffer.asFloat32List();
      return Float64List.fromList(floats.map((f) => f.toDouble()).toList());
    } else {
      // Ensure even length for int16
      final evenLength = bytes.length - (bytes.length % 2);
      final aligned = Uint8List.view(bytes.buffer, 0, evenLength);
      final ints = aligned.buffer.asInt16List();

      return Float64List.fromList(
          ints.map((i) => i.toDouble() / 32768.0).toList()
      );
    }
  }

  Float64List _resample(Float64List input, int targetLength) {
    if (input.length == targetLength) return input;

    final output = Float64List(targetLength);
    final ratio = input.length / targetLength;

    for (int i = 0; i < targetLength; i++) {
      final sourceIndex = i * ratio;
      final index = sourceIndex.floor();
      final fraction = sourceIndex - index;

      if (index + 1 < input.length) {
        output[i] = input[index] * (1 - fraction) + input[index + 1] * fraction;
      } else {
        output[i] = input[index];
      }
    }

    return output;
  }

  double _calculateVolume(Float64List frame) {
    double sum = 0;
    for (final sample in frame) {
      sum += sample * sample;
    }
    final rms = math.sqrt(sum / frame.length);
    return math.min(1.0, rms * 3.0); // Scale to reasonable range
  }

  Float64List _applyHannWindow(Float64List frame) {
    final windowed = Float64List(config.fftSize);
    final windowSize = math.min(frame.length, config.fftSize);

    for (int i = 0; i < windowSize; i++) {
      final window = 0.5 * (1 - math.cos(2 * math.pi * i / (windowSize - 1)));
      windowed[i] = frame[i] * window;
    }

    return windowed;
  }

  ({double subBass, double bass, double mid, double treble}) _extractFrequencyBands(Float64List mel) {
    if (mel.isEmpty) return (subBass: 0.0, bass: 0.0, mid: 0.0, treble: 0.0);

    final len = mel.length;
    final subBassEnd = (len * 0.1).round();
    final bassEnd = (len * 0.25).round();
    final midEnd = (len * 0.7).round();

    return (
    subBass: _average(mel, 0, subBassEnd),
    bass: _average(mel, subBassEnd, bassEnd),
    mid: _average(mel, bassEnd, midEnd),
    treble: _average(mel, midEnd, len),
    );
  }

  double _average(Float64List data, int start, int end) {
    if (start >= end || start >= data.length) return 0.0;

    double sum = 0;
    final actualEnd = math.min(end, data.length);
    for (int i = start; i < actualEnd; i++) {
      sum += data[i];
    }
    return sum / (actualEnd - start);
  }
}

/// Simple exponential smoothing filter
class _SmoothingFilter {
  final double alpha;
  double _value = 0.0;

  _SmoothingFilter(this.alpha);

  double process(double input) {
    _value = alpha * input + (1 - alpha) * _value;
    return _value;
  }

  double get value => _value;
}

/// FFT processor with magnitude calculation
class _FFTProcessor {
  final int size;
  late final Float64List _cosTable;
  late final Float64List _sinTable;

  _FFTProcessor(this.size) {
    _cosTable = Float64List(size);
    _sinTable = Float64List(size);
    for (int i = 0; i < size; i++) {
      final angle = -2 * math.pi * i / size;
      _cosTable[i] = math.cos(angle);
      _sinTable[i] = math.sin(angle);
    }
  }

  Float64List process(Float64List input) {
    final real = Float64List(size);
    final imag = Float64List(size);

    // Copy input
    for (int i = 0; i < math.min(input.length, size); i++) {
      real[i] = input[i];
    }

    _fft(real, imag);

    // Calculate magnitude spectrum
    final numBins = size ~/ 2 + 1;
    final magnitude = Float64List(numBins);

    for (int i = 0; i < numBins; i++) {
      magnitude[i] = math.sqrt(real[i] * real[i] + imag[i] * imag[i]);
    }

    return magnitude;
  }

  void _fft(Float64List real, Float64List imag) {
    final n = real.length;

    // Bit-reverse
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while ((j & bit) != 0) {
        j &= ~bit;
        bit >>= 1;
      }
      j |= bit;

      if (i < j) {
        // Swap
        final tempR = real[i]; real[i] = real[j]; real[j] = tempR;
        final tempI = imag[i]; imag[i] = imag[j]; imag[j] = tempI;
      }
    }

    // FFT
    for (int len = 2; len <= n; len *= 2) {
      final half = len ~/ 2;
      final step = n ~/ len;

      for (int i = 0; i < n; i += len) {
        for (int j = 0; j < half; j++) {
          final u = i + j;
          final v = i + j + half;
          final twiddle = j * step;

          final tempR = real[v] * _cosTable[twiddle] - imag[v] * _sinTable[twiddle];
          final tempI = real[v] * _sinTable[twiddle] + imag[v] * _cosTable[twiddle];

          real[v] = real[u] - tempR;
          imag[v] = imag[u] - tempI;
          real[u] = real[u] + tempR;
          imag[u] = imag[u] + tempI;
        }
      }
    }
  }
}

/// Mel filterbank for frequency analysis
class _MelFilterBank {
  final int sampleRate;
  final int fftSize;
  final int numBands;
  late final List<Float64List> _filters;

  _MelFilterBank({
    required this.sampleRate,
    required this.fftSize,
    required this.numBands,
  }) {
    _buildFilters();
  }

  void _buildFilters() {
    final numBins = fftSize ~/ 2 + 1;
    final minMel = _hzToMel(0);
    final maxMel = _hzToMel(sampleRate / 2);

    // Create mel scale points
    final melPoints = List<double>.generate(numBands + 2, (i) {
      return minMel + (maxMel - minMel) * i / (numBands + 1);
    });

    final hzPoints = melPoints.map(_melToHz).toList();
    final binPoints = hzPoints.map((hz) => (hz * fftSize / sampleRate).round()).toList();

    _filters = List.generate(numBands, (m) {
      final filter = Float64List(numBins);
      final left = binPoints[m];
      final center = binPoints[m + 1];
      final right = binPoints[m + 2];

      // Triangular filter
      for (int k = left; k < center; k++) {
        if (k >= 0 && k < numBins && center > left) {
          filter[k] = (k - left) / (center - left);
        }
      }

      for (int k = center; k < right; k++) {
        if (k >= 0 && k < numBins && right > center) {
          filter[k] = (right - k) / (right - center);
        }
      }

      return filter;
    });
  }

  Float64List process(Float64List spectrum) {
    final melSpectrum = Float64List(numBands);

    for (int m = 0; m < numBands; m++) {
      double sum = 0;
      for (int k = 0; k < spectrum.length; k++) {
        sum += spectrum[k] * _filters[m][k];
      }
      melSpectrum[m] = sum;
    }

    // Normalize
    final maxVal = melSpectrum.fold<double>(0, math.max);
    if (maxVal > 0) {
      for (int i = 0; i < numBands; i++) {
        melSpectrum[i] = math.min(1.0, melSpectrum[i] / maxVal);
      }
    }

    return melSpectrum;
  }

  double _hzToMel(double hz) => 2595 * math.log(1 + hz / 700) / math.ln10;
  double _melToHz(double mel) => 700 * (math.pow(10, mel / 2595) - 1);
}

/// Beat detection from volume changes
class _BeatDetector {
  final int historySize;
  final double threshold;
  final _SmoothingFilter _smoother;
  final List<double> _history = [];
  double _lastBeatTime = 0;
  double _confidence = 0;

  _BeatDetector({
    required this.historySize,
    required this.threshold,
    required double smoothing,
  }) : _smoother = _SmoothingFilter(smoothing);

  bool detectVolumeBeat(double volume) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // Add to history
    _history.add(volume);
    if (_history.length > historySize) {
      _history.removeAt(0);
    }

    if (_history.length < historySize ~/ 2) return false;

    // Calculate average and variance
    final avg = _history.fold<double>(0, (a, b) => a + b) / _history.length;
    final variance = _history.fold<double>(0, (sum, val) => sum + math.pow(val - avg, 2)) / _history.length;
    final stdDev = math.sqrt(variance);

    final dynamicThreshold = avg + threshold * stdDev;
    final isBeat = volume > dynamicThreshold && (now - _lastBeatTime) > 0.1;

    if (isBeat) {
      _lastBeatTime = now;
      _confidence = math.min(1.0, (volume - avg) / (stdDev + 1e-10));
    }

    _confidence = _smoother.process(_confidence);

    return isBeat;
  }

  double get confidence => _confidence;
}

/// Onset detection using spectral flux
class _OnsetDetector {
  Float64List? _previousSpectrum;
  final _SmoothingFilter _smoother = _SmoothingFilter(0.7);

  bool detectOnset(Float64List spectrum) {
    if (_previousSpectrum == null) {
      _previousSpectrum = Float64List.fromList(spectrum);
      return false;
    }

    double flux = 0;
    for (int i = 0; i < spectrum.length && i < _previousSpectrum!.length; i++) {
      flux += math.max(0, spectrum[i] - _previousSpectrum![i]);
    }

    final smoothedFlux = _smoother.process(flux);
    final isOnset = flux > smoothedFlux * 1.5;

    _previousSpectrum = Float64List.fromList(spectrum);

    return isOnset;
  }
}

/// Simple pitch detection
class _PitchDetector {
  final int sampleRate;

  _PitchDetector(this.sampleRate);

  ({double frequency, double midiNote, double confidence}) detect(Float64List samples) {
    if (samples.length < 100) {
      return (frequency: 0.0, midiNote: 0.0, confidence: 0.0);
    }

    // Simple autocorrelation-based pitch detection
    final minPeriod = (sampleRate / 800).round(); // 800 Hz max
    final maxPeriod = (sampleRate / 80).round();  // 80 Hz min

    double maxCorrelation = 0;
    int bestPeriod = minPeriod;

    for (int period = minPeriod; period < math.min(maxPeriod, samples.length ~/ 2); period++) {
      double correlation = 0;
      for (int i = 0; i < samples.length - period; i++) {
        correlation += samples[i] * samples[i + period];
      }

      if (correlation > maxCorrelation) {
        maxCorrelation = correlation;
        bestPeriod = period;
      }
    }

    final frequency = maxCorrelation > 0.1 ? sampleRate / bestPeriod : 0.0;
    final midiNote = frequency > 0 ? 69 + 12 * math.log(frequency / 440) / math.ln2 : 0.0;
    final confidence = math.min(1.0, maxCorrelation);

    return (frequency: frequency, midiNote: midiNote, confidence: confidence);
  }
}

/// Tempo tracking
class _TempoTracker {
  final List<double> _beatTimes = [];
  double _tempo = 120.0;
  double _lastBeatTime = 0;
  double _beatPhase = 0;

  void update(bool onset) {
    if (!onset) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _beatTimes.add(now);

    // Keep only recent beats
    while (_beatTimes.length > 8) {
      _beatTimes.removeAt(0);
    }

    if (_beatTimes.length >= 3) {
      // Calculate intervals
      final intervals = <double>[];
      for (int i = 1; i < _beatTimes.length; i++) {
        intervals.add(_beatTimes[i] - _beatTimes[i - 1]);
      }

      // Find median interval
      intervals.sort();
      final medianInterval = intervals[intervals.length ~/ 2];

      if (medianInterval > 0.2 && medianInterval < 2.0) {
        _tempo = 60.0 / medianInterval;
        _lastBeatTime = now;
      }
    }
  }

  double get tempo => _tempo;

  double get beatPhase {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (_lastBeatTime == 0) return 0;

    final beatInterval = 60.0 / _tempo;
    final timeSinceLastBeat = now - _lastBeatTime;
    return (timeSinceLastBeat % beatInterval) / beatInterval;
  }
}