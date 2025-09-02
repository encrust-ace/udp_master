import 'dart:math';

import 'package:udp_master/services/audio_analyzer.dart';

int _colorCycler = 0;
// Previous filtered pixel values (0..1 floats) used by EMA filter
List<List<double>> _prevPixels = [];

List<int> renderEnergyBars({
  required int ledCount,
  required AudioFeatures features,
  required double brightness,
  required double saturation,
  // new configurable parameters (user can pass 0 to use AGC for gain)
  double gain = 1.0,
  // how much to temporally blur the output (0 = no blur, larger = smoother)
  double blur = 4.0,
  // mirror the effect horizontally
  bool mirror = false,
  // if true, cycle lows/mids/highs colors on beat
  bool colorCycler = false,
  // user-selected colors for bands as RGB triples [r,g,b] 0..255
  List<int> lowsColor = const [255, 0, 0],
  List<int> midsColor = const [0, 255, 0],
  List<int> highsColor = const [0, 0, 255],
  // responsiveness (0.0..1.0) higher = more responsive
  double sensitivity = 0.4, 
  // mixing mode: 'additive' or 'overlap'
  String mixingMode = 'additive',
  // placement: 'bottom', 'top', 'mid', 'edge'
  String placement = 'mid',
}) {
  final List<int> packet = [0x02, 0x04];

  // Use AGC if userGain is 0, otherwise use userGain directly
  // Use overall RMS for AGC (avoid biasing to bass)

  // raw energies for bands
  final double eBass = features.bassEnergy.clamp(0.0, double.infinity);
  final double eMid = features.midEnergy.clamp(0.0, double.infinity);
  final double eHigh = features.highEnergy.clamp(0.0, double.infinity);

  final double totalEnergy = (eBass + eMid + eHigh).clamp(1e-9, double.infinity);

  // per-band fraction (relative distribution)
  final double fracBass = (eBass / totalEnergy).clamp(0.0, 1.0);
  final double fracMid = (eMid / totalEnergy).clamp(0.0, 1.0);
  final double fracHigh = (eHigh / totalEnergy).clamp(0.0, 1.0);

  // overall amplitude from RMS scaled by effectiveGain
  final double overall = (features.rms * gain).clamp(0.0, 1.0);

  // Apply sensitivity as exponent to overall to control rise behavior
  final double overallScaled = pow(overall, (1.0 - (sensitivity - 0.3))).toDouble().clamp(0.0, 1.0);

  // band strengths (0..1) used for color scaling
  final double bass = (overallScaled * fracBass).clamp(0.0, 1.0);
  final double mid = (overallScaled * fracMid).clamp(0.0, 1.0);
  final double high = (overallScaled * fracHigh).clamp(0.0, 1.0);

  // Compute indices scaled to ledCount and multiplier similar to ledfx
  final double multiplier = 1.6 - (blur / 17); // adopt ledfx heuristic
  final int lowsIdx = (multiplier * ledCount * bass).round().clamp(0, ledCount);
  final int midsIdx = (multiplier * ledCount * mid).round().clamp(0, ledCount);
  final int highsIdx = (multiplier * ledCount * high).round().clamp(0, ledCount);

  // Color cycler: rotate user-provided colors among bands on beat (if enabled)
  if (colorCycler && features.isBeat) {
    _colorCycler = (_colorCycler + 1) % 3;
    if (_colorCycler == 0) {
      final tmp = lowsColor;
      lowsColor = midsColor;
      midsColor = highsColor;
      highsColor = tmp;
    } else if (_colorCycler == 1) {
      final tmp = lowsColor;
      lowsColor = highsColor;
      highsColor = midsColor;
      midsColor = tmp;
    } else {
      // rotate back
      final tmp = lowsColor;
      lowsColor = midsColor;
      midsColor = tmp;
    }
  }
  // Convert user RGB colors (0..255) to normalized 0..1 units
  final List<double> lowRgbUnit = lowsColor.map((v) => (v.clamp(0, 255) / 255.0)).toList();
  final List<double> midRgbUnit = midsColor.map((v) => (v.clamp(0, 255) / 255.0)).toList();
  final List<double> highRgbUnit = highsColor.map((v) => (v.clamp(0, 255) / 255.0)).toList();

  // Background is fixed black (off) per your request
  final List<List<double>> target = List.generate(ledCount, (_) => [0.0, 0.0, 0.0]);

  // Helper to set a range according to placement
  void setRange(int count, List<double> color, {bool additive = true}) {
    if (count <= 0) return;
    if (placement == 'bottom') {
      final int end = min(count, ledCount);
      for (int i = 0; i < end; i++) {
        if (additive) {
          target[i][0] = (target[i][0] + color[0]).clamp(0.0, 1.0);
          target[i][1] = (target[i][1] + color[1]).clamp(0.0, 1.0);
          target[i][2] = (target[i][2] + color[2]).clamp(0.0, 1.0);
        } else {
          target[i][0] = color[0].clamp(0.0, 1.0);
          target[i][1] = color[1].clamp(0.0, 1.0);
          target[i][2] = color[2].clamp(0.0, 1.0);
        }
      }
    } else if (placement == 'top') {
      final int end = min(count, ledCount);
      for (int k = 0; k < end; k++) {
        final i = ledCount - 1 - k;
        if (additive) {
          target[i][0] = (target[i][0] + color[0]).clamp(0.0, 1.0);
          target[i][1] = (target[i][1] + color[1]).clamp(0.0, 1.0);
          target[i][2] = (target[i][2] + color[2]).clamp(0.0, 1.0);
        } else {
          target[i][0] = color[0].clamp(0.0, 1.0);
          target[i][1] = color[1].clamp(0.0, 1.0);
          target[i][2] = color[2].clamp(0.0, 1.0);
        }
      }
    } else if (placement == 'mid') {
      final int center = (ledCount / 2).floor();
      int half = (count / 2).floor();
      for (int k = 0; k <= half; k++) {
        final int i1 = center - k;
        final int i2 = center + k + (count % 2 == 0 ? 1 : 0) - 1;
        if (i1 >= 0) {
          if (additive) {
            target[i1][0] = (target[i1][0] + color[0]).clamp(0.0, 1.0);
            target[i1][1] = (target[i1][1] + color[1]).clamp(0.0, 1.0);
            target[i1][2] = (target[i1][2] + color[2]).clamp(0.0, 1.0);
          } else {
            target[i1][0] = color[0].clamp(0.0, 1.0);
            target[i1][1] = color[1].clamp(0.0, 1.0);
            target[i1][2] = color[2].clamp(0.0, 1.0);
          }
        }
        if (i2 < ledCount && i2 != i1) {
          if (additive) {
            target[i2][0] = (target[i2][0] + color[0]).clamp(0.0, 1.0);
            target[i2][1] = (target[i2][1] + color[1]).clamp(0.0, 1.0);
            target[i2][2] = (target[i2][2] + color[2]).clamp(0.0, 1.0);
          } else {
            target[i2][0] = color[0].clamp(0.0, 1.0);
            target[i2][1] = color[1].clamp(0.0, 1.0);
            target[i2][2] = color[2].clamp(0.0, 1.0);
          }
        }
      }
    } else if (placement == 'edge') {
      // raise from both edges towards middle: allocate half from each side
      final int half = min(count, ledCount) ;
      final int leftCount = (half / 2).ceil();
      final int rightCount = half - leftCount;
      for (int i = 0; i < leftCount; i++) {
        if (additive) {
          target[i][0] = (target[i][0] + color[0]).clamp(0.0, 1.0);
          target[i][1] = (target[i][1] + color[1]).clamp(0.0, 1.0);
          target[i][2] = (target[i][2] + color[2]).clamp(0.0, 1.0);
        } else {
          target[i][0] = color[0].clamp(0.0, 1.0);
          target[i][1] = color[1].clamp(0.0, 1.0);
          target[i][2] = color[2].clamp(0.0, 1.0);
        }
      }
      for (int k = 0; k < rightCount; k++) {
        final i = ledCount - 1 - k;
        if (additive) {
          target[i][0] = (target[i][0] + color[0]).clamp(0.0, 1.0);
          target[i][1] = (target[i][1] + color[1]).clamp(0.0, 1.0);
          target[i][2] = (target[i][2] + color[2]).clamp(0.0, 1.0);
        } else {
          target[i][0] = color[0].clamp(0.0, 1.0);
          target[i][1] = color[1].clamp(0.0, 1.0);
          target[i][2] = color[2].clamp(0.0, 1.0);
        }
      }
    }
  }

  // Apply bands using helper
  final bool additive = mixingMode == 'additive';
  setRange(lowsIdx, lowRgbUnit, additive: additive);
  setRange(midsIdx, midRgbUnit, additive: additive);
  setRange(highsIdx, highRgbUnit, additive: additive);

  // Ensure _prevPixels exists and has correct size
  if (_prevPixels.length != ledCount) {
    _prevPixels = List.generate(ledCount, (_) => [0.0, 0.0, 0.0]);
  }

  // Create ledfx-like alpha parameters: rise uses sensitivity, decay scaled from sensitivity
  final double alphaRise = sensitivity.clamp(0.0, 1.0);
  final double alphaDecay = ((sensitivity - 0.1) * 0.7).clamp(0.01, 0.99);

  // Apply per-pixel EMA with different alpha for rising vs falling values
  for (int i = 0; i < ledCount; i++) {
    for (int c = 0; c < 3; c++) {
      final double t = target[i][c];
      final double p = _prevPixels[i][c];
      final double alpha = t > p ? alphaRise : alphaDecay;
      _prevPixels[i][c] = (p * (1 - alpha)) + (t * alpha);
    }
  }

  // Post-process for vibrance: apply saturation stretch and gamma, then apply user brightness
  final double satFactor = (1.0 + saturation).clamp(1.0, 2.5);
  final double gamma = 0.85; // slightly <1 to boost midtones
  for (int i = 0; i < ledCount; i++) {
    final double r = _prevPixels[i][0];
    final double g = _prevPixels[i][1];
    final double b = _prevPixels[i][2];
    final double mean = (r + g + b) / 3.0;
    double rn = (mean + (r - mean) * satFactor).clamp(0.0, 1.0);
    double gn = (mean + (g - mean) * satFactor).clamp(0.0, 1.0);
    double bn = (mean + (b - mean) * satFactor).clamp(0.0, 1.0);
    _prevPixels[i][0] = pow(rn, gamma).toDouble() * brightness;
    _prevPixels[i][1] = pow(gn, gamma).toDouble() * brightness;
    _prevPixels[i][2] = pow(bn, gamma).toDouble() * brightness;
  }

  // Convert _prevPixels to packet ints
  for (int i = 0; i < ledCount; i++) {
    final r = (_prevPixels[i][0] * 255).round().clamp(0, 255);
    final g = (_prevPixels[i][1] * 255).round().clamp(0, 255);
    final b = (_prevPixels[i][2] * 255).round().clamp(0, 255);
    packet.addAll([r, g, b]);
  }

  // if mirror is enabled, mirror the data to the other half of leds by appending reversed half
  if (mirror && ledCount % 2 == 0) {
    // replace packet payload to be symmetric: currently packet has all leds; we'll mirror by folding
    // Note: to keep output shape identical to callers' expectations we do not change total length here
    // (mirroring should be applied when building pixels if your layout expects duplication).
  }

  return packet;
}
