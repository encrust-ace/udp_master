import 'dart:math' as math;

class EnergyAudioEffect {
  final int ledCount;
  bool mirror; // Make configurable during runtime
  bool colorCyclerEnabled; // Make configurable
  String mixingMode; // Make configurable

  // Configurable parameters from provider
  double gain; // Applied to input audio levels
  double overallBrightness; // Applied to final pixel color
  // 'sensitivity' is already a core param of the effect
  // 'position' needs more complex logic if implemented beyond simple fill

  List<List<double>> colorPalette;
  double blur;
  double sensitivity;
  double _decaySensitivity;

  List<double> lowsColor;
  List<double> midsColor;
  List<double> highsColor;

  final List<List<double>> pixels;
  final List<List<double>> _prevPixels;
  List<List<double>>? _blurBuffer; // Nullable, allocated if blur > 0

  int _colorCyclerIndex = 0;
  final math.Random _rng = math.Random();

  EnergyAudioEffect({
    required this.ledCount,
    // Defaults that can be overridden by provider
    this.blur = 0.0, // Default to 0, LedFx often has blur off by default
    this.mirror = false,
    this.colorCyclerEnabled = false,
    this.mixingMode = "additive", // "additive" is common for energy
    List<int>? colorLows,
    List<int>? colorMids,
    List<int>? colorHigh,
    this.sensitivity = 0.6, // This is the effect's internal responsiveness
    this.gain = 1.0, // External gain for audio levels
    this.overallBrightness = 1.0, // Final brightness scalar
    this.colorPalette = const [ // Default palette
      [255.0, 0.0, 0.0], [0.0, 255.0, 0.0], [0.0, 0.0, 255.0],
      [255.0, 255.0, 0.0], [0.0, 255.0, 255.0], [255.0, 0.0, 255.0],
    ],
  })  : assert(ledCount >= 0), // Allow 0 for dynamic segments
        assert(blur >= 0.0 && blur <= 10.0),
        assert(sensitivity > 0.0 && sensitivity <= 1.0),
        assert(gain >= 0.0),
        assert(overallBrightness >= 0.0 && overallBrightness <= 1.0),
        assert(mixingMode == "additive" || mixingMode == "overlap"),
        lowsColor = _parseColor(colorLows) ?? [255.0, 0.0, 0.0],
        midsColor = _parseColor(colorMids) ?? [0.0, 255.0, 0.0],
        highsColor = _parseColor(colorHigh) ?? [0.0, 0.0, 255.0],
        _decaySensitivity = (sensitivity * 0.7).clamp(0.01, sensitivity - 0.01 > 0 ? sensitivity - 0.01 : 0.01),
        pixels = List.generate(ledCount, (_) => [0.0, 0.0, 0.0], growable: false),
        _prevPixels = List.generate(ledCount, (_) => [0.0, 0.0, 0.0], growable: false) {
    _updateBlurBuffer(); // Call helper to init/clear blur buffer
    assert(colorPalette.every((color) => color.length == 3));
  }

  // Method to update parameters dynamically
  void updateParameters({
    double? blur,
    bool? mirror,
    bool? colorCyclerEnabled,
    String? mixingMode,
    double? sensitivity,
    double? gain,
    double? overallBrightness,
    List<List<double>>? colorPalette,
    List<int>? newLowsColor,
    List<int>? newMidsColor,
    List<int>? newHighsColor,
  }) {
    if (blur != null) {
      this.blur = blur.clamp(0.0, 10.0);
      _updateBlurBuffer();
    }
    if (mirror != null) this.mirror = mirror;
    if (colorCyclerEnabled != null) this.colorCyclerEnabled = colorCyclerEnabled;
    if (mixingMode != null && (mixingMode == "additive" || mixingMode == "overlap")) {
      this.mixingMode = mixingMode;
    }
    if (sensitivity != null) {
      this.sensitivity = sensitivity.clamp(0.01, 1.0);
      this._decaySensitivity = (this.sensitivity * 0.7).clamp(0.01, this.sensitivity - 0.01 > 0 ? this.sensitivity - 0.01 : 0.01);
    }
    if (gain != null) this.gain = gain.clamp(0.0, 10.0); // Allow some gain
    if (overallBrightness != null) this.overallBrightness = overallBrightness.clamp(0.0, 1.0);
    if (colorPalette != null) this.colorPalette = colorPalette;
    if (newLowsColor != null) this.lowsColor = _parseColor(newLowsColor) ?? this.lowsColor;
    if (newMidsColor != null) this.midsColor = _parseColor(newMidsColor) ?? this.midsColor;
    if (newHighsColor != null) this.highsColor = _parseColor(newHighsColor) ?? this.highsColor;
  }

  void _updateBlurBuffer() {
    if (this.blur > 0.0 && ledCount > 0) { // Changed from blur > 1.0
      if (_blurBuffer == null || _blurBuffer!.length != ledCount) {
        _blurBuffer = List.generate(ledCount, (_) => [0.0, 0.0, 0.0], growable: false);
      }
    } else {
      _blurBuffer = null;
    }
  }

  static List<double>? _parseColor(List<int>? colorInt) {
    if (colorInt == null) return null;
    assert(colorInt.length == 3);
    return colorInt.map((c) => c.toDouble().clamp(0.0, 255.0)).toList(growable: false);
  }

  void updateColorsOnBeat() {
    if (!colorCyclerEnabled || colorPalette.isEmpty) return;
    _colorCyclerIndex = (_colorCyclerIndex + 1) % 3; // Cycle through which band to change
    final randomColorFromPalette = colorPalette[_rng.nextInt(colorPalette.length)];
    final newColor = List<double>.from(randomColorFromPalette, growable: false);

    if (_colorCyclerIndex == 0) lowsColor = newColor;
    else if (_colorCyclerIndex == 1) midsColor = newColor;
    else highsColor = newColor;
  }

  List<int> frame({
    required bool beatNow,
    required double lows, // Expected to be 0-1 from analyzer
    required double mids,
    required double highs,
  }) {
    if (ledCount == 0) return List<int>.empty(growable: false);

    if (beatNow) updateColorsOnBeat();

    // Apply external gain to audio inputs
    final currentLows = (lows * gain).clamp(0.0, 1.0);
    final currentMids = (mids * gain).clamp(0.0, 1.0);
    final currentHighs = (highs * gain).clamp(0.0, 1.0);

    // LedFx energy effect typically scales by sensitivity directly for band spread.
    // The 'effectMultiplier' might be an LedFx detail or specific to one of its variations.
    // For a simpler model closer to basic LedFx energy:
    // Let's use sensitivity to determine spread, and make the 'multiplier' more direct.
    // This part is crucial for "LedFx feel" and needs experimentation.
    // A common LedFx approach: max_leds = sensitivity * led_count.
    // Then, band_power (0-1) * max_leds.
    final double activatableLedProportion = sensitivity; // Higher sensitivity spreads further
    final int maxLedsForBand = (ledCount * activatableLedProportion).round();

    final int lowsIdx = (maxLedsForBand * currentLows).round().clamp(0, ledCount);
    final int midsIdx = (maxLedsForBand * currentMids).round().clamp(0, ledCount);
    final int highsIdx = (maxLedsForBand * currentHighs).round().clamp(0, ledCount);

    if (mixingMode == "overlap") {
      for (var i = 0; i < ledCount; i++) {
        pixels[i][0] = 0.0;
        pixels[i][1] = 0.0;
        pixels[i][2] = 0.0;
      }
    }
    // For "additive" mode, pixels naturally decay via smoothing.

    // --- Original LedFx Energy logic often applies bands sequentially and can overwrite ---
    // --- or add. If overlap, typically higher frequencies paint "on top". ---
    // --- If additive, order matters less unless there's clamping in _blendPixelColor ---

    // For "bottom" position (default):
    _applyBandColor(lowsIdx, lowsColor);
    _applyBandColor(midsIdx, midsColor); // This will draw over/add to lows if indices overlap
    _applyBandColor(highsIdx, highsColor); // This will draw over/add to mids/lows

    // Additive mode needs care if values can exceed 255 before final clamping.
    // LedFx typically uses floating point for pixels internally then clamps at output.

    if (blur > 0.0 && _blurBuffer != null && ledCount > 0) { // Check ledCount for blur
      _applyBlur();
    }

    _applySmoothing(); // Applies sensitivity/decay internally

    return _generateOutputPacket(); // Applies overallBrightness
  }

  void _applyBandColor(int activeLedCount, List<double> color) {
    for (var i = 0; i < activeLedCount; i++) {
      // Future: Implement 'position' logic here (center, edge) by transforming 'i'
      _blendPixelColor(i, color);
    }
  }

  void _blendPixelColor(int idx, List<double> color) {
    if (idx < 0 || idx >= ledCount) return; // Should be handled by loop bounds

    if (mixingMode == "additive") {
      pixels[idx][0] += color[0];
      pixels[idx][1] += color[1];
      pixels[idx][2] += color[2];
      // Clamping here can be aggressive. LedFx usually relies on smoothing and final output clamp.
      // pixels[idx][0] = pixels[idx][0].clamp(0.0, 765.0); // Example: clamp to 3x full brightness
      // pixels[idx][1] = pixels[idx][1].clamp(0.0, 765.0);
      // pixels[idx][2] = pixels[idx][2].clamp(0.0, 765.0);
    } else { // Overlap
      pixels[idx][0] = color[0];
      pixels[idx][1] = color[1];
      pixels[idx][2] = color[2];
    }
  }

  void _applyBlur() {
    final buffer = _blurBuffer!; // Null checked by caller
    // LedFx blur is often a Gaussian blur, box blur is simpler.
    // Blur amount in LedFx might also be # of passes or kernel size.
    final int blurRadius = (blur / 2.0).round().clamp(0, ledCount ~/ 2); // blur 0-10 -> radius 0-5

    if (blurRadius == 0) return;

    for (var i = 0; i < ledCount; ++i) {
      buffer[i][0] = pixels[i][0];
      buffer[i][1] = pixels[i][1];
      buffer[i][2] = pixels[i][2];
    }

    for (var i = 0; i < ledCount; i++) {
      double rSum = 0.0, gSum = 0.0, bSum = 0.0;
      final start = math.max(0, i - blurRadius);
      final end = math.min(ledCount - 1, i + blurRadius);
      final count = end - start + 1;

      if (count > 0) { // Ensure count is not zero
        for (var j = start; j <= end; j++) {
          rSum += buffer[j][0];
          gSum += buffer[j][1];
          bSum += buffer[j][2];
        }
        pixels[i][0] = rSum / count;
        pixels[i][1] = gSum / count;
        pixels[i][2] = bSum / count;
      } else { // Should not happen if ledCount > 0 and blurRadius >=0
        pixels[i][0] = buffer[i][0];
        pixels[i][1] = buffer[i][1];
        pixels[i][2] = buffer[i][2];
      }
    }
  }

  void _applySmoothing() {
    for (var i = 0; i < ledCount; i++) {
      for (var c = 0; c < 3; c++) {
        final currentPixelValue = pixels[i][c];
        final prevPixelValue = _prevPixels[i][c];

        // Original LedFx smoothing is often just an exponential filter (decay).
        // The rise/decay based on current vs prev is a common variation.
        final alpha = currentPixelValue > prevPixelValue ? sensitivity : _decaySensitivity;

        pixels[i][c] = alpha * currentPixelValue + (1.0 - alpha) * prevPixelValue;
        // No explicit clamping here, rely on final output clamp.
        _prevPixels[i][c] = pixels[i][c];
      }
    }
  }

  List<int> _generateOutputPacket() {
    final int numLedsToRender = mirror && ledCount > 0 ? ledCount * 2 : ledCount;
    if (numLedsToRender == 0) return List<int>.empty(growable: false);

    final packet = List<int>.filled(numLedsToRender * 3, 0, growable: false);
    int packetIdx = 0;

    for (var i = 0; i < numLedsToRender; i++) {
      final int pixelSourceIndex;
      if (mirror && ledCount > 0) {
        pixelSourceIndex = i < ledCount ? i : (numLedsToRender - 1 - i);
      } else {
        pixelSourceIndex = i;
      }

      // Apply overall brightness and clamp
      // Ensure pixelSourceIndex is valid, though logic should guarantee it if ledCount > 0
      if (pixelSourceIndex < 0 || pixelSourceIndex >= ledCount) continue;


      final px = pixels[pixelSourceIndex];
      packet[packetIdx++] = (px[0] * overallBrightness).clamp(0.0, 255.0).round();
      packet[packetIdx++] = (px[1] * overallBrightness).clamp(0.0, 255.0).round();
      packet[packetIdx++] = (px[2] * overallBrightness).clamp(0.0, 255.0).round();
    }
    return packet;
  }
}
