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

  factory Theme.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';

    // Parse namespace selector from JSON
    NamespaceSelector namespaceSelector = NamespaceSelector.fromJson(
        json[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>);

    ThemeData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = ThemeData.fromJson(json[JsonFields.SPEC] as Map<String, dynamic>);
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
