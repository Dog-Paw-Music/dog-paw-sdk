import 'json_constants.dart';
import 'json_utils.dart';
import 'mapping_config.dart';
import 'search_criteria.dart';

/// Index-conversion assertion shared by explicit and endpoint-owned rules.
class IndexConversionConfig {
  final String strategy;
  final String? converter;
  final Map<String, dynamic> parameters;

  const IndexConversionConfig({
    this.strategy = JsonFields.CONVERSION_NONE,
    this.converter,
    this.parameters = const <String, dynamic>{},
  });

  /// Serializes this sparse conversion assertion.
  ///
  /// Requires a supported strategy string. Returns protocol JSON without null
  /// fields; this object remains unchanged.
  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.STRATEGY: strategy,
        JsonFields.CONVERTER: converter,
        JsonFields.PARAMETERS: parameters,
      }.toJsonClean();

  /// Parses a conversion assertion from protocol JSON.
  ///
  /// [json] must be an object. Returns a typed assertion, defaulting only values
  /// inside an asserted conversion object; the input map remains unchanged.
  factory IndexConversionConfig.fromJson(Map<String, dynamic> json) {
    final Object? rawStrategy =
        json[JsonFields.STRATEGY] ?? JsonFields.CONVERSION_NONE;
    if (rawStrategy is! String ||
        !_supportedConversionStrategies.contains(rawStrategy)) {
      throw ArgumentError.value(
        rawStrategy,
        JsonFields.STRATEGY,
        'Unsupported index conversion strategy',
      );
    }

    return IndexConversionConfig(
      strategy: rawStrategy,
      converter: json[JsonFields.CONVERTER],
      parameters: Map<String, dynamic>.from(
          json[JsonFields.PARAMETERS] ?? <String, dynamic>{}),
    );
  }
}

const Set<String> _supportedConversionStrategies = <String>{
  JsonFields.CONVERSION_NONE,
  JsonFields.CONVERSION_UNIFORM,
  JsonFields.CONVERSION_MAX_VALUE,
  JsonFields.CONVERSION_MIN_VALUE,
  JsonFields.CONVERSION_MAX_ABS,
  JsonFields.CONVERSION_AVERAGE_VALUE,
  JsonFields.CONVERSION_LAST_ACTIVE,
  JsonFields.CONVERSION_FIRST_ACTIVE,
};

/// Connection policy defining how endpoints can be connected
class ConnectionPolicy {
  /// Maximum allowed connections (-1 = unlimited)
  final int maxConnections;

  /// Optional endpoint-owned connection rule for automatic peer matching.
  final SearchCriteria? endpointConnectionRule;
  final MappingConfig? mapping;
  final IndexConversionConfig? indexConversion;
  final bool? enabled;
  final bool clearMapping;
  final bool clearIndexConversion;
  final bool clearEnabled;
  final Map<String, int> fieldPriorities;
  final Map<String, dynamic> extensions;

  /// Temporary compatibility alias for older auto-connect terminology.
  @Deprecated('Use endpointConnectionRule instead.')
  SearchCriteria? get autoConnectCriteria => endpointConnectionRule;

  /// Default constructor
  const ConnectionPolicy({
    this.maxConnections = -1,
    SearchCriteria? endpointConnectionRule,
    @Deprecated('Use endpointConnectionRule instead.')
    SearchCriteria? autoConnectCriteria,
    this.mapping,
    this.indexConversion,
    this.enabled,
    this.clearMapping = false,
    this.clearIndexConversion = false,
    this.clearEnabled = false,
    this.fieldPriorities = const <String, int>{},
    this.extensions = const <String, dynamic>{},
  })  : assert(
          endpointConnectionRule == null || autoConnectCriteria == null,
          'Specify either endpointConnectionRule or autoConnectCriteria, not both.',
        ),
        assert(mapping == null || !clearMapping,
            'mapping and clearMapping are mutually exclusive.'),
        assert(indexConversion == null || !clearIndexConversion,
            'indexConversion and clearIndexConversion are mutually exclusive.'),
        assert(enabled == null || !clearEnabled,
            'enabled and clearEnabled are mutually exclusive.'),
        endpointConnectionRule = endpointConnectionRule ?? autoConnectCriteria;

  /// Convert to JSON representation
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      JsonFields.MAX_CONNECTIONS: maxConnections,
    };

    if (endpointConnectionRule != null) {
      json[JsonFields.AUTO_CONNECT_CRITERIA] = endpointConnectionRule!.toJson();
    }
    if (mapping != null) {
      json[JsonFields.MAPPING] = mapping!.toJson();
    } else if (clearMapping) {
      json[JsonFields.MAPPING] = null;
    }
    if (indexConversion != null) {
      json[JsonFields.INDEX_CONVERSION] = indexConversion!.toJson();
    } else if (clearIndexConversion) {
      json[JsonFields.INDEX_CONVERSION] = null;
    }
    if (enabled != null) {
      json[JsonFields.ENABLED] = enabled;
    } else if (clearEnabled) {
      json[JsonFields.ENABLED] = null;
    }
    if (fieldPriorities.isNotEmpty) {
      json[JsonFields.FIELD_PRIORITIES] = fieldPriorities;
    }
    if (extensions.isNotEmpty) {
      json[JsonFields.EXTENSIONS] = extensions;
    }

    return json;
  }

  /// Create from JSON representation
  factory ConnectionPolicy.fromJson(Map<String, dynamic> json) {
    // Handle potential legacy format or direct field access
    SearchCriteria? autoConnect;
    if (json.containsKey(JsonFields.AUTO_CONNECT_CRITERIA)) {
      autoConnect =
          SearchCriteria.fromJson(json[JsonFields.AUTO_CONNECT_CRITERIA]);
    }

    return ConnectionPolicy(
      maxConnections: json[JsonFields.MAX_CONNECTIONS] ?? -1,
      endpointConnectionRule: autoConnect,
      mapping: json[JsonFields.MAPPING] is Map
          ? MappingConfig.fromJson(
              Map<String, dynamic>.from(json[JsonFields.MAPPING]))
          : null,
      indexConversion: json[JsonFields.INDEX_CONVERSION] is Map
          ? IndexConversionConfig.fromJson(
              Map<String, dynamic>.from(json[JsonFields.INDEX_CONVERSION]))
          : null,
      enabled: json[JsonFields.ENABLED] as bool?,
      clearMapping: json.containsKey(JsonFields.MAPPING) &&
          json[JsonFields.MAPPING] == null,
      clearIndexConversion: json.containsKey(JsonFields.INDEX_CONVERSION) &&
          json[JsonFields.INDEX_CONVERSION] == null,
      clearEnabled: json.containsKey(JsonFields.ENABLED) &&
          json[JsonFields.ENABLED] == null,
      fieldPriorities: Map<String, int>.from(
          json[JsonFields.FIELD_PRIORITIES] ?? <String, int>{}),
      extensions: Map<String, dynamic>.from(
          json[JsonFields.EXTENSIONS] ?? <String, dynamic>{}),
    );
  }
}
