import 'data_types.dart';
import 'json_constants.dart';
import 'namespace_selector.dart';

/// Dynamic reference to data (themes, scales, layouts)
class DataReference<T> {
  /// Type of reference
  final ReferenceType type;

  /// Name when type is NAME
  final String? name;

  /// Namespace selector when type is NAME
  final NamespaceSelector namespaceSelector;

  /// Data when type is INLINE
  final T? inlineData;

  /// Constructor with reference type
  const DataReference(this.type,
      {this.name,
      this.namespaceSelector = const NamespaceSelector.currentEntity(),
      this.inlineData});

  /// Factory method to create a reference by name
  factory DataReference.byName(String name,
      {NamespaceSelector namespaceSelector =
          const NamespaceSelector.currentEntity()}) {
    return DataReference(ReferenceType.name,
        name: name, namespaceSelector: namespaceSelector);
  }

  /// Factory method to create a reference to the current selection
  factory DataReference.current() {
    return const DataReference(ReferenceType.current);
  }

  /// Factory method to create a reference with inline data
  factory DataReference.inline(T data) {
    return DataReference(ReferenceType.inline, inlineData: data);
  }

  /// Convert to JSON representation
  Map<String, dynamic> toJson() {
    if (type == ReferenceType.name && name != null) {
      return {
        JsonFields.REF_TYPE: JsonFields.REF_TYPE_NAME,
        JsonFields.REF_NAME: name,
        JsonFields.NAMESPACE_SELECTOR: namespaceSelector.toJson(),
      };
    } else if (type == ReferenceType.current) {
      return {
        JsonFields.REF_TYPE: JsonFields.REF_TYPE_CURRENT,
      };
    } else if (type == ReferenceType.inline && inlineData != null) {
      // Inline data is returned directly as the JSON object
      // We assume T has a toJson method
      try {
        return (inlineData as dynamic).toJson();
      } catch (e) {
        throw Exception("Inline data of type $T must implement toJson()");
      }
    }
    return {};
  }

  /// Create from JSON representation
  static DataReference<T> fromJson<T>(
      Map<String, dynamic> json, T Function(Map<String, dynamic>) fromJsonT) {
    Map<String, dynamic> jsonToParse = json;

    // Handle implicit wrapping of data (common in Epiphany responses for resolved items)
    // If the object has a single 'resolved' or 'spec' key, unwrap it first
    if (jsonToParse.length == 1) {
      if (jsonToParse.containsKey(JsonFields.RESOLVED)) {
        final val = jsonToParse[JsonFields.RESOLVED];
        if (val is Map<String, dynamic>) {
          jsonToParse = val;
        }
      } else if (jsonToParse.containsKey(JsonFields.SPEC)) {
        final val = jsonToParse[JsonFields.SPEC];
        if (val is Map<String, dynamic>) {
          jsonToParse = val;
        }
      }
    }

    if (jsonToParse.containsKey(JsonFields.REF_TYPE)) {
      final refType = jsonToParse[JsonFields.REF_TYPE];
      if (refType == JsonFields.REF_TYPE_NAME) {
        final name = jsonToParse[JsonFields.REF_NAME] ?? '';
        final NamespaceSelector namespaceSelector;
        if (jsonToParse.containsKey(JsonFields.NAMESPACE_SELECTOR)) {
          namespaceSelector = NamespaceSelector.fromJson(
            jsonToParse[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>,
          );
        } else {
          // Default to currentEntity if not specified
          namespaceSelector = const NamespaceSelector.currentEntity();
        }
        return DataReference.byName(name, namespaceSelector: namespaceSelector);
      } else if (refType == JsonFields.REF_TYPE_CURRENT) {
        return DataReference.current();
      } else if (refType == JsonFields.REF_TYPE_INLINE) {
        // If explicit inline type, extract data from refData
        if (jsonToParse.containsKey(JsonFields.REF_DATA)) {
          final refData = jsonToParse[JsonFields.REF_DATA];
          if (refData is Map<String, dynamic>) {
            jsonToParse = refData;

            // Check again for wrapper inside refData (recursive unwrapping logic matching C++)
            if (jsonToParse.containsKey(JsonFields.RESOLVED)) {
              final val = jsonToParse[JsonFields.RESOLVED];
              if (val is Map<String, dynamic>) {
                jsonToParse = val;
              }
            } else if (jsonToParse.containsKey(JsonFields.SPEC)) {
              final val = jsonToParse[JsonFields.SPEC];
              if (val is Map<String, dynamic>) {
                jsonToParse = val;
              }
            }
          }
        }
      }
    } else if (jsonToParse.containsKey(JsonFields.REF_DATA)) {
      // Fallback if REF_TYPE missing but REF_DATA present
      final refData = jsonToParse[JsonFields.REF_DATA];
      if (refData is Map<String, dynamic>) {
        jsonToParse = refData;
      }
    }

    // Assume inline data if it's not a reference
    try {
      return DataReference.inline(fromJsonT(jsonToParse));
    } catch (e) {
      // If parsing fails, return a safe default or rethrow depending on needs
      // For now, we can't easily recover if inline parsing fails
      throw Exception(
          "Failed to parse inline data for DataReference<$T>: $e. JSON: $jsonToParse");
    }
  }

  @override
  String toString() =>
      'DataReference(type: $type, name: $name, namespace: $namespaceSelector)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataReference &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          name == other.name &&
          namespaceSelector == other.namespaceSelector &&
          // Note: Deep equality check for inlineData depends on T's implementation
          inlineData.toString() == other.inlineData.toString();

  @override
  int get hashCode => Object.hash(type, name, namespaceSelector, inlineData);
}
