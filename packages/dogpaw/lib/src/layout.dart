import 'data_item_type.dart';
import 'json_constants.dart';
import 'json_utils.dart';
import 'data_reference.dart';
import 'key_intent.dart';
import 'layout_choice.dart';
import 'theme.dart';
import 'namespace_selector.dart';
import 'scale.dart';

/// Layout definition data
class LayoutData {
  /// Human-readable display name
  final String displayName;

  /// Layout-level scope (`shared` or `targeted`)
  final String scope;

  /// Layout-owned bend policy mode (`fixed` or `nextInScale`)
  final String bendMode;

  /// Layout-owned bend cap in semitones
  final double bendRangeSemitones;

  /// Consumer-facing target key used when [scope] is `targeted`
  final String? targetKey;

  /// Fully composed key intent mapping (arrays per key)
  final Map<String, dynamic> keyIntents;

  /// Fully composed key color mapping - supports theme color references
  final Map<String, dynamic> keyColors;

  /// Persisted theme-choice metadata for layout specs.
  final LayoutThemeChoice? themeChoice;

  /// Persisted scale-choice metadata for layout specs.
  final LayoutScaleChoice? scaleChoice;

  /// Active resolved theme reference returned by Epiphany responses.
  final DataReference<Theme>? resolvedThemeRef;

  /// Active resolved scale reference returned by Epiphany responses.
  final DataReference<Scale>? resolvedScaleRef;

  const LayoutData({
    this.displayName = '',
    this.scope = 'shared',
    this.bendMode = 'fixed',
    this.bendRangeSemitones = 2.0,
    this.targetKey,
    this.keyIntents = const {},
    this.keyColors = const {},
    this.themeChoice,
    this.scaleChoice,
    this.resolvedThemeRef,
    this.resolvedScaleRef,
  });

  /// Purpose:
  /// Return the active theme reference represented by this layout data.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Resolved theme reference when present, otherwise the active reference
  ///   implied by `themeChoice`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Shared theme choices map to the named `System/shared_theme` reference.
  ///
  /// Invariants:
  /// - Reading this getter does not mutate layout state.
  DataReference<Theme>? get themeRef {
    return resolvedThemeRef ?? themeChoice?.toDataReference();
  }

  /// Purpose:
  /// Return the active scale reference represented by this layout data.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Resolved scale reference when present, otherwise the active reference
  ///   implied by `scaleChoice`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Shared scale choices map to the named `System/shared_scale` reference.
  ///
  /// Invariants:
  /// - Reading this getter does not mutate layout state.
  DataReference<Scale>? get scaleRef {
    return resolvedScaleRef ?? scaleChoice?.toDataReference();
  }

  Map<String, dynamic> toJson() => {
        JsonFields.DISPLAY_NAME: displayName,
        JsonFields.SCOPE: scope,
        JsonFields.BEND_MODE: bendMode,
        JsonFields.BEND_RANGE_SEMITONES: bendRangeSemitones,
        JsonFields.TARGET_KEY: targetKey,
        JsonFields.KEY_INTENTS: keyIntentsToJson(keyIntents),
        JsonFields.KEY_COLORS: keyColors,
        JsonFields.THEME_CHOICE: themeChoice?.toJson(),
        JsonFields.SCALE_CHOICE: scaleChoice?.toJson(),
      }.toJsonClean();

  factory LayoutData.fromJson(Map<String, dynamic> json) {
    // Helper to normalize keyColors - convert color objects to strings
    Map<String, dynamic> normalizeKeyColors(Map<String, dynamic> colors) {
      final result = <String, dynamic>{};
      for (final entry in colors.entries) {
        final value = entry.value;
        // If the color is an object with 'rgba' field, extract the string
        if (value is Map<String, dynamic> && value.containsKey('rgba')) {
          result[entry.key] = value['rgba'] as String;
        } else if (value is String) {
          result[entry.key] = value;
        } else {
          // Keep as-is for other types
          result[entry.key] = value;
        }
      }
      return result;
    }

    final dynamic rawKeyColorsValue = json[JsonFields.KEY_COLORS];
    final Map<String, dynamic> rawKeyColors;
    if (rawKeyColorsValue is Map<String, dynamic>) {
      rawKeyColors = rawKeyColorsValue;
    } else if (rawKeyColorsValue is String) {
      rawKeyColors = <String, dynamic>{JsonFields.SPEC: rawKeyColorsValue};
    } else {
      rawKeyColors = <String, dynamic>{};
    }

    // AppLogger.debug("LayoutData.fromJson: rawKeyColors: ${rawKeyColors.toString()}");
    // AppLogger.debug("LayoutData.fromJson: json[JsonFields.KEY_INTENTS]: ${json[JsonFields.KEY_INTENTS].toString()}");

    return LayoutData(
      displayName: json[JsonFields.DISPLAY_NAME] ?? '',
      scope: json[JsonFields.SCOPE] as String? ?? 'shared',
      bendMode: json[JsonFields.BEND_MODE] as String? ?? 'fixed',
      bendRangeSemitones:
          (json[JsonFields.BEND_RANGE_SEMITONES] as num?)?.toDouble() ?? 2.0,
      targetKey: json[JsonFields.TARGET_KEY] as String?,
      keyIntents: coerceKeyIntentsByKey(
          json[JsonFields.KEY_INTENTS] ?? <String, dynamic>{}),
      keyColors: normalizeKeyColors(rawKeyColors),
      themeChoice: json[JsonFields.THEME_CHOICE] is Map<String, dynamic>
          ? LayoutThemeChoice.fromJson(
              json[JsonFields.THEME_CHOICE] as Map<String, dynamic>,
            )
          : (json[JsonFields.THEME_REF] != null
              ? LayoutThemeChoice.fromDataReference(
                  DataReference.fromJson(
                    json[JsonFields.THEME_REF],
                    (j) => Theme.fromJson(j),
                  ),
                )
              : null),
      scaleChoice: json[JsonFields.SCALE_CHOICE] is Map<String, dynamic>
          ? LayoutScaleChoice.fromJson(
              json[JsonFields.SCALE_CHOICE] as Map<String, dynamic>,
            )
          : (json[JsonFields.SCALE_REF] != null
              ? LayoutScaleChoice.fromDataReference(
                  DataReference.fromJson(
                    json[JsonFields.SCALE_REF],
                    (j) => Scale.fromJson(j),
                  ),
                )
              : null),
      resolvedThemeRef: json[JsonFields.THEME_REF] != null
          ? DataReference.fromJson(
              json[JsonFields.THEME_REF],
              (j) => Theme.fromJson(j),
            )
          : null,
      resolvedScaleRef: json[JsonFields.SCALE_REF] != null
          ? DataReference.fromJson(
              json[JsonFields.SCALE_REF],
              (j) => Scale.fromJson(j),
            )
          : null,
    );
  }
}

/// Layout class
class Layout extends DataItemType<LayoutData> {
  Layout({
    required super.name,
    required LayoutData spec,
    super.namespaceSelector,
  }) : super(
          spec: spec,
        );

  Layout.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(LayoutData data) => data.toJson();

  factory Layout.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';

    // Parse namespace selector from JSON
    NamespaceSelector namespaceSelector = NamespaceSelector.fromJson(
        json[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>);

    LayoutData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      // AppLogger.debug("Layout.fromJson: parsing spec");
      spec = LayoutData.fromJson(json[JsonFields.SPEC] as Map<String, dynamic>);
    }

    LayoutData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      // AppLogger.debug("Layout.fromJson: parsing resolved");
      resolved = LayoutData.fromJson(
          json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    return Layout.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );
  }
}
