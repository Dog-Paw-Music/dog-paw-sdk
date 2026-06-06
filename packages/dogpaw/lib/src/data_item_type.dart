import 'json_constants.dart';
import 'namespace_selector.dart';

/// Base class for data items with optional spec and resolved fields
/// Matches C++ DataItemType template
abstract class DataItemType<T> {
  String name;
  NamespaceSelector namespaceSelector;
  T? spec;
  T? resolved;

  DataItemType({
    required this.name,
    NamespaceSelector? namespaceSelector,
    this.spec,
    this.resolved,
  }) : namespaceSelector =
            namespaceSelector ?? const NamespaceSelector.currentEntity();

  /// Check if spec data is available
  bool get hasSpecData => spec != null;

  /// Check if resolved data is available
  bool get hasResolvedData => resolved != null;

  /// Get data safely, preferring resolved over spec
  T get data {
    final resolvedData = resolved;
    if (resolvedData != null) return resolvedData;
    final specData = spec;
    if (specData != null) return specData;
    throw Exception("No data available in DataItemType for $name");
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      JsonFields.NAME: name,
      JsonFields.NAMESPACE_SELECTOR: namespaceSelector.toJson(),
    };

    if (spec != null) {
      result[JsonFields.SPEC] = specToJson(spec as T);
    }

    if (resolved != null) {
      result[JsonFields.RESOLVED] = specToJson(resolved as T);
    }

    return result;
  }

  /// Abstract method to convert spec/resolved data to JSON
  Map<String, dynamic> specToJson(T data);
}
