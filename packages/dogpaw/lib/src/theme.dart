import 'data_item_type.dart';
import 'json_constants.dart';
import 'namespace_selector.dart';

/// Color theme definition data
class ThemeData {
  /// Human-readable display name
  final String displayName;

  /// Primary color
  final String primaryColor;

  /// Secondary color
  final String secondaryColor;

  /// Accent color
  final String accentColor;

  /// Background color
  final String backgroundColor;

  const ThemeData({
    required this.displayName,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.backgroundColor,
  });

  /// Convert to JSON representation
  Map<String, dynamic> toJson() => {
        JsonFields.DISPLAY_NAME: displayName,
        JsonFields.PRIMARY_COLOR: primaryColor,
        JsonFields.SECONDARY_COLOR: secondaryColor,
        JsonFields.ACCENT_COLOR: accentColor,
        JsonFields.BACKGROUND_COLOR: backgroundColor,
      };

  /// Create from JSON representation
  factory ThemeData.fromJson(Map<String, dynamic> json) {
    // Helper to extract color string from either a string or an object with 'rgba' field
    String extractColor(dynamic colorValue, String defaultValue) {
      if (colorValue == null) return defaultValue;
      if (colorValue is String) return colorValue;
      if (colorValue is Map<String, dynamic> &&
          colorValue.containsKey('rgba')) {
        return colorValue['rgba'] as String;
      }
      return defaultValue;
    }

    return ThemeData(
      displayName: json[JsonFields.DISPLAY_NAME] ?? '',
      primaryColor: extractColor(json[JsonFields.PRIMARY_COLOR], ''),
      secondaryColor: extractColor(json[JsonFields.SECONDARY_COLOR], ''),
      accentColor: extractColor(json[JsonFields.ACCENT_COLOR], ''),
      backgroundColor: extractColor(json[JsonFields.BACKGROUND_COLOR], ''),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ThemeData &&
            other.displayName == displayName &&
            other.primaryColor == primaryColor &&
            other.secondaryColor == secondaryColor &&
            other.accentColor == accentColor &&
            other.backgroundColor == backgroundColor;
  }

  @override
  int get hashCode => Object.hash(
        displayName,
        primaryColor,
        secondaryColor,
        accentColor,
        backgroundColor,
      );
}

/// Theme class
class Theme extends DataItemType<ThemeData> {
  Theme({
    required super.name,
    required ThemeData spec,
    super.namespaceSelector,
  }) : super(
          spec: spec,
        );

  Theme.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(ThemeData data) => data.toJson();

  /// Purpose:
  /// Restore a `Theme` from either the full Epiphany item wrapper or a bare
  /// inline theme-data payload.
  ///
  /// Parameters:
  /// - `json`: serialized theme object or bare theme spec/resolved map.
  ///
  /// Return value:
  /// - Parsed immutable `Theme`.
  ///
  /// Requirements/Preconditions:
  /// - `json` should contain either item-level fields such as `name` and
  ///   `namespaceSelector`, or bare theme-data fields such as `displayName` and
  ///   `primaryColor`.
  ///
  /// Guarantees/Postconditions:
  /// - Missing `namespaceSelector` falls back to `currentEntity`.
  /// - Bare theme-data payloads are treated as inline spec data.
  ///
  /// Invariants:
  /// - Parsing is pure and performs no I/O.
  factory Theme.fromJson(Map<String, dynamic> json) {
    final String name = json[JsonFields.NAME] as String? ?? '';
    final dynamic namespaceSelectorJson = json[JsonFields.NAMESPACE_SELECTOR];
    final NamespaceSelector namespaceSelector =
        namespaceSelectorJson is Map<String, dynamic>
            ? NamespaceSelector.fromJson(namespaceSelectorJson)
            : const NamespaceSelector.currentEntity();
    final bool hasWrappedData =
        json.containsKey(JsonFields.SPEC) || json.containsKey(JsonFields.RESOLVED);

    ThemeData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = ThemeData.fromJson(json[JsonFields.SPEC] as Map<String, dynamic>);
    } else if (!hasWrappedData) {
      spec = ThemeData.fromJson(json);
    }

    ThemeData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved =
          ThemeData.fromJson(json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    return Theme.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );
  }
}
