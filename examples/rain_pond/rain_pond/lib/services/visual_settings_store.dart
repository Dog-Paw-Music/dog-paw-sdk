import 'package:dogpaw/dogpaw.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/visual_settings.dart';

/// Loads and saves [VisualSettings] to device preferences.
///
/// Sits beside [PondController]; failures are logged and defaults used.
class VisualSettingsStore {
  static const String _kRain = 'rain_pond_baseline_rain';
  static const String _kRipple = 'rain_pond_ripple_scale';
  static const String _kVel = 'rain_pond_vel_sens';
  static const String _kHeldRipple = 'rain_pond_held_ripple_intensity';
  static const String _kBendShimmer = 'rain_pond_bend_shimmer_intensity';
  static const String _kHue = 'rain_pond_hue_spread';
  static const String _kDecay = 'rain_pond_decay';
  static const String _kMax = 'rain_pond_max_ripples';
  static const String _kLine = 'rain_pond_line_scale';
  static const String _kAmb = 'rain_pond_ambient_scale';
  static const String _kSat = 'rain_pond_saturation';
  static const String _kLight = 'rain_pond_lightness';

  /// Reads stored values and returns a new [VisualSettings] instance.
  ///
  /// @pre None; safe before Flutter binding if [SharedPreferences] already initialized.
  /// @return Settings restored from disk, or defaults when keys are missing.
  /// @post No writes performed.
  static Future<VisualSettings> load() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      return VisualSettings(
        baselineRain: p.getDouble(_kRain) ?? 0.35,
        rippleSizeScale: p.getDouble(_kRipple) ?? 1.0,
        velocitySensitivity: p.getDouble(_kVel) ?? 1.0,
        heldRippleIntensity: p.getDouble(_kHeldRipple) ?? 0.7,
        bendShimmerIntensity: p.getDouble(_kBendShimmer) ?? 0.55,
        hueSpread: p.getDouble(_kHue) ?? 28.0,
        decayMultiplier: p.getDouble(_kDecay) ?? 1.0,
        maxRipples: p.getInt(_kMax) ?? 64,
        lineWeightScale: p.getDouble(_kLine) ?? 1.0,
        ambientRippleScale: p.getDouble(_kAmb) ?? 0.45,
        saturation: p.getDouble(_kSat) ?? 0.55,
        lightness: p.getDouble(_kLight) ?? 0.62,
      );
    } catch (e) {
      AppLogger.error('VisualSettingsStore.load failed: $e');
      return VisualSettings();
    }
  }

  /// Persists current [VisualSettings] fields.
  ///
  /// @param settings Source values; must not be null.
  /// @post Preference keys updated on success; errors logged only.
  static Future<void> save(VisualSettings settings) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setDouble(_kRain, settings.baselineRain);
      await p.setDouble(_kRipple, settings.rippleSizeScale);
      await p.setDouble(_kVel, settings.velocitySensitivity);
      await p.setDouble(_kHeldRipple, settings.heldRippleIntensity);
      await p.setDouble(_kBendShimmer, settings.bendShimmerIntensity);
      await p.setDouble(_kHue, settings.hueSpread);
      await p.setDouble(_kDecay, settings.decayMultiplier);
      await p.setInt(_kMax, settings.maxRipples);
      await p.setDouble(_kLine, settings.lineWeightScale);
      await p.setDouble(_kAmb, settings.ambientRippleScale);
      await p.setDouble(_kSat, settings.saturation);
      await p.setDouble(_kLight, settings.lightness);
    } catch (e) {
      AppLogger.error('VisualSettingsStore.save failed: $e');
    }
  }
}
