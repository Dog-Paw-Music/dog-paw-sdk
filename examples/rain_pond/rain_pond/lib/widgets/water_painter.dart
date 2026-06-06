import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/pond_controller.dart';
import '../models/surface_ripple.dart';
import '../utils/ripple_physics.dart';

/// Draws lofi pond gradient, soft vignette, and all [SurfaceRipple] rings.
class WaterPainter extends CustomPainter {
  WaterPainter({required this.controller});

  final PondController controller;

  @override
  void paint(Canvas canvas, Size size) {
    _paintWaterBackground(canvas, size);
    for (final SurfaceRipple r in controller.ripples) {
      _paintRipple(canvas, r);
    }
  }

  /// Fills the scene with a soft cartoon water gradient and vignette.
  void _paintWaterBackground(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint bg = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.45, size.height * 0.38),
        size.shortestSide * 0.95,
        const [
          Color(0xFF4A7DA8),
          Color(0xFF2E4E6E),
          Color(0xFF1A3048),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(rect, bg);

    final Paint wash = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height * 0.2),
        Offset(size.width * 0.3, size.height),
        [
          const Color(0xFF8ECAE6).withOpacity(0.08),
          Colors.transparent,
        ],
      );
    canvas.drawRect(rect, wash);

    final Paint vignette = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.5),
        size.longestSide * 0.72,
        [
          Colors.transparent,
          const Color(0xFF0D1820).withOpacity(0.45),
        ],
        const [0.65, 1.0],
      );
    canvas.drawRect(rect, vignette);
  }

  /// Short vertical streak above the ripple so ambient rain reads as a drop hitting the surface.
  void _paintAmbientDrop(
    Canvas canvas,
    SurfaceRipple r,
    Color ringColor,
    double alphaMul,
  ) {
    final double t = (r.ageSec / r.durationSec).clamp(0.0, 1.0);
    final double dropLen = (5.0 + r.maxRadiusPx * 0.12) * (1.0 - t * 0.85);
    if (dropLen < 1.0) {
      return;
    }
    final Offset top = Offset(r.cx, r.cy - dropLen);
    final Offset hit = Offset(r.cx, r.cy);
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..color = ringColor.withOpacity(
        (ringColor.opacity * 0.75 * alphaMul).clamp(0.0, 1.0),
      );
    canvas.drawLine(top, hit, line);
  }

  /// Strokes one expanding ring with time-based opacity.
  void _paintRipple(Canvas canvas, SurfaceRipple r) {
    final double radius = rippleRadiusPx(
      ageSec: r.ageSec,
      durationSec: r.durationSec,
      maxRadiusPx: r.maxRadiusPx,
    );
    final double alphaMul = rippleOpacityFactor(
      ageSec: r.ageSec,
      durationSec: r.durationSec,
    );
    final Color c =
        r.color.withOpacity((r.color.opacity * alphaMul).clamp(0.0, 1.0));
    if (r.isAmbient) {
      _paintAmbientDrop(canvas, r, c, alphaMul);
    }
    final double strokeW = r.isAmbient
        ? math.max(1.35, r.strokeWidthPx * 0.9)
        : r.strokeWidthPx;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..color = c;
    canvas.drawCircle(Offset(r.cx, r.cy), radius, p);
    if (!r.isAmbient && radius > 6) {
      final Paint inner = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.strokeWidthPx * 0.45
        ..color = c.withOpacity((c.opacity * 0.35).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(r.cx, r.cy), radius * 0.62, inner);
    }
  }

  @override
  bool shouldRepaint(covariant WaterPainter oldDelegate) => true;
}
