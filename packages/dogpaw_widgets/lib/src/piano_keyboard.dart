import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'note_utils.dart';

/// A reusable piano keyboard widget for displaying and interacting with musical notes.
///
/// This widget displays one octave (12 notes) of a piano keyboard with customizable
/// coloring and interaction callbacks. It handles rendering, touch detection, and
/// gesture recognition, while leaving all state management and styling to the parent.
///
/// The keyboard is responsive and scales to fit the available width while maintaining
/// proportions between white and black keys.
class PianoKeyboard extends StatelessWidget {
  /// Height of the keyboard widget
  final double height;

  /// Function that returns the color for each note (0-11 for C through B)
  final Color Function(int noteIndex) colorForNote;

  /// Called when a note is tapped (short press)
  final void Function(int noteIndex)? onNoteTap;

  /// Called when a note is long-pressed
  final void Function(int noteIndex)? onNoteLongPress;

  /// Called when a note is pressed down (useful for continuous interaction)
  final void Function(int noteIndex)? onNoteDown;

  /// Called when a note press is released
  final void Function(int noteIndex)? onNoteUp;

  /// Whether to show note labels on the keys
  final bool showNoteLabels;

  /// Style for note labels (if null, uses adaptive color based on key color)
  final TextStyle? labelStyle;

  /// Border color for white keys
  final Color whiteKeyBorderColor;

  /// Border color for black keys
  final Color blackKeyBorderColor;

  const PianoKeyboard({
    super.key,
    required this.height,
    required this.colorForNote,
    this.onNoteTap,
    this.onNoteLongPress,
    this.onNoteDown,
    this.onNoteUp,
    this.showNoteLabels = true,
    this.labelStyle,
    this.whiteKeyBorderColor = const Color(0xFFBDBDBD),
    this.blackKeyBorderColor = const Color(0xFF424242),
  });

  /// Build the full one-octave keyboard.
  ///
  /// Parameters:
  /// - `context`: Build context used for inherited layout and theme access.
  ///
  /// Return value:
  /// - A fixed-height widget that lays out seven white keys and five black keys.
  ///
  /// Requirements/Preconditions:
  /// - `height` should be positive.
  /// - `colorForNote` must return a valid color for indices `0` through `11`.
  ///
  /// Guarantees/Postconditions:
  /// - The keyboard preserves one-octave piano spacing.
  /// - Black keys render as short wide rectangles.
  /// - White and black keys begin at the same top edge.
  ///
  /// Invariants:
  /// - The widget does not own note state; all note styling remains parent-driven.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double totalWidth = constraints.maxWidth;
          final double whiteKeyWidth = totalWidth / 7;
          final double blackKeyWidth = whiteKeyWidth * 0.6;
          final double blackKeyHeight = math.min(
            blackKeyWidth * (4 / 3),
            height * 0.6,
          );
          final double whiteKeyTop = 0;
          final double whiteKeyHeight = height;

          // White key positions (C, D, E, F, G, A, B)
          final List<int> whiteKeyIndices = <int>[0, 2, 4, 5, 7, 9, 11];

          // Black key data: (noteIndex, position between white keys)
          // Position: which white key's right edge to position at
          final List<(int, int)> blackKeyData = <(int, int)>[
            (1, 0),   // C# between C(0) and D(1)
            (3, 1),   // D# between D(1) and E(2)
            (6, 3),   // F# between F(3) and G(4)
            (8, 4),   // G# between G(4) and A(5)
            (10, 5),  // A# between A(5) and B(6)
          ];

          return Stack(
            children: [
              // White keys (rendered first, so black keys appear on top)
              ...List.generate(7, (index) {
                final noteIndex = whiteKeyIndices[index];
                return Positioned(
                  left: index * whiteKeyWidth,
                  top: whiteKeyTop,
                  width: whiteKeyWidth,
                  height: whiteKeyHeight,
                  child: _buildWhiteKey(noteIndex),
                );
              }),

              // Black keys (rendered on top of white keys)
              ...blackKeyData.map((data) {
                final (noteIndex, whiteKeyPosition) = data;
                // Center the black key on the edge between two white keys
                final double leftPosition =
                    (whiteKeyPosition + 1) * whiteKeyWidth - blackKeyWidth / 2;

                return Positioned(
                  left: leftPosition,
                  top: 0,
                  width: blackKeyWidth,
                  height: blackKeyHeight,
                  child: _buildBlackKey(noteIndex),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  /// Build one white piano key.
  ///
  /// Parameters:
  /// - `noteIndex`: Chromatic note index rendered by this white key.
  ///
  /// Return value:
  /// - Interactive white-key widget for the requested note.
  ///
  /// Requirements/Preconditions:
  /// - `noteIndex` should refer to a white-key pitch class.
  ///
  /// Guarantees/Postconditions:
  /// - The key uses the parent-provided note color and forwards gestures.
  ///
  /// Invariants:
  /// - The widget remains stateless and presentation-only.
  Widget _buildWhiteKey(int noteIndex) {
    final Color keyColor = colorForNote(noteIndex);

    return GestureDetector(
      onTap: onNoteTap != null ? () => onNoteTap!(noteIndex) : null,
      onLongPress: onNoteLongPress != null ? () => onNoteLongPress!(noteIndex) : null,
      onTapDown: onNoteDown != null ? (_) => onNoteDown!(noteIndex) : null,
      onTapUp: onNoteUp != null ? (_) => onNoteUp!(noteIndex) : null,
      onTapCancel: onNoteUp != null ? () => onNoteUp!(noteIndex) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: keyColor,
          border: Border.all(color: whiteKeyBorderColor, width: 1),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: showNoteLabels
            ? Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    NoteUtils.noteNames[noteIndex],
                    style: labelStyle ??
                        TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: keyColor.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                        ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  /// Build one black piano key.
  ///
  /// Parameters:
  /// - `noteIndex`: Chromatic note index rendered by this black key.
  ///
  /// Return value:
  /// - Interactive black-key widget for the requested note.
  ///
  /// Requirements/Preconditions:
  /// - `noteIndex` should refer to a black-key pitch class.
  ///
  /// Guarantees/Postconditions:
  /// - The key uses the parent-provided note color and forwards gestures.
  ///
  /// Invariants:
  /// - The widget remains stateless and presentation-only.
  Widget _buildBlackKey(int noteIndex) {
    final Color keyColor = colorForNote(noteIndex);

    return GestureDetector(
      onTap: onNoteTap != null ? () => onNoteTap!(noteIndex) : null,
      onLongPress: onNoteLongPress != null ? () => onNoteLongPress!(noteIndex) : null,
      onTapDown: onNoteDown != null ? (_) => onNoteDown!(noteIndex) : null,
      onTapUp: onNoteUp != null ? (_) => onNoteUp!(noteIndex) : null,
      onTapCancel: onNoteUp != null ? () => onNoteUp!(noteIndex) : null,
      child: Container(
        decoration: BoxDecoration(
          color: keyColor,
          border: Border.all(color: blackKeyBorderColor, width: 2),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: showNoteLabels
            ? Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    NoteUtils.noteNames[noteIndex],
                    style: labelStyle ??
                        TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: keyColor.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                        ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
