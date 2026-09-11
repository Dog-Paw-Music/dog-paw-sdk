import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain_pond/utils/ripple_physics.dart';

void main() {
  group('rippleRadiusPx', () {
    test('starts near zero and ends at maxRadius', () {
      expect(
        rippleRadiusPx(ageSec: 0, durationSec: 1, maxRadiusPx: 100),
        lessThan(5),
      );
      expect(
        rippleRadiusPx(ageSec: 1, durationSec: 1, maxRadiusPx: 100),
        closeTo(100, 1),
      );
    });
  });

  group('noteMaxRadiusPx', () {
    test('grows with velocity and sensitivity', () {
      final double a = noteMaxRadiusPx(
        velocity: 0,
        velocitySensitivity: 1,
        baseRadiusPx: 20,
        noteScale: 1,
      );
      final double b = noteMaxRadiusPx(
        velocity: 1,
        velocitySensitivity: 1,
        baseRadiusPx: 20,
        noteScale: 1,
      );
      expect(b, greaterThan(a));
    });
  });

  group('randomRipplePosition', () {
    test('stays inside default margins', () {
      final math.Random rng = math.Random(42);
      const double w = 500;
      const double h = 400;
      for (int i = 0; i < 50; i++) {
        final Offset o = randomRipplePosition(rng, w, h);
        expect(o.dx, inInclusiveRange(w * 0.12, w * 0.88));
        expect(o.dy, inInclusiveRange(h * 0.12, h * 0.88));
      }
    });
  });

  group('ringColorFromHue', () {
    test('pairs same hue with same color', () {
      final Color a = ringColorFromHue(
        hue: 120,
        saturation: 0.5,
        lightness: 0.55,
        alpha: 0.4,
      );
      final Color b = ringColorFromHue(
        hue: 120,
        saturation: 0.5,
        lightness: 0.55,
        alpha: 0.4,
      );
      expect(a, equals(b));
    });
  });

  group('randomHueWithSpread', () {
    test('respects span bounds', () {
      final math.Random rng = math.Random(7);
      for (int i = 0; i < 30; i++) {
        final double h = randomHueWithSpread(rng, 28);
        expect(h, inInclusiveRange(0, 360));
        expect(h, lessThan(360));
      }
    });
  });
}
