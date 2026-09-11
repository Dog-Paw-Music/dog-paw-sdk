import 'layout.dart';
import 'layout_builder.dart';
import 'layout_choice.dart';

/// Purpose:
/// Shared source-of-truth object for editable layout settings before they are
/// compiled into one `LayoutData` payload.
///
/// Parameters:
/// - `settings`: interval-grid settings controlling generated key intents.
/// - `scope`: shared vs targeted ownership metadata.
/// - `themeChoice`: shared or override theme selection.
/// - `scaleChoice`: shared or override scale selection.
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
    this.themeChoice = const LayoutThemeChoice.shared(),
    this.scaleChoice = const LayoutScaleChoice.shared(),
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
  /// - Shared/override theme and scale selections are preserved in `LayoutData`.
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
      themeChoice: themeChoice,
      scaleChoice: scaleChoice,
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
          : const LayoutThemeChoice.shared(),
      scaleChoice: json['scaleChoice'] is Map<String, dynamic>
          ? LayoutScaleChoice.fromJson(
              json['scaleChoice'] as Map<String, dynamic>,
            )
          : const LayoutScaleChoice.shared(),
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
