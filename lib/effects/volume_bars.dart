import 'dart:typed_data';

import 'package:udp_master/models.dart';
import 'package:udp_master/services/audio_analyzer.dart';

List<int> renderVerticalBars({
  required LedDevice device,
  required Float32List fft,
  required double gain,
  required double brightness,
  required double saturation,
  required AudioAnalyzer analyzer,
}) {
  final int count = device.ledCount;
  if (count == 0 || fft.isEmpty) return [0x02, 0x04];

  final List<int> packet = [0x02, 0x04];
  
  // Analyze audio with enhanced features
  final features = analyzer.analyzeAudio(fft, 44100.0);
  
  // Use multiple frequency bands for better visualization
  final double bassResponse = features.bass * gain;
  final double midResponse = features.mid * gain * 0.7;
  final double trebleResponse = features.treble * gain * 0.5;
  
  // Beat enhancement
  final double beatMultiplier = 1.0 + (features.beatStrength * 0.5);
  
  for (int i = 0; i < count; i++) {
    final double pos = i / (count - 1);
    double strength = 0.0;
    
    // Different frequency responses for different LED positions
    if (pos < 0.3) {
      // Bottom LEDs respond to bass
      strength = bassResponse * beatMultiplier;
    } else if (pos < 0.7) {
      // Middle LEDs respond to mids
      strength = midResponse;
    } else {
      // Top LEDs respond to treble
      strength = trebleResponse;
    }
    
    // Apply onset enhancement for sharp attacks
    strength += features.onsetStrength * 0.3;
    
    strength = (strength * brightness).clamp(0.0, 1.0);
    
    if (strength > 0.05) { // Threshold to avoid noise
      // Dynamic hue based on spectral centroid
      final double baseHue = (1.0 - pos) * 0.7;
      final double centroidInfluence = (features.spectralCentroid / 8000.0).clamp(0.0, 1.0);
      final double hue = (baseHue + centroidInfluence * 0.3) % 1.0;
      
      final fadedColor = _hsvToRgb(hue, saturation, strength);
      packet.addAll(fadedColor);
    } else {
      packet.addAll([0, 0, 0]);
    }
  }

  return packet;
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
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    case 5: r = v; g = p; b = q; break;
    default: r = g = b = 0;
  }
  return [(r * 255).round(), (g * 255).round(), (b * 255).round()];
}