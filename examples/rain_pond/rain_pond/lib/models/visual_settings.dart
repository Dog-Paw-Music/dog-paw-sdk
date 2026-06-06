import 'package:flutter/foundation.dart';

/// User-tunable visual parameters for the pond.
///
/// Persisted via [VisualSettingsStore]; the drawer mutates this notifier.
class VisualSettings extends ChangeNotifier {
  double _baselineRain;
  double _rippleSizeScale;
  double _velocitySensitivity;
  double _heldRippleIntensity;
  double _bendShimmerIntensity;
  double _hueSpread;
  double _decayMultiplier;
  int _maxRipples;
  double _lineWeightScale;
  double _ambientRippleScale;
  double _saturation;
  double _lightness;

  VisualSettings({
    double baselineRain = 0.35,
    double rippleSizeScale = 1.0,
    double velocitySensitivity = 1.0,
    double heldRippleIntensity = 0.7,
    double bendShimmerIntensity = 0.55,
    double hueSpread = 28.0,
    double decayMultiplier = 1.0,
    int maxRipples = 64,
    double lineWeightScale = 1.0,
    double ambientRippleScale = 0.45,
    double saturation = 0.55,
    double lightness = 0.62,
  })  : _baselineRain = baselineRain,
        _rippleSizeScale = rippleSizeScale,
        _velocitySensitivity = velocitySensitivity,
        _heldRippleIntensity = heldRippleIntensity,
        _bendShimmerIntensity = bendShimmerIntensity,
        _hueSpread = hueSpread,
        _decayMultiplier = decayMultiplier,
        _maxRipples = maxRipples,
        _lineWeightScale = lineWeightScale,
        _ambientRippleScale = ambientRippleScale,
        _saturation = saturation,
        _lightness = lightness;

  double get baselineRain => _baselineRain;
  double get rippleSizeScale => _rippleSizeScale;
  double get velocitySensitivity => _velocitySensitivity;
  double get heldRippleIntensity => _heldRippleIntensity;
  double get bendShimmerIntensity => _bendShimmerIntensity;
  double get hueSpread => _hueSpread;
  double get decayMultiplier => _decayMultiplier;
  int get maxRipples => _maxRipples;
  double get lineWeightScale => _lineWeightScale;
  double get ambientRippleScale => _ambientRippleScale;
  double get saturation => _saturation;
  double get lightness => _lightness;

  /// Replaces all fields from persisted storage and notifies listeners.
  ///
  /// @param next Values to copy; each field is clamped to safe ranges.
  /// @post All getters reflect clamped values; listeners notified once.
  void loadFrom(VisualSettings next) {
    _baselineRain = next._baselineRain;
    _rippleSizeScale = next._rippleSizeScale;
    _velocitySensitivity = next._velocitySensitivity;
    _heldRippleIntensity = next._heldRippleIntensity;
    _bendShimmerIntensity = next._bendShimmerIntensity;
    _hueSpread = next._hueSpread;
    _decayMultiplier = next._decayMultiplier;
    _maxRipples = next._maxRipples;
    _lineWeightScale = next._lineWeightScale;
    _ambientRippleScale = next._ambientRippleScale;
    _saturation = next._saturation;
    _lightness = next._lightness;
    _clampAll();
    notifyListeners();
  }

  void setBaselineRain(double v) {
    _baselineRain = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setRippleSizeScale(double v) {
    _rippleSizeScale = v.clamp(0.35, 2.5);
    notifyListeners();
  }

  void setVelocitySensitivity(double v) {
    _velocitySensitivity = v.clamp(0.0, 2.5);
    notifyListeners();
  }

  /// Updates how strongly held keys emit transparent repeat ripples.
  ///
  /// @param v User-selected intensity; clamped to the supported slider range.
  /// @post [heldRippleIntensity] reflects the clamped value and listeners are notified.
  void setHeldRippleIntensity(double v) {
    _heldRippleIntensity = v.clamp(0.0, 1.5);
    notifyListeners();
  }

  /// Updates how strongly horizontal bend produces sideways shimmer echoes.
  ///
  /// @param v User-selected intensity; clamped to the supported slider range.
  /// @post [bendShimmerIntensity] reflects the clamped value and listeners are notified.
  void setBendShimmerIntensity(double v) {
    _bendShimmerIntensity = v.clamp(0.0, 1.5);
    notifyListeners();
  }

  void setHueSpread(double v) {
    _hueSpread = v.clamp(4.0, 48.0);
    notifyListeners();
  }

  void setDecayMultiplier(double v) {
    _decayMultiplier = v.clamp(0.25, 4.0);
    notifyListeners();
  }

  void setMaxRipples(int v) {
    _maxRipples = v.clamp(16, 160);
    notifyListeners();
  }

  void setLineWeightScale(double v) {
    _lineWeightScale = v.clamp(0.35, 2.5);
    notifyListeners();
  }

  void setAmbientRippleScale(double v) {
    _ambientRippleScale = v.clamp(0.1, 1.2);
    notifyListeners();
  }

  void setSaturation(double v) {
    _saturation = v.clamp(0.15, 1.0);
    notifyListeners();
  }

  void setLightness(double v) {
    _lightness = v.clamp(0.35, 0.85);
    notifyListeners();
  }

  void _clampAll() {
    _baselineRain = _baselineRain.clamp(0.0, 1.0);
    _rippleSizeScale = _rippleSizeScale.clamp(0.35, 2.5);
    _velocitySensitivity = _velocitySensitivity.clamp(0.0, 2.5);
    _heldRippleIntensity = _heldRippleIntensity.clamp(0.0, 1.5);
    _bendShimmerIntensity = _bendShimmerIntensity.clamp(0.0, 1.5);
    _hueSpread = _hueSpread.clamp(4.0, 48.0);
    _decayMultiplier = _decayMultiplier.clamp(0.25, 4.0);
    _maxRipples = _maxRipples.clamp(16, 160);
    _lineWeightScale = _lineWeightScale.clamp(0.35, 2.5);
    _ambientRippleScale = _ambientRippleScale.clamp(0.1, 1.2);
    _saturation = _saturation.clamp(0.15, 1.0);
    _lightness = _lightness.clamp(0.35, 0.85);
  }
}
