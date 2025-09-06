import 'dart:math' as math;
import 'dart:typed_data';

/// ======== CONFIG ========

enum PreEmphasisProfile { mattMel, scottMel, generic }

class AudioConfig {
  final int micRate;        // e.g. 44100
  final int sampleRate;     // analysis fps (frames per second), e.g. 60
  final int fftSize;        // e.g. 1024
  final double minVolume;   // silence threshold mapped like LedFx [0..1]
  final int delayMs;        // optional output sync delay like LedFx
  final PreEmphasisProfile preEmphasisProfile;

  // Melbank settings (rough parity with LedFx Melbanks)
  final int melBands;                 // per bank
  final List<int> maxFrequencies;     // like LedFx’s 3 banks (example)
  final double melAlphaDecay;         // attack/decay filters
  final double melAlphaRise;

  // Pitch / onset params
  final double pitchTolerance;        // YIN threshold ~0.8 like python
  final String onsetMethod;           // "hfc" used below

  AudioConfig({
    required this.micRate,
    this.sampleRate = 60,
    this.fftSize = 1024,
    this.minVolume = 0.2,
    this.delayMs = 0,
    this.preEmphasisProfile = PreEmphasisProfile.generic,
    this.melBands = 64,
    this.maxFrequencies = const [400, 4000, 12000],
    this.melAlphaDecay = 0.2,
    this.melAlphaRise = 0.97,
    this.pitchTolerance = 0.8,
    this.onsetMethod = 'hfc',
  }) : assert(fftSize > 0 && (fftSize & (fftSize - 1)) == 0,
         'fftSize must be power of 2');
}

/// ======== PUBLIC API ========

enum PcmFormat { int16LE, float32LE }

class AudioAnalysis {
  final AudioConfig config;

  // Hop size mirrors Python: MIC_RATE // sample_rate
  late final int hopSize = (config.micRate / config.sampleRate).round();

  // Pre-emphasis biquad (matches the three profiles used in Python) :contentReference[oaicite:1]{index=1}
  late final _Biquad _pre = _Biquad.fromProfile(config.preEmphasisProfile);

  // STFT
  late final _Stft _stft = _Stft(
    fftSize: config.fftSize,
    hopSize: hopSize,
    sampleRate: config.micRate,
  );

  // Melbanks (provide 3 banks with ascending max frequency like LedFx)
  late final _MelFilterBanks _mel = _MelFilterBanks(
    sampleRate: config.micRate,
    fftSize: config.fftSize,
    bands: config.melBands,
    maxFrequencies: config.maxFrequencies,
    alphaDecay: config.melAlphaDecay,
    alphaRise: config.melAlphaRise,
  );

  // Pitch (YIN)
  late final _YinPitch _yin = _YinPitch(
    sampleRate: config.micRate,
    tolerance: config.pitchTolerance,
    returnMidi: true,
  );

  // Onset (HFC)
  late final _OnsetDetector _onset = _OnsetDetector.hfc();

  // Tempo & bar oscillator (simple tempo tracker)
  late final _TempoTracker _tempo = _TempoTracker();

  // Volume smoothing
  final _ExpFilter _volumeFilter = _ExpFilter(value: 0.0, alphaDecay: 0.99, alphaRise: 0.99);

  // Beat via volume in low band (LedFx logic) :contentReference[oaicite:2]{index=2}
  late final _BeatDetector _beat = _BeatDetector(
    historySeconds: 0.2,
    minPercentDiff: 0.5,
    minTimeSince: 0.1,
    minAmplitude: 0.5,
    sampleRate: config.sampleRate, // history measured in analysis frames
  );

  // State exposed like properties
  double _volume = 0.0;
  double get volume => _volumeFilter.value;

  // pitch / onset / bpm beat flags are computed per process call
  double _pitchMidi = 0.0;
  double get pitch => _pitchMidi;

  bool _onsetNow = false;
  bool get onset => _onsetNow;

  bool _bpmBeatNow = false;
  bool get bpmBeatNow => _bpmBeatNow;

  bool _volumeBeatNow = false;
  bool get volumeBeatNow => _volumeBeatNow;

  // Bar oscillator state
  double _barPos = 0.0; // 0..4
  double get barOscillator => _barPos;
  double get beatOscillator => _barPos % 1.0;

  // For “power” groups computed from bank #2 (like Python) :contentReference[oaicite:3]{index=3}
  final List<double> _freqPowerRaw = List.filled(4, 0.0);
  late final _ExpFilter _freqPowerFilter =
      _ExpFilterVec(values: List.filled(4, 0.0), alphaDecay: 0.2, alphaRise: 0.97) as _ExpFilter;

  AudioAnalysis({required this.config});

  /// Feed one analysis frame (hop) of PCM **bytes** from `record`.
  /// Choose the correct [format]. For int16, samples are normalized to [-1, 1].
  void processPcmFrame(Uint8List bytes, {required PcmFormat format}) {
    final frame = _decode(bytes, format);
    if (frame.length != hopSize) {
      // simple resample to hopSize (linear)
      final resampled = _resampleLinear(frame, hopSize);
      _process(resampled);
    } else {
      _process(frame);
    }
  }

  /// Return the selected melbank (bank index auto-chosen by max frequency needed by effects).
  /// For parity with LedFx’s AudioReactiveEffect.melbank selection logic, you’ll typically
  /// call this and then split/resize in your effect.
  Float64List melbank({bool filtered = false, int bankIndex = 2}) {
    return filtered ? _mel.filtered(bankIndex) : _mel.raw(bankIndex);
  }

  // “Power” helpers like LedFx
  double beatPower({bool filtered = true}) => _getFreqPower(0, filtered);
  double bassPower({bool filtered = true}) => _getFreqPower(1, filtered);
  double lowsPower({bool filtered = true}) => (beatPower(filtered: filtered) + bassPower(filtered: filtered)) * 0.5;
  double midsPower({bool filtered = true}) => _getFreqPower(2, filtered);
  double highPower({bool filtered = true}) => _getFreqPower(3, filtered);

  /// ======== INTERNAL PIPELINE ========

  void _process(Float64List frame) {
    // clean NaNs
    for (var i = 0; i < frame.length; i++) {
      final v = frame[i];
      if (v.isNaN) frame[i] = 0.0;
    }

    // Volume (approx SPL -> 0..1), then smooth
    _volume = _linearVolume(frame);
    _volumeFilter.update(_volume);

    // Pre-emphasis biquad (to lift highs, like Python profiles)
    final emphasized = _pre.process(frame);

    // STFT frame -> magnitude spectrum
    final mag = _stft.forward(emphasized); // magnitude spectrum length = fftSize/2+1

    // Melbanks (3 banks)
    _mel.update(mag);

    // Pitch (YIN) — uses **raw** samples per python (audio_sample(raw=True)) :contentReference[oaicite:4]{index=4}
    _pitchMidi = _yin.detect(frame);

    // Onset (HFC)
    _onsetNow = _onset.process(mag);

    // Tempo / BPM beat (returns true when beat expected “now” like python)
    _bpmBeatNow = _tempo.update(onset: _onsetNow);

    // Bar oscillator (0..4), quantized to beats like python
    _barPos = _tempo.barPosition();

    // Volume-based beat in low melband (LedFx logic)
    final lowMel = _mel.raw(0); // bank 0 (lowest max freq), like Python’s beat region
    _volumeBeatNow = _beat.update(lowMel);

    // 4-way freq power split from bank #2 (highest max freq in default config)
    _computeFreqPower();
  }

  void _computeFreqPower() {
    final bank = _mel.raw(2);
    if (bank.isEmpty) return;

    // Edges roughly inspired by python’s freq_max_mels = [100, 250, 3000, 10000] but we map by index
    final idx0 = (bank.length * 0.10).floor().clamp(1, bank.length - 1); // beat
    final idx1 = (bank.length * 0.20).floor().clamp(idx0 + 1, bank.length - 1); // bass
    final idx2 = (bank.length * 0.70).floor().clamp(idx1 + 1, bank.length - 1); // mids

    _freqPowerRaw[0] = _avg(bank, 0, idx0);
    _freqPowerRaw[1] = _avg(bank, idx0, idx1);
    _freqPowerRaw[2] = _avg(bank, idx1, idx2);
    _freqPowerRaw[3] = _avg(bank, idx2, bank.length);

    for (var i = 0; i < 4; i++) {
      if (_freqPowerRaw[i].isNaN) _freqPowerRaw[i] = 0.0;
      _freqPowerRaw[i] = _freqPowerRaw[i].clamp(0.0, 1.0);
    }
    (_freqPowerFilter as _ExpFilterVec).updateVec(_freqPowerRaw);
  }

  double _getFreqPower(int i, bool filtered) {
    if (filtered) return (_freqPowerFilter as _ExpFilterVec).values[i];
    return _freqPowerRaw[i];
  }

  /// ======== UTILITIES ========

static Float64List _decode(Uint8List bytes, PcmFormat fmt) {
  if (fmt == PcmFormat.float32LE) {
    final floatView = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    final out = Float64List(floatView.length);
    for (var i = 0; i < floatView.length; i++) {
      out[i] = floatView[i].toDouble();
    }
    return out;
  } else {
    // --- FIX: make sure buffer length is even (multiple of 2) ---
    final aligned = Uint8List(bytes.lengthInBytes - (bytes.lengthInBytes % 2));
    aligned.setRange(0, aligned.length, bytes);

    // Now it’s safe to view as Int16
    final intView = aligned.buffer.asInt16List();
    final out = Float64List(intView.length);
    for (var i = 0; i < intView.length; i++) {
      out[i] = intView[i] / 32768.0; // normalize to [-1,1]
    }
    return out;
  }
}


  static Float64List _resampleLinear(Float64List input, int outLen) {
    if (input.isEmpty) return Float64List(outLen);
    final out = Float64List(outLen);
    final scale = (input.length - 1) / math.max(1, outLen - 1);
    for (var i = 0; i < outLen; i++) {
      final x = i * scale;
      final i0 = x.floor();
      final frac = x - i0;
      final i1 = math.min(i0 + 1, input.length - 1);
      out[i] = input[i0] * (1.0 - frac) + input[i1] * frac;
    }
    return out;
  }

  static double _avg(Float64List v, int a, int b) {
    if (b <= a) return 0.0;
    var s = 0.0;
    for (var i = a; i < b; i++) {
      s += v[i];
    }
    return s / (b - a);
  }

  static double _linearVolume(Float64List frame) {
    // Approx SPL-ish in 0..1: map RMS -> dB -> 0..1 (like python clamps)
    var sum = 0.0;
    for (final x in frame) {
      sum += x * x;
    }
    final rms = math.sqrt(sum / math.max(1, frame.length));
    // Map RMS to [0,1] by a soft knee curve (avoid log(0))
    final db = 20 * math.log(rms + 1e-6) / math.ln10;
    var vol = 1 + db / 100.0;       // mirror python scaling (1 + dB/100) clamped
    if (!vol.isFinite) vol = 0.0;
    return vol.clamp(0.0, 1.0);
  }
}

/// ======== EXP FILTERS ========

class _ExpFilter {
  double value;
  final double alphaDecay;
  final double alphaRise;

  _ExpFilter({required this.value, required this.alphaDecay, required this.alphaRise});

  void update(double x) {
    final alpha = x > value ? alphaRise : alphaDecay;
    value = alpha * x + (1.0 - alpha) * value;
  }
}

class _ExpFilterVec extends _ExpFilter {
  List<double> values;

  _ExpFilterVec({required this.values, required super.alphaDecay, required super.alphaRise})
      : super(value: 0.0);

  void updateVec(List<double> x) {
    for (var i = 0; i < x.length; i++) {
      final a = x[i] > values[i] ? alphaRise : alphaDecay;
      values[i] = a * x[i] + (1.0 - a) * values[i];
    }
  }
}

/// ======== BIQUAD PRE-EMPHASIS (matches LedFx profiles) ========
/// Coefficients are taken from the Python file’s set_biquad calls. :contentReference[oaicite:5]{index=5}
class _Biquad {
  // Direct Form I
  final double b0, b1, b2, a1, a2;
  double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;

  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _Biquad.fromProfile(PreEmphasisProfile p) {
    switch (p) {
      case PreEmphasisProfile.mattMel:
        return _Biquad(0.8268, -1.6536, 0.8268, -1.6536, 0.6536);
      case PreEmphasisProfile.scottMel:
        return _Biquad(1.3662, -1.9256, 0.5621, -1.9256, 0.9283);
      case PreEmphasisProfile.generic:
      return _Biquad(0.85870, -1.71740, 0.85870, -1.71605, 0.71874);
    }
  }

  Float64List process(Float64List x) {
    final y = Float64List(x.length);
    for (var n = 0; n < x.length; n++) {
      final xn = x[n];
      final yn = b0 * xn + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      y[n] = yn;
      x2 = x1; x1 = xn;
      y2 = y1; y1 = yn;
    }
    return y;
  }
}

/// ======== STFT / FFT ========
/// Simple Hann-windowed FFT using radix-2 Cooley–Tukey.
class _Stft {
  final int fftSize;
  final int hopSize;
  final int sampleRate;
  late final Float64List _window;
  late final _Fft _fft;

  _Stft({required this.fftSize, required this.hopSize, required this.sampleRate}) {
    _window = Float64List(fftSize);
    for (var i = 0; i < fftSize; i++) {
      _window[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (fftSize - 1)));
    }
    _fft = _Fft(fftSize);
  }

  Float64List forward(Float64List frame) {
    // zero-pad or slice to fftSize with hop-size hop; here we assume frame length == hop
    // We’ll just use the frame as is (no internal overlap), mirroring pvoc hop size.
    final buf = Float64List(fftSize);
    final copy = math.min(frame.length, fftSize);
    for (var i = 0; i < copy; i++) {
      buf[i] = frame[i] * _window[i];
    }
    for (var i = copy; i < fftSize; i++) {
      buf[i] = 0.0;
    }

    final spec = _fft.fftReal(buf); // interleaved re,im for N/2+1 bins
    final bins = fftSize ~/ 2 + 1;
    final mag = Float64List(bins);
    for (var k = 0; k < bins; k++) {
      final re = spec[2 * k];
      final im = spec[2 * k + 1];
      mag[k] = math.sqrt(re * re + im * im);
    }
    // Normalize a bit to roughly 0..1
    final maxv = mag.fold<double>(1e-9, (a, b) => math.max(a, b));
    final scale = 1.0 / maxv;
    for (var i = 0; i < mag.length; i++) {
      mag[i] *= scale;
    }
    return mag;
  }
}

/// Minimal in-place FFT for real signals → returns interleaved complex bins (N/2+1)
class _Fft {
  final int n;
  _Fft(this.n);

  List<double> fftReal(Float64List x) {
    // Convert to complex, run FFT, then discard symmetric half.
    final re = Float64List(n)..setAll(0, x);
    final im = Float64List(n);
    _fft(re, im);
    final bins = n ~/ 2 + 1;
    final out = List<double>.filled(bins * 2, 0.0);
    for (var k = 0; k < bins; k++) {
      out[2 * k] = re[k];
      out[2 * k + 1] = im[k];
    }
    return out;
  }

  void _fft(Float64List re, Float64List im) {
    final n = re.length;
    // bit-reverse
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j &= ~bit;
      }
      j |= bit;
      if (i < j) {
        final tr = re[i]; re[i] = re[j]; re[j] = tr;
        final ti = im[i]; im[i] = im[j]; im[j] = ti;
      }
    }

    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wlenCos = math.cos(ang);
      final wlenSin = math.sin(ang);
      for (var i = 0; i < n; i += len) {
        var wCos = 1.0, wSin = 0.0;
        for (var j = 0; j < len ~/ 2; j++) {
          final uRe = re[i + j];
          final uIm = im[i + j];
          final vRe = re[i + j + len ~/ 2] * wCos - im[i + j + len ~/ 2] * wSin;
          final vIm = re[i + j + len ~/ 2] * wSin + im[i + j + len ~/ 2] * wCos;

          re[i + j] = uRe + vRe;
          im[i + j] = uIm + vIm;
          re[i + j + len ~/ 2] = uRe - vRe;
          im[i + j + len ~/ 2] = uIm - vIm;

          final nextCos = wCos * wlenCos - wSin * wlenSin;
          final nextSin = wCos * wlenSin + wSin * wlenCos;
          wCos = nextCos;
          wSin = nextSin;
        }
      }
    }
  }
}

/// ======== MEL FILTER BANKS (3 banks like LedFx) ========

class _MelFilterBanks {
  final int sampleRate;
  final int fftSize;
  final int bands;
  final List<int> maxFrequencies;

  // smoothing
  final double alphaDecay, alphaRise;

  late final int _bins = fftSize ~/ 2 + 1;
  late final List<Float64List> _filters; // one matrix per bank
  late final List<Float64List> _melRaw;       // last raw melbank per bank
  late final List<Float64List> _melFiltered;  // filtered

  _MelFilterBanks({
    required this.sampleRate,
    required this.fftSize,
    required this.bands,
    required this.maxFrequencies,
    required this.alphaDecay,
    required this.alphaRise,
  }) {
    _filters = List.generate(maxFrequencies.length, (i) {
      final maxF = math.min(maxFrequencies[i], sampleRate ~/ 2);
      return _buildMelFilters(bands: bands, fMin: 20.0, fMax: maxF.toDouble());
    });
    _melRaw = List.generate(maxFrequencies.length, (_) => Float64List(bands));
    _melFiltered = List.generate(maxFrequencies.length, (_) => Float64List(bands));
  }

  void update(Float64List magnitudeSpectrum) {
    for (var b = 0; b < _filters.length; b++) {
      final filt = _filters[b];
      final out = _melRaw[b];
      // multiply filters by spectrum
      for (var m = 0; m < bands; m++) {
        var s = 0.0;
        final rowOff = m * _bins;
        for (var k = 0; k < _bins; k++) {
          s += filt[rowOff + k] * magnitudeSpectrum[k];
        }
        out[m] = s;
      }
      // normalize 0..1
      final maxv = out.fold<double>(1e-9, (a, v) => math.max(a, v));
      for (var i = 0; i < bands; i++) {
        out[i] = (out[i] / maxv).clamp(0.0, 1.0);
      }
      _smoothInto(_melFiltered[b], out);
    }
  }

  Float64List raw(int bankIndex) => _melRaw[bankIndex];
  Float64List filtered(int bankIndex) => _melFiltered[bankIndex];

  void _smoothInto(Float64List dst, Float64List src) {
    for (var i = 0; i < dst.length; i++) {
      final a = src[i] > dst[i] ? alphaRise : alphaDecay;
      dst[i] = a * src[i] + (1.0 - a) * dst[i];
    }
  }

  // Build triangular mel filters as a dense (bands x bins) matrix
Float64List _buildMelFilters({
  required int bands,
  required double fMin,
  required double fMax,
}) {
  final bins = _bins;
  final out = Float64List(bands * bins);

  double hzToMel(double f) => 2595.0 * math.log(1 + f / 700.0) / math.ln10;
  double melToHz(double m) => 700.0 * (math.pow(10, m / 2595.0) - 1);

  final mMin = hzToMel(fMin);
  final mMax = hzToMel(fMax);

  // We need bands + 2 points (edges), so we can build bands filters
  final mPoints = List<double>.generate(
    bands + 2,
    (i) => mMin + (mMax - mMin) * i / (bands + 1),
  );
  final fPoints = mPoints.map(melToHz).toList();

  int bin(double f) => ((fftSize + 1) * f / sampleRate).floor();

  // Loop over mel filters 0..bands-1
  for (var m = 0; m < bands; m++) {
    final f0 = fPoints[m];
    final f1 = fPoints[m + 1];
    final f2 = fPoints[m + 2];

    final b0 = bin(f0);
    final b1 = bin(f1);
    final b2 = bin(f2);

    // Rising slope
    for (var k = b0; k < b1; k++) {
      if (k >= 0 && k < bins) {
        out[m * bins + k] = (k - b0) / math.max(1, (b1 - b0));
      }
    }
    // Falling slope
    for (var k = b1; k < b2; k++) {
      if (k >= 0 && k < bins) {
        out[m * bins + k] = (b2 - k) / math.max(1, (b2 - b1));
      }
    }
  }

  return out;
}

}

/// ======== YIN PITCH (returns MIDI if requested) ========
/// Lightweight implementation adequate for real-time frames.
class _YinPitch {
  final int sampleRate;
  final double tolerance;
  final bool returnMidi;

  _YinPitch({required this.sampleRate, required this.tolerance, this.returnMidi = true});

  double detect(Float64List x) {
    if (x.length < 32) return returnMidi ? 0.0 : 0.0;
    final n = x.length;
    final maxTau = (sampleRate / 50).floor();  // ~50 Hz lower bound
    final minTau = (sampleRate / 2000).floor(); // ~2 kHz upper bound

    final d = Float64List(maxTau + 1);
    for (var tau = 1; tau <= maxTau; tau++) {
      var sum = 0.0;
      for (var i = 0; i < n - tau; i++) {
        final diff = x[i] - x[i + tau];
        sum += diff * diff;
      }
      d[tau] = sum;
    }

    final cmnd = Float64List(maxTau + 1);
    cmnd[0] = 1.0;
    var running = 0.0;
    for (var tau = 1; tau <= maxTau; tau++) {
      running += d[tau];
      cmnd[tau] = d[tau] * tau / math.max(1e-12, running);
    }

    var bestTau = -1;
    for (var tau = minTau; tau <= maxTau; tau++) {
      if (cmnd[tau] < tolerance) {
        bestTau = tau;
        while (tau + 1 <= maxTau && cmnd[tau + 1] < cmnd[bestTau]) {
          bestTau = ++tau;
        }
        break;
      }
    }

    if (bestTau == -1) return returnMidi ? 0.0 : 0.0;

    final f0 = sampleRate / bestTau;
    if (!returnMidi) return f0;
    return _hzToMidi(f0);
  }

  static double _hzToMidi(double f) {
    if (f <= 0) return 0.0;
    return 69.0 + 12.0 * (math.log(f / 440.0) / math.ln2);
  }
}

/// ======== ONSET DETECTOR (HFC) ========
class _OnsetDetector {
  double _prevHfc = 0.0;
  double _threshold = 0.2; // simple adaptive level

  _OnsetDetector._();

  factory _OnsetDetector.hfc() => _OnsetDetector._();

  bool process(Float64List mag) {
    // High-Frequency Content = sum_k (k * |X[k]|^2)
    var hfc = 0.0;
    for (var k = 0; k < mag.length; k++) {
      final v = mag[k];
      hfc += k * v * v;
    }
    // detection: positive difference over threshold
    final diff = math.max(0.0, hfc - _prevHfc);
    _prevHfc = hfc;

    final onset = diff > _threshold;
    // slowly adapt threshold
    _threshold = 0.99 * _threshold + 0.01 * diff;
    return onset;
  }
}

/// ======== TEMPO TRACKER + BAR OSCILLATOR ========
class _TempoTracker {
  // crude inter-onset interval tracker -> beat period (seconds)
  final List<double> _onsetTimes = [];
  double _lastOnsetTs = -1;
  double _beatPeriod = 0.5; // default 120 bpm
  double _lastBeatTs = -1;
  int _beatCounter = 0;

  // call this each frame with onset flag; returns true when a beat is expected "now"
  bool update({required bool onset}) {
    final t = _now();
    var beatNow = false;

    if (onset) {
      if (_lastOnsetTs > 0) {
        final ioi = t - _lastOnsetTs;
        _onsetTimes.add(ioi);
        if (_onsetTimes.length > 16) _onsetTimes.removeAt(0);
        _beatPeriod = _median(_onsetTimes).clamp(0.25, 1.5); // 40–240 bpm
      }
      _lastOnsetTs = t;

      // quantize beat to detected period
      if (_lastBeatTs < 0 || (t - _lastBeatTs) >= 0.5 * _beatPeriod) {
        _lastBeatTs = t;
        _beatCounter = (_beatCounter + 1) % 4;
        beatNow = true;
      }
    }
    return beatNow;
  }

  double barPosition() {
    final t = _now();
    if (_lastBeatTs < 0) return _beatCounter.toDouble();
    final since = t - _lastBeatTs;
    final phase = (since / _beatPeriod).clamp(0.0, 1.0);
    return (_beatCounter.toDouble() + phase) % 4.0;
  }

  static double _now() => DateTime.now().millisecondsSinceEpoch / 1000.0;

  static double _median(List<double> v) {
    if (v.isEmpty) return 0.5;
    final s = List<double>.from(v)..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : 0.5 * (s[m - 1] + s[m]);
    }
}

/// ======== VOLUME-BASED BEAT DETECTOR (LedFx logic) ========
/// Mirrors the Python algorithm using a short history of low-band energy. :contentReference[oaicite:6]{index=6}
class _BeatDetector {
  final int historyLen;
  final double minPercentDiff;
  final double minTimeSince;
  final double minAmplitude;
  double _prevBeatTs = -1;
  final List<double> _hist = [];

  _BeatDetector({
    required double historySeconds,
    required this.minPercentDiff,
    required this.minTimeSince,
    required this.minAmplitude,
    required int sampleRate, // analysis frames per second
  }) : historyLen = math.max(1, (historySeconds * sampleRate).round());

  bool update(Float64List lowBandMel) {
    // compute power = sum of low mel bins (like Python)
    var sum = 0.0, maxv = 0.0;
    for (final v in lowBandMel) { sum += v; if (v > maxv) maxv = v; }
    final beatPower = sum;
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // % difference vs average
    final histSum = _hist.fold<double>(0.0, (a, b) => a + b);
    final diff = histSum > 0 ? (beatPower * historyLen / histSum - 1.0) : 0.0;

    // circular buffer push front (match deque behavior)
    if (_hist.length < historyLen) {
      _hist.insert(0, beatPower);
    } else {
      _hist.removeLast();
      _hist.insert(0, beatPower);
    }

    final enoughTime = _prevBeatTs < 0 || (now - _prevBeatTs) > minTimeSince;
    if (diff >= minPercentDiff && maxv >= minAmplitude && enoughTime) {
      _prevBeatTs = now;
      return true;
    }
    return false;
  }
}
