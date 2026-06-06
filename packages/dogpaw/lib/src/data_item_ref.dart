import 'json_constants.dart';
import 'namespace_selector.dart';

/// Reference to a data item by name and namespace
///
/// Identifies a data item by name and namespace.
/// Default namespace is currentEntity (resolved at request time by Epiphany).
class DataItemRef {
  /// Name of the item
  final String name;

  /// Namespace selector for the item
  final NamespaceSelector namespaceSelector;

  /// Default constructor (defaults to currentEntity namespace)
  const DataItemRef({
    required this.name,
    this.namespaceSelector = const NamespaceSelector.currentEntity(),
  });

  /// Factory for creating from name and namespace selector
  factory DataItemRef.byName({
    required String name,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) {
    return DataItemRef(
      name: name,
      namespaceSelector: namespaceSelector,
    );
  }

  /// Convert to JSON representation with name and namespaceSelector
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.NAME: name,
      JsonFields.NAMESPACE_SELECTOR: namespaceSelector.toJson(),
    };
  }

  /// Create from JSON representation
  ///
  /// Requires name and namespaceSelector fields.
  /// Defaults to currentEntity if namespaceSelector is missing.
  factory DataItemRef.fromJson(Map<String, dynamic> json) {
    final dynamic rawName = json[JsonFields.NAME] ?? json[JsonFields.REF_NAME];
    if (rawName is! String || rawName.isEmpty) {
      throw ArgumentError(
        'Invalid data item ref json: missing name/refName field',
      );
    }

    final NamespaceSelector namespaceSelector;

    if (json.containsKey(JsonFields.NAMESPACE_SELECTOR)) {
      namespaceSelector = NamespaceSelector.fromJson(
        json[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>,
      );
    } else {
      // Default to currentEntity if not specified
      namespaceSelector = const NamespaceSelector.currentEntity();
    }

    return DataItemRef(
      name: rawName,
      namespaceSelector: namespaceSelector,
    );
  }

  @override
  String toString() =>
      'DataItemRef(name: $name, namespace: $namespaceSelector)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataItemRef &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          namespaceSelector == other.namespaceSelector;

  @override
  int get hashCode => Object.hash(name, namespaceSelector);
}
