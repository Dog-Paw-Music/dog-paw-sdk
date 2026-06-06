import 'package:flutter/foundation.dart';

/// Identifies one physical key for pairing note-on and note-off ripples.
///
/// Mirrors the idea of [KeySource] in `common/dataTypes/KeySource.hpp`: grid
/// keys are unique by `(col, row)`; keyboard keys are unique by Flutter’s
/// `LogicalKeyboardKey.keyId`. The pond uses this as a [Map] key so release
/// ripples reuse the same random position and hue as the matching press.
@immutable
class RippleKeySource {
  /// BladeHW grid cell (Dog Paw).
  const RippleKeySource.internalGrid({required this.col, required this.row})
      : isKeyboard = false,
        keyboardKeyId = 0;

  /// Desktop test keyboard (one entry per logical key).
  const RippleKeySource.keyboard({required this.keyboardKeyId})
      : isKeyboard = true,
        col = 0,
        row = 0;

  /// True when this source is a Flutter keyboard key.
  final bool isKeyboard;

  /// Grid column when [isKeyboard] is false.
  final int col;

  /// Grid row when [isKeyboard] is false.
  final int row;

  /// [LogicalKeyboardKey.keyId] when [isKeyboard] is true.
  final int keyboardKeyId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is RippleKeySource &&
        isKeyboard == other.isKeyboard &&
        col == other.col &&
        row == other.row &&
        keyboardKeyId == other.keyboardKeyId;
  }

  @override
  int get hashCode => Object.hash(isKeyboard, col, row, keyboardKeyId);
}
