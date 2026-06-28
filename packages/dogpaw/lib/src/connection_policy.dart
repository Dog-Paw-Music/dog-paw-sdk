import 'json_constants.dart';
import 'search_criteria.dart';

/// Connection policy defining how endpoints can be connected
class ConnectionPolicy {
  /// Maximum allowed connections (-1 = unlimited)
  final int maxConnections;

  /// Optional endpoint-owned connection rule for automatic peer matching.
  final SearchCriteria? endpointConnectionRule;

  /// Temporary compatibility alias for older auto-connect terminology.
  @Deprecated('Use endpointConnectionRule instead.')
  SearchCriteria? get autoConnectCriteria => endpointConnectionRule;

  /// Default constructor
  const ConnectionPolicy({
    this.maxConnections = -1,
    SearchCriteria? endpointConnectionRule,
    @Deprecated('Use endpointConnectionRule instead.')
    SearchCriteria? autoConnectCriteria,
  }) : assert(
          endpointConnectionRule == null || autoConnectCriteria == null,
          'Specify either endpointConnectionRule or autoConnectCriteria, not both.',
        ),
        endpointConnectionRule =
            endpointConnectionRule ?? autoConnectCriteria;

  /// Convert to JSON representation
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      JsonFields.MAX_CONNECTIONS: maxConnections,
    };

    if (endpointConnectionRule != null) {
      json[JsonFields.AUTO_CONNECT_CRITERIA] =
          endpointConnectionRule!.toJson();
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
    );
  }
}
