import 'scale.dart';

/// One named scale definition used by editor-facing scale tools.
///
/// Purpose:
/// Captures the stable musical identity of a named scale so multiple UI apps can
/// share the same catalog, detection logic, and pattern generation rules.
class ScaleDefinition {
  /// Human-facing scale name shown in selection UIs.
  final String name;

  /// Semitone offsets from the root note that belong to this scale.
  final List<int> intervals;

  /// Optional legacy enum mapping used by older factory helpers.
  final ScaleType? scaleType;

  /// Whether this definition should appear in the default editor-visible list.
  final bool includeInEditorList;

  /// Create one immutable named scale definition.
  ///
  /// Parameters:
  /// - `name`: Human-facing scale name.
  /// - `intervals`: Semitone offsets from the root that belong to the scale.
  /// - `scaleType`: Optional mapping to the legacy `ScaleType` enum.
  /// - `includeInEditorList`: Whether the definition appears in the default UI list.
  ///
  /// Return value:
  /// - A new immutable `ScaleDefinition`.
  ///
  /// Requirements/Preconditions:
  /// - `intervals` should contain only semitone offsets in `0..11`.
  ///
  /// Guarantees/Postconditions:
  /// - The created definition preserves the provided musical pattern exactly.
  ///
  /// Invariants:
  /// - Definitions are pure metadata and do not contact Epiphany.
  const ScaleDefinition({
    required this.name,
    required this.intervals,
    this.scaleType,
    this.includeInEditorList = true,
  });
}

/// Shared scale catalog and editor-facing scale transformation helpers.
///
/// Purpose:
/// Centralizes scale-name discovery, root transposition, named-scale creation,
/// and note-membership editing so `dogpaw_widgets` and app code can reuse one
/// musical source of truth.
abstract final class ScaleCatalog {
  /// Flat-oriented note names for the twelve semitones.
  static const List<String> noteNames = <String>[
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'Gb',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];

  /// Named scale definitions used by the reusable editor work.
  static const List<ScaleDefinition> definitions = <ScaleDefinition>[
    ScaleDefinition(
      name: 'Major',
      intervals: <int>[0, 2, 4, 5, 7, 9, 11],
      scaleType: ScaleType.major,
    ),
    ScaleDefinition(
      name: 'Minor',
      intervals: <int>[0, 2, 3, 5, 7, 8, 10],
      scaleType: ScaleType.minor,
    ),
    ScaleDefinition(
      name: 'Harmonic Minor',
      intervals: <int>[0, 2, 3, 5, 7, 8, 11],
      scaleType: ScaleType.harmonicMinor,
    ),
    ScaleDefinition(
      name: 'Melodic Minor',
      intervals: <int>[0, 2, 3, 5, 7, 9, 11],
    ),
    ScaleDefinition(
      name: 'Dorian',
      intervals: <int>[0, 2, 3, 5, 7, 9, 10],
      scaleType: ScaleType.dorian,
    ),
    ScaleDefinition(
      name: 'Phrygian',
      intervals: <int>[0, 1, 3, 5, 7, 8, 10],
      scaleType: ScaleType.phrygian,
    ),
    ScaleDefinition(
      name: 'Lydian',
      intervals: <int>[0, 2, 4, 6, 7, 9, 11],
      scaleType: ScaleType.lydian,
    ),
    ScaleDefinition(
      name: 'Mixolydian',
      intervals: <int>[0, 2, 4, 5, 7, 9, 10],
      scaleType: ScaleType.mixolydian,
    ),
    ScaleDefinition(
      name: 'Locrian',
      intervals: <int>[0, 1, 3, 5, 6, 8, 10],
      scaleType: ScaleType.locrian,
    ),
    ScaleDefinition(
      name: 'Major Pentatonic',
      intervals: <int>[0, 2, 4, 7, 9],
      scaleType: ScaleType.majorPent,
    ),
    ScaleDefinition(
      name: 'Minor Pentatonic',
      intervals: <int>[0, 3, 5, 7, 10],
      scaleType: ScaleType.minorPent,
    ),
    ScaleDefinition(
      name: 'Blues',
      intervals: <int>[0, 3, 5, 6, 7, 10],
      scaleType: ScaleType.blues,
    ),
    ScaleDefinition(
      name: 'Whole Tone',
      intervals: <int>[0, 2, 4, 6, 8, 10],
      scaleType: ScaleType.wholeTone,
    ),
    ScaleDefinition(
      name: 'Barry Harris',
      intervals: <int>[0, 2, 4, 5, 7, 8, 9, 11],
      scaleType: ScaleType.barryHarris,
    ),
    ScaleDefinition(
      name: 'Diminished (Half-Whole)',
      intervals: <int>[0, 1, 3, 4, 6, 7, 9, 10],
      scaleType: ScaleType.diminishedHalfWhole,
    ),
    ScaleDefinition(
      name: 'Diminished (Whole-Half)',
      intervals: <int>[0, 2, 3, 5, 6, 8, 9, 11],
      scaleType: ScaleType.diminishedWholeHalf,
    ),
    ScaleDefinition(
      name: 'Chromatic',
      intervals: <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    ),
    ScaleDefinition(
      name: 'Ionian',
      intervals: <int>[0, 2, 4, 5, 7, 9, 11],
      scaleType: ScaleType.ionian,
      includeInEditorList: false,
    ),
    ScaleDefinition(
      name: 'Aeolian',
      intervals: <int>[0, 2, 3, 5, 7, 8, 10],
      scaleType: ScaleType.aeolian,
      includeInEditorList: false,
    ),
  ];

  /// Ordered scale names for the reusable editor, with `Custom` last.
  static List<String> get scaleNames {
    return <String>[
      ...definitions
          .where((ScaleDefinition definition) => definition.includeInEditorList)
          .map((ScaleDefinition definition) => definition.name),
      'Custom',
    ];
  }

  /// Return the visible note name for one root index.
  ///
  /// Parameters:
  /// - `rootNote`: Chromatic note index, normalized mod 12.
  ///
  /// Return value:
  /// - Flat-oriented note name for the normalized root.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The returned note name always comes from the shared 12-note catalog.
  ///
  /// Invariants:
  /// - Does not mutate any scale values.
  static String rootNoteName(int rootNote) {
    return noteNames[_normalizeNoteIndex(rootNote)];
  }

  /// Look up one scale definition by display name.
  ///
  /// Parameters:
  /// - `scaleName`: Human-facing name to search for.
  ///
  /// Return value:
  /// - Matching `ScaleDefinition`, or `null` when absent.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returns the first matching definition from the shared catalog.
  ///
  /// Invariants:
  /// - The shared catalog remains unchanged.
  static ScaleDefinition? definitionByName(String scaleName) {
    for (final ScaleDefinition definition in definitions) {
      if (definition.name == scaleName) {
        return definition;
      }
    }
    return null;
  }

  /// Build one `ScaleData` value from a named scale and root note.
  ///
  /// Parameters:
  /// - `scaleName`: Human-facing scale name to apply.
  /// - `rootNote`: Root note index for the resulting scale.
  /// - `displayName`: Optional explicit display name override.
  ///
  /// Return value:
  /// - A new `ScaleData` matching the requested named scale.
  ///
  /// Requirements/Preconditions:
  /// - `scaleName` must match one non-`Custom` definition in the shared catalog.
  ///
  /// Guarantees/Postconditions:
  /// - The returned scale uses the requested root and named pattern.
  ///
  /// Invariants:
  /// - This helper does not read or write remote state.
  static ScaleData scaleDataForName({
    required String scaleName,
    required int rootNote,
    String? displayName,
  }) {
    final ScaleDefinition? definition = definitionByName(scaleName);
    if (definition == null || scaleName == 'Custom') {
      throw ArgumentError('Unknown named scale: $scaleName');
    }

    final int normalizedRoot = _normalizeNoteIndex(rootNote);
    return ScaleData(
      displayName:
          displayName ?? _displayNameForRootAndScale(normalizedRoot, definition.name),
      rootNote: normalizedRoot,
      noteCategories:
          _patternToCategories(definition.intervals, normalizedRoot),
    );
  }

  /// Detect the current named scale identity for one `ScaleData` value.
  ///
  /// Parameters:
  /// - `scaleData`: Scale value whose note membership should be inspected.
  ///
  /// Return value:
  /// - Matching named scale, or `Custom` when no shared definition matches.
  ///
  /// Requirements/Preconditions:
  /// - `scaleData.noteCategories` should contain at least twelve entries.
  ///
  /// Guarantees/Postconditions:
  /// - Returns one stable label from the shared catalog or `Custom`.
  ///
  /// Invariants:
  /// - Detection is read-only and does not mutate `scaleData`.
  static String detectScaleName(ScaleData scaleData) {
    final List<int> normalizedPattern =
        _categoriesToIntervals(scaleData.noteCategories, scaleData.rootNote);
    for (final ScaleDefinition definition in definitions) {
      if (_listsEqual(normalizedPattern, definition.intervals)) {
        return definition.name;
      }
    }
    return 'Custom';
  }

  /// Move the current root by a semitone delta while preserving the scale shape.
  ///
  /// Parameters:
  /// - `scaleData`: Existing scale value to transpose.
  /// - `deltaSemitones`: Signed semitone offset to apply to the root.
  ///
  /// Return value:
  /// - A new `ScaleData` whose root and included notes have both been rotated.
  ///
  /// Requirements/Preconditions:
  /// - `scaleData.noteCategories` should contain at least twelve entries.
  ///
  /// Guarantees/Postconditions:
  /// - The returned scale preserves the original interval structure relative to
  ///   its new root note.
  ///
  /// Invariants:
  /// - The original `scaleData` remains unchanged.
  static ScaleData transposeRoot(ScaleData scaleData, int deltaSemitones) {
    final int normalizedDelta = _normalizeNoteIndex(deltaSemitones);
    final int nextRoot = _normalizeNoteIndex(scaleData.rootNote + deltaSemitones);
    final List<int> rotatedCategories =
        _rotateRight(_normalizedCategories(scaleData.noteCategories), normalizedDelta);
    return ScaleData(
      displayName: _displayNameForRootAndScale(nextRoot, detectScaleName(ScaleData(
        displayName: scaleData.displayName,
        rootNote: nextRoot,
        noteCategories: rotatedCategories,
      ))),
      rootNote: nextRoot,
      noteCategories: rotatedCategories,
    );
  }

  /// Set the root note directly while preserving the current scale shape.
  ///
  /// Parameters:
  /// - `scaleData`: Existing scale value to retarget.
  /// - `newRootNote`: Absolute chromatic root to assign.
  ///
  /// Return value:
  /// - A new `ScaleData` whose root is `newRootNote`.
  ///
  /// Requirements/Preconditions:
  /// - `scaleData.noteCategories` should contain at least twelve entries.
  ///
  /// Guarantees/Postconditions:
  /// - The returned scale preserves the original interval structure relative to
  ///   the newly assigned root.
  ///
  /// Invariants:
  /// - The original `scaleData` remains unchanged.
  static ScaleData setRootNote(ScaleData scaleData, int newRootNote) {
    final int delta = _normalizeNoteIndex(newRootNote - scaleData.rootNote);
    return transposeRoot(scaleData, delta);
  }

  /// Toggle one non-root note between included and out-of-scale states.
  ///
  /// Parameters:
  /// - `scaleData`: Existing scale value to edit.
  /// - `noteIndex`: Absolute chromatic note index to toggle.
  ///
  /// Return value:
  /// - A new `ScaleData` with the requested note toggled.
  ///
  /// Requirements/Preconditions:
  /// - `scaleData.noteCategories` should contain at least twelve entries.
  ///
  /// Guarantees/Postconditions:
  /// - Root-note membership is preserved even when `noteIndex` points at the root.
  /// - Non-root notes toggle between `1` and `-1`.
  ///
  /// Invariants:
  /// - The original `scaleData` remains unchanged.
  static ScaleData toggleIncludedNote(ScaleData scaleData, int noteIndex) {
    final int normalizedIndex = _normalizeNoteIndex(noteIndex);
    final List<int> categories = _normalizedCategories(scaleData.noteCategories);
    if (normalizedIndex != scaleData.rootNote) {
      categories[normalizedIndex] =
          isIncluded(scaleData, normalizedIndex) ? -1 : 1;
    }

    final ScaleData nextValue = ScaleData(
      displayName: scaleData.displayName,
      rootNote: scaleData.rootNote,
      noteCategories: categories,
    );

    return ScaleData(
      displayName: _displayNameForRootAndScale(
        nextValue.rootNote,
        detectScaleName(nextValue),
      ),
      rootNote: nextValue.rootNote,
      noteCategories: nextValue.noteCategories,
    );
  }

  /// Report whether one absolute note index is the current root.
  ///
  /// Parameters:
  /// - `scaleData`: Scale value being inspected.
  /// - `noteIndex`: Absolute chromatic note index to inspect.
  ///
  /// Return value:
  /// - `true` when `noteIndex` matches `scaleData.rootNote`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Result is normalized mod 12.
  ///
  /// Invariants:
  /// - This helper is read-only.
  static bool isRoot(ScaleData scaleData, int noteIndex) {
    return _normalizeNoteIndex(noteIndex) == _normalizeNoteIndex(scaleData.rootNote);
  }

  /// Report whether one absolute note index belongs to the current scale.
  ///
  /// Parameters:
  /// - `scaleData`: Scale value being inspected.
  /// - `noteIndex`: Absolute chromatic note index to inspect.
  ///
  /// Return value:
  /// - `true` when the note is treated as in-scale.
  ///
  /// Requirements/Preconditions:
  /// - `scaleData.noteCategories` should contain at least twelve entries.
  ///
  /// Guarantees/Postconditions:
  /// - Positive legacy category values are treated as included notes.
  ///
  /// Invariants:
  /// - This helper is read-only.
  static bool isIncluded(ScaleData scaleData, int noteIndex) {
    final int normalizedIndex = _normalizeNoteIndex(noteIndex);
    final List<int> categories = _normalizedCategories(scaleData.noteCategories);
    return categories[normalizedIndex] > 0;
  }

  /// Normalize one scale category array to a fixed 12-note list.
  ///
  /// Parameters:
  /// - `categories`: Possibly short or oversized note-category list.
  ///
  /// Return value:
  /// - A 12-element category list suitable for editor logic.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Missing elements are filled with `-1`.
  ///
  /// Invariants:
  /// - The input list remains unchanged.
  static List<int> _normalizedCategories(List<int> categories) {
    final List<int> normalized = List<int>.filled(12, -1);
    for (int index = 0; index < normalized.length && index < categories.length; index++) {
      normalized[index] = categories[index];
    }
    return normalized;
  }

  /// Build one category list from a root-relative interval pattern.
  ///
  /// Parameters:
  /// - `intervals`: Semitone offsets from the root that belong to the scale.
  /// - `rootNote`: Absolute chromatic root note.
  ///
  /// Return value:
  /// - A 12-element category list using `1` for included notes and `-1` for others.
  ///
  /// Requirements/Preconditions:
  /// - `intervals` should contain only semitone offsets in `0..11`.
  ///
  /// Guarantees/Postconditions:
  /// - Every interval listed in `intervals` becomes an included note.
  ///
  /// Invariants:
  /// - The helper does not mutate shared definition metadata.
  static List<int> _patternToCategories(List<int> intervals, int rootNote) {
    final List<int> categories = List<int>.filled(12, -1);
    for (final int interval in intervals) {
      categories[_normalizeNoteIndex(rootNote + interval)] = 1;
    }
    return categories;
  }

  /// Convert one category list back into root-relative interval offsets.
  ///
  /// Parameters:
  /// - `categories`: Category list to inspect.
  /// - `rootNote`: Root note used to normalize the pattern.
  ///
  /// Return value:
  /// - Sorted semitone offsets from the root that are considered in-scale.
  ///
  /// Requirements/Preconditions:
  /// - `categories` should describe a 12-note chromatic octave.
  ///
  /// Guarantees/Postconditions:
  /// - Positive category values are treated as included notes.
  ///
  /// Invariants:
  /// - The input list remains unchanged.
  static List<int> _categoriesToIntervals(List<int> categories, int rootNote) {
    final List<int> normalized = _normalizedCategories(categories);
    final List<int> intervals = <int>[];
    for (int noteIndex = 0; noteIndex < normalized.length; noteIndex++) {
      if (normalized[noteIndex] > 0) {
        intervals.add(_normalizeNoteIndex(noteIndex - rootNote));
      }
    }
    intervals.sort();
    return intervals;
  }

  /// Rotate a 12-note list to the right by one normalized offset.
  ///
  /// Parameters:
  /// - `values`: 12-note chromatic list to rotate.
  /// - `positions`: Signed offset to apply.
  ///
  /// Return value:
  /// - Rotated copy of `values`.
  ///
  /// Requirements/Preconditions:
  /// - `values` should contain at least one element.
  ///
  /// Guarantees/Postconditions:
  /// - Rotation is normalized mod the list length.
  ///
  /// Invariants:
  /// - The input list remains unchanged.
  static List<int> _rotateRight(List<int> values, int positions) {
    if (values.isEmpty) {
      return values;
    }
    final int normalizedPositions = positions % values.length;
    if (normalizedPositions == 0) {
      return List<int>.from(values);
    }
    return <int>[
      ...values.sublist(values.length - normalizedPositions),
      ...values.sublist(0, values.length - normalizedPositions),
    ];
  }

  /// Compare two integer lists for exact equality.
  ///
  /// Parameters:
  /// - `left`: First list to compare.
  /// - `right`: Second list to compare.
  ///
  /// Return value:
  /// - `true` when the lists have identical lengths and elements.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Comparison is deterministic and order-sensitive.
  ///
  /// Invariants:
  /// - Neither list is mutated.
  static bool _listsEqual(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  /// Normalize one chromatic note index into the `0..11` range.
  ///
  /// Parameters:
  /// - `noteIndex`: Arbitrary signed note index.
  ///
  /// Return value:
  /// - Equivalent chromatic index in `0..11`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Negative values wrap correctly into the chromatic octave.
  ///
  /// Invariants:
  /// - Pure arithmetic helper with no side effects.
  static int _normalizeNoteIndex(int noteIndex) {
    final int normalized = noteIndex % 12;
    return normalized < 0 ? normalized + 12 : normalized;
  }

  /// Build the default musician-facing display name for one scale value.
  ///
  /// Parameters:
  /// - `rootNote`: Root note used in the display label.
  /// - `scaleName`: Named scale identity or `Custom`.
  ///
  /// Return value:
  /// - Combined display label in the form `<Root> <Scale Name>`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The returned string always uses the shared flat-oriented root names.
  ///
  /// Invariants:
  /// - String generation does not mutate any scale state.
  static String _displayNameForRootAndScale(int rootNote, String scaleName) {
    return '${rootNoteName(rootNote)} $scaleName';
  }
}
