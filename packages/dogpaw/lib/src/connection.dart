import 'data_item_type.dart';
import 'mapping_config.dart';
import 'json_constants.dart';
import 'json_utils.dart';
import 'endpoint.dart';
import 'namespace_selector.dart';
import 'data_item_ref.dart';
import 'search_criteria.dart';

/// Index conversion configuration
class IndexConversionConfig {
  final String strategy;
  final String? converter;
  final Map<String, dynamic> parameters;

  const IndexConversionConfig({
    this.strategy = JsonFields.CONVERSION_NONE,
    this.converter,
    this.parameters = const {},
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.STRATEGY: strategy,
      JsonFields.CONVERTER: converter,
      JsonFields.PARAMETERS: parameters,
    }.toJsonClean();
  }

  factory IndexConversionConfig.fromJson(Map<String, dynamic> json) {
    return IndexConversionConfig(
      strategy: json[JsonFields.STRATEGY] ?? JsonFields.CONVERSION_NONE,
      converter: json[JsonFields.CONVERTER],
      parameters: json[JsonFields.PARAMETERS] ?? {},
    );
  }
}

/// Connection data specification
class ConnectionData {
  final DataItemRef sourceRef;
  final DataItemRef destinationRef;
  final EndpointInfo? source;
  final EndpointInfo? destination;
  final MappingConfig mapping;
  final IndexConversionConfig indexConversion;
  final bool enabled;

  ConnectionData({
    required this.sourceRef,
    required this.destinationRef,
    this.source,
    this.destination,
    this.mapping = const MappingConfig(),
    this.indexConversion = const IndexConversionConfig(),
    this.enabled = true,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.SOURCE_REF: sourceRef.toJson(),
      JsonFields.DESTINATION_REF: destinationRef.toJson(),
      // Resolved endpoints are typically not serialized back to JSON for spec
      JsonFields.MAPPING: mapping.toJson(),
      JsonFields.INDEX_CONVERSION: indexConversion.toJson(),
      JsonFields.ENABLED: enabled,
    }.toJsonClean();
  }

  factory ConnectionData.fromJson(Map<String, dynamic> json) {
    return ConnectionData(
      sourceRef: DataItemRef.fromJson(json[JsonFields.SOURCE_REF] ?? {}),
      destinationRef:
          DataItemRef.fromJson(json[JsonFields.DESTINATION_REF] ?? {}),
      source: json[JsonFields.SOURCE] != null
          ? EndpointInfo.fromJson(json[JsonFields.SOURCE])
          : null,
      destination: json[JsonFields.DESTINATION] != null
          ? EndpointInfo.fromJson(json[JsonFields.DESTINATION])
          : null,
      mapping: MappingConfig.fromJson(json[JsonFields.MAPPING] ?? {}),
      indexConversion: IndexConversionConfig.fromJson(
          json[JsonFields.INDEX_CONVERSION] ?? {}),
      enabled: json[JsonFields.ENABLED] ?? true,
    );
  }
}

/// Connection class
class Connection extends DataItemType<ConnectionData> {
  Connection({
    required super.name,
    required ConnectionData spec,
    super.namespaceSelector,
  }) : super(
          spec: spec,
        );

  Connection.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(ConnectionData data) => data.toJson();

  factory Connection.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';
    const NamespaceSelector namespaceSelector = NamespaceSelector.global();

    ConnectionData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = ConnectionData.fromJson(
          json[JsonFields.SPEC] as Map<String, dynamic>);
    }

    ConnectionData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved = ConnectionData.fromJson(
          json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    return Connection.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );
  }
}

/// Stored request that asks Epiphany to realize a connection.
class ConnectionRuleSelector {
  final DataItemRef? endpointRef;
  final SearchCriteria? matchCriteria;

  const ConnectionRuleSelector._({
    this.endpointRef,
    this.matchCriteria,
  });

  factory ConnectionRuleSelector.endpointRef(DataItemRef endpointRef) {
    return ConnectionRuleSelector._(endpointRef: endpointRef);
  }

  factory ConnectionRuleSelector.matchCriteria(SearchCriteria matchCriteria) {
    return ConnectionRuleSelector._(matchCriteria: matchCriteria);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (endpointRef != null) 'endpointRef': endpointRef!.toJson(),
      if (matchCriteria != null) 'matchCriteria': matchCriteria!.toJson(),
    }.toJsonClean();
  }

  factory ConnectionRuleSelector.fromJson(Map<String, dynamic> json) {
    final bool hasEndpointRef = json.containsKey('endpointRef');
    final bool hasMatchCriteria = json.containsKey('matchCriteria');
    if (hasEndpointRef == hasMatchCriteria) {
      throw StateError(
        'ConnectionRuleSelector requires exactly one of endpointRef or matchCriteria.',
      );
    }
    if (hasEndpointRef) {
      return ConnectionRuleSelector.endpointRef(
        DataItemRef.fromJson(json['endpointRef'] ?? <String, dynamic>{}),
      );
    }
    return ConnectionRuleSelector.matchCriteria(
      SearchCriteria.fromJson(json['matchCriteria'] ?? <String, dynamic>{}),
    );
  }
}

/// Stored rule that asks Epiphany to realize a connection.
class ConnectionRuleData {
  final ConnectionRuleSelector sourceSelector;
  final ConnectionRuleSelector destinationSelector;

  ConnectionRuleData({
    DataItemRef? sourceRef,
    DataItemRef? destinationRef,
    ConnectionRuleSelector? sourceSelector,
    ConnectionRuleSelector? destinationSelector,
  })  : assert(
          sourceSelector != null || sourceRef != null,
          'Provide sourceSelector or sourceRef.',
        ),
        assert(
          destinationSelector != null || destinationRef != null,
          'Provide destinationSelector or destinationRef.',
        ),
        assert(
          sourceSelector == null || sourceRef == null,
          'Specify only one of sourceSelector or sourceRef.',
        ),
        assert(
          destinationSelector == null || destinationRef == null,
          'Specify only one of destinationSelector or destinationRef.',
        ),
        sourceSelector = sourceSelector ??
            ConnectionRuleSelector.endpointRef(sourceRef!),
        destinationSelector = destinationSelector ??
            ConnectionRuleSelector.endpointRef(destinationRef!);

  DataItemRef get sourceRef {
    if (sourceSelector.endpointRef == null) {
      throw StateError(
        'This connection rule uses sourceSelector.matchCriteria instead of an exact sourceRef.',
      );
    }
    return sourceSelector.endpointRef!;
  }

  DataItemRef get destinationRef {
    if (destinationSelector.endpointRef == null) {
      throw StateError(
        'This connection rule uses destinationSelector.matchCriteria instead of an exact destinationRef.',
      );
    }
    return destinationSelector.endpointRef!;
  }
  SearchCriteria? get sourceCriteria => sourceSelector.matchCriteria;
  SearchCriteria? get destinationCriteria => destinationSelector.matchCriteria;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sourceSelector': sourceSelector.toJson(),
      'destinationSelector': destinationSelector.toJson(),
    }.toJsonClean();
  }

  factory ConnectionRuleData.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('sourceSelector') &&
        json.containsKey('destinationSelector')) {
      return ConnectionRuleData(
        sourceSelector: ConnectionRuleSelector.fromJson(
          Map<String, dynamic>.from(json['sourceSelector'] ?? {}),
        ),
        destinationSelector: ConnectionRuleSelector.fromJson(
          Map<String, dynamic>.from(json['destinationSelector'] ?? {}),
        ),
      );
    }

    return ConnectionRuleData(
      sourceRef: DataItemRef.fromJson(json[JsonFields.SOURCE_REF] ?? {}),
      destinationRef:
          DataItemRef.fromJson(json[JsonFields.DESTINATION_REF] ?? {}),
    );
  }
}

/// Writable entity-scoped routing intent.
class ConnectionRule extends DataItemType<ConnectionRuleData> {
  ConnectionRule({
    required super.name,
    required ConnectionRuleData spec,
    NamespaceSelector? namespaceSelector,
  }) : super(
          spec: spec,
          namespaceSelector:
              namespaceSelector ?? const NamespaceSelector.currentEntity(),
        );

  ConnectionRule.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(ConnectionRuleData data) => data.toJson();

  factory ConnectionRule.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';
    final NamespaceSelector namespaceSelector = NamespaceSelector.fromJson(
        json[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>);

    ConnectionRuleData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = ConnectionRuleData.fromJson(
          json[JsonFields.SPEC] as Map<String, dynamic>);
    }

    ConnectionRuleData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved = ConnectionRuleData.fromJson(
          json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    return ConnectionRule.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );
  }
}

/// Stored rule that asks Epiphany to mirror routing from matching leaders.
class FollowRuleData {
  final DataItemRef followerRef;
  final SearchCriteria leaderCriteria;

  FollowRuleData({
    required this.followerRef,
    required this.leaderCriteria,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.FOLLOWER_REF: followerRef.toJson(),
      JsonFields.LEADER_CRITERIA: leaderCriteria.toJson(),
    }.toJsonClean();
  }

  factory FollowRuleData.fromJson(Map<String, dynamic> json) {
    return FollowRuleData(
      followerRef: DataItemRef.fromJson(
          Map<String, dynamic>.from(json[JsonFields.FOLLOWER_REF] ?? {})),
      leaderCriteria: SearchCriteria.fromJson(
          Map<String, dynamic>.from(json[JsonFields.LEADER_CRITERIA] ?? {})),
    );
  }
}

/// Writable entity-scoped routing intent for selector-based follow behavior.
class FollowRule extends DataItemType<FollowRuleData> {
  FollowRule({
    required super.name,
    required FollowRuleData spec,
    NamespaceSelector? namespaceSelector,
  }) : super(
          spec: spec,
          namespaceSelector:
              namespaceSelector ?? const NamespaceSelector.currentEntity(),
        );

  FollowRule.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(FollowRuleData data) => data.toJson();

  factory FollowRule.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';
    final NamespaceSelector namespaceSelector = NamespaceSelector.fromJson(
        json[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>);

    FollowRuleData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = FollowRuleData.fromJson(
          json[JsonFields.SPEC] as Map<String, dynamic>);
    }

    FollowRuleData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved = FollowRuleData.fromJson(
          json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    return FollowRule.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );
  }
}

