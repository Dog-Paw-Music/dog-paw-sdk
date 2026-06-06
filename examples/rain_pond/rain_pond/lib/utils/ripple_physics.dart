import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show HSLColor;

/// Pure helpers for ripple geometry and color.
///
/// Used by [PondController] and [WaterPainter] so behavior can be unit tested
/// without Flutter widgets.

/// Computes ring radius at [ageSec] for a linear ease-out expansion.
///
/// @param ageSec Elapsed time since spawn; must be non-negative.
/// @param durationSec Total ripple lifetime; must be positive for smooth motion.
/// @param maxRadiusPx Target radius at end of life.
/// @return Current radius in pixels.
double rippleRadiusPx({
  required double ageSec,
  required double durationSec,
  required double maxRadiusPx,
}) {
  if (durationSec <= 0) {
    return maxRadiusPx;
  }
  final double t = (ageSec / durationSec).clamp(0.0, 1.0);
  final double eased = 1.0 - math.pow(1.0 - t, 2).toDouble();
  return maxRadiusPx * eased;
}

/// Multiplier for fading the ring (1 at birth, 0 at end).
///
/// @param ageSec Elapsed time since spawn; must be non-negative.
/// @param durationSec Total ripple lifetime; must be positive.
/// @return Opacity factor in \[0, 1\].
double rippleOpacityFactor({
  required double ageSec,
  required double durationSec,
}) {
  if (durationSec <= 0) {
    return 0;
  }
  final double t = (ageSec / durationSec).clamp(0.0, 1.0);
  return math.pow(1.0 - t, 1.35).toDouble();
}

/// Peak radius for a note-driven ripple from velocity and sliders.
///
/// @param velocity Raw velocity from hardware or synthetic \[0, 127\] or \[0, 1\].
/// @param velocitySensitivity User multiplier for how much velocity stretches the ring.
/// @param baseRadiusPx Minimum radius contribution from sliders.
/// @param noteScale Extra scale from user “ripple size” control.
/// @return Radius in logical pixels.
double noteMaxRadiusPx({
  required double velocity,
  required double velocitySensitivity,
  required double baseRadiusPx,
  required double noteScale,
}) {
  final double vn = _normalizeVelocity(velocity);
  return baseRadiusPx + velocitySensitivity * vn * noteScale * 140.0;
}

/// Normalizes velocity to \[0, 1\] whether it looks MIDI-like or unit-scaled.
double _normalizeVelocity(double velocity) {
  if (velocity > 1.0) {
    return (velocity / 127.0).clamp(0.0, 1.0);
  }
  return velocity.clamp(0.0, 1.0);
}

/// Uniform random hue in \[0, 360).
///
/// @param rng Non-null random stream.
/// @return Hue in degrees for [ringColorFromHue].
double randomHueDegrees(math.Random rng) {
  return rng.nextDouble() * 360.0;
}

/// Random hue whose range is driven by the same slider as the old note-based spread.
///
/// @param rng Non-null random stream.
/// @param hueSpreadSetting Drawer “hue spread” value (typically 4–48).
/// @return Hue in \[0, span) degrees with span between ~72° and 360°.
double randomHueWithSpread(math.Random rng, double hueSpreadSetting) {
  final double span = (hueSpreadSetting * 13.0).clamp(72.0, 360.0);
  return rng.nextDouble() * span;
}

/// Ring color from an absolute hue (paired press/release use the same hue).
///
/// @param hue Degrees \[0, 360).
/// @param saturation HSL saturation \[0, 1\].
/// @param lightness HSL lightness \[0, 1\].
/// @param alpha Base alpha before time fade in the painter.
/// @return ARGB color.
Color ringColorFromHue({
  required double hue,
  required double saturation,
  required double lightness,
  required double alpha,
}) {
  final double h = hue % 360.0;
  return HSLColor.fromAHSL(alpha, h, saturation, lightness).toColor();
}

/// Random splash position inset from canvas edges (cartoon pond margins).
///
/// @param rng Non-null random stream.
/// @param width Canvas width; must be positive.
/// @param height Canvas height; must be positive.
/// @param margin Fraction \[0, 0.45\] inset on each side.
/// @return Center in logical pixels.
Offset randomRipplePosition(
  math.Random rng,
  double width,
  double height, {
  double margin = 0.12,
}) {
  final double m = margin.clamp(0.05, 0.45);
  final double x0 = width * m;
  final double y0 = height * m;
  final double x1 = width * (1.0 - m);
  final double y1 = height * (1.0 - m);
  return Offset(
    x0 + rng.nextDouble() * (x1 - x0),
    y0 + rng.nextDouble() * (y1 - y0),
  );
}

/// Default duration in seconds for a note ripple before pruning.
///
/// @param decayMultiplier User value > 0; higher means longer-lived ripples.
/// @return Duration clamped to reasonable bounds.
double noteRippleDurationSec({required double decayMultiplier}) {
  final double m = decayMultiplier.clamp(0.25, 4.0);
  return (0.85 * m).clamp(0.35, 6.0);
}

/// Stroke width peak from user style and velocity.
///
/// @param velocity Raw or normalized velocity.
/// @param lineScale User multiplier.
/// @param baseWidth Minimum stroke in pixels.
/// @return Stroke width in logical pixels.
double noteStrokeWidthPx({
  required double velocity,
  required double lineScale,
  required double baseWidth,
}) {
  final double vn = _normalizeVelocity(velocity);
  return baseWidth + lineScale * (2.0 + vn * 5.0);
}
