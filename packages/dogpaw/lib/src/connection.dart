import 'data_item_type.dart';
import 'mapping_config.dart';
import 'connection_policy.dart';
import 'json_constants.dart';
import 'json_utils.dart';
import 'endpoint.dart';
import 'namespace_selector.dart';
import 'data_item_ref.dart';
import 'search_criteria.dart';

/// Connection data specification
class ConnectionData {
  final DataItemRef sourceRef;
  final DataItemRef destinationRef;
  final EndpointInfo? source;
  final EndpointInfo? destination;
  final MappingConfig mapping;
  final IndexConversionConfig indexConversion;
  final bool enabled;
  final Map<String, dynamic> fieldAttribution;
  final List<Map<String, dynamic>> contributingRationales;
  final String sourceLabel;
  final String sourceEntityLabel;
  final String destinationLabel;
  final String destinationEntityLabel;

  ConnectionData({
    required this.sourceRef,
    required this.destinationRef,
    this.source,
    this.destination,
    this.mapping = const MappingConfig(),
    this.indexConversion = const IndexConversionConfig(),
    this.enabled = true,
    this.fieldAttribution = const <String, dynamic>{},
    this.contributingRationales = const <Map<String, dynamic>>[],
    this.sourceLabel = '',
    this.sourceEntityLabel = '',
    this.destinationLabel = '',
    this.destinationEntityLabel = '',
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.SOURCE_REF: sourceRef.toJson(),
      JsonFields.DESTINATION_REF: destinationRef.toJson(),
      // Resolved endpoints are typically not serialized back to JSON for spec
      JsonFields.MAPPING: mapping.toJson(),
      JsonFields.INDEX_CONVERSION: indexConversion.toJson(),
      JsonFields.ENABLED: enabled,
      if (fieldAttribution.isNotEmpty)
        JsonFields.FIELD_ATTRIBUTION: fieldAttribution,
      if (contributingRationales.isNotEmpty)
        JsonFields.CONTRIBUTING_RATIONALES: contributingRationales,
      if (sourceLabel.isNotEmpty) JsonFields.SOURCE_LABEL: sourceLabel,
      if (sourceEntityLabel.isNotEmpty)
        JsonFields.SOURCE_ENTITY_LABEL: sourceEntityLabel,
      if (destinationLabel.isNotEmpty)
        JsonFields.DESTINATION_LABEL: destinationLabel,
      if (destinationEntityLabel.isNotEmpty)
        JsonFields.DESTINATION_ENTITY_LABEL: destinationEntityLabel,
    };
  }

  /// Parses projected connection content with optional envelope identity refs.
  ///
  /// [json] is a spec or resolved object. [fallbackSourceRef] and
  /// [fallbackDestinationRef] must be supplied when refs live only in the
  /// connection envelope. Returns typed projection content; does not mutate
  /// inputs. Effective defaults are read only from server-provided resolved
  /// content.
  factory ConnectionData.fromJson(
    Map<String, dynamic> json, {
    DataItemRef? fallbackSourceRef,
    DataItemRef? fallbackDestinationRef,
  }) {
    return ConnectionData(
      sourceRef: json.containsKey(JsonFields.SOURCE_REF)
          ? DataItemRef.fromJson(json[JsonFields.SOURCE_REF])
          : fallbackSourceRef!,
      destinationRef: json.containsKey(JsonFields.DESTINATION_REF)
          ? DataItemRef.fromJson(json[JsonFields.DESTINATION_REF])
          : fallbackDestinationRef!,
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
      fieldAttribution: Map<String, dynamic>.from(
          json[JsonFields.FIELD_ATTRIBUTION] ?? <String, dynamic>{}),
      contributingRationales:
          (json[JsonFields.CONTRIBUTING_RATIONALES] as List<dynamic>? ??
                  <dynamic>[])
              .map((dynamic item) =>
                  Map<String, dynamic>.from(item as Map<dynamic, dynamic>))
              .toList(),
      sourceLabel: json[JsonFields.SOURCE_LABEL] ?? '',
      sourceEntityLabel: json[JsonFields.SOURCE_ENTITY_LABEL] ?? '',
      destinationLabel: json[JsonFields.DESTINATION_LABEL] ?? '',
      destinationEntityLabel: json[JsonFields.DESTINATION_ENTITY_LABEL] ?? '',
    );
  }
}

/// Connection class
class Connection extends DataItemType<ConnectionData> {
  final DataItemRef? identitySourceRef;
  final DataItemRef? identityDestinationRef;

  Connection({
    required String name,
    required ConnectionData spec,
    NamespaceSelector? namespaceSelector,
  })  : identitySourceRef = spec.sourceRef,
        identityDestinationRef = spec.destinationRef,
        super(
          name: name,
          spec: spec,
          namespaceSelector: namespaceSelector,
        );

  Connection.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
    this.identitySourceRef,
    this.identityDestinationRef,
  });

  /// Returns the source pair identity from effective/spec data or the envelope.
  ///
  /// Requires a server payload with `sourceRef`; returns null only for malformed
  /// legacy payloads. Reading this value does not mutate connection state.
  DataItemRef? get sourceRef =>
      resolved?.sourceRef ?? spec?.sourceRef ?? identitySourceRef;

  /// Returns the destination pair identity from effective/spec data or envelope.
  ///
  /// Requires a server payload with `destinationRef`; returns null only for
  /// malformed legacy payloads. Reading this value does not mutate state.
  DataItemRef? get destinationRef =>
      resolved?.destinationRef ??
      spec?.destinationRef ??
      identityDestinationRef;

  @override
  Map<String, dynamic> specToJson(ConnectionData data) => data.toJson();

  factory Connection.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';
    const NamespaceSelector namespaceSelector = NamespaceSelector.global();
    final DataItemRef? identitySourceRef =
        json.containsKey(JsonFields.SOURCE_REF)
            ? DataItemRef.fromJson(json[JsonFields.SOURCE_REF])
            : null;
    final DataItemRef? identityDestinationRef =
        json.containsKey(JsonFields.DESTINATION_REF)
            ? DataItemRef.fromJson(json[JsonFields.DESTINATION_REF])
            : null;

    ConnectionData? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec = ConnectionData.fromJson(
        json[JsonFields.SPEC] as Map<String, dynamic>,
        fallbackSourceRef: identitySourceRef,
        fallbackDestinationRef: identityDestinationRef,
      );
    }

    ConnectionData? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved = ConnectionData.fromJson(
        json[JsonFields.RESOLVED] as Map<String, dynamic>,
        fallbackSourceRef: identitySourceRef,
        fallbackDestinationRef: identityDestinationRef,
      );
    }

    return Connection.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
      identitySourceRef: identitySourceRef,
      identityDestinationRef: identityDestinationRef,
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
  final MappingConfig? mapping;
  final IndexConversionConfig? indexConversion;
  final bool? enabled;
  final bool clearMapping;
  final bool clearIndexConversion;
  final bool clearEnabled;
  final Map<String, int> fieldPriorities;
  final Map<String, dynamic> extensions;

  ConnectionRuleData({
    DataItemRef? sourceRef,
    DataItemRef? destinationRef,
    ConnectionRuleSelector? sourceSelector,
    ConnectionRuleSelector? destinationSelector,
    this.mapping,
    this.indexConversion,
    this.enabled,
    this.clearMapping = false,
    this.clearIndexConversion = false,
    this.clearEnabled = false,
    this.fieldPriorities = const <String, int>{},
    this.extensions = const <String, dynamic>{},
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
        assert(mapping == null || !clearMapping,
            'mapping and clearMapping are mutually exclusive.'),
        assert(indexConversion == null || !clearIndexConversion,
            'indexConversion and clearIndexConversion are mutually exclusive.'),
        assert(enabled == null || !clearEnabled,
            'enabled and clearEnabled are mutually exclusive.'),
        sourceSelector =
            sourceSelector ?? ConnectionRuleSelector.endpointRef(sourceRef!),
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
      JsonFields.SOURCE_SELECTOR: sourceSelector.toJson(),
      JsonFields.DESTINATION_SELECTOR: destinationSelector.toJson(),
      if (mapping != null) JsonFields.MAPPING: mapping!.toJson(),
      if (clearMapping) JsonFields.MAPPING: null,
      if (indexConversion != null)
        JsonFields.INDEX_CONVERSION: indexConversion!.toJson(),
      if (clearIndexConversion) JsonFields.INDEX_CONVERSION: null,
      if (enabled != null) JsonFields.ENABLED: enabled,
      if (clearEnabled) JsonFields.ENABLED: null,
      if (fieldPriorities.isNotEmpty)
        JsonFields.FIELD_PRIORITIES: fieldPriorities,
      if (extensions.isNotEmpty) JsonFields.EXTENSIONS: extensions,
    };
  }

  factory ConnectionRuleData.fromJson(Map<String, dynamic> json) {
    if (json.containsKey(JsonFields.SOURCE_SELECTOR) &&
        json.containsKey(JsonFields.DESTINATION_SELECTOR)) {
      return ConnectionRuleData(
        sourceSelector: ConnectionRuleSelector.fromJson(
          Map<String, dynamic>.from(
              json[JsonFields.SOURCE_SELECTOR] ?? <String, dynamic>{}),
        ),
        destinationSelector: ConnectionRuleSelector.fromJson(
          Map<String, dynamic>.from(
              json[JsonFields.DESTINATION_SELECTOR] ?? <String, dynamic>{}),
        ),
        mapping: json[JsonFields.MAPPING] is Map
            ? MappingConfig.fromJson(
                Map<String, dynamic>.from(json[JsonFields.MAPPING]))
            : null,
        indexConversion: json[JsonFields.INDEX_CONVERSION] is Map
            ? IndexConversionConfig.fromJson(
                Map<String, dynamic>.from(json[JsonFields.INDEX_CONVERSION]))
            : null,
        enabled: json[JsonFields.ENABLED] is bool
            ? json[JsonFields.ENABLED] as bool
            : null,
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
