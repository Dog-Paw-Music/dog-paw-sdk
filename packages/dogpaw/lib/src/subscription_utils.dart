import 'app_logger.dart';
import 'namespace_selector.dart';
import 'data_item_ref.dart';

/// Builds the `DataItemRef` passed to a subscription callback.
///
/// Purpose:
/// Converts an incoming notification message plus the extracted payload value
/// into the item reference that the callback should see.
///
/// Parameters:
/// - `messageContent`: Full decoded notification message body from Epiphany.
/// - `value`: The payload extracted from `CallbackInfo.valueJsonKey`.
///
/// Return value:
/// - A parsed `DataItemRef` describing the item associated with the callback.
///
/// Requirements:
/// - `messageContent` and `value` must contain the fields expected by the
///   parser implementation.
///
/// Guarantees:
/// - Returned refs preserve the namespace/name information encoded by the
///   underlying notification schema.
///
/// Invariants:
/// - Parsers are pure helpers and do not mutate subscription state.
typedef DataItemRefParser = DataItemRef Function(
  Map<String, dynamic> messageContent,
  dynamic value,
);

/// Key used to match subscription callbacks with incoming notifications
/// Matches C++ SubscriptionKey
class SubscriptionKey {
  final String topic;
  final NamespaceSelector? namespaceSelector;
  final String? name;

  const SubscriptionKey._(this.topic, this.namespaceSelector, this.name);

  factory SubscriptionKey(String topic,
      {NamespaceSelector? namespaceSelector, String? name}) {
    if (namespaceSelector != null &&
        (namespaceSelector.isCurrentEntity ||
            namespaceSelector.isAllEntities)) {
      AppLogger.warning(
          "SubscriptionKey created with CURRENT_ENTITY or ALL_ENTITIES - should be resolved first");
    }
    return SubscriptionKey._(topic, namespaceSelector, name);
  }

  factory SubscriptionKey.fromDataItemRef(
      String topic, DataItemRef? dataItemRef) {
    NamespaceSelector? ns;
    String? name;

    if (dataItemRef != null) {
      // Read namespaceSelector directly from DataItemRef
      ns = dataItemRef.namespaceSelector;
      name = dataItemRef.name;
    }

    return SubscriptionKey._(topic, ns, name);
  }

  /// Check if this key (registered) matches the incoming key (notification)
  ///
  /// [other] is the incoming notification key
  bool matches(SubscriptionKey other) {
    if (topic != other.topic) {
      return false;
    }

    // If this (registered) has no namespace selector, it matches any namespace (wildcard)
    if (namespaceSelector == null) {
      return true;
    }

    // If this has a namespace but incoming doesn't, it matches
    // Might happen if we have a list of objects. Erring on the side of matching.
    if (other.namespaceSelector == null) {
      return true;
    }

    // Both have namespace selectors - compare them
    final thisNs = namespaceSelector!;
    final otherNs = other.namespaceSelector!;

    // Compare namespace type
    if (thisNs.type != otherNs.type) {
      return false;
    }

    // If both are SPECIFIC_ENTITY, compare sourceEntity values
    if (thisNs.type == NamespaceSelectorType.specificEntity) {
      if (thisNs.sourceEntity != otherNs.sourceEntity) {
        return false;
      }
    }

    // Namespace matches, now check name
    if (name == null) {
      return true; // Wildcard name
    }
    if (name != other.name) {
      return false;
    }

    return true;
  }

  @override
  String toString() =>
      'SubscriptionKey(topic: $topic, ns: $namespaceSelector, name: $name)';
}

/// Holds callback and keys for subscription management
/// Matches C++ CallbackInfo
class CallbackInfo {
  final List<SubscriptionKey> keys;
  final List<bool> oneOffs;
  final String valueJsonKey;
  final Function(String, DataItemRef, dynamic) handler;
  final DataItemRefParser refParser;

  CallbackInfo({
    required SubscriptionKey key,
    required this.valueJsonKey,
    required this.handler,
    DataItemRefParser? refParser,
    bool oneOff = false,
  })  : keys = [key],
        oneOffs = [oneOff],
        refParser = refParser ??
            ((Map<String, dynamic> _, dynamic value) =>
                DataItemRef.fromJson(value as Map<String, dynamic>));

  CallbackInfo.multi({
    required this.keys,
    required this.oneOffs,
    required this.valueJsonKey,
    required this.handler,
    DataItemRefParser? refParser,
  }) : refParser = refParser ??
            ((Map<String, dynamic> _, dynamic value) =>
                DataItemRef.fromJson(value as Map<String, dynamic>));

  void addKey(SubscriptionKey key, {bool oneOff = false}) {
    keys.add(key);
    oneOffs.add(oneOff);
  }

  /// Checks if any key matches and removes if it's a one-off
  bool matchesAndRemove(SubscriptionKey key) {
    bool ret = false;
    final toRemove = <int>[];

    for (int i = 0; i < keys.length; i++) {
      if (keys[i].matches(key)) {
        ret = true;
        if (oneOffs[i]) {
          toRemove.add(i);
        }
      }
    }

    if (toRemove.isNotEmpty) {
      // Remove in reverse order to maintain indices
      for (final index in toRemove.reversed) {
        keys.removeAt(index);
        oneOffs.removeAt(index);
      }
    }

    return ret;
  }

  /// Check if matches without side effects
  bool matches(SubscriptionKey key) {
    for (final k in keys) {
      if (k.matches(key)) {
        return true;
      }
    }
    return false;
  }
}
