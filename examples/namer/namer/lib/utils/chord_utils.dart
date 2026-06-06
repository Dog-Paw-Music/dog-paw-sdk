import 'package:dogpaw/dogpaw.dart';

/// Utilities for chord detection and naming
class ChordUtils {
  /// Chord flavor names
  static const List<String> chordFlavors = [
    'Major',
    'Minor',
    'Diminished',
    'Augmented',
    'Dominant 7th',
    'Major 7th',
    'Minor 7th',
    'Half-diminished 7th',
    'Diminished 7th',
    'sus2',
    'sus4',
  ];

  /// Chord patterns: Map from flavor to intervals from root (in semitones)
  static const Map<String, List<int>> chordPatterns = {
    'Major': [0, 4, 7], // Root, Major 3rd, Perfect 5th
    'Minor': [0, 3, 7], // Root, Minor 3rd, Perfect 5th
    'Diminished': [0, 3, 6], // Root, Minor 3rd, Diminished 5th
    'Augmented': [0, 4, 8], // Root, Major 3rd, Augmented 5th
    'Dominant 7th': [0, 4, 7, 10], // Root, Major 3rd, Perfect 5th, Minor 7th (dominant 7th)
    'Major 7th': [0, 4, 7, 11], // Root, Major 3rd, Perfect 5th, Major 7th
    'Minor 7th': [0, 3, 7, 10], // Root, Minor 3rd, Perfect 5th, Minor 7th
    'Half-diminished 7th': [0, 3, 6, 10], // Root, Minor 3rd, Diminished 5th, Minor 7th
    'Diminished 7th': [0, 3, 6, 9], // Root, Minor 3rd, Diminished 5th, Diminished 7th
    'sus2': [0, 2, 7], // Root, Major 2nd, Perfect 5th
    'sus4': [0, 5, 7], // Root, Perfect 4th, Perfect 5th
  };

  /// Detect chord from a set of MIDI note values.
  /// Returns (rootNoteName, chordFlavor, bassNoteName) or null if no match.
  /// bassNoteName is the lowest note, used for slash chord notation if it's not the root.
  static (String, String, String?)? detectChord(Set<int> noteValues) {
    AppLogger.info('Namer: Detecting chord from note values: $noteValues');
    if (noteValues.isEmpty) return null;
    if (noteValues.length == 1) {
      final note = noteValues.first;
      return (_noteNames[note % 12], 'Major', null);
    }

    // Get note classes (0-11) from MIDI values
    final noteClasses = noteValues.map((n) => n % 12).toSet();

    // Find the lowest note for slash chord notation
    final lowestNote = noteValues.reduce((a, b) => a < b ? a : b);
    final lowestNoteClass = lowestNote % 12;

    // Try each note class as a potential root
    for (final rootClass in noteClasses) {
      // Check each chord pattern
      for (final entry in chordPatterns.entries) {
        final flavor = entry.key;
        final pattern = entry.value;

        // Convert pattern to expected note classes relative to this root
        final expectedNotes = pattern.map((interval) => (rootClass + interval) % 12).toSet();

        // Check if the held notes match this pattern
        if (noteClasses.containsAll(expectedNotes) && expectedNotes.containsAll(noteClasses)) {
          final rootName = _noteNames[rootClass];

          // Check if it's an inversion (lowest note is not the root)
          String? bassName;
          if (lowestNoteClass != rootClass) {
            bassName = _noteNames[lowestNoteClass];
          }

          return (rootName, flavor, bassName);
        }
      }
    }

    // No match found
    return null;
  }

  /// Format chord name in standard notation
  static String formatChordStandard(String root, String flavor, String? bass) {
    String chordName;

    switch (flavor) {
      case 'Major':
        chordName = root;
        break;
      case 'Minor':
        chordName = '${root}min';
        break;
      case 'Diminished':
        chordName = '${root}dim';
        break;
      case 'Augmented':
        chordName = '${root}aug';
        break;
      case 'Dominant 7th':
        chordName = '${root}7';
        break;
      case 'Major 7th':
        chordName = '${root}maj7';
        break;
      case 'Minor 7th':
        chordName = '${root}min7';
        break;
      case 'Half-diminished 7th':
        chordName = '${root}half-dim7';
        break;
      case 'Diminished 7th':
        chordName = '${root}dim7';
        break;
      case 'sus2':
        chordName = '${root}sus2';
        break;
      case 'sus4':
        chordName = '${root}sus4';
        break;
      default:
        chordName = root;
    }

    // Add slash chord notation if bass is different
    if (bass != null && bass != root) {
      chordName = '$chordName/$bass';
    }

    return chordName;
  }

  /// Format chord name in jazz notation
  static String formatChordJazz(String root, String flavor, String? bass) {
    String chordName;

    switch (flavor) {
      case 'Major':
        chordName = root;
        break;
      case 'Minor':
        chordName = '$root-'; // Minus sign for minor
        break;
      case 'Diminished':
        chordName = '$root°'; // Circle for diminished
        break;
      case 'Augmented':
        chordName = '$root+'; // Plus for augmented
        break;
      case 'Dominant 7th':
        chordName = '${root}7';
        break;
      case 'Major 7th':
        chordName = '$root△7';
        break;
      case 'Minor 7th':
        chordName = '$root-7';
        break;
      case 'Half-diminished 7th':
        chordName = '$rootø7';
        break;
      case 'Diminished 7th':
        chordName = '$root°7';
        break;
      case 'sus2':
        chordName = '${root}sus2';
        break;
      case 'sus4':
        chordName = '${root}sus4';
        break;
      default:
        chordName = root;
    }

    // Add slash chord notation if bass is different
    if (bass != null && bass != root) {
      chordName = '$chordName/$bass';
    }

    return chordName;
  }

  /// Format chord using the specified naming scheme
  static String formatChord(String root, String flavor, String? bass, bool useJazzNotation) {
    return useJazzNotation ? formatChordJazz(root, flavor, bass) : formatChordStandard(root, flavor, bass);
  }

  /// Note names
  static const List<String> _noteNames = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];

  /// Get note name for a MIDI note value
  static String getNoteName(int midiNote) {
    return _noteNames[midiNote % 12];
  }

  /// Get the note class (0-11) for a note name
  static int? getNoteClass(String noteName) {
    return _noteNames.indexOf(noteName);
  }
}
