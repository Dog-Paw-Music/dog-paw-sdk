import 'ripple_key_source.dart';

/// Normalized note input for the pond visualizer (hardware or keyboard).
///
/// [source] ties press and release together so visuals can match (see
/// [RippleKeySource]).
class RippleNoteEvent {
  /// Physical origin of this transition (grid cell or keyboard key).
  final RippleKeySource source;

  /// Strike velocity for a press; may be 0 on release.
  final double velocity;

  /// True when the key is engaged (pressed); false on release.
  final bool isDown;

  const RippleNoteEvent({
    required this.source,
    required this.velocity,
    required this.isDown,
  });
}
