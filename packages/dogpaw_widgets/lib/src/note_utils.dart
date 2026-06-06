/// Utility functions for working with musical notes
class NoteUtils {
  /// Note names using flats
  static const List<String> noteNames = [
    'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'
  ];

  /// Note names with both sharp and flat for display purposes
  static const List<String> dualNoteNames = [
    'C', 'C#/Db', 'D', 'D#/Eb', 'E', 'F', 'F#/Gb', 'G', 'G#/Ab', 'A', 'A#/Bb', 'B'
  ];

  /// Get note name for a given MIDI note number
  static String getNoteName(int midiNote) {
    return noteNames[midiNote % 12];
  }

  /// Get dual note name (with sharps and flats) for a given MIDI note number
  static String getDualNoteName(int midiNote) {
    return dualNoteNames[midiNote % 12];
  }

  /// Check if a note index (0-11) is a black key on a piano
  static bool isBlackKey(int noteIndex) {
    return [1, 3, 6, 8, 10].contains(noteIndex % 12);
  }

  /// Check if a note index (0-11) is a white key on a piano
  static bool isWhiteKey(int noteIndex) {
    return !isBlackKey(noteIndex);
  }
}
