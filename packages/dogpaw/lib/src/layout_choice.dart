import 'data_types.dart';
import 'data_reference.dart';
import 'json_constants.dart';
import 'scale.dart';
import 'system_shared_theme_scale.dart';
import 'theme.dart';

/// Purpose:
/// Describes which layout-owned source is currently active for theme or scale
/// selection.
///
/// `shared` means the layout follows the shared system value. `overrideValue`
/// means the layout uses its own saved override payload.
enum LayoutChoiceActiveSource {
  shared,
  overrideValue,
}

/// Purpose:
/// Editable and persisted theme-selection contract for a layout.
///
/// Parameters:
/// - `activeSource`: whether the layout currently follows the shared theme or a
///   saved override theme.
/// - `overrideTheme`: saved override theme data, retained even when
///   `activeSource` is `shared`.
///
/// Return value:
/// - Immutable layout theme-choice value.
///
/// Requirements/Preconditions:
/// - `overrideTheme` should be non-null when `activeSource` is `overrideValue`.
///
/// Guarantees/Postconditions:
/// - The choice can convert itself to the active `DataReference<Theme>`.
///
/// Invariants:
/// - Construction performs no I/O.
class LayoutThemeChoice {
  final LayoutChoiceActiveSource activeSource;
  final ThemeData? overrideTheme;

  const LayoutThemeChoice._({
    required this.activeSource,
    required this.overrideTheme,
  });

  const LayoutThemeChoice.shared({
    this.overrideTheme,
  }) : activeSource = LayoutChoiceActiveSource.shared;

  const LayoutThemeChoice.overrideValue(
    ThemeData overrideTheme,
  ) : this._(
          activeSource: LayoutChoiceActiveSource.overrideValue,
          overrideTheme: overrideTheme,
        );

  /// Purpose:
  /// Convert this editable theme choice into the active layout data reference.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Active `DataReference<Theme>` for layout serialization and preview.
  ///
  /// Requirements/Preconditions:
  /// - `overrideTheme` should be present when `activeSource` is
  ///   `overrideValue`.
  ///
  /// Guarantees/Postconditions:
  /// - Shared mode maps to the named `System/shared_theme` reference.
  /// - Override mode maps to an inline `Theme` payload.
  ///
  /// Invariants:
  /// - Conversion is pure.
  DataReference<Theme> toDataReference() {
    if (activeSource == LayoutChoiceActiveSource.overrideValue &&
        overrideTheme != null) {
      return DataReference<Theme>.inline(
        Theme(
          name: 'inline_theme',
          spec: overrideTheme!,
        ),
      );
    }
    return sharedThemeDataReference();
  }

  /// Purpose:
  /// Restore a layout theme choice from an existing data reference contract.
  ///
  /// Parameters:
  /// - `reference`: active theme reference to reinterpret as a choice.
  ///
  /// Return value:
  /// - Parsed layout theme choice that matches the active reference.
  ///
  /// Requirements/Preconditions:
  /// - `reference` should describe either a current/shared theme or an inline
  ///   theme payload.
  ///
  /// Guarantees/Postconditions:
  /// - Inline references become active overrides.
  /// - All other references fall back to shared mode.
  ///
  /// Invariants:
  /// - Parsing is pure and performs no I/O.
  factory LayoutThemeChoice.fromDataReference(DataReference<Theme> reference) {
    if (reference.type == ReferenceType.inline &&
        reference.inlineData?.spec != null) {
      return LayoutThemeChoice.overrideValue(reference.inlineData!.spec!);
    }
    return const LayoutThemeChoice.shared();
  }

  /// Purpose:
  /// Clone this theme choice while overriding only the requested fields.
  ///
  /// Parameters:
  /// - `activeSource`: replacement active source.
  /// - `overrideTheme`: replacement saved override theme.
  ///
  /// Return value:
  /// - New immutable `LayoutThemeChoice`.
  ///
  /// Requirements/Preconditions:
  /// - Any provided values should satisfy the same expectations as the
  ///   constructors.
  ///
  /// Guarantees/Postconditions:
  /// - Unspecified fields keep their current values.
  ///
  /// Invariants:
  /// - This instance remains unchanged.
  LayoutThemeChoice copyWith({
    LayoutChoiceActiveSource? activeSource,
    ThemeData? overrideTheme,
    bool clearOverrideTheme = false,
  }) {
    return LayoutThemeChoice._(
      activeSource: activeSource ?? this.activeSource,
      overrideTheme:
          clearOverrideTheme ? null : (overrideTheme ?? this.overrideTheme),
    );
  }

  /// Purpose:
  /// Serialize this theme choice for layout persistence.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - JSON-ready map containing the active source and optional override theme.
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
      JsonFields.ACTIVE_SOURCE: _jsonSourceName(activeSource),
      if (overrideTheme != null)
        JsonFields.OVERRIDE_THEME: overrideTheme!.toJson(),
    };
  }

  /// Purpose:
  /// Restore a serialized theme choice from JSON.
  ///
  /// Parameters:
  /// - `json`: serialized layout theme-choice map.
  ///
  /// Return value:
  /// - Parsed immutable `LayoutThemeChoice`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should match the format produced by `toJson()`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing or invalid sources fall back to shared mode.
  ///
  /// Invariants:
  /// - Parsing performs no I/O.
  factory LayoutThemeChoice.fromJson(Map<String, dynamic> json) {
    final LayoutChoiceActiveSource source =
        _activeSourceFromJson(json[JsonFields.ACTIVE_SOURCE] as String?);
    final ThemeData? overrideTheme =
        json[JsonFields.OVERRIDE_THEME] is Map<String, dynamic>
            ? ThemeData.fromJson(
                json[JsonFields.OVERRIDE_THEME] as Map<String, dynamic>,
              )
            : null;
    if (source == LayoutChoiceActiveSource.overrideValue &&
        overrideTheme != null) {
      return LayoutThemeChoice.overrideValue(overrideTheme);
    }
    return LayoutThemeChoice.shared(overrideTheme: overrideTheme);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LayoutThemeChoice &&
            other.activeSource == activeSource &&
            other.overrideTheme == overrideTheme;
  }

  @override
  int get hashCode => Object.hash(activeSource, overrideTheme);
}

/// Purpose:
/// Editable and persisted scale-selection contract for a layout.
///
/// Parameters:
/// - `activeSource`: whether the layout currently follows the shared scale or a
///   saved override scale.
/// - `overrideScale`: saved override scale data, retained even when
///   `activeSource` is `shared`.
///
/// Return value:
/// - Immutable layout scale-choice value.
///
/// Requirements/Preconditions:
/// - `overrideScale` should be non-null when `activeSource` is `overrideValue`.
///
/// Guarantees/Postconditions:
/// - The choice can convert itself to the active `DataReference<Scale>`.
///
/// Invariants:
/// - Construction performs no I/O.
class LayoutScaleChoice {
  final LayoutChoiceActiveSource activeSource;
  final ScaleData? overrideScale;

  const LayoutScaleChoice._({
    required this.activeSource,
    required this.overrideScale,
  });

  const LayoutScaleChoice.shared({
    this.overrideScale,
  }) : activeSource = LayoutChoiceActiveSource.shared;

  const LayoutScaleChoice.overrideValue(
    ScaleData overrideScale,
  ) : this._(
          activeSource: LayoutChoiceActiveSource.overrideValue,
          overrideScale: overrideScale,
        );

  /// Purpose:
  /// Convert this editable scale choice into the active layout data reference.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Active `DataReference<Scale>` for layout serialization and preview.
  ///
  /// Requirements/Preconditions:
  /// - `overrideScale` should be present when `activeSource` is
  ///   `overrideValue`.
  ///
  /// Guarantees/Postconditions:
  /// - Shared mode maps to the named `System/shared_scale` reference.
  /// - Override mode maps to an inline `Scale` payload.
  ///
  /// Invariants:
  /// - Conversion is pure.
  DataReference<Scale> toDataReference() {
    if (activeSource == LayoutChoiceActiveSource.overrideValue &&
        overrideScale != null) {
      return DataReference<Scale>.inline(
        Scale(
          name: 'inline_scale',
          spec: overrideScale!,
        ),
      );
    }
    return sharedScaleDataReference();
  }

  /// Purpose:
  /// Restore a layout scale choice from an existing data reference contract.
  ///
  /// Parameters:
  /// - `reference`: active scale reference to reinterpret as a choice.
  ///
  /// Return value:
  /// - Parsed layout scale choice that matches the active reference.
  ///
  /// Requirements/Preconditions:
  /// - `reference` should describe either a current/shared scale or an inline
  ///   scale payload.
  ///
  /// Guarantees/Postconditions:
  /// - Inline references become active overrides.
  /// - All other references fall back to shared mode.
  ///
  /// Invariants:
  /// - Parsing is pure and performs no I/O.
  factory LayoutScaleChoice.fromDataReference(DataReference<Scale> reference) {
    if (reference.type == ReferenceType.inline &&
        reference.inlineData?.spec != null) {
      return LayoutScaleChoice.overrideValue(reference.inlineData!.spec!);
    }
    return const LayoutScaleChoice.shared();
  }

  /// Purpose:
  /// Clone this scale choice while overriding only the requested fields.
  ///
  /// Parameters:
  /// - `activeSource`: replacement active source.
  /// - `overrideScale`: replacement saved override scale.
  ///
  /// Return value:
  /// - New immutable `LayoutScaleChoice`.
  ///
  /// Requirements/Preconditions:
  /// - Any provided values should satisfy the same expectations as the
  ///   constructors.
  ///
  /// Guarantees/Postconditions:
  /// - Unspecified fields keep their current values.
  ///
  /// Invariants:
  /// - This instance remains unchanged.
  LayoutScaleChoice copyWith({
    LayoutChoiceActiveSource? activeSource,
    ScaleData? overrideScale,
    bool clearOverrideScale = false,
  }) {
    return LayoutScaleChoice._(
      activeSource: activeSource ?? this.activeSource,
      overrideScale:
          clearOverrideScale ? null : (overrideScale ?? this.overrideScale),
    );
  }

  /// Purpose:
  /// Serialize this scale choice for layout persistence.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - JSON-ready map containing the active source and optional override scale.
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
      JsonFields.ACTIVE_SOURCE: _jsonSourceName(activeSource),
      if (overrideScale != null)
        JsonFields.OVERRIDE_SCALE: overrideScale!.toJson(),
    };
  }

  /// Purpose:
  /// Restore a serialized scale choice from JSON.
  ///
  /// Parameters:
  /// - `json`: serialized layout scale-choice map.
  ///
  /// Return value:
  /// - Parsed immutable `LayoutScaleChoice`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should match the format produced by `toJson()`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing or invalid sources fall back to shared mode.
  ///
  /// Invariants:
  /// - Parsing performs no I/O.
  factory LayoutScaleChoice.fromJson(Map<String, dynamic> json) {
    final LayoutChoiceActiveSource source =
        _activeSourceFromJson(json[JsonFields.ACTIVE_SOURCE] as String?);
    final ScaleData? overrideScale =
        json[JsonFields.OVERRIDE_SCALE] is Map<String, dynamic>
            ? ScaleData.fromJson(
                json[JsonFields.OVERRIDE_SCALE] as Map<String, dynamic>,
              )
            : null;
    if (source == LayoutChoiceActiveSource.overrideValue &&
        overrideScale != null) {
      return LayoutScaleChoice.overrideValue(overrideScale);
    }
    return LayoutScaleChoice.shared(overrideScale: overrideScale);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LayoutScaleChoice &&
            other.activeSource == activeSource &&
            other.overrideScale == overrideScale;
  }

  @override
  int get hashCode => Object.hash(activeSource, overrideScale);
}

/// Purpose:
/// Convert one active-source enum into its persisted JSON string.
///
/// Parameters:
/// - `source`: active source enum value to serialize.
///
/// Return value:
/// - Persisted JSON string for the supplied source.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Shared maps to `"shared"` and override maps to `"override"`.
///
/// Invariants:
/// - This helper is pure.
String _jsonSourceName(LayoutChoiceActiveSource source) {
  return source == LayoutChoiceActiveSource.overrideValue
      ? JsonFields.ACTIVE_SOURCE_OVERRIDE
      : JsonFields.ACTIVE_SOURCE_SHARED;
}

/// Purpose:
/// Parse one persisted active-source string into the shared enum.
///
/// Parameters:
/// - `sourceName`: serialized active-source string from layout JSON.
///
/// Return value:
/// - Parsed enum value, or `shared` when the input is missing or invalid.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Unknown values safely fall back to `shared`.
///
/// Invariants:
/// - This helper is pure.
LayoutChoiceActiveSource _activeSourceFromJson(String? sourceName) {
  if (sourceName == JsonFields.ACTIVE_SOURCE_OVERRIDE) {
    return LayoutChoiceActiveSource.overrideValue;
  }
  return LayoutChoiceActiveSource.shared;
}
