import 'dart:math' as math;

/// Dart version of LedFx "EnergyAudioEffect" closer to Python logic
class EnergyAudioEffect {
  final int ledCount;
  final double blur; // 0..10
  final bool mirror;
  final bool colorCyclerEnabled;
  final String mixingMode; // "additive" or "overlap"
  final List<List<double>> colorPalette; // optional palette for cycling

  final double sensitivity;
  final double _decaySensitivity;

  // Color state as RGB floats [0..255]
  List<double> lowsColor;
  List<double> midsColor;
  List<double> highsColor;

  // Pixel buffers as List<List<double>> (ledCount x 3)
  late List<List<double>> pixels;
  late List<List<double>> _prevPixels;

  int colorCycler = 0;
  final math.Random _rng = math.Random();

  EnergyAudioEffect({
    required this.ledCount,
    this.blur = 4.0,
    this.mirror = true,
    this.colorCyclerEnabled = false,
    this.mixingMode = "additive",
    List<int>? colorLows,
    List<int>? colorMids,
    List<int>? colorHigh,
    this.sensitivity = 0.6,
    this.colorPalette = const [
      [255, 0, 0],
      [0, 255, 0],
      [0, 0, 255],
      [255, 255, 0],
      [0, 255, 255],
      [255, 0, 255],
    ],
  }) : lowsColor = colorLows?.map((c) => c.toDouble()).toList() ?? [255, 0, 0],
       midsColor = colorMids?.map((c) => c.toDouble()).toList() ?? [0, 255, 0],
       highsColor = colorHigh?.map((c) => c.toDouble()).toList() ?? [0, 0, 255],
       _decaySensitivity = (sensitivity - 0.1) * 0.7 {
    pixels = List.generate(ledCount, (_) => [0.0, 0.0, 0.0]);
    _prevPixels = List.generate(ledCount, (_) => [0.0, 0.0, 0.0]);
  }

  /// Call this on each beat to cycle colors if enabled
  void updateColorsOnBeat() {
    if (!colorCyclerEnabled) return;

    colorCycler = (colorCycler + 1) % 3;

    // Pick random color from palette
    final color = colorPalette[_rng.nextInt(colorPalette.length)];

    if (colorCycler == 0) {
      lowsColor = color;
    } else if (colorCycler == 1) {
      midsColor = color;
    } else {
      highsColor = color;
    }
  }

  /// Render frame given beat flag and melbank thirds (lows, mids, highs in [0..1])
  /// Returns flattened RGB int list (0..255) for all LEDs (mirrored if enabled)
  List<int> frame({
    required bool beatNow,
    required double lows, // fraction of energy in lows (0..1)
    required double mids,
    required double highs,
  }) {
    if (beatNow) updateColorsOnBeat();

    final multiplier = 1.6 - blur / 17.0;

    // Calculate LED indexes for each band based on energy and multiplier
    final lowsIdx = (multiplier * ledCount * lows).round().clamp(0, ledCount);
    final midsIdx = (multiplier * ledCount * mids).round().clamp(0, ledCount);
    final highsIdx = (multiplier * ledCount * highs).round().clamp(0, ledCount);

    // Reset pixels to zero if overlap mode (like Python)
    if (mixingMode == "overlap") {
      for (var i = 0; i < ledCount; i++) {
        pixels[i][0] = 0.0;
        pixels[i][1] = 0.0;
        pixels[i][2] = 0.0;
      }
    }

    // Apply colors per band with additive or overlap blending
    for (var i = 0; i < lowsIdx; i++) {
      _blendColor(i, lowsColor);
    }
    for (var i = 0; i < midsIdx; i++) {
      _blendColor(i, midsColor);
    }
    for (var i = 0; i < highsIdx; i++) {
      _blendColor(i, highsColor);
    }

    // Apply blur (simple box blur) if blur > 1
    if (blur > 1) {
      final tmp = List.generate(ledCount, (_) => [0.0, 0.0, 0.0]);
      final k = blur.round();
      for (var i = 0; i < ledCount; i++) {
        final start = math.max(0, i - k);
        final end = math.min(ledCount - 1, i + k);
        final count = end - start + 1;
        for (var j = start; j <= end; j++) {
          tmp[i][0] += pixels[j][0];
          tmp[i][1] += pixels[j][1];
          tmp[i][2] += pixels[j][2];
        }
        tmp[i][0] /= count;
        tmp[i][1] /= count;
        tmp[i][2] /= count;
      }
      pixels = tmp;
    }

    // Apply smoothing filter per pixel channel (like ExpFilter in Python)
    for (var i = 0; i < ledCount; i++) {
      for (var c = 0; c < 3; c++) {
        final alpha = pixels[i][c] > _prevPixels[i][c]
            ? sensitivity
            : _decaySensitivity;
        pixels[i][c] = alpha * pixels[i][c] + (1 - alpha) * _prevPixels[i][c];
        _prevPixels[i][c] = pixels[i][c];
      }
    }

    // Mirror pixels if enabled
    final renderPixels = mirror ? [...pixels, ...pixels.reversed] : pixels;

    // Flatten to int list clamped to 0..255
    final packet = <int>[];
    for (var px in renderPixels) {
      for (var c = 0; c < 3; c++) {
        packet.add(px[c].clamp(0.0, 255.0).round());
      }
    }

    return packet;
  }

  void _blendColor(int idx, List<double> color) {
    if (mixingMode == "additive") {
      for (var c = 0; c < 3; c++) {
        pixels[idx][c] += color[c];
      }
    } else {
      for (var c = 0; c < 3; c++) {
        pixels[idx][c] = color[c];
      }
    }
  }
}
