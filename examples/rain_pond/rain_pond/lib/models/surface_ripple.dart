import 'dart:ui';

/// One expanding ring on the water surface.
///
/// Created by [PondController] when a note fires; advanced each frame by
/// [SurfaceRipple.advance].
class SurfaceRipple {
  /// Horizontal center in logical pixels.
  double cx;

  /// Vertical center in logical pixels.
  double cy;

  /// Time since spawn in seconds.
  double ageSec;

  /// Total lifetime in seconds until removal.
  final double durationSec;

  /// Maximum radius in logical pixels at end of life.
  final double maxRadiusPx;

  /// Peak stroke width in logical pixels.
  final double strokeWidthPx;

  /// Ring color including alpha (fade applied in painter).
  final Color color;

  /// When true, this ripple came from ambient rain (subtle).
  final bool isAmbient;

  SurfaceRipple({
    required this.cx,
    required this.cy,
    required this.ageSec,
    required this.durationSec,
    required this.maxRadiusPx,
    required this.strokeWidthPx,
    required this.color,
    this.isAmbient = false,
  });

  /// Advances time and returns false when the ripple should be removed.
  ///
  /// @param dtSec Frame delta in seconds; must be non-negative.
  /// @return false if [ageSec] exceeded [durationSec] after advance.
  bool advance(double dtSec) {
    ageSec += dtSec;
    return ageSec < durationSec;
  }
}
