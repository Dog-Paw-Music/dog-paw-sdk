import 'data_reference.dart';
import 'json_constants.dart';
import 'layout.dart';
import 'layout_builder.dart';
import 'scale.dart';
import 'theme.dart';

/// Purpose:
/// Describes whether a reusable layout editor is using the current shared item or
/// an inline embedded value for one referenced data type.
enum LayoutDraftReferenceMode {
  current,
  inline,
}

/// Purpose:
/// Editable theme selection owned by a `LayoutDraft`.
///
/// Parameters:
/// - `mode`: whether the layout should use the current theme or an inline theme.
/// - `inlineTheme`: inline theme value when `mode` is `inline`.
///
/// Return value:
/// - Immutable theme-choice value for layout editing.
///
/// Requirements/Preconditions:
/// - `inlineTheme` should be non-null when `mode` is `inline`.
///
/// Guarantees/Postconditions:
/// - The choice can convert itself to a `DataReference<Theme>`.
///
/// Invariants:
/// - Construction performs no I/O.
class LayoutThemeChoice {
  final LayoutDraftReferenceMode mode;
  final ThemeData? inlineTheme;

  const LayoutThemeChoice._({
    required this.mode,
    required this.inlineTheme,
  });

  const LayoutThemeChoice.current()
      : this._(
          mode: LayoutDraftReferenceMode.current,
          inlineTheme: null,
        );

  const LayoutThemeChoice.inline(ThemeData inlineTheme)
      : this._(
          mode: LayoutDraftReferenceMode.inline,
          inlineTheme: inlineTheme,
        );

  /// Purpose:
  /// Convert this editable theme choice into a persisted layout data reference.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - `DataReference<Theme>` suitable for `LayoutData.themeRef`.
  ///
  /// Requirements/Preconditions:
  /// - `inlineTheme` should be present when `mode` is `inline`.
  ///
  /// Guarantees/Postconditions:
  /// - Current mode maps to `DataReference.current()`.
  /// - Inline mode maps to an inline `Theme` payload.
  ///
  /// Invariants:
  /// - Conversion is pure.
  DataReference<Theme> toDataReference() {
    if (mode == LayoutDraftReferenceMode.inline && inlineTheme != null) {
      return DataReference<Theme>.inline(
        Theme(
          name: 'inline_theme',
          spec: inlineTheme!,
        ),
      );
    }
    return DataReference<Theme>.current();
  }

  /// Purpose:
  /// Clone this theme choice while overriding only the requested fields.
  ///
  /// Parameters:
  /// - `mode`: replacement reference mode.
  /// - `inlineTheme`: replacement inline theme.
  ///
  /// Return value:
  /// - New immutable `LayoutThemeChoice`.
  ///
  /// Requirements/Preconditions:
  /// - Any provided values should satisfy the same expectations as the
  ///   constructor.
  ///
  /// Guarantees/Postconditions:
  /// - Unspecified fields keep their current values.
  ///
  /// Invariants:
  /// - This instance remains unchanged.
  LayoutThemeChoice copyWith({
    LayoutDraftReferenceMode? mode,
    ThemeData? inlineTheme,
  }) {
    final LayoutDraftReferenceMode nextMode = mode ?? this.mode;
    return LayoutThemeChoice._(
      mode: nextMode,
      inlineTheme: nextMode == LayoutDraftReferenceMode.inline
          ? (inlineTheme ?? this.inlineTheme)
          : null,
    );
  }

  /// Purpose:
  /// Serialize this theme choice for draft persistence.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - JSON-ready map containing the mode and optional inline theme.
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
      JsonFields.REF_TYPE: mode.name,
      if (inlineTheme != null) JsonFields.REF_DATA: inlineTheme!.toJson(),
    };
  }

  /// Purpose:
  /// Restore a serialized theme choice from app-owned JSON.
  ///
  /// Parameters:
  /// - `json`: persisted theme-choice map.
  ///
  /// Return value:
  /// - Parsed immutable `LayoutThemeChoice`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should match the format produced by `toJson()`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing or invalid modes fall back to the current-theme choice.
  ///
  /// Invariants:
  /// - Parsing performs no I/O.
  factory LayoutThemeChoice.fromJson(Map<String, dynamic> json) {
    final String modeName = json[JsonFields.REF_TYPE] as String? ?? 'current';
    if (modeName == LayoutDraftReferenceMode.inline.name &&
        json[JsonFields.REF_DATA] is Map<String, dynamic>) {
      return LayoutThemeChoice.inline(
        ThemeData.fromJson(
          json[JsonFields.REF_DATA] as Map<String, dynamic>,
        ),
      );
    }
    return const LayoutThemeChoice.current();
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LayoutThemeChoice &&
            other.mode == mode &&
            other.inlineTheme == inlineTheme;
  }

  @override
  int get hashCode => Object.hash(mode, inlineTheme);
}

/// Purpose:
/// Editable scale selection owned by a `LayoutDraft`.
///
/// Parameters:
/// - `mode`: whether the layout should use the current scale or an inline scale.
/// - `inlineScale`: inline scale value when `mode` is `inline`.
///
/// Return value:
/// - Immutable scale-choice value for layout editing.
///
/// Requirements/Preconditions:
/// - `inlineScale` should be non-null when `mode` is `inline`.
///
/// Guarantees/Postconditions:
/// - The choice can convert itself to a `DataReference<Scale>`.
///
/// Invariants:
/// - Construction performs no I/O.
class LayoutScaleChoice {
  final LayoutDraftReferenceMode mode;
  final ScaleData? inlineScale;

  const LayoutScaleChoice._({
    required this.mode,
    required this.inlineScale,
  });

  const LayoutScaleChoice.current()
      : this._(
          mode: LayoutDraftReferenceMode.current,
          inlineScale: null,
        );

  const LayoutScaleChoice.inline(ScaleData inlineScale)
      : this._(
          mode: LayoutDraftReferenceMode.inline,
          inlineScale: inlineScale,
        );

  /// Purpose:
  /// Convert this editable scale choice into a persisted layout data reference.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - `DataReference<Scale>` suitable for `LayoutData.scaleRef`.
  ///
  /// Requirements/Preconditions:
  /// - `inlineScale` should be present when `mode` is `inline`.
  ///
  /// Guarantees/Postconditions:
  /// - Current mode maps to `DataReference.current()`.
  /// - Inline mode maps to an inline `Scale` payload.
  ///
  /// Invariants:
  /// - Conversion is pure.
  DataReference<Scale> toDataReference() {
    if (mode == LayoutDraftReferenceMode.inline && inlineScale != null) {
      return DataReference<Scale>.inline(
        Scale(
          name: 'inline_scale',
          spec: inlineScale!,
        ),
      );
    }
    return DataReference<Scale>.current();
  }

  /// Purpose:
  /// Clone this scale choice while overriding only the requested fields.
  ///
  /// Parameters:
  /// - `mode`: replacement reference mode.
  /// - `inlineScale`: replacement inline scale.
  ///
  /// Return value:
  /// - New immutable `LayoutScaleChoice`.
  ///
  /// Requirements/Preconditions:
  /// - Any provided values should satisfy the same expectations as the
  ///   constructor.
  ///
  /// Guarantees/Postconditions:
  /// - Unspecified fields keep their current values.
  ///
  /// Invariants:
  /// - This instance remains unchanged.
  LayoutScaleChoice copyWith({
    LayoutDraftReferenceMode? mode,
    ScaleData? inlineScale,
  }) {
    final LayoutDraftReferenceMode nextMode = mode ?? this.mode;
    return LayoutScaleChoice._(
      mode: nextMode,
      inlineScale: nextMode == LayoutDraftReferenceMode.inline
          ? (inlineScale ?? this.inlineScale)
          : null,
    );
  }

  /// Purpose:
  /// Serialize this scale choice for draft persistence.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - JSON-ready map containing the mode and optional inline scale.
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
      JsonFields.REF_TYPE: mode.name,
      if (inlineScale != null) JsonFields.REF_DATA: inlineScale!.toJson(),
    };
  }

  /// Purpose:
  /// Restore a serialized scale choice from app-owned JSON.
  ///
  /// Parameters:
  /// - `json`: persisted scale-choice map.
  ///
  /// Return value:
  /// - Parsed immutable `LayoutScaleChoice`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should match the format produced by `toJson()`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing or invalid modes fall back to the current-scale choice.
  ///
  /// Invariants:
  /// - Parsing performs no I/O.
  factory LayoutScaleChoice.fromJson(Map<String, dynamic> json) {
    final String modeName = json[JsonFields.REF_TYPE] as String? ?? 'current';
    if (modeName == LayoutDraftReferenceMode.inline.name &&
        json[JsonFields.REF_DATA] is Map<String, dynamic>) {
      return LayoutScaleChoice.inline(
        ScaleData.fromJson(
          json[JsonFields.REF_DATA] as Map<String, dynamic>,
        ),
      );
    }
    return const LayoutScaleChoice.current();
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LayoutScaleChoice &&
            other.mode == mode &&
            other.inlineScale == inlineScale;
  }

  @override
  int get hashCode => Object.hash(mode, inlineScale);
}

/// Purpose:
/// Shared source-of-truth object for editable layout settings before they are
/// compiled into one `LayoutData` payload.
///
/// Parameters:
/// - `settings`: interval-grid settings controlling generated key intents.
/// - `scope`: shared vs targeted ownership metadata.
/// - `themeChoice`: current or inline theme selection.
/// - `scaleChoice`: current or inline scale selection.
/// - `colorStrategy`: key-color generation strategy.
///
/// Return value:
/// - Immutable draft value suitable for reusable layout editing widgets.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - The draft can serialize itself and generate `LayoutData` on demand.
///
/// Invariants:
/// - Construction performs no I/O and does not contact Epiphany.
class LayoutDraft {
  final LayoutSettings settings;
  final LayoutScopeSettings scope;
  final LayoutThemeChoice themeChoice;
  final LayoutScaleChoice scaleChoice;
  final LayoutColorStrategy colorStrategy;

  const LayoutDraft({
    this.settings = const LayoutSettings(),
    this.scope = const LayoutScopeSettings.shared(),
    this.themeChoice = const LayoutThemeChoice.current(),
    this.scaleChoice = const LayoutScaleChoice.current(),
    this.colorStrategy = const LayoutColorStrategy.scaleCategories(),
  });

  /// Purpose:
  /// Clone this draft while overriding only the requested fields.
  ///
  /// Parameters:
  /// - Each optional parameter replaces the corresponding current field.
  ///
  /// Return value:
  /// - New immutable `LayoutDraft`.
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
  LayoutDraft copyWith({
    LayoutSettings? settings,
    LayoutScopeSettings? scope,
    LayoutThemeChoice? themeChoice,
    LayoutScaleChoice? scaleChoice,
    LayoutColorStrategy? colorStrategy,
  }) {
    return LayoutDraft(
      settings: settings ?? this.settings,
      scope: scope ?? this.scope,
      themeChoice: themeChoice ?? this.themeChoice,
      scaleChoice: scaleChoice ?? this.scaleChoice,
      colorStrategy: colorStrategy ?? this.colorStrategy,
    );
  }

  /// Purpose:
  /// Compile this editable draft into persisted `LayoutData`.
  ///
  /// Parameters:
  /// - `displayName`: layout display name supplied by the owner.
  /// - `bounds`: optional bounded grid rectangle for partial layouts.
  ///
  /// Return value:
  /// - Generated `LayoutData` using the draft's settings and references.
  ///
  /// Requirements/Preconditions:
  /// - `displayName` should be appropriate for the owning app.
  ///
  /// Guarantees/Postconditions:
  /// - Current/inline theme and scale selections are converted to data refs.
  ///
  /// Invariants:
  /// - Conversion is pure and does not mutate the draft.
  LayoutData toLayoutData({
    required String displayName,
    LayoutGridBounds bounds = const LayoutGridBounds.fullGrid(),
  }) {
    return buildIntervalGridLayoutData(
      displayName: displayName,
      settings: settings,
      scope: scope,
      bounds: bounds,
      colorStrategy: colorStrategy,
      themeRef: themeChoice.toDataReference(),
      scaleRef: scaleChoice.toDataReference(),
    );
  }

  /// Purpose:
  /// Serialize this editable draft for app-owned persistence or diagnostics.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - JSON-ready map containing the draft fields.
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
      'settings': settings.toJson(),
      'scope': scope.toJson(),
      'themeChoice': themeChoice.toJson(),
      'scaleChoice': scaleChoice.toJson(),
      'colorStrategy': colorStrategy.toJson(),
    };
  }

  /// Purpose:
  /// Restore a serialized layout draft from app-owned JSON.
  ///
  /// Parameters:
  /// - `json`: persisted layout-draft map.
  ///
  /// Return value:
  /// - Parsed immutable `LayoutDraft`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should match the format produced by `toJson()`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing fields fall back to the same defaults as the constructor.
  ///
  /// Invariants:
  /// - Parsing performs no I/O.
  factory LayoutDraft.fromJson(Map<String, dynamic> json) {
    return LayoutDraft(
      settings: json['settings'] is Map<String, dynamic>
          ? LayoutSettings.fromJson(json['settings'] as Map<String, dynamic>)
          : const LayoutSettings(),
      scope: json['scope'] is Map<String, dynamic>
          ? LayoutScopeSettings.fromJson(json['scope'] as Map<String, dynamic>)
          : const LayoutScopeSettings.shared(),
      themeChoice: json['themeChoice'] is Map<String, dynamic>
          ? LayoutThemeChoice.fromJson(
              json['themeChoice'] as Map<String, dynamic>,
            )
          : const LayoutThemeChoice.current(),
      scaleChoice: json['scaleChoice'] is Map<String, dynamic>
          ? LayoutScaleChoice.fromJson(
              json['scaleChoice'] as Map<String, dynamic>,
            )
          : const LayoutScaleChoice.current(),
      colorStrategy: json['colorStrategy'] is Map<String, dynamic>
          ? LayoutColorStrategy.fromJson(
              json['colorStrategy'] as Map<String, dynamic>,
            )
          : const LayoutColorStrategy.scaleCategories(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LayoutDraft &&
            other.settings == settings &&
            other.scope == scope &&
            other.themeChoice == themeChoice &&
            other.scaleChoice == scaleChoice &&
            other.colorStrategy == colorStrategy;
  }

  @override
  int get hashCode => Object.hash(
        settings,
        scope,
        themeChoice,
        scaleChoice,
        colorStrategy,
      );
}
