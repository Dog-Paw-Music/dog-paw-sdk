// Unit tests for Scale.fromKey factory method.
//
// These tests require no external dependencies (no Epiphany server).
// They test pure Dart logic that can run entirely in isolation.
//
// RUN WITH: flutter test test/unit/scale_factory_test.dart
// (not dart test - this package depends on Flutter)
//
// NOTE: These tests mirror the C++ equivalent tests in
// dogPawEntity/tests/gtest/unit/ScaleFactoryTests.cpp
import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

void main() {
  // Helper to check if a note is in the scale (category >= 0)
  bool isInScale(List<int> categories, int note) {
    return categories[note % 12] >= 0;
  }

  // Helper to count notes in scale
  int countNotesInScale(List<int> categories) {
    return categories.where((cat) => cat >= 0).length;
  }

  group('Basic Key Name Parsing', () {
    test('CMajorHasCorrectRootNote', () {
      final scale = Scale.fromKey('c_major', 'C', type: ScaleType.major);
      expect(scale.rootNote, equals(0));
    });

    test('DMajorHasCorrectRootNote', () {
      final scale = Scale.fromKey('d_major', 'D', type: ScaleType.major);
      expect(scale.rootNote, equals(2));
    });

    test('SharpNotesParsedCorrectly', () {
      final fSharp = Scale.fromKey('fs_major', 'F#', type: ScaleType.major);
      expect(fSharp.rootNote, equals(6));

      final cSharp = Scale.fromKey('cs_major', 'C#', type: ScaleType.major);
      expect(cSharp.rootNote, equals(1));

      final gSharp = Scale.fromKey('gs_major', 'G#', type: ScaleType.major);
      expect(gSharp.rootNote, equals(8));
    });

    test('FlatNotesParsedCorrectly', () {
      final db = Scale.fromKey('db_major', 'Db', type: ScaleType.major);
      expect(db.rootNote, equals(1));

      final bb = Scale.fromKey('bb_major', 'Bb', type: ScaleType.major);
      expect(bb.rootNote, equals(10));

      final eb = Scale.fromKey('eb_major', 'Eb', type: ScaleType.major);
      expect(eb.rootNote, equals(3));
    });

    test('InvalidNoteNameThrows', () {
      expect(() => Scale.fromKey('invalid', 'H', type: ScaleType.major), throwsArgumentError);
      expect(() => Scale.fromKey('invalid', 'X', type: ScaleType.major), throwsArgumentError);
      expect(() => Scale.fromKey('invalid', '', type: ScaleType.major), throwsArgumentError);
    });
  });

  group('Display Name Generation', () {
    test('MajorScaleGeneratesCorrectDisplayName', () {
      final scale = Scale.fromKey('c_major', 'C', type: ScaleType.major);
      expect(scale.displayName, equals('C Major'));
    });

    test('SharpDisplayNameFormatted', () {
      final scale = Scale.fromKey('fs_major', 'F#', type: ScaleType.major);
      expect(scale.displayName, equals('F# Major'));
    });

    test('FlatDisplayNameFormatted', () {
      final scale = Scale.fromKey('db_major', 'Db', type: ScaleType.major);
      expect(scale.displayName, equals('Db Major'));
    });

    test('CustomDisplayNameOverride', () {
      final scale = Scale.fromKey('custom', 'G', type: ScaleType.major, displayName: 'My Custom Scale');
      expect(scale.displayName, equals('My Custom Scale'));
    });

    test('PentatonicDisplayName', () {
      final scale = Scale.fromKey('a_pent', 'A', type: ScaleType.majorPent);
      expect(scale.displayName, equals('A Major Pentatonic'));
    });
  });

  group('Major Scale Intervals (W-W-H-W-W-W-H)', () {
    test('CMajorHasCorrectIntervals', () {
      final scale = Scale.fromKey('c_major', 'C', type: ScaleType.major);
      final categories = scale.noteCategories!;

      // C Major: C D E F G A B (0, 2, 4, 5, 7, 9, 11)
      expect(isInScale(categories, 0), isTrue);   // C
      expect(isInScale(categories, 1), isFalse);  // C#
      expect(isInScale(categories, 2), isTrue);   // D
      expect(isInScale(categories, 3), isFalse);  // D#
      expect(isInScale(categories, 4), isTrue);   // E
      expect(isInScale(categories, 5), isTrue);   // F
      expect(isInScale(categories, 6), isFalse);  // F#
      expect(isInScale(categories, 7), isTrue);   // G
      expect(isInScale(categories, 8), isFalse);  // G#
      expect(isInScale(categories, 9), isTrue);   // A
      expect(isInScale(categories, 10), isFalse); // A#
      expect(isInScale(categories, 11), isTrue);  // B

      expect(countNotesInScale(categories), equals(7));
    });

    test('GMajorHasCorrectIntervals', () {
      final scale = Scale.fromKey('g_major', 'G', type: ScaleType.major);
      final categories = scale.noteCategories!;

      // G Major: G A B C D E F# (7, 9, 11, 0, 2, 4, 6)
      expect(isInScale(categories, 7), isTrue);   // G (root)
      expect(isInScale(categories, 9), isTrue);   // A
      expect(isInScale(categories, 11), isTrue);  // B
      expect(isInScale(categories, 0), isTrue);   // C
      expect(isInScale(categories, 2), isTrue);   // D
      expect(isInScale(categories, 4), isTrue);   // E
      expect(isInScale(categories, 6), isTrue);   // F#

      expect(countNotesInScale(categories), equals(7));
    });
  });

  group('Major Pentatonic Scale (5 notes)', () {
    test('MajorPentatonicHasFiveNotes', () {
      final scale = Scale.fromKey('c_pent', 'C', type: ScaleType.majorPent);
      final categories = scale.noteCategories!;

      // C Major Pentatonic: C D E G A (0, 2, 4, 7, 9)
      expect(isInScale(categories, 0), isTrue);   // C
      expect(isInScale(categories, 2), isTrue);   // D
      expect(isInScale(categories, 4), isTrue);   // E
      expect(isInScale(categories, 7), isTrue);   // G
      expect(isInScale(categories, 9), isTrue);   // A

      expect(countNotesInScale(categories), equals(5));
    });
  });

  group('Dorian Mode', () {
    test('DorianModeHasCorrectIntervals', () {
      final scale = Scale.fromKey('d_dorian', 'D', type: ScaleType.dorian);
      final categories = scale.noteCategories!;

      // D Dorian: D E F G A B C (same notes as C major, but rooted on D)
      // Intervals: W-H-W-W-W-H-W
      expect(isInScale(categories, 2), isTrue);   // D (root)
      expect(isInScale(categories, 4), isTrue);   // E
      expect(isInScale(categories, 5), isTrue);   // F
      expect(isInScale(categories, 7), isTrue);   // G
      expect(isInScale(categories, 9), isTrue);   // A
      expect(isInScale(categories, 11), isTrue);  // B
      expect(isInScale(categories, 0), isTrue);   // C

      expect(countNotesInScale(categories), equals(7));
    });
  });

  group('Default Scale Type', () {
    test('DefaultsToMajorScale', () {
      final scale = Scale.fromKey('e_default', 'E');
      expect(scale.displayName, equals('E Major'));
      expect(countNotesInScale(scale.noteCategories!), equals(7));
    });
  });

  group('Name Assignment', () {
    test('NameIsAssignedCorrectly', () {
      final scale = Scale.fromKey('my_scale_name', 'C', type: ScaleType.major);
      expect(scale.name, equals('my_scale_name'));
    });
  });
}
