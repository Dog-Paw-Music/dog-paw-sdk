import 'json_constants.dart';
import 'search_criteria.dart';

/// Connection policy defining how endpoints can be connected
class ConnectionPolicy {
  /// Maximum allowed connections (-1 = unlimited)
  final int maxConnections;

  /// Optional search criteria for automatic connection establishment
  final SearchCriteria? autoConnectCriteria;

  /// Default constructor
  const ConnectionPolicy({
    this.maxConnections = -1,
    this.autoConnectCriteria,
  });

  /// Convert to JSON representation
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      JsonFields.MAX_CONNECTIONS: maxConnections,
    };

    if (autoConnectCriteria != null) {
      json[JsonFields.AUTO_CONNECT_CRITERIA] = autoConnectCriteria!.toJson();
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
      autoConnectCriteria: autoConnect,
    );
  }
}
