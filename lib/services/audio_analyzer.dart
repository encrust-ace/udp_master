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
  List<double> _beatHistory = [];
  double _avgBeat = 0.0;
  double _lastBeatTime = 0.0;
  
  // Onset detection
  List<double> _spectralFlux = [];
  double _onsetThreshold = 0.1;
  
  // Attack/Decay envelopes
  double _attackTime = 0.05; // 50ms
  double _decayTime = 0.3;   // 300ms
  
  static const int BEAT_HISTORY_SIZE = 43; // ~1 second at 43fps
  static const int FLUX_HISTORY_SIZE = 10;

  AudioFeatures analyzeAudio(Float32List fft, double sampleRate) {
    if (fft.isEmpty) return AudioFeatures.empty();
    
    final int fftSize = fft.length;
    final double binWidth = sampleRate / (2 * fftSize);
    
    // 1. Calculate frequency bands
    final bands = _calculateFrequencyBands(fft, binWidth);
    
    // 2. Beat detection
    final beatStrength = _detectBeat(bands.bass);
    
    // 3. Onset detection using spectral flux
    final onsetStrength = _detectOnset(fft);
    
    // 4. Spectral features
    final spectralCentroid = _calculateSpectralCentroid(fft, binWidth);
    
    // 5. Apply temporal smoothing
    final smoothedBands = _applySmoothing(bands);
    
    // 6. Volume analysis with RMS
    final volume = _calculateRMS(fft);
    
    return AudioFeatures(
      bass: smoothedBands.bass,
      mid: smoothedBands.mid,
      treble: smoothedBands.treble,
      volume: volume,
      beatStrength: beatStrength,
      onsetStrength: onsetStrength,
      spectralCentroid: spectralCentroid,
      tempo: _estimateTempo(),
    );
  }
  
  FrequencyBands _calculateFrequencyBands(Float32List fft, double binWidth) {
    // Define frequency ranges (Hz)
    const double bassMax = 250.0;
    const double midMax = 4000.0;
    // treble is everything above midMax
    
    int bassEnd = (bassMax / binWidth).floor().clamp(1, fft.length);
    int midEnd = (midMax / binWidth).floor().clamp(bassEnd, fft.length);
    
    // Calculate band energies with proper weighting
    double bassEnergy = 0.0;
    double midEnergy = 0.0;
    double trebleEnergy = 0.0;
    
    // Bass: 0 Hz to 250 Hz
    for (int i = 1; i < bassEnd; i++) {
      double magnitude = fft[i].abs();
      bassEnergy += magnitude * magnitude; // Power spectrum
    }
    bassEnergy = math.sqrt(bassEnergy / bassEnd);
    
    // Mid: 250 Hz to 4000 Hz
    for (int i = bassEnd; i < midEnd; i++) {
      double magnitude = fft[i].abs();
      midEnergy += magnitude * magnitude;
    }
    midEnergy = math.sqrt(midEnergy / (midEnd - bassEnd));
    
    // Treble: 4000 Hz and above
    for (int i = midEnd; i < fft.length; i++) {
      double magnitude = fft[i].abs();
      trebleEnergy += magnitude * magnitude;
    }
    trebleEnergy = math.sqrt(trebleEnergy / (fft.length - midEnd));
    
    return FrequencyBands(
      bass: bassEnergy,
      mid: midEnergy,
      treble: trebleEnergy,
    );
  }
  
  double _detectBeat(double currentBass) {
    _beatHistory.add(currentBass);
    if (_beatHistory.length > BEAT_HISTORY_SIZE) {
      _beatHistory.removeAt(0);
    }
    
    if (_beatHistory.length < 10) return 0.0;
    
    // Calculate local average
    double localAvg = _beatHistory.reduce((a, b) => a + b) / _beatHistory.length;
    
    // Beat detection: current energy significantly above local average
    double threshold = localAvg * 1.5; // 50% above average
    double beatStrength = 0.0;
    
    if (currentBass > threshold) {
      beatStrength = ((currentBass - threshold) / threshold).clamp(0.0, 1.0);
    }
    
    return beatStrength;
  }
  
  double _detectOnset(Float32List fft) {
    // Calculate spectral flux (rate of change in spectrum)
    double flux = 0.0;
    
    if (_spectralFlux.isNotEmpty && _spectralFlux.length == fft.length) {
      for (int i = 0; i < fft.length; i++) {
        double diff = fft[i].abs() - _spectralFlux[i];
        if (diff > 0) flux += diff; // Only positive changes
      }
    }
    
    // Store current spectrum for next comparison
    _spectralFlux = fft.map((f) => f.abs()).toList();
    
    // Normalize flux
    flux = flux / fft.length;
    
    return flux > _onsetThreshold ? flux : 0.0;
  }
  
  double _calculateSpectralCentroid(Float32List fft, double binWidth) {
    double weightedSum = 0.0;
    double magnitudeSum = 0.0;
    
    for (int i = 1; i < fft.length; i++) {
      double magnitude = fft[i].abs();
      double frequency = i * binWidth;
      
      weightedSum += frequency * magnitude;
      magnitudeSum += magnitude;
    }
    
    return magnitudeSum > 0 ? weightedSum / magnitudeSum : 0.0;
  }
  
  FrequencyBands _applySmoothing(FrequencyBands current) {
    // Exponential moving average for smoothing
    const double smoothingFactor = 0.3;
    
    _prevBass = _prevBass * (1 - smoothingFactor) + current.bass * smoothingFactor;
    _prevMid = _prevMid * (1 - smoothingFactor) + current.mid * smoothingFactor;
    _prevTreble = _prevTreble * (1 - smoothingFactor) + current.treble * smoothingFactor;
    
    return FrequencyBands(
      bass: _prevBass,
      mid: _prevMid,
      treble: _prevTreble,
    );
  }
  
  double _calculateRMS(Float32List fft) {
    double sum = 0.0;
    for (double value in fft) {
      sum += value * value;
    }
    double rms = math.sqrt(sum / fft.length);
    
    // Apply smoothing
    const double smoothing = 0.2;
    _prevVolume = _prevVolume * (1 - smoothing) + rms * smoothing;
    
    return _prevVolume;
  }
  
  double _estimateTempo() {
    // Simple tempo estimation based on beat intervals
    // This is a simplified version - full implementation would be more complex
    return 120.0; // Placeholder
  }
}

class AudioFeatures {
  final double bass;
  final double mid;
  final double treble;
  final double volume;
  final double beatStrength;
  final double onsetStrength;
  final double spectralCentroid;
  final double tempo;
  
  const AudioFeatures({
    required this.bass,
    required this.mid,
    required this.treble,
    required this.volume,
    required this.beatStrength,
    required this.onsetStrength,
    required this.spectralCentroid,
    required this.tempo,
  });
  
  factory AudioFeatures.empty() {
    return const AudioFeatures(
      bass: 0.0,
      mid: 0.0,
      treble: 0.0,
      volume: 0.0,
      beatStrength: 0.0,
      onsetStrength: 0.0,
      spectralCentroid: 0.0,
      tempo: 0.0,
    );
  }
}

class FrequencyBands {
  final double bass;
  final double mid;
  final double treble;
  
  const FrequencyBands({
    required this.bass,
    required this.mid,
    required this.treble,
  });
}