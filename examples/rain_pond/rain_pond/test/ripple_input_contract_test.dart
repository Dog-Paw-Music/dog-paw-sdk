import 'dart:math' as math;

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain_pond/controllers/pond_controller.dart';
import 'package:rain_pond/models/ripple_key_source.dart';
import 'package:rain_pond/models/ripple_note_event.dart';
import 'package:rain_pond/utils/pond_keyboard_notes.dart';

void main() {
  test('supportsQwertyRippleKey recognizes configured keys', () {
    expect(supportsQwertyRippleKey(LogicalKeyboardKey.keyA), isTrue);
    expect(supportsQwertyRippleKey(LogicalKeyboardKey.enter), isTrue);
    expect(supportsQwertyRippleKey(LogicalKeyboardKey.keyQ), isFalse);
  });

  test('keyboard ripple events do not require note numbers', () {
    final PondController controller = PondController(
      entity: dp.DogPawEntity('RainPondUnitTest'),
      random: math.Random(1),
      startInitialized: true,
    );
    controller.setCanvasSize(const Size(400, 400));
    final RippleKeySource source = RippleKeySource.keyboard(
      keyboardKeyId: LogicalKeyboardKey.keyA.keyId,
    );

    controller.submitKeyboardNote(
      RippleNoteEvent(
        source: source,
        velocity: 0.88,
        isDown: true,
      ),
    );
    expect(controller.ripples, hasLength(1));

    controller.submitKeyboardNote(
      RippleNoteEvent(
        source: source,
        velocity: 0.0,
        isDown: false,
      ),
    );
    expect(controller.ripples, hasLength(2));
  });
}
