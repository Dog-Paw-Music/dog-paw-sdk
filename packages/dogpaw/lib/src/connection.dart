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
class ConnectionRequestData {
  final DataItemRef sourceRef;
  final DataItemRef destinationRef;

  ConnectionRequestData({
    required this.sourceRef,
    required this.destinationRef,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.SOURCE_REF: sourceRef.toJson(),
      JsonFields.DESTINATION_REF: destinationRef.toJson(),
    }.toJsonClean();
  }

  factory ConnectionRequestData.fromJson(Map<String, dynamic> json) {
    return ConnectionRequestData(
      sourceRef: DataItemRef.fromJson(json[JsonFields.SOURCE_REF] ?? {}),
      destinationRef:
          DataItemRef.fromJson(json[JsonFields.DESTINATION_REF] ?? {}),
    );
  }
}

/// Writable entity-scoped routing intent.
class ConnectionRequest extends DataItemType<ConnectionRequestData> {
  ConnectionRequest({
    required super.name,
    required ConnectionRequestData spec,
    NamespaceSelector? namespaceSelector,
  }) : super(
          spec: spec,
          namespaceSelector:
              namespaceSelector ?? const NamespaceSelector.currentEntity(),
        );

  ConnectionRequest.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(ConnectionRequestData data) => data.toJson();

  factory ConnectionRequest.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';
    final NamespaceSelector namespaceSelector = NamespaceSelector.fromJson(
        json[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>);

    ConnectionRequestData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = ConnectionRequestData.fromJson(
          json[JsonFields.SPEC] as Map<String, dynamic>);
    }

    ConnectionRequestData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved = ConnectionRequestData.fromJson(
          json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    return ConnectionRequest.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );
  }
}

/// Stored request that asks Epiphany to mirror routing from matching leaders.
class FollowRequestData {
  final DataItemRef followerRef;
  final SearchCriteria leaderCriteria;

  FollowRequestData({
    required this.followerRef,
    required this.leaderCriteria,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.FOLLOWER_REF: followerRef.toJson(),
      JsonFields.LEADER_CRITERIA: leaderCriteria.toJson(),
    }.toJsonClean();
  }

  factory FollowRequestData.fromJson(Map<String, dynamic> json) {
    return FollowRequestData(
      followerRef: DataItemRef.fromJson(
          Map<String, dynamic>.from(json[JsonFields.FOLLOWER_REF] ?? {})),
      leaderCriteria: SearchCriteria.fromJson(
          Map<String, dynamic>.from(json[JsonFields.LEADER_CRITERIA] ?? {})),
    );
  }
}

/// Writable entity-scoped routing intent for selector-based follow behavior.
class FollowRequest extends DataItemType<FollowRequestData> {
  FollowRequest({
    required super.name,
    required FollowRequestData spec,
    NamespaceSelector? namespaceSelector,
  }) : super(
          spec: spec,
          namespaceSelector:
              namespaceSelector ?? const NamespaceSelector.currentEntity(),
        );

  FollowRequest.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(FollowRequestData data) => data.toJson();

  factory FollowRequest.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';
    final NamespaceSelector namespaceSelector = NamespaceSelector.fromJson(
        json[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>);

    FollowRequestData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = FollowRequestData.fromJson(
          json[JsonFields.SPEC] as Map<String, dynamic>);
    }

    FollowRequestData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved = FollowRequestData.fromJson(
          json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    return FollowRequest.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );
  }
}
