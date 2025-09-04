import 'dart:math' as math;

/// Dart version of LedFx "EnergyAudioEffect"
class EnergyAudioEffect {
  final int ledCount;
  final double blur; // 0..10
  final bool mirror;
  final bool colorCyclerEnabled;
  final String mixingMode; // "additive" or "overlap"

  final List<double> _pFilterAlphaRise;
  final List<double> _pFilterAlphaDecay;
  final math.Random _rng = math.Random();

  // Color state
  List<double> lowsColor;
  List<double> midsColor;
  List<double> highsColor;

  // Pixel buffers
  late List<List<double>> pixels;
  late List<List<double>> _prevPixels;

  int colorCycler = 0;

  EnergyAudioEffect({
    required this.ledCount,
    this.blur = 4.0,
    this.mirror = true,
    this.colorCyclerEnabled = false,
    this.mixingMode = "additive",
    List<int>? colorLows,
    List<int>? colorMids,
    List<int>? colorHigh,
    double sensitivity = 0.6,
  })  : lowsColor = colorLows?.map((c) => c.toDouble()).toList() ?? [255, 0, 0],
        midsColor = colorMids?.map((c) => c.toDouble()).toList() ?? [0, 255, 0],
        highsColor = colorHigh?.map((c) => c.toDouble()).toList() ?? [0, 0, 255],
        _pFilterAlphaRise = List.filled(ledCount, sensitivity),
        _pFilterAlphaDecay = List.filled(ledCount, (sensitivity - 0.1) * 0.7) {
    pixels = List.generate(ledCount, (_) => [0.0, 0.0, 0.0]);
    _prevPixels = List.generate(ledCount, (_) => [0.0, 0.0, 0.0]);
  }

  /// Optional color cycling on beat
  void updateColorsOnBeat() {
    if (!colorCyclerEnabled) return;

    colorCycler = (colorCycler + 1) % 3;
    final randColor = [
      _rng.nextInt(256).toDouble(),
      _rng.nextInt(256).toDouble(),
      _rng.nextInt(256).toDouble(),
    ];

    if (colorCycler == 0) {
      lowsColor = randColor;
    } else if (colorCycler == 1) {
      midsColor = randColor;
    } else {
      highsColor = randColor;
    }
  }

  /// Render frame
  List<int> frame({
    required bool beatNow,
    required double lows, // 0..1
    required double mids,
    required double highs,
  }) {
    if (beatNow) updateColorsOnBeat();

    final multiplier = 1.6 - blur / 17.0;
    final lowsIdx = (multiplier * ledCount * lows).round().clamp(0, ledCount);
    final midsIdx = (multiplier * ledCount * mids).round().clamp(0, ledCount);
    final highsIdx = (multiplier * ledCount * highs).round().clamp(0, ledCount);

    // Reset pixels only if using overlap mode
    if (mixingMode == "overlap") {
      for (var i = 0; i < ledCount; i++) {
        for (var c = 0; c < 3; c++) {
          pixels[i][c] = 0.0;
        }
      }
    }

    // Apply additive or overlap blending
    for (var i = 0; i < lowsIdx; i++) _blendColor(i, lowsColor);
    for (var i = 0; i < midsIdx; i++) _blendColor(i, midsColor);
    for (var i = 0; i < highsIdx; i++) _blendColor(i, highsColor);

    // Apply blur (simple box blur)
    if (blur > 1) {
      final tmp = List.generate(ledCount, (_) => [0.0, 0.0, 0.0]);
      final k = blur.round();
      for (var i = 0; i < ledCount; i++) {
        final start = math.max(0, i - k);
        final end = math.min(ledCount - 1, i + k);
        final count = end - start + 1;
        for (var j = start; j <= end; j++) {
          for (var c = 0; c < 3; c++) {
            tmp[i][c] += pixels[j][c];
          }
        }
        for (var c = 0; c < 3; c++) {
          tmp[i][c] /= count;
        }
      }
      pixels = tmp;
    }

    // Apply smoothing filter per pixel
    for (var i = 0; i < ledCount; i++) {
      for (var c = 0; c < 3; c++) {
        final alpha = pixels[i][c] > _prevPixels[i][c]
            ? _pFilterAlphaRise[i]
            : _pFilterAlphaDecay[i];
        pixels[i][c] = alpha * pixels[i][c] + (1 - alpha) * _prevPixels[i][c];
        _prevPixels[i][c] = pixels[i][c];
      }
    }

    // Mirror if enabled
    final renderPixels = mirror
        ? [...pixels, ...pixels.reversed]
        : pixels;

    // Flatten to UDP packet
    final packet = <int>[];
    for (var i = 0; i < renderPixels.length; i++) {
      for (var c = 0; c < 3; c++) {
        packet.add(renderPixels[i][c].clamp(0.0, 255.0).round());
      }
    }

    return packet;
  }

  void _blendColor(int idx, List<double> color) {
    if (mixingMode == "additive") {
      for (var c = 0; c < 3; c++) pixels[idx][c] += color[c];
    } else {
      for (var c = 0; c < 3; c++) pixels[idx][c] = color[c];
    }
  }
}
