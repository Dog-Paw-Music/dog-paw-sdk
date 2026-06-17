import 'dart:collection';

import 'data_reference.dart';
import 'json_constants.dart';
import 'layout.dart';
import 'scale.dart';
import 'theme.dart';

/// Purpose:
/// Shared immutable musical grid settings used to generate interval-based layout
/// data for Dog Paw layouts.
///
/// Parameters:
/// - `layoutMode`: `'scale'` uses scale degrees; `'chromatic'` uses semitones.
/// - `rowInterval`: interval added per row movement.
/// - `columnInterval`: interval added per column movement.
/// - `rowIntervalUp`: whether larger row indices move upward in pitch.
/// - `columnIntervalRight`: whether larger column indices move upward in pitch.
/// - `octaveTranspose`: octave offset applied to the generated grid.
/// - `semitoneTranspose`: semitone offset applied before octave placement.
/// - `bendRange`: stored for parity with existing app-owned settings models.
///
/// Return value:
/// - Immutable value object describing one interval-grid layout recipe.
///
/// Requirements/Preconditions:
/// - `layoutMode` should be `'scale'` or `'chromatic'`.
///
/// Guarantees/Postconditions:
/// - Instances are immutable and safe to reuse across builders and widgets.
///
/// Invariants:
/// - Construction performs no I/O.
class LayoutSettings {
  final String layoutMode;
  final int rowInterval;
  final int columnInterval;
  final bool rowIntervalUp;
  final bool columnIntervalRight;
  final int octaveTranspose;
  final int semitoneTranspose;
  final int bendRange;

  const LayoutSettings({
    this.layoutMode = 'scale',
    this.rowInterval = 3,
    this.columnInterval = 1,
    this.rowIntervalUp = true,
    this.columnIntervalRight = true,
    this.octaveTranspose = 0,
    this.semitoneTranspose = 0,
    this.bendRange = 1,
  });

  /// Purpose:
  /// Clone these settings while overriding only the requested fields.
  ///
  /// Parameters:
  /// - Each optional parameter replaces the current field when provided.
  ///
  /// Return value:
  /// - New immutable `LayoutSettings` instance.
  ///
  /// Requirements/Preconditions:
  /// - Any supplied values should satisfy the same expectations as the
  ///   constructor.
  ///
  /// Guarantees/Postconditions:
  /// - Unspecified fields keep their current values.
  ///
  /// Invariants:
  /// - This instance remains unchanged.
  LayoutSettings copyWith({
    String? layoutMode,
    int? rowInterval,
    int? columnInterval,
    bool? rowIntervalUp,
    bool? columnIntervalRight,
    int? octaveTranspose,
    int? semitoneTranspose,
    int? bendRange,
  }) {
    return LayoutSettings(
      layoutMode: layoutMode ?? this.layoutMode,
      rowInterval: rowInterval ?? this.rowInterval,
      columnInterval: columnInterval ?? this.columnInterval,
      rowIntervalUp: rowIntervalUp ?? this.rowIntervalUp,
      columnIntervalRight: columnIntervalRight ?? this.columnIntervalRight,
      octaveTranspose: octaveTranspose ?? this.octaveTranspose,
      semitoneTranspose: semitoneTranspose ?? this.semitoneTranspose,
      bendRange: bendRange ?? this.bendRange,
    );
  }

  /// Purpose:
  /// Serialize these settings for app-owned persistence.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - JSON-ready map preserving the stored fields.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returned JSON round-trips through `fromJson`.
  ///
  /// Invariants:
  /// - Serialization is pure.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'layoutMode': layoutMode,
      'rowInterval': rowInterval,
      'columnInterval': columnInterval,
      'rowIntervalUp': rowIntervalUp,
      'columnIntervalRight': columnIntervalRight,
      'octaveTranspose': octaveTranspose,
      'semitoneTranspose': semitoneTranspose,
      'bendRange': bendRange,
    };
  }

  /// Purpose:
  /// Restore layout settings from app-owned JSON.
  ///
  /// Parameters:
  /// - `json`: persisted layout-settings map.
  ///
  /// Return value:
  /// - Parsed immutable `LayoutSettings`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should contain the fields written by `toJson`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing fields fall back to constructor defaults.
  ///
  /// Invariants:
  /// - Parsing performs no I/O.
  factory LayoutSettings.fromJson(Map<String, dynamic> json) {
    return LayoutSettings(
      layoutMode: json['layoutMode'] as String? ?? 'scale',
      rowInterval: json['rowInterval'] as int? ?? 3,
      columnInterval: json['columnInterval'] as int? ?? 1,
      rowIntervalUp: json['rowIntervalUp'] as bool? ?? true,
      columnIntervalRight: json['columnIntervalRight'] as bool? ?? true,
      octaveTranspose: json['octaveTranspose'] as int? ?? 0,
      semitoneTranspose: json['semitoneTranspose'] as int? ?? 0,
      bendRange: json['bendRange'] as int? ?? 1,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LayoutSettings &&
            other.layoutMode == layoutMode &&
            other.rowInterval == rowInterval &&
            other.columnInterval == columnInterval &&
            other.rowIntervalUp == rowIntervalUp &&
            other.columnIntervalRight == columnIntervalRight &&
            other.octaveTranspose == octaveTranspose &&
            other.semitoneTranspose == semitoneTranspose &&
            other.bendRange == bendRange;
  }

  @override
  int get hashCode {
    return Object.hash(
      layoutMode,
      rowInterval,
      columnInterval,
      rowIntervalUp,
      columnIntervalRight,
      octaveTranspose,
      semitoneTranspose,
      bendRange,
    );
  }

  @override
  String toString() {
    return 'LayoutSettings('
        'layoutMode: $layoutMode, '
        'rowInterval: $rowInterval, '
        'columnInterval: $columnInterval, '
        'rowIntervalUp: $rowIntervalUp, '
        'columnIntervalRight: $columnIntervalRight, '
        'octaveTranspose: $octaveTranspose, '
        'semitoneTranspose: $semitoneTranspose, '
        'bendRange: $bendRange)';
  }
}

/// Purpose:
/// Inclusive bounds describing which keys of the 8x8 Dog Paw grid should be
/// emitted by shared layout-generation helpers.
///
/// Parameters:
/// - `startColumn`, `endColumn`: inclusive column range in `[0, 7]`.
/// - `startRow`, `endRow`: inclusive row range in `[0, 7]`.
///
/// Return value:
/// - Immutable rectangle descriptor for layout generation.
///
/// Requirements/Preconditions:
/// - Start values should be less than or equal to end values.
///
/// Guarantees/Postconditions:
/// - Bounds can be reused across builders and tests without mutation.
///
/// Invariants:
/// - Construction performs no clamping or I/O.
class LayoutGridBounds {
  final int startColumn;
  final int endColumn;
  final int startRow;
  final int endRow;

  const LayoutGridBounds({
    required this.startColumn,
    required this.endColumn,
    required this.startRow,
    required this.endRow,
  });

  const LayoutGridBounds.fullGrid()
      : startColumn = 0,
        endColumn = 7,
        startRow = 0,
        endRow = 7;
}

/// Purpose:
/// Immutable layout ownership metadata used when generating one `LayoutData`
/// object.
///
/// Parameters:
/// - `scope`: `'shared'` or `'targeted'`.
/// - `targetKey`: consumer-facing target key when `scope` is `'targeted'`.
///
/// Return value:
/// - Immutable layout scope descriptor.
///
/// Requirements/Preconditions:
/// - `targetKey` should be non-empty when `scope` is `'targeted'`.
///
/// Guarantees/Postconditions:
/// - Scope metadata can be copied directly onto `LayoutData`.
///
/// Invariants:
/// - Construction performs no I/O.
class LayoutScopeSettings {
  final String scope;
  final String? targetKey;

  const LayoutScopeSettings._({
    required this.scope,
    required this.targetKey,
  });

  const LayoutScopeSettings.shared() : this._(scope: 'shared', targetKey: null);

  const LayoutScopeSettings.targeted(String targetKey)
      : this._(scope: 'targeted', targetKey: targetKey);

  /// Purpose:
  /// Serialize this scope selection for app-owned draft persistence.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - JSON-ready map containing `scope` and optional `targetKey`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returned JSON round-trips through `fromJson`.
  ///
  /// Invariants:
  /// - Serialization is pure.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.SCOPE: scope,
      JsonFields.TARGET_KEY: targetKey,
    }..removeWhere((String key, dynamic value) => value == null);
  }

  /// Purpose:
  /// Restore layout scope metadata from app-owned JSON.
  ///
  /// Parameters:
  /// - `json`: persisted scope selection map.
  ///
  /// Return value:
  /// - Parsed immutable `LayoutScopeSettings`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should contain a `scope` string written by `toJson`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing fields fall back to the shared scope defaults.
  ///
  /// Invariants:
  /// - Parsing performs no I/O.
  factory LayoutScopeSettings.fromJson(Map<String, dynamic> json) {
    final String scope = json[JsonFields.SCOPE] as String? ?? 'shared';
    final String? targetKey = json[JsonFields.TARGET_KEY] as String?;
    if (scope == 'targeted' && targetKey != null && targetKey.isNotEmpty) {
      return LayoutScopeSettings.targeted(targetKey);
    }
    return const LayoutScopeSettings.shared();
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LayoutScopeSettings &&
            other.scope == scope &&
            other.targetKey == targetKey;
  }

  @override
  int get hashCode => Object.hash(scope, targetKey);
}

/// Purpose:
/// One reusable color value that can be expressed either as a theme role or as
/// a literal RGBA color string.
///
/// Parameters:
/// - `themeRole`: Dog Paw theme role such as `'primary'`.
/// - `rgba`: literal color in `rgba(r,g,b,a)` form.
///
/// Return value:
/// - Immutable color-spec fragment ready for `ColorSpec` JSON generation.
///
/// Requirements/Preconditions:
/// - Exactly one representation should be set for valid output.
///
/// Guarantees/Postconditions:
/// - `toJson()` returns JSON accepted by existing ColorSpec parsing.
///
/// Invariants:
/// - Construction performs no I/O.
class LayoutColorValue {
  final String? themeRole;
  final String? rgba;

  const LayoutColorValue._({
    required this.themeRole,
    required this.rgba,
  });

  const LayoutColorValue.themeRole(String themeRole)
      : this._(themeRole: themeRole, rgba: null);

  const LayoutColorValue.rgba(String rgba)
      : this._(themeRole: null, rgba: rgba);

  /// Purpose:
  /// Serialize this color value into a ColorSpec-compatible JSON fragment.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Theme-role string or `{ "rgba": ... }` map.
  ///
  /// Requirements/Preconditions:
  /// - At least one representation was provided at construction time.
  ///
  /// Guarantees/Postconditions:
  /// - Returned JSON can be embedded inside note/category maps.
  ///
  /// Invariants:
  /// - Serialization is pure.
  dynamic toJson() {
    if (themeRole != null) {
      return themeRole;
    }
    if (rgba != null) {
      return <String, dynamic>{JsonFields.RGBA: rgba};
    }
    return null;
  }

  /// Purpose:
  /// Parse one serialized color value from draft JSON.
  ///
  /// Parameters:
  /// - `json`: theme-role string or `{ "rgba": ... }` object.
  ///
  /// Return value:
  /// - Parsed immutable `LayoutColorValue`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should match the format produced by `toJson()`.
  ///
  /// Guarantees/Postconditions:
  /// - Valid theme-role strings restore as theme-role values.
  /// - Valid `rgba` maps restore as literal color values.
  ///
  /// Invariants:
  /// - Parsing performs no I/O.
  factory LayoutColorValue.fromJson(dynamic json) {
    if (json is String) {
      return LayoutColorValue.themeRole(json);
    }
    if (json is Map && json[JsonFields.RGBA] is String) {
      return LayoutColorValue.rgba(json[JsonFields.RGBA] as String);
    }
    throw ArgumentError('Unsupported LayoutColorValue JSON: $json');
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LayoutColorValue &&
            other.themeRole == themeRole &&
            other.rgba == rgba;
  }

  @override
  int get hashCode => Object.hash(themeRole, rgba);
}

/// Purpose:
/// Shared key-color generation strategy for interval-grid layout builders.
///
/// Parameters:
/// - For `scaleCategories`: root/in-scale/out-of-scale color values.
/// - For `noteNumberMap`: explicit chromatic note-color mapping.
///
/// Return value:
/// - Immutable strategy value consumed by `generateLayoutKeyColors`.
///
/// Requirements/Preconditions:
/// - `noteNumberColors` keys should be note numbers in the chromatic octave.
///
/// Guarantees/Postconditions:
/// - Strategy carries no resolved colors, only generation intent.
///
/// Invariants:
/// - Construction performs no I/O.
class LayoutColorStrategy {
  final String _kind;
  final LayoutColorValue rootColor;
  final LayoutColorValue inScaleColor;
  final LayoutColorValue outOfScaleColor;
  final Map<int, LayoutColorValue> noteNumberColors;

  const LayoutColorStrategy._({
    required String kind,
    required this.rootColor,
    required this.inScaleColor,
    required this.outOfScaleColor,
    required this.noteNumberColors,
  }) : _kind = kind;

  const LayoutColorStrategy.scaleCategories({
    this.rootColor = const LayoutColorValue.themeRole('primary'),
    this.inScaleColor = const LayoutColorValue.themeRole('secondary'),
    this.outOfScaleColor = const LayoutColorValue.themeRole('background'),
  })  : _kind = 'scaleCategories',
        noteNumberColors = const <int, LayoutColorValue>{};

  factory LayoutColorStrategy.noteNumberMap(
    Map<int, LayoutColorValue> noteNumberColors,
  ) {
    return LayoutColorStrategy._(
      kind: 'noteNumberMap',
      rootColor: const LayoutColorValue.themeRole('primary'),
      inScaleColor: const LayoutColorValue.themeRole('secondary'),
      outOfScaleColor: const LayoutColorValue.themeRole('background'),
      noteNumberColors: UnmodifiableMapView<int, LayoutColorValue>(
        Map<int, LayoutColorValue>.from(noteNumberColors),
      ),
    );
  }

  /// Purpose:
  /// Serialize this color strategy for app-owned draft persistence.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - JSON-ready map preserving the strategy kind and associated color values.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returned JSON round-trips through `fromJson`.
  ///
  /// Invariants:
  /// - Serialization is pure.
  Map<String, dynamic> toJson() {
    if (_kind == 'noteNumberMap') {
      return <String, dynamic>{
        'kind': _kind,
        JsonFields.NOTE_NUMBER_MAP: <String, dynamic>{
          for (final MapEntry<int, LayoutColorValue> entry
              in noteNumberColors.entries)
            '${entry.key}': entry.value.toJson(),
        },
      };
    }

    return <String, dynamic>{
      'kind': _kind,
      'rootColor': rootColor.toJson(),
      'inScaleColor': inScaleColor.toJson(),
      'outOfScaleColor': outOfScaleColor.toJson(),
    };
  }

  /// Purpose:
  /// Parse one serialized color strategy from app-owned draft JSON.
  ///
  /// Parameters:
  /// - `json`: persisted color-strategy map.
  ///
  /// Return value:
  /// - Parsed immutable `LayoutColorStrategy`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should match the format produced by `toJson()`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing or unknown kinds fall back to the shared scale-category colors.
  ///
  /// Invariants:
  /// - Parsing performs no I/O.
  factory LayoutColorStrategy.fromJson(Map<String, dynamic> json) {
    final String kind = json['kind'] as String? ?? 'scaleCategories';
    if (kind == 'noteNumberMap') {
      final Map<String, dynamic> rawNoteNumberMap = Map<String, dynamic>.from(
        json[JsonFields.NOTE_NUMBER_MAP] as Map? ?? const <String, dynamic>{},
      );
      return LayoutColorStrategy.noteNumberMap(<int, LayoutColorValue>{
        for (final MapEntry<String, dynamic> entry in rawNoteNumberMap.entries)
          int.parse(entry.key): LayoutColorValue.fromJson(entry.value),
      });
    }

    return LayoutColorStrategy.scaleCategories(
      rootColor: LayoutColorValue.fromJson(
        json['rootColor'] ?? const LayoutColorValue.themeRole('primary').toJson(),
      ),
      inScaleColor: LayoutColorValue.fromJson(
        json['inScaleColor'] ??
            const LayoutColorValue.themeRole('secondary').toJson(),
      ),
      outOfScaleColor: LayoutColorValue.fromJson(
        json['outOfScaleColor'] ??
            const LayoutColorValue.themeRole('background').toJson(),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LayoutColorStrategy &&
            other._kind == _kind &&
            other.rootColor == rootColor &&
            other.inScaleColor == inScaleColor &&
            other.outOfScaleColor == outOfScaleColor &&
            _layoutColorValueMapsEqual(other.noteNumberColors, noteNumberColors);
  }

  @override
  int get hashCode {
    return Object.hash(
      _kind,
      rootColor,
      inScaleColor,
      outOfScaleColor,
      Object.hashAll(
        noteNumberColors.entries
            .map((MapEntry<int, LayoutColorValue> entry) => Object.hash(entry.key, entry.value)),
      ),
    );
  }
}

/// Purpose:
/// Compare two note-number color maps for logical equality.
///
/// Parameters:
/// - `a`: first immutable note-number color map.
/// - `b`: second immutable note-number color map.
///
/// Return value:
/// - `true` when both maps contain the same keys and color values.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Map order does not affect the result.
///
/// Invariants:
/// - This helper is pure.
bool _layoutColorValueMapsEqual(
  Map<int, LayoutColorValue> a,
  Map<int, LayoutColorValue> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<int, LayoutColorValue> entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// Purpose:
/// Generate interval-grid key intents for one bounded rectangle of the Dog Paw
/// 8x8 surface.
///
/// Parameters:
/// - `settings`: immutable musical grid settings.
/// - `bounds`: inclusive rectangle of keys to emit; defaults to the full grid.
///
/// Return value:
/// - Key-intent map keyed by `"column,row"` with one `midiNote` intent per key.
///
/// Requirements/Preconditions:
/// - `bounds` should describe a valid rectangle inside the 8x8 grid.
///
/// Guarantees/Postconditions:
/// - Output contains only keys inside `bounds`.
/// - Each emitted key contains exactly one note intent.
/// - The lowest generated note stays anchored to the edge implied by the
///   effective signed row and column intervals.
///
/// Invariants:
/// - This helper is pure.
Map<String, List<Map<String, dynamic>>> generateIntervalGridKeyIntents(
  LayoutSettings settings, {
  LayoutGridBounds bounds = const LayoutGridBounds.fullGrid(),
}) {
  final Map<String, List<Map<String, dynamic>>> keyIntents =
      <String, List<Map<String, dynamic>>>{};
  final int baseOctave = 3 + settings.octaveTranspose;
  final int baseSemitoneOffset = settings.semitoneTranspose;
  final int effectiveColumnInterval =
      settings.columnIntervalRight ? settings.columnInterval : -settings.columnInterval;
  final int effectiveRowInterval =
      settings.rowIntervalUp ? settings.rowInterval : -settings.rowInterval;
  final int lowestNoteColumn = effectiveColumnInterval >= 0 ? 0 : 7;
  final int lowestNoteRow = effectiveRowInterval >= 0 ? 0 : 7;

  for (int column = bounds.startColumn; column <= bounds.endColumn; column += 1) {
    for (int row = bounds.startRow; row <= bounds.endRow; row += 1) {
      final int columnDistanceFromLowestNote = column - lowestNoteColumn;
      final int rowDistanceFromLowestNote = row - lowestNoteRow;
      final int offset = columnDistanceFromLowestNote * effectiveColumnInterval +
          rowDistanceFromLowestNote * effectiveRowInterval;

      final Map<String, dynamic> intent = <String, dynamic>{
        JsonFields.INTENT: JsonFields.MIDI_NOTE,
        JsonFields.OCTAVE: baseOctave,
      };
      if (settings.layoutMode == 'scale') {
        intent[JsonFields.SCALE_DEGREES_FROM_ROOT] =
            offset + baseSemitoneOffset;
      } else {
        intent[JsonFields.SEMITONES_FROM_ROOT] = offset + baseSemitoneOffset;
      }

      keyIntents['$column,$row'] = <Map<String, dynamic>>[intent];
    }
  }

  return keyIntents;
}

/// Purpose:
/// Generate a `keyColors` JSON fragment from one shared layout-color strategy.
///
/// Parameters:
/// - `strategy`: immutable color-generation strategy.
///
/// Return value:
/// - JSON-ready `keyColors` map suitable for `LayoutData.keyColors`.
///
/// Requirements/Preconditions:
/// - `strategy` should contain at least one valid color mapping.
///
/// Guarantees/Postconditions:
/// - The returned structure uses existing ColorSpec wire formats.
///
/// Invariants:
/// - This helper is pure.
Map<String, dynamic> generateLayoutKeyColors(LayoutColorStrategy strategy) {
  if (strategy._kind == 'noteNumberMap') {
    final Map<String, dynamic> noteNumberMap = <String, dynamic>{};
    for (final MapEntry<int, LayoutColorValue> entry
        in strategy.noteNumberColors.entries) {
      noteNumberMap['${entry.key}'] = entry.value.toJson();
    }
    return <String, dynamic>{JsonFields.NOTE_NUMBER_MAP: noteNumberMap};
  }

  return <String, dynamic>{
    JsonFields.NOTE_CATEGORY_MAP: <String, dynamic>{
      '-1': strategy.outOfScaleColor.toJson(),
      '1': strategy.inScaleColor.toJson(),
      '3': strategy.rootColor.toJson(),
    },
  };
}

/// Purpose:
/// Build one reusable `LayoutData` object from interval-grid settings, scope,
/// color strategy, and theme/scale references.
///
/// Parameters:
/// - `displayName`: human-facing layout display name.
/// - `settings`: immutable musical grid settings.
/// - `scope`: layout ownership metadata.
/// - `bounds`: inclusive grid rectangle to emit.
/// - `colorStrategy`: key-color generation strategy.
/// - `themeRef`: theme reference to embed; defaults to current theme.
/// - `scaleRef`: scale reference to embed; defaults to current scale.
///
/// Return value:
/// - Fully populated `LayoutData`.
///
/// Requirements/Preconditions:
/// - `displayName` should be appropriate for the owner UI.
///
/// Guarantees/Postconditions:
/// - Returned layout data is ready for serialization or preview.
///
/// Invariants:
/// - This helper is pure and does not mutate shared state.
LayoutData buildIntervalGridLayoutData({
  required String displayName,
  required LayoutSettings settings,
  LayoutScopeSettings scope = const LayoutScopeSettings.shared(),
  LayoutGridBounds bounds = const LayoutGridBounds.fullGrid(),
  LayoutColorStrategy colorStrategy = const LayoutColorStrategy.scaleCategories(),
  DataReference<Theme>? themeRef,
  DataReference<Scale>? scaleRef,
}) {
  return LayoutData(
    displayName: displayName,
    scope: scope.scope,
    targetKey: scope.targetKey,
    keyIntents: generateIntervalGridKeyIntents(settings, bounds: bounds),
    keyColors: generateLayoutKeyColors(colorStrategy),
    themeRef: themeRef ?? DataReference<Theme>.current(),
    scaleRef: scaleRef ?? DataReference<Scale>.current(),
  );
}
