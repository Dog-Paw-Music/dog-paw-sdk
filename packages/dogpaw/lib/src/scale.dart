import 'data_item_type.dart';
import 'json_constants.dart';
import 'json_utils.dart';
import 'namespace_selector.dart';

/// Musical scale definition data
class ScaleData {
  /// Human-readable name (optional, distinct from ID)
  final String? displayName;

  /// Root note (0-11, C=0)
  final int rootNote;

  /// Category for each semitone (-1=out of scale, 0=placeholder, 1=in scale, 2=passing)
  final List<int> noteCategories;

  const ScaleData({
    this.displayName,
    required this.rootNote,
    required this.noteCategories,
  });

  Map<String, dynamic> toJson() => {
        JsonFields.DISPLAY_NAME: displayName,
        JsonFields.ROOT_NOTE: rootNote,
        JsonFields.NOTE_CATEGORIES: noteCategories,
      }.toJsonClean();

  factory ScaleData.fromJson(Map<String, dynamic> json) => ScaleData(
        displayName: json[JsonFields.DISPLAY_NAME],
        rootNote: json[JsonFields.ROOT_NOTE] ?? 0,
        noteCategories: List<int>.from(
            json[JsonFields.NOTE_CATEGORIES] ?? List.filled(12, 0)),
      );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ScaleData &&
            other.displayName == displayName &&
            other.rootNote == rootNote &&
            _listEquals(other.noteCategories, noteCategories);
  }

  @override
  int get hashCode => Object.hash(
        displayName,
        rootNote,
        Object.hashAll(noteCategories),
      );
}

/// Purpose:
/// Compare two integer lists for element-wise equality.
///
/// Parameters:
/// - `a`: first integer list.
/// - `b`: second integer list.
///
/// Return value:
/// - `true` when both lists contain the same values in the same order.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - List lengths and all corresponding elements are checked.
///
/// Invariants:
/// - This helper is pure.
bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

/// Scale type enum for convenience factory method
enum ScaleType {
  major,
  majorPent,
  minor,
  minorPent,
  blues,
  ionian,
  dorian,
  phrygian,
  lydian,
  mixolydian,
  aeolian,
  locrian,
  barryHarris,
  wholeTone,
  diminishedHalfWhole,
  diminishedWholeHalf,
  harmonicMinor,
}

/// Scale class
class Scale extends DataItemType<ScaleData> {
  Scale({
    required super.name,
    required ScaleData spec,
    super.namespaceSelector,
  }) : super(
          spec: spec,
        );

  Scale.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(ScaleData data) => data.toJson();

  /// Purpose:
  /// Restore a `Scale` from either the full Epiphany item wrapper or a bare
  /// inline scale-data payload.
  ///
  /// Parameters:
  /// - `json`: serialized scale object or bare scale spec/resolved map.
  ///
  /// Return value:
  /// - Parsed immutable `Scale`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should contain either item-level fields such as `name` and
  ///   `namespaceSelector`, or bare scale-data fields such as `rootNote` and
  ///   `noteCategories`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing `namespaceSelector` falls back to `currentEntity`.
  /// - Bare scale-data payloads are treated as inline spec data.
  ///
  /// Invariants:
  /// - Parsing is pure and performs no I/O.
  factory Scale.fromJson(Map<String, dynamic> json) {
    final String name = json[JsonFields.NAME] as String? ?? '';
    final dynamic namespaceSelectorJson = json[JsonFields.NAMESPACE_SELECTOR];
    final NamespaceSelector namespaceSelector =
        namespaceSelectorJson is Map<String, dynamic>
            ? NamespaceSelector.fromJson(namespaceSelectorJson)
            : const NamespaceSelector.currentEntity();
    final bool hasWrappedData =
        json.containsKey(JsonFields.SPEC) || json.containsKey(JsonFields.RESOLVED);

    ScaleData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = ScaleData.fromJson(json[JsonFields.SPEC] as Map<String, dynamic>);
    } else if (!hasWrappedData) {
      spec = ScaleData.fromJson(json);
    }

    ScaleData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved =
          ScaleData.fromJson(json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    return Scale.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );
  }

  // Convenience accessors for scale-specific data
  String? get displayName => spec?.displayName ?? resolved?.displayName;
  int? get rootNote => spec?.rootNote ?? resolved?.rootNote;
  List<int>? get noteCategories =>
      spec?.noteCategories ?? resolved?.noteCategories;

  /// Note name to chromatic position mapping (C=0, C#=1, etc.)
  static const Map<String, int> _noteNameToNumber = {
    'C': 0,
    'C#': 1,
    'Db': 1,
    'D': 2,
    'D#': 3,
    'Eb': 3,
    'E': 4,
    'F': 5,
    'F#': 6,
    'Gb': 6,
    'G': 7,
    'G#': 8,
    'Ab': 8,
    'A': 9,
    'A#': 10,
    'Bb': 10,
    'B': 11,
  };

  /// Create a scale from a root note name and scale type.
  ///
  /// Convenience factory method that automatically sets the root note, display name,
  /// and note categories based on the provided key and scale type.
  ///
  /// Supports major/minor scales, pentatonics, blues, all 7 jazz modes, Barry Harris,
  /// whole tone, diminished scales, and harmonic minor.
  ///
  /// @param name Unique identifier for the scale
  /// @param rootNoteName Root note name (e.g., "C", "Db", "F#")
  /// @param type Scale type (major, minor, blues, dorian, lydian, etc.)
  /// @param displayName Optional custom display name (defaults to "rootNoteName typeName")
  /// @return Scale with properly configured root note, display name, and categories
  /// @throws ArgumentError if rootNoteName is invalid
  ///
  /// Example: Scale.fromKey('myScale', 'Db', ScaleType.dorian)
  ///          creates a scale named "myScale" with display name "Db Dorian"
  factory Scale.fromKey(
    String name,
    String rootNoteName, {
    ScaleType type = ScaleType.major,
    String? displayName,
  }) {
    final rootNote = _noteNameToNumber[rootNoteName];
    if (rootNote == null) {
      throw ArgumentError('Invalid root note name: $rootNoteName');
    }

    // Define scale intervals (semitones from root) and display names
    List<int> intervals;
    String typeName;

    switch (type) {
      case ScaleType.major:
        intervals = [0, 2, 4, 5, 7, 9, 11]; // W-W-H-W-W-W-H pattern
        typeName = 'Major';
        break;
      case ScaleType.majorPent:
        intervals = [0, 2, 4, 7, 9]; // Major pentatonic: 1-2-3-5-6
        typeName = 'Major Pentatonic';
        break;
      case ScaleType.minor:
        intervals = [
          0,
          2,
          3,
          5,
          7,
          8,
          10
        ]; // W-H-W-W-H-W-W pattern (natural minor)
        typeName = 'Minor';
        break;
      case ScaleType.minorPent:
        intervals = [0, 3, 5, 7, 10]; // Minor pentatonic: 1-b3-4-5-b7
        typeName = 'Minor Pentatonic';
        break;
      case ScaleType.blues:
        intervals = [0, 3, 5, 6, 7, 10]; // Minor pentatonic + b5
        typeName = 'Blues';
        break;
      case ScaleType.ionian:
        intervals = [0, 2, 4, 5, 7, 9, 11]; // Same as major
        typeName = 'Ionian';
        break;
      case ScaleType.dorian:
        intervals = [0, 2, 3, 5, 7, 9, 10]; // Minor with raised 6th
        typeName = 'Dorian';
        break;
      case ScaleType.phrygian:
        intervals = [0, 1, 3, 5, 7, 8, 10]; // Minor with lowered 2nd
        typeName = 'Phrygian';
        break;
      case ScaleType.lydian:
        intervals = [0, 2, 4, 6, 7, 9, 11]; // Major with raised 4th
        typeName = 'Lydian';
        break;
      case ScaleType.mixolydian:
        intervals = [0, 2, 4, 5, 7, 9, 10]; // Major with lowered 7th
        typeName = 'Mixolydian';
        break;
      case ScaleType.aeolian:
        intervals = [0, 2, 3, 5, 7, 8, 10]; // Natural minor (same as minor)
        typeName = 'Aeolian';
        break;
      case ScaleType.locrian:
        intervals = [0, 1, 3, 5, 6, 8, 10]; // Minor with lowered 2nd and 5th
        typeName = 'Locrian';
        break;
      case ScaleType.barryHarris:
        intervals = [0, 2, 4, 5, 7, 8, 9, 11]; // Major with added b6 (8 notes)
        typeName = 'Barry Harris';
        break;
      case ScaleType.wholeTone:
        intervals = [0, 2, 4, 6, 8, 10]; // All whole steps (6 notes)
        typeName = 'Whole Tone';
        break;
      case ScaleType.diminishedHalfWhole:
        intervals = [0, 1, 3, 4, 6, 7, 9, 10]; // Half-whole pattern (8 notes)
        typeName = 'Diminished (Half-Whole)';
        break;
      case ScaleType.diminishedWholeHalf:
        intervals = [0, 2, 3, 5, 6, 8, 9, 11]; // Whole-half pattern (8 notes)
        typeName = 'Diminished (Whole-Half)';
        break;
      case ScaleType.harmonicMinor:
        intervals = [0, 2, 3, 5, 7, 8, 11]; // Minor with raised 7th
        typeName = 'Harmonic Minor';
        break;
    }

    // Calculate noteCategories: 1=in scale, -1=out of scale
    final noteCategories = List<int>.filled(12, -1);
    for (final interval in intervals) {
      final position = (rootNote + interval) % 12;
      noteCategories[position] = 1; // Mark as in scale
    }

    final display = displayName ?? '$rootNoteName $typeName';

    return Scale(
      name: name,
      spec: ScaleData(
        displayName: display,
        rootNote: rootNote,
        noteCategories: noteCategories,
      ),
    );
  }
}
