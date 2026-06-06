import 'data_item_type.dart';
import 'json_constants.dart';
import 'namespace_selector.dart';

/// Key-value data structure containing the actual value
class KVData {
  String value;

  KVData(this.value);

  Map<String, dynamic> toJson() => {JsonFields.VALUE: value};

  factory KVData.fromJson(Map<String, dynamic> json) {
    return KVData(json[JsonFields.VALUE] as String);
  }
}

/// Key-value pair type
class KV extends DataItemType<KVData> {
  // Convenience constructor for creating new KVs
  KV({
    required super.name,
    required String value,
    super.namespaceSelector,
  }) : super(
          spec: KVData(value),
        );

  // Full constructor for reconstruction
  KV.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(KVData data) => data.toJson();

  factory KV.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';

    // Parse namespace selector from JSON
    NamespaceSelector namespaceSelector = NamespaceSelector.fromJson(
        json[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>);

    KVData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = KVData.fromJson(json[JsonFields.SPEC] as Map<String, dynamic>);
    }

    KVData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved =
          KVData.fromJson(json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    return KV.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );
  }

  String? get value => spec?.value ?? resolved?.value;
}
