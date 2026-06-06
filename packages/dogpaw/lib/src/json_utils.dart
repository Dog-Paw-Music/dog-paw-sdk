/// Utility functions for JSON operations
class JsonUtils {
  /// Convert a map to JSON, filtering out null values
  /// This is useful for creating clean JSON without null fields
  static Map<String, dynamic> toJson(Map<String, dynamic> map) {
    return Map.fromEntries(
      map.entries.where((entry) => entry.value != null),
    );
  }

  /// Convert a map to JSON, filtering out null values and empty collections
  /// This is useful for creating clean JSON without null or empty fields
  static Map<String, dynamic> toJsonClean(Map<String, dynamic> map) {
    return Map.fromEntries(
      map.entries.where((entry) {
        if (entry.value == null) {
          return false;
        }
        if (entry.value is List && (entry.value as List).isEmpty) {
          return false;
        }
        if (entry.value is Map && (entry.value as Map).isEmpty) {
          return false;
        }
        if (entry.value is String && (entry.value as String).isEmpty) {
          return false;
        }
        return true;
      }),
    );
  }

  /// Convert a map to JSON, filtering out null values and applying custom filters
  /// [map] - The map to convert
  /// [filterNull] - Whether to filter out null values (default: true)
  /// [filterEmpty] - Whether to filter out empty collections/strings (default: false)
  /// [customFilters] - Additional custom filters to apply
  static Map<String, dynamic> toJsonFiltered(
    Map<String, dynamic> map, {
    bool filterNull = true,
    bool filterEmpty = false,
    Map<String, bool Function(dynamic)>? customFilters,
  }) {
    return Map.fromEntries(
      map.entries.where((entry) {
        // Apply null filter
        if (filterNull && entry.value == null) return false;

        // Apply empty filter
        if (filterEmpty) {
          if (entry.value is List && (entry.value as List).isEmpty) {
            return false;
          }
          if (entry.value is Map && (entry.value as Map).isEmpty) {
            return false;
          }
          if (entry.value is String && (entry.value as String).isEmpty) {
            return false;
          }
        }

        // Apply custom filters
        if (customFilters != null && customFilters.containsKey(entry.key)) {
          final customFilter = customFilters[entry.key]!;
          if (!customFilter(entry.value)) return false;
        }

        return true;
      }),
    );
  }
}

/// Extension methods for easier JSON operations
extension JsonUtilsExtension on Map<String, dynamic> {
  /// Convert to JSON, filtering out null values
  Map<String, dynamic> toJsonClean() => JsonUtils.toJson(this);

  /// Convert to JSON, filtering out null values and empty collections
  Map<String, dynamic> toJsonCleanStrict() => JsonUtils.toJsonClean(this);

  /// Convert to JSON with custom filtering
  Map<String, dynamic> toJsonFiltered({
    bool filterNull = true,
    bool filterEmpty = false,
    Map<String, bool Function(dynamic)>? customFilters,
  }) =>
      JsonUtils.toJsonFiltered(
        this,
        filterNull: filterNull,
        filterEmpty: filterEmpty,
        customFilters: customFilters,
      );
}
