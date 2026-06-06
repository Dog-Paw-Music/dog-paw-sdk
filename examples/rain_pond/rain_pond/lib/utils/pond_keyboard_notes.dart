import 'package:flutter/services.dart';

/// Reports whether a physical typing key is bound for desktop ripple testing.
///
/// Purpose:
///     Keeps keyboard test input explicit without implying Rain Pond depends on
///     musical note numbers.
/// Parameters:
///     key: Logical key from a [KeyDownEvent] or [KeyUpEvent].
/// Return value:
///     `true` when Rain Pond should treat the key as a ripple trigger.
/// Requirements:
///     `key` must be a valid Flutter logical keyboard key.
/// Guarantees:
///     Returns the same answer for the same key on every call.
/// Invariants:
///     Pure function; does not mutate Flutter or application state.
bool supportsQwertyRippleKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.keyA) {
    return true;
  }
  if (key == LogicalKeyboardKey.keyS) {
    return true;
  }
  if (key == LogicalKeyboardKey.keyD) {
    return true;
  }
  if (key == LogicalKeyboardKey.keyF) {
    return true;
  }
  if (key == LogicalKeyboardKey.keyG) {
    return true;
  }
  if (key == LogicalKeyboardKey.keyH) {
    return true;
  }
  if (key == LogicalKeyboardKey.keyJ) {
    return true;
  }
  if (key == LogicalKeyboardKey.keyK) {
    return true;
  }
  if (key == LogicalKeyboardKey.keyL) {
    return true;
  }
  if (key == LogicalKeyboardKey.semicolon) {
    return true;
  }
  if (key == LogicalKeyboardKey.quote) {
    return true;
  }
  if (key == LogicalKeyboardKey.enter) {
    return true;
  }
  return false;
}
