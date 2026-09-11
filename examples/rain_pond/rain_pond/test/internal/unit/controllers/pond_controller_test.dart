import 'dart:math' as math;
import 'dart:ui';

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter_test/flutter_test.dart';
import 'package:rain_pond/controllers/pond_controller.dart';
import 'package:rain_pond/models/ripple_key_source.dart';
import 'package:rain_pond/models/ripple_note_event.dart';
import 'package:rain_pond/models/surface_ripple.dart';
import 'package:rain_pond/models/visual_settings.dart';

void main() {
  const RippleKeySource heldSource =
      RippleKeySource.internalGrid(col: 2, row: 3);

  PondController makeController(VisualSettings settings) {
    return PondController(
      entity: dp.DogPawEntity('RainPondTest'),
      settings: settings,
      random: math.Random(7),
      startInitialized: true,
    )..setCanvasSize(const Size(420, 300));
  }

  RippleNoteEvent keyDown() {
    return const RippleNoteEvent(
      source: heldSource,
      velocity: 0.9,
      isDown: true,
    );
  }

  RippleNoteEvent keyUp() {
    return const RippleNoteEvent(
      source: heldSource,
      velocity: 0.0,
      isDown: false,
    );
  }

  group('held note visuals', () {
    test(
        'user flow turns one key press into press ripple, held shimmer, release ripple, and then silence',
        () {
      final VisualSettings settings = VisualSettings(
        baselineRain: 0.0,
        heldRippleIntensity: 1.0,
        bendShimmerIntensity: 1.0,
      );
      final PondController controller = makeController(settings);

      controller.submitKeyboardNote(keyDown());
      expect(controller.ripples, hasLength(1));

      controller.updateHeldNoteExpression(
        source: heldSource,
        pressure: 1.0,
        bend: 0.85,
      );
      controller.advance(const Duration(milliseconds: 900));

      final int rippleCountWhileHeld = controller.ripples.length;
      expect(rippleCountWhileHeld, greaterThan(1));

      controller.submitKeyboardNote(keyUp());
      final int rippleCountImmediatelyAfterRelease = controller.ripples.length;
      expect(
        rippleCountImmediatelyAfterRelease,
        greaterThanOrEqualTo(rippleCountWhileHeld),
      );

      controller.updateHeldNoteExpression(
        source: heldSource,
        pressure: 1.0,
        bend: 0.9,
      );
      controller.advance(const Duration(milliseconds: 120));

      expect(
        controller.ripples.length,
        equals(rippleCountImmediatelyAfterRelease),
      );
    });

    test('spawns transparent repeats and bend shimmer while held', () {
      final VisualSettings settings = VisualSettings(
        baselineRain: 0.0,
        heldRippleIntensity: 1.0,
        bendShimmerIntensity: 1.0,
      );
      final PondController controller = makeController(settings);

      controller.submitKeyboardNote(keyDown());
      final SurfaceRipple initialPress = controller.ripples.single;

      controller.updateHeldNoteExpression(
        source: heldSource,
        pressure: 1.0,
        bend: 0.85,
      );
      controller.advance(const Duration(milliseconds: 900));

      final List<SurfaceRipple> extraRipples =
          controller.ripples.skip(1).toList();
      expect(extraRipples, isNotEmpty);
      expect(
        extraRipples.any(
          (SurfaceRipple ripple) =>
              (ripple.cx - initialPress.cx).abs() < 0.001 &&
              (ripple.cy - initialPress.cy).abs() < 0.001 &&
              ripple.color.opacity < initialPress.color.opacity,
        ),
        isTrue,
      );
      expect(
        extraRipples.any(
          (SurfaceRipple ripple) => (ripple.cx - initialPress.cx).abs() > 6.0,
        ),
        isTrue,
      );
    });

    test('stops spawning held repeats after release', () {
      final VisualSettings settings = VisualSettings(
        baselineRain: 0.0,
        heldRippleIntensity: 1.0,
        bendShimmerIntensity: 1.0,
      );
      final PondController controller = makeController(settings);

      controller.submitKeyboardNote(keyDown());
      controller.updateHeldNoteExpression(
        source: heldSource,
        pressure: 1.0,
        bend: 0.7,
      );
      controller.advance(const Duration(milliseconds: 900));

      controller.submitKeyboardNote(keyUp());
      final int rippleCountAfterRelease = controller.ripples.length;

      controller.updateHeldNoteExpression(
        source: heldSource,
        pressure: 1.0,
        bend: 0.9,
      );
      controller.advance(const Duration(milliseconds: 80));

      expect(controller.ripples.length, equals(rippleCountAfterRelease));
    });
  });
}
