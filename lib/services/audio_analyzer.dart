import 'dart:typed_data';
import 'dart:math' as math;
import 'package:udp_master/models.dart';

class AudioAnalyzer {
  // Previous values for smoothing
  double _prevBass = 0.0;
  double _prevMid = 0.0;
  double _prevTreble = 0.0;
  double _prevVolume = 0.0;

  // Beat detection state
  final List<double> _beatHistory = [];
  final List<double> _beatIntervals = [];
  double _lastBeatTime = 0.0;
  int _frameCount = 0;

  // Onset detection
  List<double> _prevSpectrum = [];
  final List<double> _spectralFluxBuffer = [];
  double _onsetThreshold = 0.15;

  // Automatic gain control
  final List<double> _recentPeaks = [];
  double _adaptiveGain = 1.0;

  // Tempo detection
  final List<double> _tempoHistory = [];
  double _currentTempo = 120.0;

  // Windowing function coefficients (Hanning window)
  List<double>? _hanningWindow;

  // Energy normalization
  double _energyBaseline = 0.0;
  final List<double> _energyHistory = [];

  // Advanced beat tracking
  final List<double> _beatStrengthHistory = [];

  static const int beatHistorySize = 43; // ~1 second at 43fps
  static const int fluxHistorySize = 20;
  static const int enerygyHistorySize = 200; // ~5 seconds
  static const int peakHistorySize = 100;
  static const int tempoHistorySize = 50;
  static const double frameRate = 43.0; // Assuming 43fps

  AudioFeatures analyzeAudio(Float32List fft, double sampleRate) {
    if (fft.isEmpty) return AudioFeatures.empty();

    _frameCount++;

    // 1. Apply windowing function
    final windowedFFT = _applyWindowing(fft);

    // 2. Calculate frequency bands with improved resolution
    final bands = _calculateFrequencyBands(windowedFFT, sampleRate);

    // 3. Advanced beat detection with confidence
    final beatInfo = _detectBeatAdvanced(bands.bass);

    // 4. Multi-method onset detection
    final onsetStrength = _detectOnsetAdvanced(windowedFFT);

    // 5. Spectral features
    final spectralFeatures = _calculateSpectralFeatures(
      windowedFFT,
      sampleRate,
    );

    // 6. Apply temporal smoothing with adaptive response
    final smoothedBands = _applyAdaptiveSmoothing(bands);

    // 7. Volume analysis with multiple methods
    final volumeInfo = _calculateVolumeAdvanced(windowedFFT);

    // 8. Automatic gain control
    _updateAutomaticGain(volumeInfo.peak);

    // 9. Tempo estimation with autocorrelation
    final tempo = _estimateTempoAdvanced(beatInfo.strength);

    // 10. Energy normalization
    final normalizedEnergy = _normalizeEnergy(volumeInfo.rms);

    return AudioFeatures(
      bass: smoothedBands.bass,
      mid: smoothedBands.mid,
      treble: smoothedBands.treble,
      subBass: bands.subBass,
      highMid: bands.highMid,
      presence: bands.presence,
      brilliance: bands.brilliance,
      volume: volumeInfo.rms,
      volumePeak: volumeInfo.peak,
      volumeNormalized: normalizedEnergy,
      beatStrength: beatInfo.strength,
      beatConfidence: beatInfo.confidence,
      onsetStrength: onsetStrength,
      spectralCentroid: spectralFeatures.centroid,
      spectralRolloff: spectralFeatures.rolloff,
      spectralBandwidth: spectralFeatures.bandwidth,
      zeroCrossingRate: spectralFeatures.zcr,
      tempo: tempo,
      adaptiveGain: _adaptiveGain,
      energyVariance: _calculateEnergyVariance(),
      harmonicity: spectralFeatures.harmonicity,
      attack: _calculateAttackTime(volumeInfo.rms),
      decay: _calculateDecayTime(volumeInfo.rms),
      lowMid: bands.lowMid,
    );
  }

  Float32List _applyWindowing(Float32List fft) {
    if (_hanningWindow == null || _hanningWindow!.length != fft.length) {
      _hanningWindow = _generateHanningWindow(fft.length);
    }

    final windowed = Float32List(fft.length);
    for (int i = 0; i < fft.length; i++) {
      windowed[i] = fft[i] * _hanningWindow![i];
    }
    return windowed;
  }

  List<double> _generateHanningWindow(int size) {
    final window = List<double>.filled(size, 0.0);
    for (int i = 0; i < size; i++) {
      window[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (size - 1)));
    }
    return window;
  }

  ExtendedFrequencyBands _calculateFrequencyBands(
    Float32List fft,
    double sampleRate,
  ) {
    final double binWidth = sampleRate / (2 * fft.length);

    // Extended frequency ranges for better analysis
    const frequencyRanges = {
      'subBass': [20.0, 60.0], // Sub-bass
      'bass': [60.0, 250.0], // Bass
      'lowMid': [250.0, 500.0], // Low midrange
      'mid': [500.0, 2000.0], // Midrange
      'highMid': [2000.0, 4000.0], // High midrange
      'presence': [4000.0, 6000.0], // Presence
      'brilliance': [6000.0, 20000.0], // Brilliance
    };

    final Map<String, double> bandEnergies = {};

    for (final entry in frequencyRanges.entries) {
      final String bandName = entry.key;
      final List<double> range = entry.value;

      int startBin = (range[0] / binWidth).floor().clamp(1, fft.length - 1);
      int endBin = (range[1] / binWidth).floor().clamp(
        startBin + 1,
        fft.length,
      );

      double energy = 0.0;
      for (int i = startBin; i < endBin; i++) {
        double magnitude = fft[i].abs();
        energy += magnitude * magnitude; // Power spectrum
      }

      // Apply psychoacoustic weighting
      double weight = _getPsychoacousticWeight(range[0], range[1]);
      energy = math.sqrt(energy / (endBin - startBin)) * weight;

      bandEnergies[bandName] = energy;
    }

    return ExtendedFrequencyBands(
      subBass: bandEnergies['subBass'] ?? 0.0,
      bass: bandEnergies['bass'] ?? 0.0,
      lowMid: bandEnergies['lowMid'] ?? 0.0,
      mid: bandEnergies['mid'] ?? 0.0,
      highMid: bandEnergies['highMid'] ?? 0.0,
      presence: bandEnergies['presence'] ?? 0.0,
      brilliance: bandEnergies['brilliance'] ?? 0.0,
      treble: bandEnergies['treble'] ?? 0.0,
    );
  }

  double _getPsychoacousticWeight(double lowFreq, double highFreq) {
    // A-weighting approximation for psychoacoustic perception
    double centerFreq = math.sqrt(lowFreq * highFreq);
    double weight = 1.0;

    if (centerFreq < 1000) {
      weight = math.pow(centerFreq / 1000, 0.6).toDouble();
    } else if (centerFreq > 3000) {
      weight = math.pow(3000 / centerFreq, 0.3).toDouble();
    }

    return weight.clamp(0.1, 2.0);
  }

  BeatInfo _detectBeatAdvanced(double currentBass) {
    _beatHistory.add(currentBass);
    if (_beatHistory.length > beatHistorySize) {
      _beatHistory.removeAt(0);
    }

    if (_beatHistory.length < 10) {
      return BeatInfo(strength: 0.0, confidence: 0.0);
    }

    // Multiple beat detection methods

    // 1. Energy-based detection
    double localAvg =
        _beatHistory.reduce((a, b) => a + b) / _beatHistory.length;
    double variance = 0.0;
    for (double value in _beatHistory) {
      variance += math.pow(value - localAvg, 2);
    }
    variance /= _beatHistory.length;
    double threshold = localAvg + math.sqrt(variance) * 1.5;

    double energyBeat = 0.0;
    if (currentBass > threshold) {
      energyBeat = ((currentBass - threshold) / threshold).clamp(0.0, 1.0);
    }

    // 2. Derivative-based detection (rate of change)
    double derivative = 0.0;
    if (_beatHistory.length >= 2) {
      derivative = _beatHistory.last - _beatHistory[_beatHistory.length - 2];
      derivative = (derivative / localAvg).clamp(-1.0, 1.0);
      if (derivative < 0) derivative = 0.0; // Only positive changes
    }

    // 3. Complex domain analysis
    double complexBeat = _detectBeatComplex();

    // Combine methods
    double combinedStrength =
        (energyBeat * 0.5 + derivative * 0.3 + complexBeat * 0.2);

    // Update beat strength history for confidence calculation
    _beatStrengthHistory.add(combinedStrength);
    if (_beatStrengthHistory.length > 20) {
      _beatStrengthHistory.removeAt(0);
    }

    // Calculate confidence based on consistency
    double confidence = _calculateBeatConfidence();

    // Beat interval tracking for tempo
    if (combinedStrength > 0.3 && confidence > 0.5) {
      double currentTime = _frameCount / frameRate;
      if (_lastBeatTime > 0) {
        double interval = currentTime - _lastBeatTime;
        if (interval > 0.3 && interval < 2.0) {
          // Reasonable beat intervals
          _beatIntervals.add(interval);
          if (_beatIntervals.length > 10) {
            _beatIntervals.removeAt(0);
          }
        }
      }
      _lastBeatTime = currentTime;
    }

    return BeatInfo(strength: combinedStrength, confidence: confidence);
  }

  double _detectBeatComplex() {
    if (_beatHistory.length < 8) return 0.0;

    // Simple autocorrelation for periodicity detection
    double maxCorr = 0.0;
    for (int lag = 2; lag < math.min(20, _beatHistory.length ~/ 2); lag++) {
      double correlation = 0.0;
      for (int i = lag; i < _beatHistory.length; i++) {
        correlation += _beatHistory[i] * _beatHistory[i - lag];
      }
      correlation /= (_beatHistory.length - lag);
      maxCorr = math.max(maxCorr, correlation);
    }

    return (maxCorr /
            (_beatHistory.reduce(math.max) * _beatHistory.reduce(math.max)))
        .clamp(0.0, 1.0);
  }

  double _calculateBeatConfidence() {
    if (_beatStrengthHistory.length < 5) return 0.0;

    // Calculate variance in beat strengths
    double avg =
        _beatStrengthHistory.reduce((a, b) => a + b) /
        _beatStrengthHistory.length;
    double variance = 0.0;
    for (double strength in _beatStrengthHistory) {
      variance += math.pow(strength - avg, 2);
    }
    variance /= _beatStrengthHistory.length;

    // Lower variance = higher confidence
    return (1.0 - math.sqrt(variance)).clamp(0.0, 1.0);
  }

  double _detectOnsetAdvanced(Float32List fft) {
    // 1. Spectral flux (rate of change)
    double flux = 0.0;
    if (_prevSpectrum.isNotEmpty && _prevSpectrum.length == fft.length) {
      for (int i = 0; i < fft.length; i++) {
        double diff = fft[i].abs() - _prevSpectrum[i];
        if (diff > 0) flux += diff; // Only positive changes (spectral flux)
      }
    }

    // Store current spectrum
    _prevSpectrum = fft.map((f) => f.abs()).toList();

    // 2. High-frequency content
    double hfc = 0.0;
    for (int i = 1; i < fft.length; i++) {
      hfc += i * fft[i].abs() * fft[i].abs();
    }
    hfc = math.sqrt(hfc / fft.length);

    // 3. Phase deviation (simplified)
    double phaseDeviation = _calculatePhaseDeviation(fft);

    // Combine onset detection methods
    flux = flux / fft.length;
    hfc = hfc / 1000.0; // Normalize

    double combinedOnset = flux * 0.6 + hfc * 0.3 + phaseDeviation * 0.1;

    // Adaptive threshold
    _spectralFluxBuffer.add(combinedOnset);
    if (_spectralFluxBuffer.length > fluxHistorySize) {
      _spectralFluxBuffer.removeAt(0);
    }

    if (_spectralFluxBuffer.length >= 5) {
      double avgFlux =
          _spectralFluxBuffer.reduce((a, b) => a + b) /
          _spectralFluxBuffer.length;
      _onsetThreshold = avgFlux * 2.0 + 0.1;
    }

    return combinedOnset > _onsetThreshold ? combinedOnset : 0.0;
  }

  double _calculatePhaseDeviation(Float32List fft) {
    // Simplified phase deviation calculation
    // In a real implementation, this would require complex FFT
    double deviation = 0.0;
    for (int i = 1; i < fft.length - 1; i++) {
      double current = fft[i].abs();
      double prev = fft[i - 1].abs();
      double next = fft[i + 1].abs();

      if (current > 0) {
        deviation += (next - prev).abs() / current;
      }
    }
    return (deviation / fft.length).clamp(0.0, 1.0);
  }

  SpectralFeatures _calculateSpectralFeatures(
    Float32List fft,
    double sampleRate,
  ) {
    final double binWidth = sampleRate / (2 * fft.length);

    // 1. Spectral Centroid (brightness)
    double weightedSum = 0.0;
    double magnitudeSum = 0.0;

    for (int i = 1; i < fft.length; i++) {
      double magnitude = fft[i].abs();
      double frequency = i * binWidth;

      weightedSum += frequency * magnitude;
      magnitudeSum += magnitude;
    }

    double centroid = magnitudeSum > 0 ? weightedSum / magnitudeSum : 0.0;

    // 2. Spectral Rolloff (frequency below which 85% of energy lies)
    double totalEnergy = 0.0;
    for (int i = 1; i < fft.length; i++) {
      totalEnergy += fft[i].abs() * fft[i].abs();
    }

    double cumulativeEnergy = 0.0;
    double rolloff = 0.0;
    for (int i = 1; i < fft.length; i++) {
      cumulativeEnergy += fft[i].abs() * fft[i].abs();
      if (cumulativeEnergy >= 0.85 * totalEnergy) {
        rolloff = i * binWidth;
        break;
      }
    }

    // 3. Spectral Bandwidth
    double variance = 0.0;
    for (int i = 1; i < fft.length; i++) {
      double magnitude = fft[i].abs();
      double frequency = i * binWidth;
      variance += math.pow(frequency - centroid, 2) * magnitude;
    }
    double bandwidth = magnitudeSum > 0
        ? math.sqrt(variance / magnitudeSum)
        : 0.0;

    // 4. Zero Crossing Rate (approximated from FFT)
    double zcr = _estimateZeroCrossingRate(fft);

    // 5. Harmonicity (measure of harmonic content)
    double harmonicity = _calculateHarmonicity(fft, sampleRate);

    return SpectralFeatures(
      centroid: centroid,
      rolloff: rolloff,
      bandwidth: bandwidth,
      zcr: zcr,
      harmonicity: harmonicity,
    );
  }

  double _estimateZeroCrossingRate(Float32List fft) {
    // Estimate ZCR from high-frequency content
    double highFreqEnergy = 0.0;
    double totalEnergy = 0.0;

    for (int i = 0; i < fft.length; i++) {
      double energy = fft[i].abs();
      totalEnergy += energy;

      if (i > fft.length * 0.5) {
        // High frequencies
        highFreqEnergy += energy;
      }
    }

    return totalEnergy > 0 ? highFreqEnergy / totalEnergy : 0.0;
  }

  double _calculateHarmonicity(Float32List fft, double sampleRate) {
    // Simple harmonicity measure based on peak relationships
    final peaks = _findSpectralPeaks(fft, sampleRate);
    if (peaks.length < 2) return 0.0;

    double harmonicScore = 0.0;
    double fundamentalFreq = peaks.first.frequency;

    for (int i = 1; i < math.min(peaks.length, 6); i++) {
      double expectedHarmonic = fundamentalFreq * (i + 1);
      double actualFreq = peaks[i].frequency;
      double ratio = actualFreq / expectedHarmonic;

      if (ratio > 0.9 && ratio < 1.1) {
        harmonicScore += peaks[i].magnitude / peaks.first.magnitude;
      }
    }

    return harmonicScore.clamp(0.0, 1.0);
  }

  List<SpectralPeak> _findSpectralPeaks(Float32List fft, double sampleRate) {
    final double binWidth = sampleRate / (2 * fft.length);
    final List<SpectralPeak> peaks = [];

    for (int i = 2; i < fft.length - 2; i++) {
      double current = fft[i].abs();
      if (current > fft[i - 1].abs() &&
          current > fft[i + 1].abs() &&
          current > fft[i - 2].abs() &&
          current > fft[i + 2].abs() &&
          current > 0.01) {
        peaks.add(SpectralPeak(frequency: i * binWidth, magnitude: current));
      }
    }

    // Sort by magnitude, keep top peaks
    peaks.sort((a, b) => b.magnitude.compareTo(a.magnitude));
    return peaks.take(10).toList();
  }

  ExtendedFrequencyBands _applyAdaptiveSmoothing(
    ExtendedFrequencyBands current,
  ) {
    // Adaptive smoothing based on rate of change
    double adaptiveFactor = _calculateAdaptiveSmoothingFactor(current);

    _prevBass = _smoothValue(_prevBass, current.bass, adaptiveFactor);
    _prevMid = _smoothValue(_prevMid, current.mid, adaptiveFactor);
    _prevTreble = _smoothValue(_prevTreble, current.brilliance, adaptiveFactor);

    return ExtendedFrequencyBands(
      subBass: _smoothValue(0.0, current.subBass, adaptiveFactor * 0.8),
      bass: _prevBass,
      treble: _prevTreble,
      lowMid: _smoothValue(0.0, current.lowMid, adaptiveFactor),
      mid: _prevMid,
      highMid: _smoothValue(0.0, current.highMid, adaptiveFactor),
      presence: _smoothValue(0.0, current.presence, adaptiveFactor * 1.2),
      brilliance: _prevTreble,
    );
  }

  double _calculateAdaptiveSmoothingFactor(ExtendedFrequencyBands current) {
    // Calculate rate of change to determine smoothing intensity
    double changeRate = 0.0;
    changeRate += (current.bass - _prevBass).abs();
    changeRate += (current.mid - _prevMid).abs();
    changeRate += (current.brilliance - _prevTreble).abs();

    // Higher change rate = less smoothing for responsiveness
    double baseSmoothingFactor = 0.3;
    double adaptiveFactor = baseSmoothingFactor * (1.0 + changeRate * 2.0);

    return adaptiveFactor.clamp(0.1, 0.8);
  }

  double _smoothValue(double previous, double current, double factor) {
    return previous * (1 - factor) + current * factor;
  }

  VolumeInfo _calculateVolumeAdvanced(Float32List fft) {
    // 1. RMS (Root Mean Square)
    double sumSquares = 0.0;
    for (double value in fft) {
      sumSquares += value * value;
    }
    double rms = math.sqrt(sumSquares / fft.length);

    // 2. Peak value
    double peak = 0.0;
    for (double value in fft) {
      peak = math.max(peak, value.abs());
    }

    // 3. Loudness (A-weighted approximation)
    double loudness = _calculateLoudness(fft);

    // Apply smoothing
    const double rmsSmoothing = 0.2;

    _prevVolume = _prevVolume * (1 - rmsSmoothing) + rms * rmsSmoothing;

    return VolumeInfo(rms: _prevVolume, peak: peak, loudness: loudness);
  }

  double _calculateLoudness(Float32List fft) {
    // Simplified A-weighting for perceived loudness
    double weightedSum = 0.0;
    double totalSum = 0.0;

    for (int i = 1; i < fft.length; i++) {
      double magnitude = fft[i].abs();
      double weight = _getAWeight(i, fft.length);

      weightedSum += magnitude * weight;
      totalSum += magnitude;
    }

    return totalSum > 0 ? weightedSum / totalSum : 0.0;
  }

  double _getAWeight(int bin, int fftSize) {
    // Simplified A-weighting curve
    double normalizedBin = bin.toDouble() / fftSize;

    if (normalizedBin < 0.1) return 0.5; // Low frequencies attenuated
    if (normalizedBin < 0.3) return 1.0; // Mid frequencies boosted
    if (normalizedBin < 0.7) return 1.2; // High-mid frequencies boosted
    return 0.8; // High frequencies slightly attenuated
  }

  void _updateAutomaticGain(double currentPeak) {
    _recentPeaks.add(currentPeak);
    if (_recentPeaks.length > peakHistorySize) {
      _recentPeaks.removeAt(0);
    }

    if (_recentPeaks.length >= 20) {
      // Calculate 95th percentile of recent peaks
      List<double> sortedPeaks = List.from(_recentPeaks)..sort();
      double percentile95 = sortedPeaks[(sortedPeaks.length * 0.95).floor()];

      // Target level (avoid clipping, maintain dynamic range)
      double targetLevel = 0.7;

      if (percentile95 > 0.001) {
        double newGain = targetLevel / percentile95;

        // Smooth gain changes to avoid artifacts
        _adaptiveGain = _adaptiveGain * 0.95 + newGain * 0.05;
        _adaptiveGain = _adaptiveGain.clamp(0.1, 10.0);
      }
    }
  }

  double _estimateTempoAdvanced(double beatStrength) {
    if (_beatIntervals.isEmpty) return _currentTempo;

    // Calculate tempo from beat intervals using median
    List<double> tempos = _beatIntervals
        .map((interval) => 60.0 / interval)
        .toList();
    tempos.sort();

    double medianTempo = tempos[tempos.length ~/ 2];

    // Validate tempo range
    if (medianTempo >= 60.0 && medianTempo <= 200.0) {
      _tempoHistory.add(medianTempo);
      if (_tempoHistory.length > tempoHistorySize) {
        _tempoHistory.removeAt(0);
      }

      // Smooth tempo changes
      double avgTempo =
          _tempoHistory.reduce((a, b) => a + b) / _tempoHistory.length;
      _currentTempo = _currentTempo * 0.9 + avgTempo * 0.1;
    }

    return _currentTempo;
  }

  double _normalizeEnergy(double currentEnergy) {
    _energyHistory.add(currentEnergy);
    if (_energyHistory.length > enerygyHistorySize) {
      _energyHistory.removeAt(0);
    }

    if (_energyHistory.length >= 50) {
      double avgEnergy =
          _energyHistory.reduce((a, b) => a + b) / _energyHistory.length;
      _energyBaseline = _energyBaseline * 0.99 + avgEnergy * 0.01;

      if (_energyBaseline > 0) {
        return (currentEnergy / _energyBaseline).clamp(0.0, 3.0);
      }
    }

    return currentEnergy;
  }

  double _calculateEnergyVariance() {
    if (_energyHistory.length < 10) return 0.0;

    double mean =
        _energyHistory.reduce((a, b) => a + b) / _energyHistory.length;
    double variance = 0.0;

    for (double energy in _energyHistory) {
      variance += math.pow(energy - mean, 2);
    }

    return math.sqrt(variance / _energyHistory.length);
  }

  double _calculateAttackTime(double currentVolume) {
    // Simplified attack time calculation
    if (_prevVolume > 0 && currentVolume > _prevVolume * 1.5) {
      return 0.0; // Fast attack detected
    }
    return 1.0; // No attack
  }

  double _calculateDecayTime(double currentVolume) {
    // Simplified decay time calculation
    if (_prevVolume > 0 && currentVolume < _prevVolume * 0.8) {
      return (_prevVolume - currentVolume) / _prevVolume;
    }
    return 0.0;
  }
}

// Enhanced data classes
class AudioFeatures {
  final double bass;
  final double mid;
  final double treble;
  final double subBass;
  final double highMid;
  final double lowMid;
  final double presence;
  final double brilliance;
  final double volume;
  final double volumePeak;
  final double volumeNormalized;
  final double beatStrength;
  final double beatConfidence;
  final double onsetStrength;
  final double spectralCentroid;
  final double spectralRolloff;
  final double spectralBandwidth;
  final double zeroCrossingRate;
  final double tempo;
  final double adaptiveGain;
  final double energyVariance;
  final double harmonicity;
  final double attack;
  final double decay;

  const AudioFeatures({
    required this.bass,
    required this.mid,
    required this.treble,
    required this.subBass,
    required this.highMid,
    required this.lowMid,
    required this.presence,
    required this.brilliance,
    required this.volume,
    required this.volumePeak,
    required this.volumeNormalized,
    required this.beatStrength,
    required this.beatConfidence,
    required this.onsetStrength,
    required this.spectralCentroid,
    required this.spectralRolloff,
    required this.spectralBandwidth,
    required this.zeroCrossingRate,
    required this.tempo,
    required this.adaptiveGain,
    required this.energyVariance,
    required this.harmonicity,
    required this.attack,
    required this.decay,
  });

  factory AudioFeatures.empty() {
    return const AudioFeatures(
      bass: 0.0,
      mid: 0.0,
      treble: 0.0,
      subBass: 0.0,
      highMid: 0.0,
      lowMid: 0.0,
      presence: 0.0,
      brilliance: 0.0,
      volume: 0.0,
      volumePeak: 0.0,
      volumeNormalized: 0.0,
      beatStrength: 0.0,
      beatConfidence: 0.0,
      onsetStrength: 0.0,
      spectralCentroid: 0.0,
      spectralRolloff: 0.0,
      spectralBandwidth: 0.0,
      zeroCrossingRate: 0.0,
      tempo: 120.0,
      adaptiveGain: 1.0,
      energyVariance: 0.0,
      harmonicity: 0.0,
      attack: 0.0,
      decay: 0.0,
    );
  }
}

class ExtendedFrequencyBands {
  final double subBass;
  final double bass;
  final double lowMid;
  final double mid;
  final double highMid;
  final double treble;
  final double presence;
  final double brilliance;

  const ExtendedFrequencyBands({
    required this.subBass,
    required this.bass,
    required this.lowMid,
    required this.mid,
    required this.treble,
    required this.highMid,
    required this.presence,
    required this.brilliance,
  });
}

class BeatInfo {
  final double strength;
  final double confidence;

  const BeatInfo({required this.strength, required this.confidence});
}

class SpectralFeatures {
  final double centroid;
  final double rolloff;
  final double bandwidth;
  final double zcr;
  final double harmonicity;

  const SpectralFeatures({
    required this.centroid,
    required this.rolloff,
    required this.bandwidth,
    required this.zcr,
    required this.harmonicity,
  });
}

class SpectralPeak {
  final double frequency;
  final double magnitude;

  const SpectralPeak({required this.frequency, required this.magnitude});
}

class VolumeInfo {
  final double rms;
  final double peak;
  final double loudness;

  const VolumeInfo({
    required this.rms,
    required this.peak,
    required this.loudness,
  });
}

// Advanced Effect Implementations

List<int> renderEnergyEffect({
  required LedDevice device,
  required AudioFeatures features,
  required double gain,
  required double brightness,
  required double saturation,
}) {
  final int count = device.ledCount;
  if (count == 0) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];

  // Energy-based visualization inspired by LedFx
  double energy =
      (features.bass * 0.4 + features.mid * 0.4 + features.treble * 0.2) * gain;
  energy *= features.adaptiveGain;

  // Beat enhancement with confidence
  double beatMultiplier =
      1.0 + (features.beatStrength * features.beatConfidence * 0.8);
  energy *= beatMultiplier;

  // Onset enhancement for sharp attacks
  energy += features.onsetStrength * 0.3;

  energy = energy.clamp(0.0, 1.0);

  for (int i = 0; i < count; i++) {
    final double pos = i / (count - 1);

    // Dynamic hue based on spectral characteristics
    double baseHue = (features.spectralCentroid / 8000.0).clamp(0.0, 1.0);
    double hue = (baseHue + pos * 0.3) % 1.0;

    // Position-based energy distribution
    double positionEnergy = energy * math.exp(-math.pow(pos - 0.5, 2) * 4);
    positionEnergy = (positionEnergy * brightness).clamp(0.0, 1.0);

    if (positionEnergy > 0.05) {
      final color = _hsvToRgb(hue, saturation, positionEnergy);
      packet.addAll(color);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
}

List<int> renderScrollEffect({
  required LedDevice device,
  required AudioFeatures features,
  required double gain,
  required double brightness,
  required double saturation,
  required double speed,
}) {
  final int count = device.ledCount;
  if (count == 0) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];

  // Scrolling effect with tempo sync
  double scrollPos =
      (DateTime.now().millisecondsSinceEpoch / 1000.0 * speed) % 1.0;

  // Tempo synchronization
  if (features.tempo > 0) {
    double tempoSync = (features.tempo / 120.0) * speed;
    scrollPos =
        (DateTime.now().millisecondsSinceEpoch / 1000.0 * tempoSync) % 1.0;
  }

  double energy = (features.volumeNormalized * gain).clamp(0.0, 1.0);

  for (int i = 0; i < count; i++) {
    final double pos = i / (count - 1);
    final double distance = ((pos - scrollPos).abs() * 2) % 2;

    double intensity = 0.0;
    if (distance < 0.2) {
      intensity = (1.0 - distance / 0.2) * energy;
    }

    // Color based on frequency content
    double hue =
        0.7 -
        (features.bass * 0.3 + features.mid * 0.4 + features.treble * 0.3);
    intensity = (intensity * brightness).clamp(0.0, 1.0);

    if (intensity > 0.05) {
      final color = _hsvToRgb(hue, saturation, intensity);
      packet.addAll(color);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
}

List<int> renderWavelengthEffect({
  required LedDevice device,
  required AudioFeatures features,
  required double gain,
  required double brightness,
  required double saturation,
}) {
  final int count = device.ledCount;
  if (count == 0) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];

  // Wavelength effect based on spectral centroid
  double wavelength = (features.spectralCentroid / 4000.0).clamp(0.2, 1.0);
  double phase =
      (DateTime.now().millisecondsSinceEpoch / 1000.0 * 2 * math.pi) %
      (2 * math.pi);

  double amplitude = (features.volumeNormalized * gain).clamp(0.0, 1.0);
  amplitude *= (1.0 + features.beatStrength * 0.5);

  for (int i = 0; i < count; i++) {
    final double pos = i / (count - 1);

    // Sine wave with variable wavelength
    double waveValue = math.sin(pos * 2 * math.pi / wavelength + phase);
    double intensity = ((waveValue + 1) / 2) * amplitude;

    // Hue based on harmonicity and position
    double hue = (features.harmonicity * 0.7 + pos * 0.3) % 1.0;
    intensity = (intensity * brightness).clamp(0.0, 1.0);

    if (intensity > 0.05) {
      final color = _hsvToRgb(hue, saturation, intensity);
      packet.addAll(color);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
}

List<int> renderSpectrumEffect({
  required LedDevice device,
  required AudioFeatures features,
  required double gain,
  required double brightness,
  required double saturation,
}) {
  final int count = device.ledCount;
  if (count == 0) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];

  // Map different frequency bands to different sections of LED strip
  final bands = [
    features.subBass,
    features.bass,
    features.lowMid,
    features.mid,
    features.highMid,
    features.presence,
    features.brilliance,
  ];

  final bandColors = [
    0.0, // Red for sub-bass
    0.08, // Orange for bass
    0.17, // Yellow for low-mid
    0.33, // Green for mid
    0.5, // Cyan for high-mid
    0.67, // Blue for presence
    0.83, // Purple for brilliance
  ];

  for (int i = 0; i < count; i++) {
    final double pos = i / (count - 1);
    final int bandIndex = (pos * bands.length).floor().clamp(
      0,
      bands.length - 1,
    );

    double intensity = bands[bandIndex] * gain * features.adaptiveGain;
    intensity = (intensity * brightness).clamp(0.0, 1.0);

    // Beat enhancement for all bands
    intensity *= (1.0 + features.beatStrength * 0.3);

    if (intensity > 0.05) {
      final color = _hsvToRgb(bandColors[bandIndex], saturation, intensity);
      packet.addAll(color);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
}

List<int> renderBeatPulseEffect({
  required LedDevice device,
  required AudioFeatures features,
  required double gain,
  required double brightness,
  required double saturation,
}) {
  final int count = device.ledCount;
  if (count == 0) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];

  // Pulse effect triggered by confident beats
  double pulseIntensity = features.beatStrength * features.beatConfidence;

  // Decay the pulse over time
  double timeSinceLastBeat = DateTime.now().millisecondsSinceEpoch / 1000.0;
  double decayFactor = math.exp(-timeSinceLastBeat * 5); // 5 second decay

  pulseIntensity *= decayFactor * gain;

  for (int i = 0; i < count; i++) {
    final double pos = i / (count - 1);

    // Radial pulse from center
    double distance = (pos - 0.5).abs() * 2;
    double intensity = pulseIntensity * (1.0 - distance);

    // Add base level from volume
    intensity += features.volumeNormalized * 0.3;
    intensity = (intensity * brightness).clamp(0.0, 1.0);

    // Dynamic hue based on tempo
    double hue = (features.tempo / 200.0) % 1.0;

    if (intensity > 0.05) {
      final color = _hsvToRgb(hue, saturation, intensity);
      packet.addAll(color);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
}

List<int> renderAdvancedMusicRhythm({
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

  // Enhanced rhythm effect with multiple frequency responses
  final frequencyResponses = [
    features.bass * 1.2, // Strong bass response
    features.mid * 1.0, // Mid response
    features.treble * 0.8, // Softer treble response
    features.presence * 0.6, // Presence response
  ];

  for (int i = 0; i < count; i++) {
    final double pos = i / (count - 1);

    // Map position to frequency response
    int responseIndex = (pos * frequencyResponses.length).floor().clamp(
      0,
      frequencyResponses.length - 1,
    );

    double baseIntensity = frequencyResponses[responseIndex] * gain;

    // Apply beat enhancement with confidence weighting
    double beatEnhancement = features.beatStrength * features.beatConfidence;
    baseIntensity *= (1.0 + beatEnhancement);

    // Onset enhancement for sharp attacks
    baseIntensity += features.onsetStrength * 0.4;

    // Apply attack/decay envelope
    double envelopeMultiplier = 1.0;
    if (features.attack > 0.5) {
      envelopeMultiplier *= (1.0 + raiseSpeed / 10.0);
    }
    if (features.decay > 0.5) {
      envelopeMultiplier *= (1.0 - decaySpeed);
    }

    baseIntensity *= envelopeMultiplier;
    baseIntensity = (baseIntensity * brightness).clamp(0.0, 1.0);

    // Dynamic color based on spectral characteristics
    double hue = 0.7;
    if (features.spectralCentroid > 0) {
      hue = (features.spectralCentroid / 6000.0).clamp(0.0, 1.0);
      hue = 0.7 - hue * 0.4; // Map to red-blue range
    }

    // Add harmonicity influence to color
    hue += features.harmonicity * 0.2;
    hue = hue % 1.0;

    if (baseIntensity > 0.05) {
      final color = _hsvToRgb(hue, saturation, baseIntensity);
      packet.addAll(color);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
}

// Enhanced main rendering function
List<int> renderEnhancedEffect({
  required LedDevice device,
  required AudioFeatures features,
  required String effectId,
  required Map<String, dynamic> parameters,
}) {
  final double gain = parameters['gain']?['value'] ?? 2.0;
  final double brightness = parameters['brightness']?['value'] ?? 1.0;
  final double saturation = parameters['saturation']?['value'] ?? 1.0;

  switch (effectId) {
    case 'energy':
      return renderEnergyEffect(
        device: device,
        features: features,
        gain: gain,
        brightness: brightness,
        saturation: saturation,
      );

    case 'scroll':
      final double speed = parameters['speed']?['value'] ?? 1.0;
      return renderScrollEffect(
        device: device,
        features: features,
        gain: gain,
        brightness: brightness,
        saturation: saturation,
        speed: speed,
      );

    case 'wavelength':
      return renderWavelengthEffect(
        device: device,
        features: features,
        gain: gain,
        brightness: brightness,
        saturation: saturation,
      );

    case 'spectrum':
      return renderSpectrumEffect(
        device: device,
        features: features,
        gain: gain,
        brightness: brightness,
        saturation: saturation,
      );

    case 'beat-pulse':
      return renderBeatPulseEffect(
        device: device,
        features: features,
        gain: gain,
        brightness: brightness,
        saturation: saturation,
      );

    case 'advanced-rhythm':
      final double raiseSpeed = parameters['raiseSpeed']?['value'] ?? 12.5;
      final double decaySpeed = parameters['decaySpeed']?['value'] ?? 0.5;
      final double dropSpeed = parameters['dropSpeed']?['value'] ?? 0.5;
      return renderAdvancedMusicRhythm(
        device: device,
        features: features,
        gain: gain,
        brightness: brightness,
        saturation: saturation,
        raiseSpeed: raiseSpeed,
        decaySpeed: decaySpeed,
        dropSpeed: dropSpeed,
      );

    default:
      return [0x02, 0x04]; // Empty packet
  }
}

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
