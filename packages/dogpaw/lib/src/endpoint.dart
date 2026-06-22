import 'dart:typed_data';
import 'dart:convert';

import 'app_logger.dart';

import 'data_item_type.dart';
import 'data_types.dart';
import 'data_type_spec.dart';
import 'connection_policy.dart';
import 'json_constants.dart';
import 'data_item_ref.dart';
import 'namespace_selector.dart';
import 'json_utils.dart';
import 'key_event.dart';
import 'led_message.dart';
import 'near_press_position_data.dart';
import 'pos_data.dart';
import 'result.dart';
import 'scope_buffer_data.dart';

/// How a JACK-capable endpoint binds to the JACK graph.
enum JackBindingMode {
  registerNewPort,
  adoptExistingPort,
}

/// Concrete queue payload carried by a message-queue endpoint.
enum MessageQueuePayloadContract {
  endpointData,
  statefulFloatAction,
  statefulIntAction,
  statefulToggleAction,
  statefulEnumAction,
  statefulColorAction,
}

/// Owner behavior for a stateful input endpoint.
enum StatefulInputBehavior {
  autoReduced,
  ownerManaged,
}

/// Owner-side consumption mode for a stateful input endpoint.
enum StatefulInputConsumptionMode {
  callbackOnly,
  retainedStateOnly,
  callbackAndRetainedState,
}

/// Public matched-output configuration paired with a stateful input endpoint.
class MatchedStateOutputSpec {
  final String name;
  final String displayName;
  final String description;
  final List<String> flags;
  final String? groupKey;

  const MatchedStateOutputSpec({
    required this.name,
    this.displayName = '',
    this.description = '',
    this.flags = const <String>[],
    this.groupKey,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.NAME: name,
      JsonFields.DISPLAY_NAME: displayName,
      JsonFields.DESCRIPTION: description,
      JsonFields.FLAGS: flags,
      JsonFields.GROUP_KEY: groupKey,
    }.toJsonClean();
  }

  factory MatchedStateOutputSpec.fromJson(Map<String, dynamic> json) {
    return MatchedStateOutputSpec(
      name: json[JsonFields.NAME] as String? ?? '',
      displayName: json[JsonFields.DISPLAY_NAME] as String? ?? '',
      description: json[JsonFields.DESCRIPTION] as String? ?? '',
      flags: (json[JsonFields.FLAGS] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      groupKey: json[JsonFields.GROUP_KEY] as String?,
    );
  }
}

/// Stateful contract nested under one input endpoint spec.
class EndpointStatefulInputSpec {
  final StatefulInputBehavior behavior;
  final StatefulInputConsumptionMode consumptionMode;
  final Object? initialValue;
  final MatchedStateOutputSpec? matchedOutput;

  const EndpointStatefulInputSpec({
    this.behavior = StatefulInputBehavior.autoReduced,
    this.consumptionMode =
        StatefulInputConsumptionMode.callbackAndRetainedState,
    this.initialValue,
    this.matchedOutput,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.STATEFUL_BEHAVIOR: switch (behavior) {
        StatefulInputBehavior.autoReduced =>
          JsonFields.STATEFUL_BEHAVIOR_AUTO_REDUCED,
        StatefulInputBehavior.ownerManaged =>
          JsonFields.STATEFUL_BEHAVIOR_OWNER_MANAGED,
      },
      JsonFields.STATEFUL_CONSUMPTION_MODE: switch (consumptionMode) {
        StatefulInputConsumptionMode.callbackOnly =>
          JsonFields.STATEFUL_CONSUMPTION_CALLBACK_ONLY,
        StatefulInputConsumptionMode.retainedStateOnly =>
          JsonFields.STATEFUL_CONSUMPTION_RETAINED_STATE_ONLY,
        StatefulInputConsumptionMode.callbackAndRetainedState =>
          JsonFields.STATEFUL_CONSUMPTION_CALLBACK_AND_RETAINED_STATE,
      },
      JsonFields.INITIAL_VALUE: initialValue,
      JsonFields.MATCHED_OUTPUT: matchedOutput?.toJson(),
    }.toJsonClean();
  }

  factory EndpointStatefulInputSpec.fromJson(Map<String, dynamic> json) {
    return EndpointStatefulInputSpec(
      behavior: json[JsonFields.STATEFUL_BEHAVIOR] ==
              JsonFields.STATEFUL_BEHAVIOR_OWNER_MANAGED
          ? StatefulInputBehavior.ownerManaged
          : StatefulInputBehavior.autoReduced,
      consumptionMode: switch (json[JsonFields.STATEFUL_CONSUMPTION_MODE]) {
        JsonFields.STATEFUL_CONSUMPTION_CALLBACK_ONLY =>
          StatefulInputConsumptionMode.callbackOnly,
        JsonFields.STATEFUL_CONSUMPTION_RETAINED_STATE_ONLY =>
          StatefulInputConsumptionMode.retainedStateOnly,
        _ => StatefulInputConsumptionMode.callbackAndRetainedState,
      },
      initialValue: json[JsonFields.INITIAL_VALUE],
      matchedOutput: json[JsonFields.MATCHED_OUTPUT] is Map<String, dynamic>
          ? MatchedStateOutputSpec.fromJson(
              json[JsonFields.MATCHED_OUTPUT] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// Complete endpoint specification
///
/// WARNING: Keep in sync with C++ EndpointSpec in dogPawEntity/cpp/EndpointData.hpp
class EndpointSpec {
  /// Human-readable name
  final String displayName;

  /// Detailed description
  final String description;

  /// Data flow direction
  final EndpointDirection direction;

  /// Type and constraints
  final DataTypeSpec dataType;

  /// Connection behavior
  final ConnectionPolicy connectionPolicy;

  /// Data flow category (default: message queue)
  final EndpointCategory category;

  /// Concrete queue payload used when [category] is message queue.
  final MessageQueuePayloadContract messageQueuePayloadContract;

  /// JACK client name for ordinary JACK-backed endpoints.
  final String? jackClientName;

  /// Canonical physical JACK port name when known.
  final String? fullJackPortName;

  /// Whether the endpoint registers or adopts a JACK port.
  final JackBindingMode jackBindingMode;

  /// Semantic tags used by search and auto-connect.
  final List<String> flags;

  /// Optional grouping key for stereo/device grouping.
  final String? groupKey;

  /// Optional backing endpoint reference for output shims.
  final DataItemRef? shimTargetRef;

  /// Optional stateful-input contract layered on queue inputs.
  final EndpointStatefulInputSpec? statefulInput;

  const EndpointSpec({
    required this.direction,
    required this.dataType,
    this.displayName = '',
    this.description = '',
    this.connectionPolicy = const ConnectionPolicy(),
    this.category = EndpointCategory.messageQueue,
    this.messageQueuePayloadContract =
        MessageQueuePayloadContract.endpointData,
    this.jackClientName,
    this.fullJackPortName,
    this.jackBindingMode = JackBindingMode.registerNewPort,
    this.flags = const <String>[],
    this.groupKey,
    this.shimTargetRef,
    this.statefulInput,
  });

  /// Purpose: Resolve the concrete queue payload contract used by this spec.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - The action-oriented payload contract for supported scalar/control
  ///   message-queue endpoints, or the stored contract for all other cases.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Endpoint metadata remains unchanged.
  ///
  /// Invariants:
  /// - `endpointData` is treated as a sentinel default for supported scalar
  ///   queue types rather than an instruction to force raw-value transport.
  MessageQueuePayloadContract get effectiveMessageQueuePayloadContract =>
      _resolveEffectiveMessageQueuePayloadContract(
        category: category,
        dataType: dataType,
        requestedContract: messageQueuePayloadContract,
      );

  /// Purpose: Report whether this spec uses a typed action queue payload.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - `true` when this spec resolves to a non-raw message-queue contract.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Endpoint metadata remains unchanged.
  ///
  /// Invariants:
  /// - This depends only on the spec fields.
  bool get usesActionMessageQueuePayload =>
      category == EndpointCategory.messageQueue &&
      effectiveMessageQueuePayloadContract !=
          MessageQueuePayloadContract.endpointData;

  static MessageQueuePayloadContract _resolveEffectiveMessageQueuePayloadContract({
    required EndpointCategory category,
    required DataTypeSpec dataType,
    required MessageQueuePayloadContract requestedContract,
  }) {
    if (category != EndpointCategory.messageQueue ||
        requestedContract != MessageQueuePayloadContract.endpointData) {
      return requestedContract;
    }

    switch (dataType.baseType) {
      case DataType.float:
        return MessageQueuePayloadContract.statefulFloatAction;
      case DataType.int_:
        return MessageQueuePayloadContract.statefulIntAction;
      case DataType.toggle:
        return MessageQueuePayloadContract.statefulToggleAction;
      case DataType.enum_:
        return MessageQueuePayloadContract.statefulEnumAction;
      case DataType.color:
        return MessageQueuePayloadContract.statefulColorAction;
      default:
        return requestedContract;
    }
  }

  Map<String, dynamic> toJson() {
    String directionStr;
    switch (direction) {
      case EndpointDirection.input:
        directionStr = JsonFields.DIRECTION_INPUT;
        break;
      case EndpointDirection.output:
        directionStr = JsonFields.DIRECTION_OUTPUT;
        break;
      case EndpointDirection.bidirectional:
        directionStr = JsonFields.DIRECTION_BIDIRECTIONAL;
        break;
    }

    String categoryStr;
    switch (category) {
      case EndpointCategory.messageQueue:
        categoryStr = JsonFields.CATEGORY_MESSAGE_QUEUE;
        break;
      case EndpointCategory.continuous:
        categoryStr = JsonFields.CATEGORY_CONTINUOUS;
        break;
      case EndpointCategory.audioStream:
        categoryStr = JsonFields.CATEGORY_AUDIO_STREAM;
        break;
      case EndpointCategory.jackMidiStream:
        categoryStr = JsonFields.CATEGORY_JACK_MIDI_STREAM;
        break;
      case EndpointCategory.fileBacked:
        categoryStr = JsonFields.CATEGORY_FILE_BACKED;
        break;
    }

    final String jackBindingModeStr = switch (jackBindingMode) {
      JackBindingMode.registerNewPort =>
        JsonFields.JACK_BINDING_MODE_REGISTER_NEW_PORT,
      JackBindingMode.adoptExistingPort =>
        JsonFields.JACK_BINDING_MODE_ADOPT_EXISTING_PORT,
    };

    return <String, dynamic>{
      JsonFields.DISPLAY_NAME: displayName,
      JsonFields.DESCRIPTION: description,
      JsonFields.DIRECTION: directionStr,
      JsonFields.DATA_TYPE: dataType.toJson(),
      JsonFields.CONNECTION_POLICY: connectionPolicy.toJson(),
      JsonFields.CATEGORY: categoryStr,
      JsonFields.MESSAGE_QUEUE_PAYLOAD_CONTRACT:
          switch (effectiveMessageQueuePayloadContract) {
        MessageQueuePayloadContract.endpointData =>
          JsonFields.MESSAGE_QUEUE_PAYLOAD_ENDPOINT_DATA,
        MessageQueuePayloadContract.statefulFloatAction =>
          JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_FLOAT_ACTION,
        MessageQueuePayloadContract.statefulIntAction =>
          JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_INT_ACTION,
        MessageQueuePayloadContract.statefulToggleAction =>
          JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_TOGGLE_ACTION,
        MessageQueuePayloadContract.statefulEnumAction =>
          JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_ENUM_ACTION,
        MessageQueuePayloadContract.statefulColorAction =>
          JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_COLOR_ACTION,
      },
      JsonFields.JACK_CLIENT_NAME: jackClientName,
      JsonFields.FULL_JACK_PORT_NAME: fullJackPortName,
      JsonFields.JACK_BINDING_MODE: jackBindingModeStr,
      JsonFields.FLAGS: flags,
      JsonFields.GROUP_KEY: groupKey,
      JsonFields.SHIM_TARGET_REF: shimTargetRef?.toJson(),
      JsonFields.STATEFUL_INPUT: statefulInput?.toJson(),
    }.toJsonClean();
  }

  factory EndpointSpec.fromJson(Map<String, dynamic> json) {
    return EndpointSpec(
      direction: EndpointDirection.values.firstWhere(
        (e) {
          if (e == EndpointDirection.input) {
            return json[JsonFields.DIRECTION] == JsonFields.DIRECTION_INPUT;
          }
          if (e == EndpointDirection.output) {
            return json[JsonFields.DIRECTION] == JsonFields.DIRECTION_OUTPUT;
          }
          if (e == EndpointDirection.bidirectional) {
            return json[JsonFields.DIRECTION] ==
                JsonFields.DIRECTION_BIDIRECTIONAL;
          }
          return e.name == json[JsonFields.DIRECTION];
        },
        orElse: () => EndpointDirection.input,
      ),
      dataType: DataTypeSpec.fromJson(json[JsonFields.DATA_TYPE] ?? {}),
      displayName: json[JsonFields.DISPLAY_NAME] ?? '',
      description: json[JsonFields.DESCRIPTION] ?? '',
      connectionPolicy:
          ConnectionPolicy.fromJson(json[JsonFields.CONNECTION_POLICY] ?? {}),
      category: EndpointCategory.values.firstWhere(
        (e) {
          if (e == EndpointCategory.messageQueue) {
            return json[JsonFields.CATEGORY] ==
                JsonFields.CATEGORY_MESSAGE_QUEUE;
          }
          if (e == EndpointCategory.continuous) {
            return json[JsonFields.CATEGORY] == JsonFields.CATEGORY_CONTINUOUS;
          }
          if (e == EndpointCategory.audioStream) {
            return json[JsonFields.CATEGORY] ==
                JsonFields.CATEGORY_AUDIO_STREAM;
          }
          if (e == EndpointCategory.jackMidiStream) {
            return json[JsonFields.CATEGORY] ==
                JsonFields.CATEGORY_JACK_MIDI_STREAM;
          }
          if (e == EndpointCategory.fileBacked) {
            return json[JsonFields.CATEGORY] == JsonFields.CATEGORY_FILE_BACKED;
          }

          return e.name == json[JsonFields.CATEGORY];
        },
        orElse: () => EndpointCategory.messageQueue,
      ),
      messageQueuePayloadContract:
          switch (json[JsonFields.MESSAGE_QUEUE_PAYLOAD_CONTRACT]) {
        JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_FLOAT_ACTION =>
          MessageQueuePayloadContract.statefulFloatAction,
        JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_INT_ACTION =>
          MessageQueuePayloadContract.statefulIntAction,
        JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_TOGGLE_ACTION =>
          MessageQueuePayloadContract.statefulToggleAction,
        JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_ENUM_ACTION =>
          MessageQueuePayloadContract.statefulEnumAction,
        JsonFields.MESSAGE_QUEUE_PAYLOAD_STATEFUL_COLOR_ACTION =>
          MessageQueuePayloadContract.statefulColorAction,
        _ => MessageQueuePayloadContract.endpointData,
      },
      jackClientName: json[JsonFields.JACK_CLIENT_NAME] as String?,
      fullJackPortName: json[JsonFields.FULL_JACK_PORT_NAME] as String?,
      jackBindingMode: json[JsonFields.JACK_BINDING_MODE] ==
              JsonFields.JACK_BINDING_MODE_ADOPT_EXISTING_PORT
          ? JackBindingMode.adoptExistingPort
          : JackBindingMode.registerNewPort,
      flags: (json[JsonFields.FLAGS] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      groupKey: json[JsonFields.GROUP_KEY] as String?,
      shimTargetRef: json[JsonFields.SHIM_TARGET_REF] is Map<String, dynamic>
          ? DataItemRef.fromJson(
              json[JsonFields.SHIM_TARGET_REF] as Map<String, dynamic>,
            )
          : null,
      statefulInput: json[JsonFields.STATEFUL_INPUT] is Map<String, dynamic>
          ? EndpointStatefulInputSpec.fromJson(
              json[JsonFields.STATEFUL_INPUT] as Map<String, dynamic>,
            )
          : null,
    );
  }

  EndpointSpec copyWithStatefulTransport({
    MessageQueuePayloadContract? messageQueuePayloadContract,
    EndpointStatefulInputSpec? statefulInput,
  }) {
    return EndpointSpec(
      displayName: displayName,
      description: description,
      direction: direction,
      dataType: dataType,
      connectionPolicy: connectionPolicy,
      category: category,
      messageQueuePayloadContract:
          messageQueuePayloadContract ?? this.messageQueuePayloadContract,
      jackClientName: jackClientName,
      fullJackPortName: fullJackPortName,
      jackBindingMode: jackBindingMode,
      flags: flags,
      groupKey: groupKey,
      shimTargetRef: shimTargetRef,
      statefulInput: statefulInput ?? this.statefulInput,
    );
  }
}

enum StatefulFloatActionType { setValue, add }
enum StatefulIntActionType { setValue, add }
enum StatefulToggleActionType { setValue, toggle }
enum StatefulEnumActionType { setId, step }
enum StatefulColorActionType { setValue }

class StatefulFloatAction {
  final StatefulFloatActionType action;
  final double value;

  const StatefulFloatAction({
    required this.action,
    required this.value,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.ACTION: action == StatefulFloatActionType.add
            ? JsonFields.STATEFUL_ACTION_ADD
            : JsonFields.STATEFUL_ACTION_SET_VALUE,
        JsonFields.VALUE: value,
      };

  factory StatefulFloatAction.fromJson(Map<String, dynamic> json) {
    return StatefulFloatAction(
      action: json[JsonFields.ACTION] == JsonFields.STATEFUL_ACTION_ADD
          ? StatefulFloatActionType.add
          : StatefulFloatActionType.setValue,
      value: (json[JsonFields.VALUE] as num).toDouble(),
    );
  }
}

class StatefulIntAction {
  final StatefulIntActionType action;
  final int value;

  const StatefulIntAction({
    required this.action,
    required this.value,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.ACTION: action == StatefulIntActionType.add
            ? JsonFields.STATEFUL_ACTION_ADD
            : JsonFields.STATEFUL_ACTION_SET_VALUE,
        JsonFields.VALUE: value,
      };

  factory StatefulIntAction.fromJson(Map<String, dynamic> json) {
    return StatefulIntAction(
      action: json[JsonFields.ACTION] == JsonFields.STATEFUL_ACTION_ADD
          ? StatefulIntActionType.add
          : StatefulIntActionType.setValue,
      value: json[JsonFields.VALUE] as int? ?? 0,
    );
  }
}

class StatefulToggleAction {
  final StatefulToggleActionType action;
  final bool value;

  const StatefulToggleAction({
    required this.action,
    required this.value,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.ACTION: action == StatefulToggleActionType.toggle
            ? JsonFields.STATEFUL_ACTION_TOGGLE
            : JsonFields.STATEFUL_ACTION_SET_VALUE,
        JsonFields.VALUE: value,
      };

  factory StatefulToggleAction.fromJson(Map<String, dynamic> json) {
    return StatefulToggleAction(
      action: json[JsonFields.ACTION] == JsonFields.STATEFUL_ACTION_TOGGLE
          ? StatefulToggleActionType.toggle
          : StatefulToggleActionType.setValue,
      value: json[JsonFields.VALUE] as bool? ?? false,
    );
  }
}

class StatefulEnumAction {
  final StatefulEnumActionType action;
  final int value;

  const StatefulEnumAction({
    required this.action,
    required this.value,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.ACTION: action == StatefulEnumActionType.step
            ? JsonFields.STATEFUL_ACTION_STEP
            : JsonFields.STATEFUL_ACTION_SET_ID,
        JsonFields.VALUE: value,
      };

  factory StatefulEnumAction.fromJson(Map<String, dynamic> json) {
    return StatefulEnumAction(
      action: json[JsonFields.ACTION] == JsonFields.STATEFUL_ACTION_STEP
          ? StatefulEnumActionType.step
          : StatefulEnumActionType.setId,
      value: json[JsonFields.VALUE] as int? ?? 0,
    );
  }
}

class StatefulColorAction {
  final StatefulColorActionType action;
  final int value;

  const StatefulColorAction({
    required this.action,
    required this.value,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.ACTION: JsonFields.STATEFUL_ACTION_SET_VALUE,
        JsonFields.VALUE: value,
      };

  factory StatefulColorAction.fromJson(Map<String, dynamic> json) {
    return StatefulColorAction(
      action: StatefulColorActionType.setValue,
      value: json[JsonFields.VALUE] as int? ?? 0,
    );
  }
}

class StatefulEnumCommittedState {
  final int id;

  const StatefulEnumCommittedState({
    required this.id,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.ID: id,
      };

  factory StatefulEnumCommittedState.fromJson(Map<String, dynamic> json) {
    return StatefulEnumCommittedState(
      id: json[JsonFields.ID] as int? ?? 0,
    );
  }
}

/// Immutable-ish metadata snapshot for one endpoint.
class EndpointInfo extends DataItemType<EndpointSpec> {
  // Fully-resolved resource paths/names (assigned by Epiphany for OUTPUT endpoints)
  String? _queueShmName;
  String? _socketPath;
  String? _sharedDataName;
  String? _shmNamespacePrefix;
  String? _jackPortName;
  String? _filePath;

  /// Getters for fully resolved runtime resource names.
  String? get queueShmName => _queueShmName;
  String? get socketPath => _socketPath;
  String? get sharedDataName => _sharedDataName;
  String? get shmNamespacePrefix => _shmNamespacePrefix;
  String? get jackPortName => _jackPortName;
  String? get filePath => _filePath;

  EndpointInfo({
    required super.name,
    required EndpointSpec spec,
    super.namespaceSelector,
  }) : super(
          spec: spec,
        );

  EndpointInfo.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  });

  @override
  Map<String, dynamic> specToJson(EndpointSpec data) => data.toJson();

  factory EndpointInfo.fromJson(Map<String, dynamic> json) {
    final name = json[JsonFields.NAME] as String? ?? '';

    // Parse namespace selector from JSON
    // Note: Endpoints cannot use GLOBAL namespace
    NamespaceSelector namespaceSelector = NamespaceSelector.fromJson(
        json[JsonFields.NAMESPACE_SELECTOR] as Map<String, dynamic>);

    EndpointSpec? spec;
    if (json.containsKey(JsonFields.SPEC)) {
      spec =
          EndpointSpec.fromJson(json[JsonFields.SPEC] as Map<String, dynamic>);
    }

    EndpointSpec? resolved;
    if (json.containsKey(JsonFields.RESOLVED)) {
      resolved = EndpointSpec.fromJson(
          json[JsonFields.RESOLVED] as Map<String, dynamic>);
    }

    final endpoint = EndpointInfo.full(
      name: name,
      namespaceSelector: namespaceSelector,
      spec: spec,
      resolved: resolved,
    );

    // Parse sharedMemory object with fully-resolved paths/names from Epiphany
    if (json.containsKey('sharedMemory')) {
      final sharedMemory = json['sharedMemory'] as Map<String, dynamic>;
      endpoint._queueShmName =
          sharedMemory[JsonFields.QUEUE_SHM_NAME] as String?;
      endpoint._socketPath = sharedMemory[JsonFields.SOCKET_PATH] as String?;
      endpoint._sharedDataName =
          sharedMemory[JsonFields.SHARED_DATA_NAME] as String?;
      endpoint._shmNamespacePrefix =
          sharedMemory[JsonFields.SHM_NAMESPACE_PREFIX] as String?;
      endpoint._jackPortName =
          sharedMemory[JsonFields.JACK_PORT_NAME] as String?;
      endpoint._filePath = sharedMemory[JsonFields.FILE_PATH] as String?;
    }

    return endpoint;
  }

  /// Purpose: Copy metadata fields from another endpoint snapshot.
  ///
  /// Parameters:
  /// - [other]: `EndpointInfo` whose metadata should replace this snapshot.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [other] describes the same logical endpoint identity or a newer snapshot
  ///   that should replace this one.
  ///
  /// Guarantees/Postconditions:
  /// - This instance's public metadata and resolved resource fields match
  ///   [other] after the call returns.
  ///
  /// Invariants:
  /// - No native runtime handles are created, destroyed, or mutated here.
  void copyMetadataFrom(EndpointInfo other) {
    final EndpointSpec? previousSpec = spec;
    final EndpointSpec? previousResolved = resolved;
    name = other.name;
    namespaceSelector = other.namespaceSelector;
    spec = other.spec;
    resolved = other.resolved;
    if (spec != null &&
        previousSpec != null &&
        spec!.messageQueuePayloadContract ==
            MessageQueuePayloadContract.endpointData &&
        previousSpec.messageQueuePayloadContract !=
            MessageQueuePayloadContract.endpointData) {
      spec = spec!.copyWithStatefulTransport(
        messageQueuePayloadContract: previousSpec.messageQueuePayloadContract,
      );
    }
    if (spec != null &&
        previousSpec != null &&
        spec!.statefulInput == null &&
        previousSpec.statefulInput != null) {
      spec = spec!.copyWithStatefulTransport(
        statefulInput: previousSpec.statefulInput,
      );
    }
    if (resolved != null &&
        previousResolved != null &&
        resolved!.messageQueuePayloadContract ==
            MessageQueuePayloadContract.endpointData &&
        previousResolved.messageQueuePayloadContract !=
            MessageQueuePayloadContract.endpointData) {
      resolved = resolved!.copyWithStatefulTransport(
        messageQueuePayloadContract:
            previousResolved.messageQueuePayloadContract,
      );
    }
    if (resolved != null &&
        previousResolved != null &&
        resolved!.statefulInput == null &&
        previousResolved.statefulInput != null) {
      resolved = resolved!.copyWithStatefulTransport(
        statefulInput: previousResolved.statefulInput,
      );
    }
    _queueShmName = other._queueShmName;
    _socketPath = other._socketPath;
    _sharedDataName = other._sharedDataName;
    _shmNamespacePrefix = other._shmNamespacePrefix;
    _jackPortName = other._jackPortName;
    _filePath = other._filePath;
  }
}

/// One serialized payload polled from the native local-endpoint runtime.
class LocalEndpointPollPacket {
  /// Realized connection identifier that produced these bytes.
  final String connectionName;

  /// Serialized payload bytes from the native endpoint runtime.
  final Uint8List bytes;

  /// Effective connection-specific payload shape for these bytes.
  final IndexSpec indexSpec;

  const LocalEndpointPollPacket({
    required this.connectionName,
    required this.bytes,
    required this.indexSpec,
  });
}

/// Sender metadata for one realized local-endpoint connection.
class EndpointSenderInfo {
  /// Realized Epiphany connection identifier.
  final String connectionName;

  /// Logical source endpoint participating in this connection.
  final DataItemRef sourceEndpointRef;

  const EndpointSenderInfo({
    required this.connectionName,
    required this.sourceEndpointRef,
  });
}

/// One decoded polled payload paired with sender metadata.
class LocalEndpointPollResult {
  /// Decoded payload value for the endpoint's declared data type.
  final dynamic data;

  /// Logical sender metadata for the realized connection that produced [data].
  final EndpointSenderInfo senderInfo;

  const LocalEndpointPollResult({
    required this.data,
    required this.senderInfo,
  });
}

/// Semantic observation that one realized connection became available.
class LocalEndpointConnectionAddedEvent {
  /// Realized connection identifier assigned by Epiphany.
  final String connectionName;

  /// Peer endpoint participating in this realized connection.
  final DataItemRef peerEndpointRef;

  const LocalEndpointConnectionAddedEvent({
    required this.connectionName,
    required this.peerEndpointRef,
  });
}

/// Semantic observation that one realized connection was removed.
class LocalEndpointConnectionRemovedEvent {
  /// Realized connection identifier assigned by Epiphany.
  final String connectionName;

  /// Peer endpoint that used to participate in this connection.
  final DataItemRef peerEndpointRef;

  const LocalEndpointConnectionRemovedEvent({
    required this.connectionName,
    required this.peerEndpointRef,
  });
}

/// Semantic observation that one realized input connection changed shape.
class LocalEndpointConnectionIndexSpecChangedEvent {
  /// Realized connection identifier assigned by Epiphany.
  final String connectionName;

  /// Peer endpoint whose source-side shape changed.
  final DataItemRef peerEndpointRef;

  /// Latest source-side index specification for this connection.
  final IndexSpec newIndexSpec;

  const LocalEndpointConnectionIndexSpecChangedEvent({
    required this.connectionName,
    required this.peerEndpointRef,
    required this.newIndexSpec,
  });
}

/// Internal runtime adapter used by `LocalEndpoint` for native-backed I/O.
abstract class LocalEndpointRuntimeDelegate {
  /// Number of currently realized native input connections.
  int get inputConnectionCount;

  /// Read the native retained-state snapshot for this local endpoint.
  EndpointRetainedStateSnapshot getRetainedStateSnapshot();

  /// Adopt one retained-state snapshot into the native local endpoint runtime.
  bool adoptRetainedStateSnapshot(
    EndpointRetainedStateSnapshot snapshot, {
    bool publishMatchedOutput = true,
    EndpointSenderInfo? senderInfo,
  });

  /// Write serialized bytes through the native local endpoint runtime.
  bool writeBytes(Uint8List bytes, {bool immediate = true});

  /// Poll serialized bytes from the native local endpoint runtime.
  List<LocalEndpointPollPacket> pollBytes({String? connectionName});

  /// Poll changed file-backed bytes from the native local endpoint runtime.
  List<LocalEndpointPollPacket> pollFileBackedBytes({String? connectionName});

  /// Read current file-backed bytes from the native local endpoint runtime.
  List<LocalEndpointPollPacket> readFileBackedBytes({String? connectionName});

  /// Release any delegate-owned runtime resources.
  void dispose();
}

/// Live runtime endpoint owned by the current Dart `DogPawEntity`.
class LocalEndpoint extends EndpointInfo {
  static const int _voiceRefSizeBytes = 16;
  static const int _keySourceSizeBytes = 12;
  static const int _voiceMemberSizeBytes = 40;
  static const int _voiceMessageSizeBytes = 724;
  static const int _maxVoiceMembers = 16;

  /// The number of input handles currently tracked for this local endpoint.
  int get inputHandlesCount => _runtimeDelegate?.inputConnectionCount ?? 0;

  LocalEndpointRuntimeDelegate? _runtimeDelegate;
  void Function(LocalEndpointConnectionAddedEvent event)?
      _connectionAddedCallback;
  void Function(LocalEndpointConnectionRemovedEvent event)?
      _connectionRemovedCallback;
  void Function(LocalEndpointConnectionIndexSpecChangedEvent event)?
      _connectionIndexSpecChangedCallback;
  void Function(StatefulFloatAction action, EndpointSenderInfo senderInfo)?
      _statefulFloatInputCallback;
  void Function(StatefulIntAction action, EndpointSenderInfo senderInfo)?
      _statefulIntInputCallback;
  void Function(StatefulToggleAction action, EndpointSenderInfo senderInfo)?
      _statefulToggleInputCallback;
  void Function(StatefulEnumAction action, EndpointSenderInfo senderInfo)?
      _statefulEnumInputCallback;
  void Function(StatefulColorAction action, EndpointSenderInfo senderInfo)?
      _statefulColorInputCallback;
  EndpointRetainedStateSnapshot? _callbackScopedRetainedStateSnapshot;
  final Map<String, EndpointSenderInfo> _senderInfoByConnectionName =
      <String, EndpointSenderInfo>{};

  LocalEndpoint({
    required super.name,
    required super.spec,
    super.namespaceSelector,
  });

  LocalEndpoint.full({
    required super.name,
    super.namespaceSelector,
    super.spec,
    super.resolved,
  }) : super.full(
        );

  /// Purpose: Create one local runtime endpoint from endpoint metadata.
  ///
  /// Parameters:
  /// - [info]: `EndpointInfo` snapshot received from the native bridge.
  ///
  /// Return value:
  /// - `LocalEndpoint` with identical metadata and no runtime handles yet.
  ///
  /// Requirements/Preconditions:
  /// - [info] describes an endpoint owned by the current entity.
  ///
  /// Guarantees/Postconditions:
  /// - The returned endpoint preserves all metadata and resolved resource names
  ///   from [info].
  ///
  /// Invariants:
  /// - Runtime handles are still lazily initialized after construction.
  factory LocalEndpoint.fromEndpointInfo(EndpointInfo info) {
    final EndpointSpec? initialSpec = info.spec ?? info.resolved;
    if (initialSpec == null) {
      throw StateError(
        'LocalEndpoint requires spec or resolved metadata to initialize.',
      );
    }
    final LocalEndpoint endpoint = LocalEndpoint.full(
      name: info.name,
      namespaceSelector: info.namespaceSelector,
      spec: initialSpec,
      resolved: info.resolved,
    );
    endpoint.copyMetadataFrom(info);
    return endpoint;
  }

  /// Purpose: Attach the native-backed runtime delegate used for live endpoint
  /// I/O.
  ///
  /// Parameters:
  /// - [runtimeDelegate]: native runtime delegate for this local endpoint.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [runtimeDelegate] targets the same logical endpoint identity as this
  ///   instance.
  ///
  /// Guarantees/Postconditions:
  /// - Future `write()` / `poll()` calls use [runtimeDelegate] instead of the
  ///   old Dart-managed transport state where supported.
  ///
  /// Invariants:
  /// - Attaching a new delegate disposes the previous delegate first.
  void attachRuntimeDelegate(LocalEndpointRuntimeDelegate runtimeDelegate) {
    _runtimeDelegate?.dispose();
    _runtimeDelegate = runtimeDelegate;
  }

  /// Purpose: Return the attached native runtime delegate or throw when this
  /// endpoint is used outside a live `DogPawEntity` runtime.
  ///
  /// Parameters:
  /// - [methodName]: human-readable API name for the failing call site.
  ///
  /// Return value:
  /// - Attached `LocalEndpointRuntimeDelegate`.
  ///
  /// Requirements/Preconditions:
  /// - Callers should only reach this helper from live runtime methods such as
  ///   `write()`, `poll()`, `readFileBacked()`, or `writeFileBacked()`.
  ///
  /// Guarantees/Postconditions:
  /// - Throws `UnsupportedError` instead of silently using legacy Dart-managed
  ///   transport state when no delegate is attached.
  ///
  /// Invariants:
  /// - This helper does not mutate endpoint metadata or runtime state.
  LocalEndpointRuntimeDelegate _requireRuntimeDelegate(String methodName) {
    final LocalEndpointRuntimeDelegate? runtimeDelegate = _runtimeDelegate;
    if (runtimeDelegate != null) {
      return runtimeDelegate;
    }

    throw UnsupportedError(
      'LocalEndpoint.$methodName requires a native runtime delegate. '
      'Construct this endpoint through DogPawEntity.createEndpoint(), '
      'DogPawEntity.updateEndpoint(), or DogPawEntity.setEndpoint().',
    );
  }

  /// Purpose: Register one observational callback for realized connection-added
  /// events on this local endpoint.
  ///
  /// Parameters:
  /// - [callback]: callback invoked after native runtime has already applied the
  ///   connection change, or `null` to clear the callback.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Future matching connection-added or connection-updated notifications
  ///   replace any previous callback and invoke [callback] best-effort.
  ///
  /// Invariants:
  /// - This callback is observational only; runtime correctness does not depend
  ///   on Dart receiving it.
  void setConnectionAddedCallback(
    void Function(LocalEndpointConnectionAddedEvent event)? callback,
  ) {
    _connectionAddedCallback = callback;
  }

  /// Purpose: Register one observational callback for realized
  /// connection-removed events on this local endpoint.
  ///
  /// Parameters:
  /// - [callback]: callback invoked after native runtime has already applied the
  ///   connection removal, or `null` to clear the callback.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Future matching connection-removed notifications replace any previous
  ///   callback and invoke [callback] best-effort.
  ///
  /// Invariants:
  /// - This callback is observational only; runtime correctness does not depend
  ///   on Dart receiving it.
  void setConnectionRemovedCallback(
    void Function(LocalEndpointConnectionRemovedEvent event)? callback,
  ) {
    _connectionRemovedCallback = callback;
  }

  /// Purpose: Register one observational callback for realized input
  /// connection shape changes on this local endpoint.
  ///
  /// Parameters:
  /// - [callback]: callback invoked after native runtime has already applied the
  ///   new source-side shape, or `null` to clear the callback.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Future matching index-spec-change notifications replace any previous
  ///   callback and invoke [callback] best-effort.
  ///
  /// Invariants:
  /// - This callback is observational only; runtime correctness does not depend
  ///   on Dart receiving it.
  void setConnectionIndexSpecChangedCallback(
    void Function(LocalEndpointConnectionIndexSpecChangedEvent event)? callback,
  ) {
    _connectionIndexSpecChangedCallback = callback;
  }

  /// Purpose: Dispatch one connection-added observation to the currently
  /// registered callback.
  ///
  /// Parameters:
  /// - [event]: semantic event payload that has already been applied natively.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Intended for internal `DogPawEntity` notification dispatch.
  ///
  /// Guarantees/Postconditions:
  /// - Invokes the registered callback synchronously when present.
  ///
  /// Invariants:
  /// - Missing callbacks are ignored.
  void dispatchConnectionAddedEvent(LocalEndpointConnectionAddedEvent event) {
    _senderInfoByConnectionName[event.connectionName] = EndpointSenderInfo(
      connectionName: event.connectionName,
      sourceEndpointRef: event.peerEndpointRef,
    );
    _connectionAddedCallback?.call(event);
  }

  /// Purpose: Dispatch one connection-removed observation to the currently
  /// registered callback.
  ///
  /// Parameters:
  /// - [event]: semantic event payload that has already been applied natively.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Intended for internal `DogPawEntity` notification dispatch.
  ///
  /// Guarantees/Postconditions:
  /// - Invokes the registered callback synchronously when present.
  ///
  /// Invariants:
  /// - Missing callbacks are ignored.
  void dispatchConnectionRemovedEvent(
    LocalEndpointConnectionRemovedEvent event,
  ) {
    _senderInfoByConnectionName.remove(event.connectionName);
    _connectionRemovedCallback?.call(event);
  }

  /// Purpose: Dispatch one connection index-spec observation to the currently
  /// registered callback.
  ///
  /// Parameters:
  /// - [event]: semantic event payload that has already been applied natively.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Intended for internal `DogPawEntity` notification dispatch.
  ///
  /// Guarantees/Postconditions:
  /// - Invokes the registered callback synchronously when present.
  ///
  /// Invariants:
  /// - Missing callbacks are ignored.
  void dispatchConnectionIndexSpecChangedEvent(
    LocalEndpointConnectionIndexSpecChangedEvent event,
  ) {
    _senderInfoByConnectionName[event.connectionName] = EndpointSenderInfo(
      connectionName: event.connectionName,
      sourceEndpointRef: event.peerEndpointRef,
    );
    _connectionIndexSpecChangedCallback?.call(event);
  }

  /// Purpose: Store one callback for processed float action messages.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each native-processed float action and
  ///   sender metadata, or `null` to clear it.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - This endpoint should describe an action-oriented float input.
  ///
  /// Guarantees/Postconditions:
  /// - Future stateful float action events replace the previous callback.
  ///
  /// Invariants:
  /// - Callback registration does not start another Dart-side polling system.
  void setStatefulFloatInputCallback(
    void Function(StatefulFloatAction action, EndpointSenderInfo senderInfo)?
        callback,
  ) {
    _statefulFloatInputCallback = callback;
  }

  /// Purpose: Store one callback for processed int action messages.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each native-processed int action and
  ///   sender metadata, or `null` to clear it.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - This endpoint should describe an action-oriented int input.
  ///
  /// Guarantees/Postconditions:
  /// - Future stateful int action events replace the previous callback.
  ///
  /// Invariants:
  /// - Callback registration does not start another Dart-side polling system.
  void setStatefulIntInputCallback(
    void Function(StatefulIntAction action, EndpointSenderInfo senderInfo)?
        callback,
  ) {
    _statefulIntInputCallback = callback;
  }

  /// Purpose: Store one callback for processed toggle action messages.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each native-processed toggle action
  ///   and sender metadata, or `null` to clear it.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - This endpoint should describe an action-oriented toggle input.
  ///
  /// Guarantees/Postconditions:
  /// - Future stateful toggle action events replace the previous callback.
  ///
  /// Invariants:
  /// - Callback registration does not start another Dart-side polling system.
  void setStatefulToggleInputCallback(
    void Function(StatefulToggleAction action, EndpointSenderInfo senderInfo)?
        callback,
  ) {
    _statefulToggleInputCallback = callback;
  }

  /// Purpose: Store one callback for processed enum action messages.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each native-processed enum action and
  ///   sender metadata, or `null` to clear it.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - This endpoint should describe an action-oriented enum input.
  ///
  /// Guarantees/Postconditions:
  /// - Future stateful enum action events replace the previous callback.
  ///
  /// Invariants:
  /// - Callback registration does not start another Dart-side polling system.
  void setStatefulEnumInputCallback(
    void Function(StatefulEnumAction action, EndpointSenderInfo senderInfo)?
        callback,
  ) {
    _statefulEnumInputCallback = callback;
  }

  /// Purpose: Store one callback for processed color action messages.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each native-processed color action and
  ///   sender metadata, or `null` to clear it.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - This endpoint should describe an action-oriented color input.
  ///
  /// Guarantees/Postconditions:
  /// - Future stateful color action events replace the previous callback.
  ///
  /// Invariants:
  /// - Callback registration does not start another Dart-side polling system.
  void setStatefulColorInputCallback(
    void Function(StatefulColorAction action, EndpointSenderInfo senderInfo)?
        callback,
  ) {
    _statefulColorInputCallback = callback;
  }

  /// Purpose: Return the latest retained float value from the native endpoint
  /// runtime.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Retained float value, or `null` when the native reducer is not retaining
  ///   state for this endpoint.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Endpoint metadata and runtime handles remain unchanged.
  ///
  /// Invariants:
  /// - Returned state is sourced from the native local endpoint runtime when
  ///   available.
  double? getRetainedStatefulFloatValue() {
    final EndpointRetainedStateSnapshot snapshot = getRetainedStateSnapshot();
    return snapshot.hasState && snapshot.value is num
        ? (snapshot.value as num).toDouble()
        : null;
  }

  /// Purpose: Return the latest retained int value from the native endpoint
  /// runtime.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Retained int value, or `null` when unavailable.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Endpoint metadata and runtime handles remain unchanged.
  ///
  /// Invariants:
  /// - Returned state is sourced from the native local endpoint runtime when
  ///   available.
  int? getRetainedStatefulIntValue() {
    final EndpointRetainedStateSnapshot snapshot = getRetainedStateSnapshot();
    return snapshot.hasState && snapshot.value is int ? snapshot.value as int : null;
  }

  /// Purpose: Return the latest retained toggle value from the native endpoint
  /// runtime.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Retained toggle value, or `null` when unavailable.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Endpoint metadata and runtime handles remain unchanged.
  ///
  /// Invariants:
  /// - Returned state is sourced from the native local endpoint runtime when
  ///   available.
  bool? getRetainedStatefulToggleValue() {
    final EndpointRetainedStateSnapshot snapshot = getRetainedStateSnapshot();
    return snapshot.hasState && snapshot.value is bool
        ? snapshot.value as bool
        : null;
  }

  /// Purpose: Return the latest retained enum id from the native endpoint
  /// runtime.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Retained enum id, or `null` when unavailable.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Endpoint metadata and runtime handles remain unchanged.
  ///
  /// Invariants:
  /// - Returned state is sourced from the native local endpoint runtime when
  ///   available.
  int? getRetainedStatefulEnumId() {
    final EndpointRetainedStateSnapshot snapshot = getRetainedStateSnapshot();
    return snapshot.hasState && snapshot.value is int ? snapshot.value as int : null;
  }

  /// Purpose: Return the latest retained packed color value from the native
  /// endpoint runtime.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Retained packed color value, or `null` when unavailable.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Endpoint metadata and runtime handles remain unchanged.
  ///
  /// Invariants:
  /// - Returned state is sourced from the native local endpoint runtime when
  ///   available.
  int? getRetainedStatefulColorValue() {
    final EndpointRetainedStateSnapshot snapshot = getRetainedStateSnapshot();
    return snapshot.hasState && snapshot.value is int ? snapshot.value as int : null;
  }

  /// Purpose: Return the current retained-state snapshot for this local
  /// endpoint.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - `EndpointRetainedStateSnapshot` describing the current retained input or
  ///   constrained retained output state.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Endpoint metadata and runtime delegates remain unchanged.
  ///
  /// Invariants:
  /// - Returned data reflects the native local endpoint runtime when this
  ///   endpoint is runtime-backed.
  EndpointRetainedStateSnapshot getRetainedStateSnapshot() {
    final EndpointRetainedStateSnapshot? callbackScopedSnapshot =
        _callbackScopedRetainedStateSnapshot;
    if (callbackScopedSnapshot != null) {
      return callbackScopedSnapshot;
    }
    final LocalEndpointRuntimeDelegate? runtimeDelegate = _runtimeDelegate;
    if (runtimeDelegate != null) {
      return runtimeDelegate.getRetainedStateSnapshot();
    }
    return const EndpointRetainedStateSnapshot(hasState: false);
  }

  /// Purpose: Commit one accepted retained-state snapshot through the attached
  /// native endpoint runtime.
  ///
  /// Parameters:
  /// - [snapshot]: retained-state snapshot to adopt as the endpoint's committed
  ///   state.
  /// - [publishMatchedOutput]: whether a linked matched output should publish
  ///   the committed state immediately.
  /// - [senderInfo]: optional logical sender metadata associated with the
  ///   deferred request being accepted.
  ///
  /// Return value:
  /// - `true` when the native runtime accepted and applied [snapshot],
  ///   otherwise `false`.
  ///
  /// Requirements/Preconditions:
  /// - This endpoint must have a native runtime delegate attached.
  ///
  /// Guarantees/Postconditions:
  /// - On success, subsequent retained-state reads come from the newly adopted
  ///   native state.
  /// - When [publishMatchedOutput] is `true`, any linked matched output
  ///   publishes the committed state through the native runtime path.
  ///
  /// Invariants:
  /// - This method does not mutate authored endpoint metadata.
  bool adoptRetainedStateSnapshot(
    EndpointRetainedStateSnapshot snapshot, {
    bool publishMatchedOutput = true,
    EndpointSenderInfo? senderInfo,
  }) {
    return _requireRuntimeDelegate('adoptRetainedStateSnapshot')
        .adoptRetainedStateSnapshot(
      snapshot,
      publishMatchedOutput: publishMatchedOutput,
      senderInfo: senderInfo,
    );
  }

  void dispatchStatefulFloatActionEvent({
    required StatefulFloatAction action,
    required EndpointSenderInfo senderInfo,
    required double? retainedValue,
  }) {
    _invokeWithCallbackScopedRetainedState(
      retainedValue == null
          ? const EndpointRetainedStateSnapshot(hasState: false)
          : EndpointRetainedStateSnapshot(
              hasState: true,
              value: retainedValue,
              timestampUs: DateTime.now().microsecondsSinceEpoch,
            ),
      () => _statefulFloatInputCallback?.call(action, senderInfo),
    );
  }

  void dispatchStatefulIntActionEvent({
    required StatefulIntAction action,
    required EndpointSenderInfo senderInfo,
    required int? retainedValue,
  }) {
    _invokeWithCallbackScopedRetainedState(
      retainedValue == null
          ? const EndpointRetainedStateSnapshot(hasState: false)
          : EndpointRetainedStateSnapshot(
              hasState: true,
              value: retainedValue,
              timestampUs: DateTime.now().microsecondsSinceEpoch,
            ),
      () => _statefulIntInputCallback?.call(action, senderInfo),
    );
  }

  void dispatchStatefulToggleActionEvent({
    required StatefulToggleAction action,
    required EndpointSenderInfo senderInfo,
    required bool? retainedValue,
  }) {
    _invokeWithCallbackScopedRetainedState(
      retainedValue == null
          ? const EndpointRetainedStateSnapshot(hasState: false)
          : EndpointRetainedStateSnapshot(
              hasState: true,
              value: retainedValue,
              timestampUs: DateTime.now().microsecondsSinceEpoch,
            ),
      () => _statefulToggleInputCallback?.call(action, senderInfo),
    );
  }

  /// Purpose: Deliver one processed enum action from the native runtime to this
  /// Dart endpoint wrapper.
  ///
  /// Parameters:
  /// - [action]: processed enum action payload.
  /// - [senderInfo]: logical upstream sender metadata.
  /// - [retainedValue]: latest retained enum id after native reduction.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - This endpoint represents a locally owned enum input.
  ///
  /// Guarantees/Postconditions:
  /// - Any registered enum callback is invoked once with the processed action.
  /// - During that callback, retained-state reads stay aligned with the
  ///   triggering action.
  ///
  /// Invariants:
  /// - Endpoint authored metadata is unchanged.
  void dispatchStatefulEnumActionEvent({
    required StatefulEnumAction action,
    required EndpointSenderInfo senderInfo,
    required int? retainedValue,
  }) {
    _invokeWithCallbackScopedRetainedState(
      retainedValue == null
          ? const EndpointRetainedStateSnapshot(hasState: false)
          : EndpointRetainedStateSnapshot(
              hasState: true,
              value: retainedValue,
              timestampUs: DateTime.now().microsecondsSinceEpoch,
            ),
      () => _statefulEnumInputCallback?.call(action, senderInfo),
    );
  }

  /// Purpose: Deliver one processed color action from the native runtime to
  /// this Dart endpoint wrapper.
  ///
  /// Parameters:
  /// - [action]: processed color action payload.
  /// - [senderInfo]: logical upstream sender metadata.
  /// - [retainedValue]: latest retained packed color value after native
  ///   reduction.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - This endpoint represents a locally owned color input.
  ///
  /// Guarantees/Postconditions:
  /// - Any registered color callback is invoked once with the processed action.
  /// - During that callback, retained-state reads stay aligned with the
  ///   triggering action.
  ///
  /// Invariants:
  /// - Endpoint authored metadata is unchanged.
  void dispatchStatefulColorActionEvent({
    required StatefulColorAction action,
    required EndpointSenderInfo senderInfo,
    required int? retainedValue,
  }) {
    _invokeWithCallbackScopedRetainedState(
      retainedValue == null
          ? const EndpointRetainedStateSnapshot(hasState: false)
          : EndpointRetainedStateSnapshot(
              hasState: true,
              value: retainedValue,
              timestampUs: DateTime.now().microsecondsSinceEpoch,
            ),
      () => _statefulColorInputCallback?.call(action, senderInfo),
    );
  }

  /// Purpose: Expose one event-local retained-state snapshot while invoking a
  /// typed callback, so callback reads stay aligned with the triggering action.
  ///
  /// Parameters:
  /// - [snapshot]: retained-state view for the in-flight callback.
  /// - [callback]: synchronous callback body to run.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [callback] must finish synchronously and should not store references that
  ///   depend on [snapshot] remaining active afterward.
  ///
  /// Guarantees/Postconditions:
  /// - `getRetainedStateSnapshot()` returns [snapshot] only during [callback].
  /// - After [callback] returns, ordinary retained-state reads revert to the
  ///   native runtime delegate.
  ///
  /// Invariants:
  /// - Authored endpoint metadata and runtime delegates remain unchanged.
  void _invokeWithCallbackScopedRetainedState(
    EndpointRetainedStateSnapshot snapshot,
    void Function() callback,
  ) {
    final EndpointRetainedStateSnapshot? previousSnapshot =
        _callbackScopedRetainedStateSnapshot;
    _callbackScopedRetainedStateSnapshot = snapshot;
    try {
      callback();
    } finally {
      _callbackScopedRetainedStateSnapshot = previousSnapshot;
    }
  }

  /// Write data to a file-backed endpoint
  Future<bool> writeFileBacked(dynamic data) async {
    // 1. Check if this is an output file-backed endpoint
    final currentSpec = spec ?? resolved;
    if (currentSpec == null) return false;

    if (currentSpec.direction != EndpointDirection.output) return false;
    if (currentSpec.category != EndpointCategory.fileBacked) return false;

    final Uint8List? encodedBytes = _encodeFileBackedPayload(data);
    if (encodedBytes == null) {
      return false;
    }
    return _requireRuntimeDelegate('writeFileBacked').writeBytes(encodedBytes);
  }

  /// Purpose: Encode one file-backed payload into raw bytes for runtime
  /// transport.
  ///
  /// Parameters:
  /// - [data]: payload value supplied by the caller.
  ///
  /// Return value:
  /// - `Uint8List` containing serialized bytes, or `null` if encoding failed.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - `String` payloads become UTF-8 text.
  /// - `List<int>` payloads are passed through unchanged.
  /// - Other payloads are JSON-encoded using `jsonEncode`.
  ///
  /// Invariants:
  /// - This helper does not mutate endpoint state.
  Uint8List? _encodeFileBackedPayload(dynamic data) {
    try {
      if (data is String) {
        return Uint8List.fromList(utf8.encode(data));
      }
      if (data is List<int>) {
        return Uint8List.fromList(data);
      }
      return Uint8List.fromList(utf8.encode(jsonEncode(data)));
    } catch (error) {
      AppLogger.error('Failed to encode file-backed payload for $name: $error');
      return null;
    }
  }

  /// Purpose: Decode one file-backed payload from raw bytes.
  ///
  /// Parameters:
  /// - [bytes]: serialized file-backed contents returned by the runtime.
  /// - [onlyAsBytes]: whether the payload should stay as bytes instead of
  ///   attempting JSON decode.
  ///
  /// Return value:
  /// - Decoded JSON value when possible, otherwise the original `Uint8List`.
  ///
  /// Requirements/Preconditions:
  /// - [bytes] contains the complete current file contents for one connection.
  ///
  /// Guarantees/Postconditions:
  /// - When [onlyAsBytes] is `true`, the original bytes are returned.
  /// - When [onlyAsBytes] is `false`, the helper attempts JSON decode first and
  ///   falls back to bytes if decoding fails.
  ///
  /// Invariants:
  /// - This helper does not mutate endpoint state.
  dynamic _decodeFileBackedPayload(
    Uint8List bytes, {
    required bool onlyAsBytes,
  }) {
    if (onlyAsBytes) {
      return bytes;
    }

    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return bytes;
    }
  }

  /// Purpose: Dispatch a batch of native file-backed payload packets to one
  /// consumer callback.
  ///
  /// Parameters:
  /// - [packets]: serialized file-backed payloads returned by the runtime.
  /// - [onData]: callback invoked once per decoded payload.
  /// - [onlyAsBytes]: whether payloads should remain raw bytes.
  ///
  /// Return value:
  /// - `true` when at least one packet was decoded and dispatched.
  ///
  /// Requirements/Preconditions:
  /// - [onData] is safe to invoke synchronously on the current isolate.
  ///
  /// Guarantees/Postconditions:
  /// - The callback runs once for each packet in [packets].
  ///
  /// Invariants:
  /// - Dispatch order matches the packet order returned by the runtime.
  bool _dispatchFileBackedPackets(
    List<LocalEndpointPollPacket> packets,
    Function(dynamic) onData, {
    required bool onlyAsBytes,
  }) {
    bool anySuccess = false;
    for (final LocalEndpointPollPacket packet in packets) {
      onData(_decodeFileBackedPayload(
        packet.bytes,
        onlyAsBytes: onlyAsBytes,
      ));
      anySuccess = true;
    }
    return anySuccess;
  }

  /// Poll for new data (Input only)
  /// Returns a list of data objects from all active connections, or the specific connection if named.
  Future<bool> pollFileBacked(Function(dynamic) onData,
      {String? connectionName, bool onlyAsBytes = false}) async {
    final currentSpec = spec ?? resolved;
    if (currentSpec == null) {
      AppLogger.warning(
          'pollFileBacked called on non-resolved endpoint: $name');
      return false;
    }

    if (currentSpec.direction != EndpointDirection.input) {
      AppLogger.warning('pollFileBacked called on non-input endpoint: $name');
      return false;
    }

    if (currentSpec.category != EndpointCategory.fileBacked) {
      AppLogger.warning(
          'pollFileBacked called on non-file-backed endpoint: $name');
      return false;
    }
    return _dispatchFileBackedPackets(
      _requireRuntimeDelegate('pollFileBacked')
          .pollFileBackedBytes(connectionName: connectionName),
      onData,
      onlyAsBytes:
          currentSpec.dataType.baseType != DataType.custom || onlyAsBytes,
    );
  }

  /// Read data from a file-backed endpoint
  Future<bool> readFileBacked(Function(dynamic) onData,
      {String? connectionName}) async {
    // 1. Check if this is a file-backed input endpoint
    final currentSpec = spec ?? resolved;
    if (currentSpec == null) {
      AppLogger.warning(
          'readFileBacked called on non-resolved endpoint: $name');
      return false;
    }

    if (currentSpec.direction != EndpointDirection.input) {
      AppLogger.warning('readFileBacked called on non-input endpoint: $name');
      return false;
    }

    if (currentSpec.category != EndpointCategory.fileBacked) {
      AppLogger.warning(
          'readFileBacked called on non-file-backed endpoint: $name');
      return false;
    }
    return _dispatchFileBackedPackets(
      _requireRuntimeDelegate('readFileBacked')
          .readFileBackedBytes(connectionName: connectionName),
      onData,
      onlyAsBytes: currentSpec.dataType.baseType != DataType.custom,
    );
  }

  /// Dispose native resources
  void dispose() {
    _runtimeDelegate?.dispose();
    _runtimeDelegate = null;
  }

  /// Update endpoint from another endpoint's data
  /// Handles changes in shared memory structure names and index specs
  /// Mirrors C++ Endpoint::update() logic (excluding Jack audio/MIDI)
  void update(EndpointInfo other) {
    copyMetadataFrom(other);
  }

  /// Write data to endpoint (Output only)
  bool write(dynamic data) {
    final effectiveSpec = spec ?? resolved;
    if (effectiveSpec == null) return false;

    try {
      final bytes = _serializeEndpointData(data, effectiveSpec);
      if (bytes == null) return false;
      return _requireRuntimeDelegate('write').writeBytes(bytes);
    } catch (e) {
      if (e is UnsupportedError) {
        rethrow;
      }
      // print('Write error: $e');
      AppLogger.error('Write error: $e');
      return false;
    }
  }

  /// Poll for new data (Input only)
  /// Returns a list of data objects from all active connections, or the specific connection if named.
  List<dynamic> poll({String? connectionName}) {
    final effectiveSpec = spec ?? resolved;
    if (effectiveSpec == null) return [];
    if (effectiveSpec.direction != EndpointDirection.input) return [];
    final List<dynamic> results = <dynamic>[];
    final List<LocalEndpointPollPacket> packets =
        _requireRuntimeDelegate('poll')
            .pollBytes(connectionName: connectionName);
    for (final LocalEndpointPollPacket packet in packets) {
      final dynamic data =
          _deserializeEndpointData(packet.bytes, effectiveSpec, packet.indexSpec);
      if (data != null) {
        results.add(data);
      }
    }
    return results;
  }

  /// Poll for new data together with sender metadata (Input only).
  ///
  /// Returns decoded payloads from all active connections, or the specific
  /// connection if named, paired with the logical source endpoint for each
  /// realized connection.
  List<LocalEndpointPollResult> pollWithSenderInfo({String? connectionName}) {
    final EndpointSpec? effectiveSpec = spec ?? resolved;
    if (effectiveSpec == null) return <LocalEndpointPollResult>[];
    if (effectiveSpec.direction != EndpointDirection.input) {
      return <LocalEndpointPollResult>[];
    }
    final List<LocalEndpointPollResult> results = <LocalEndpointPollResult>[];
    final List<LocalEndpointPollPacket> packets =
        _requireRuntimeDelegate('pollWithSenderInfo')
            .pollBytes(connectionName: connectionName);
    for (final LocalEndpointPollPacket packet in packets) {
      final EndpointSenderInfo? senderInfo =
          _senderInfoByConnectionName[packet.connectionName];
      if (senderInfo == null) {
        AppLogger.warning(
          'LocalEndpoint.pollWithSenderInfo missing sender metadata for '
          'connection ${packet.connectionName} on endpoint $name',
        );
        continue;
      }
      final dynamic data =
          _deserializeEndpointData(packet.bytes, effectiveSpec, packet.indexSpec);
      if (data != null) {
        results
            .add(LocalEndpointPollResult(data: data, senderInfo: senderInfo));
      }
    }
    return results;
  }

  //---------------------------------------------------------------------------
  // Serialization Helpers
  //---------------------------------------------------------------------------
  Uint8List? _serializeEndpointData(dynamic data, EndpointSpec endpointSpec) {
    if (endpointSpec.usesActionMessageQueuePayload) {
      return _serializeMessageQueuePayload(
        data,
        endpointSpec.effectiveMessageQueuePayloadContract,
      );
    }
    return _serializeData(
      data,
      endpointSpec.dataType,
      endpointSpec.category,
    );
  }

  dynamic _deserializeEndpointData(
    Uint8List bytes,
    EndpointSpec endpointSpec,
    IndexSpec indexSpec,
  ) {
    if (endpointSpec.usesActionMessageQueuePayload) {
      return _deserializeMessageQueuePayload(
        bytes,
        endpointSpec.effectiveMessageQueuePayloadContract,
      );
    }
    return _deserializeData(
      bytes,
      endpointSpec.dataType.baseType,
      indexSpec,
      endpointSpec.category,
    );
  }

  Uint8List? _serializeMessageQueuePayload(
    dynamic data,
    MessageQueuePayloadContract payloadContract,
  ) {
    switch (payloadContract) {
      case MessageQueuePayloadContract.endpointData:
        return null;
      case MessageQueuePayloadContract.statefulFloatAction:
        if (data is! StatefulFloatAction) {
          throw ArgumentError.value(
            data,
            'data',
            'Expected StatefulFloatAction payload',
          );
        }
        final ByteData buffer = ByteData(8);
        buffer.setInt32(
          0,
          data.action == StatefulFloatActionType.add ? 1 : 0,
          Endian.little,
        );
        buffer.setFloat32(4, data.value, Endian.little);
        return buffer.buffer.asUint8List();
      case MessageQueuePayloadContract.statefulIntAction:
        if (data is! StatefulIntAction) {
          throw ArgumentError.value(
            data,
            'data',
            'Expected StatefulIntAction payload',
          );
        }
        final ByteData buffer = ByteData(8);
        buffer.setInt32(
          0,
          data.action == StatefulIntActionType.add ? 1 : 0,
          Endian.little,
        );
        buffer.setInt32(4, data.value, Endian.little);
        return buffer.buffer.asUint8List();
      case MessageQueuePayloadContract.statefulToggleAction:
        if (data is! StatefulToggleAction) {
          throw ArgumentError.value(
            data,
            'data',
            'Expected StatefulToggleAction payload',
          );
        }
        final ByteData buffer = ByteData(8);
        buffer.setInt32(
          0,
          data.action == StatefulToggleActionType.toggle ? 1 : 0,
          Endian.little,
        );
        buffer.setUint8(4, data.value ? 1 : 0);
        return buffer.buffer.asUint8List();
      case MessageQueuePayloadContract.statefulEnumAction:
        if (data is! StatefulEnumAction) {
          throw ArgumentError.value(
            data,
            'data',
            'Expected StatefulEnumAction payload',
          );
        }
        final ByteData enumBuffer = ByteData(8);
        enumBuffer.setInt32(
          0,
          data.action == StatefulEnumActionType.step ? 1 : 0,
          Endian.little,
        );
        enumBuffer.setInt32(4, data.value, Endian.little);
        return enumBuffer.buffer.asUint8List();
      case MessageQueuePayloadContract.statefulColorAction:
        if (data is! StatefulColorAction) {
          throw ArgumentError.value(
            data,
            'data',
            'Expected StatefulColorAction payload',
          );
        }
        final ByteData colorBuffer = ByteData(8);
        colorBuffer.setInt32(0, 0, Endian.little);
        colorBuffer.setUint32(4, data.value, Endian.little);
        return colorBuffer.buffer.asUint8List();
    }
  }

  dynamic _deserializeMessageQueuePayload(
    Uint8List bytes,
    MessageQueuePayloadContract payloadContract,
  ) {
    final ByteData payload = ByteData.sublistView(bytes);
    switch (payloadContract) {
      case MessageQueuePayloadContract.endpointData:
        return null;
      case MessageQueuePayloadContract.statefulFloatAction:
        return StatefulFloatAction(
          action: payload.getInt32(0, Endian.little) == 1
              ? StatefulFloatActionType.add
              : StatefulFloatActionType.setValue,
          value: payload.getFloat32(4, Endian.little),
        );
      case MessageQueuePayloadContract.statefulIntAction:
        return StatefulIntAction(
          action: payload.getInt32(0, Endian.little) == 1
              ? StatefulIntActionType.add
              : StatefulIntActionType.setValue,
          value: payload.getInt32(4, Endian.little),
        );
      case MessageQueuePayloadContract.statefulToggleAction:
        return StatefulToggleAction(
          action: payload.getInt32(0, Endian.little) == 1
              ? StatefulToggleActionType.toggle
              : StatefulToggleActionType.setValue,
          value: payload.getUint8(4) != 0,
        );
      case MessageQueuePayloadContract.statefulEnumAction:
        return StatefulEnumAction(
          action: payload.getInt32(0, Endian.little) == 1
              ? StatefulEnumActionType.step
              : StatefulEnumActionType.setId,
          value: payload.getInt32(4, Endian.little),
        );
      case MessageQueuePayloadContract.statefulColorAction:
        return StatefulColorAction(
          action: StatefulColorActionType.setValue,
          value: payload.getUint32(4, Endian.little),
        );
    }
  }


  // Helper: Get size in bytes for a single element of any data type
  int _getElementSize(DataType type) {
    switch (type) {
      case DataType.float:
        return 4;
      case DataType.float2:
        return 8;
      case DataType.float3:
        return 12;
      case DataType.float4:
        return 16;
      case DataType.int_:
        return 4;
      case DataType.int2:
        return 8;
      case DataType.toggle:
        return 1;
      case DataType.momentary:
        return 1;
      case DataType.enum_:
        return 4;
      case DataType.color:
        return 4;
      case DataType.keyPress:
        return 20;
      case DataType.nearPress:
        return 148;
      case DataType.rawSensors:
        return 4; // 2 uint16s
      case DataType.ledMessage:
        return LedWire.size;
      case DataType.keyPosition:
        return 12;
      case DataType.noteControl:
        return 12;
      case DataType.midiMessage:
        return 3;
      case DataType.voiceMessage:
        return _voiceMessageSizeBytes;
      case DataType.voiceOutputValue:
        return 24;
      case DataType.globalOutputValue:
        return 8;
      case DataType.dppEditorMessage:
        return 24;
      case DataType.custom:
        return -1; // Custom data is handled by file-backed endpoints
      case DataType.audioStream:
        return -1; // Audio stream is handled by file-backed endpoints
      case DataType.scopeBuffer:
        return 16 + ScopeBufferData.maxSamplesPerChannel * 4 * 2;
    }
  }

  // Helper: Serialize a single element at an offset
  ///
  /// Purpose:
  /// Encode one `KeySource`-shaped map into the native shared binary layout used
  /// by `VOICE_MESSAGE`.
  ///
  /// Parameters:
  /// - [bd]: Destination byte buffer.
  /// - [offset]: Starting byte offset for this encoded key source.
  /// - [keySource]: Map containing `origin`, `channel`, `note`, `col`, and `row`.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [keySource] must provide integer values for all required fields.
  ///
  /// Guarantees/Postconditions:
  /// - Writes the shared Dog Paw `KeySource` layout exactly.
  ///
  /// Invariants:
  /// - Writes stay within the fixed 12-byte `KeySource` footprint.
  void _serializeVoiceKeySource(
    ByteData bd,
    int offset,
    Map<String, dynamic> keySource,
  ) {
    bd.setInt32(offset, keySource['origin'] as int, Endian.little);
    bd.setUint8(offset + 4, keySource['channel'] as int);
    bd.setUint8(offset + 5, keySource['note'] as int);
    bd.setUint16(offset + 6, keySource['col'] as int, Endian.little);
    bd.setUint16(offset + 8, keySource['row'] as int, Endian.little);
  }

  /// Purpose:
  /// Encode one `VoiceRef`-shaped map into the native shared binary layout used
  /// by `VOICE_MESSAGE` and `VOICE_OUTPUT_VALUE`.
  ///
  /// Parameters:
  /// - [bd]: Destination byte buffer.
  /// - [offset]: Starting byte offset for this encoded voice reference.
  /// - [voiceRef]: Map containing `regionId`, `regionInstanceId`,
  ///   `logicalVoiceId`, and `slotIdx`.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [voiceRef] must provide integer values for all four required fields.
  ///
  /// Guarantees/Postconditions:
  /// - Writes the shared Dog Paw `VoiceRef` layout exactly.
  ///
  /// Invariants:
  /// - Writes stay within the fixed 16-byte `VoiceRef` footprint.
  void _serializeVoiceRef(
    ByteData bd,
    int offset,
    Map<String, dynamic> voiceRef,
  ) {
    bd.setInt32(offset, voiceRef['regionId'] as int, Endian.little);
    bd.setInt32(offset + 4, voiceRef['regionInstanceId'] as int, Endian.little);
    bd.setInt32(offset + 8, voiceRef['logicalVoiceId'] as int, Endian.little);
    bd.setInt32(offset + 12, voiceRef['slotIdx'] as int, Endian.little);
  }

  /// Purpose:
  /// Encode one `VoiceMember`-shaped map into the native shared binary layout
  /// used inside `VOICE_MESSAGE`.
  ///
  /// Parameters:
  /// - [bd]: Destination byte buffer.
  /// - [offset]: Starting byte offset for this encoded member.
  /// - [member]: Map containing `keySource` plus the scalar member fields.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [member] must provide a valid `keySource` map and numeric scalar fields.
  ///
  /// Guarantees/Postconditions:
  /// - Writes one complete 40-byte shared `VoiceMember`.
  ///
  /// Invariants:
  /// - The scalar field ordering matches the shared C++ struct exactly.
  void _serializeVoiceMember(
    ByteData bd,
    int offset,
    Map<String, dynamic> member,
  ) {
    _serializeVoiceKeySource(
      bd,
      offset,
      Map<String, dynamic>.from(member['keySource'] as Map),
    );
    bd.setFloat32(
      offset + _keySourceSizeBytes,
      (member['noteValue'] as num).toDouble(),
      Endian.little,
    );
    bd.setFloat32(
      offset + _keySourceSizeBytes + 4,
      (member['velocity'] as num).toDouble(),
      Endian.little,
    );
    bd.setFloat32(
      offset + _keySourceSizeBytes + 8,
      (member['pressure'] as num).toDouble(),
      Endian.little,
    );
    bd.setFloat32(
      offset + _keySourceSizeBytes + 12,
      (member['bend'] as num).toDouble(),
      Endian.little,
    );
    bd.setFloat32(
      offset + _keySourceSizeBytes + 16,
      (member['slide'] as num).toDouble(),
      Endian.little,
    );
    bd.setFloat32(
      offset + _keySourceSizeBytes + 20,
      (member['row'] as num).toDouble(),
      Endian.little,
    );
    bd.setFloat32(
      offset + _keySourceSizeBytes + 24,
      (member['column'] as num).toDouble(),
      Endian.little,
    );
  }

  /// Purpose:
  /// Encode one rich `VOICE_MESSAGE` payload map into the native shared binary
  /// layout consumed by the Dog Paw runtime.
  ///
  /// Parameters:
  /// - [bd]: Destination byte buffer.
  /// - [offset]: Starting byte offset for this encoded message.
  /// - [message]: Map containing `kind`, `voice`, `relatedVoice`,
  ///   `hasRelatedMember`, `relatedMember`, `memberCount`, and `members`.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [message] must provide the full rich voice-message shape.
  /// - `memberCount` must be between `0` and `16`.
  ///
  /// Guarantees/Postconditions:
  /// - Writes one complete shared `VoiceMessage`.
  ///
  /// Invariants:
  /// - Member payloads beyond `memberCount` remain zeroed.
  void _serializeVoiceMessage(
    ByteData bd,
    int offset,
    Map<String, dynamic> message,
  ) {
    final int memberCount = message['memberCount'] as int;
    if (memberCount < 0 || memberCount > _maxVoiceMembers) {
      throw ArgumentError(
        'VOICE_MESSAGE memberCount must be between 0 and $_maxVoiceMembers.',
      );
    }
    final List<dynamic> members =
        (message['members'] as List<dynamic>? ?? const <dynamic>[]);
    if (members.length < memberCount) {
      throw ArgumentError(
        'VOICE_MESSAGE members length ${members.length} is smaller than '
        'memberCount $memberCount.',
      );
    }

    bd.setInt32(offset, message['kind'] as int, Endian.little);
    _serializeVoiceRef(
      bd,
      offset + 4,
      Map<String, dynamic>.from(message['voice'] as Map),
    );
    _serializeVoiceRef(
      bd,
      offset + 20,
      Map<String, dynamic>.from(message['relatedVoice'] as Map),
    );
    bd.setUint8(
      offset + 36,
      (message['hasRelatedMember'] as bool?) == true ? 1 : 0,
    );
    _serializeVoiceMember(
      bd,
      offset + 40,
      Map<String, dynamic>.from(message['relatedMember'] as Map),
    );
    bd.setUint32(offset + 80, memberCount, Endian.little);
    for (int memberIndex = 0; memberIndex < memberCount; memberIndex++) {
      _serializeVoiceMember(
        bd,
        offset + 84 + memberIndex * _voiceMemberSizeBytes,
        Map<String, dynamic>.from(members[memberIndex] as Map),
      );
    }
  }

  /// Purpose:
  /// Decode one shared `KeySource` value from raw bytes.
  ///
  /// Parameters:
  /// - [bd]: Source byte buffer.
  /// - [offset]: Starting byte offset for this key source.
  ///
  /// Return value:
  /// - Map containing `origin`, `channel`, `note`, `col`, and `row`.
  ///
  /// Requirements/Preconditions:
  /// - [bd] contains a complete encoded `KeySource` at [offset].
  ///
  /// Guarantees/Postconditions:
  /// - Returned map is detached from the underlying bytes.
  ///
  /// Invariants:
  /// - Field names mirror the shared `KeySource` meaning.
  Map<String, dynamic> _deserializeVoiceKeySource(ByteData bd, int offset) {
    return <String, dynamic>{
      'origin': bd.getInt32(offset, Endian.little),
      'channel': bd.getUint8(offset + 4),
      'note': bd.getUint8(offset + 5),
      'col': bd.getUint16(offset + 6, Endian.little),
      'row': bd.getUint16(offset + 8, Endian.little),
    };
  }

  /// Purpose:
  /// Decode one shared `VoiceRef` value from raw bytes.
  ///
  /// Parameters:
  /// - [bd]: Source byte buffer.
  /// - [offset]: Starting byte offset for this voice reference.
  ///
  /// Return value:
  /// - Map containing `regionId`, `regionInstanceId`, `logicalVoiceId`, and
  ///   `slotIdx`.
  ///
  /// Requirements/Preconditions:
  /// - [bd] contains a complete encoded `VoiceRef` at [offset].
  ///
  /// Guarantees/Postconditions:
  /// - Returned map is detached from the underlying bytes.
  ///
  /// Invariants:
  /// - Field names mirror the shared `VoiceRef` meaning.
  Map<String, dynamic> _deserializeVoiceRef(ByteData bd, int offset) {
    return <String, dynamic>{
      'regionId': bd.getInt32(offset, Endian.little),
      'regionInstanceId': bd.getInt32(offset + 4, Endian.little),
      'logicalVoiceId': bd.getInt32(offset + 8, Endian.little),
      'slotIdx': bd.getInt32(offset + 12, Endian.little),
    };
  }

  /// Purpose:
  /// Decode one shared `VoiceMember` value from raw bytes.
  ///
  /// Parameters:
  /// - [bd]: Source byte buffer.
  /// - [offset]: Starting byte offset for this member.
  ///
  /// Return value:
  /// - Map containing `keySource` plus the scalar member fields.
  ///
  /// Requirements/Preconditions:
  /// - [bd] contains a complete encoded `VoiceMember` at [offset].
  ///
  /// Guarantees/Postconditions:
  /// - Returned map is detached from the underlying bytes.
  ///
  /// Invariants:
  /// - Field ordering matches the shared C++ `VoiceMember` layout.
  Map<String, dynamic> _deserializeVoiceMember(ByteData bd, int offset) {
    return <String, dynamic>{
      'keySource': _deserializeVoiceKeySource(bd, offset),
      'noteValue': bd.getFloat32(offset + _keySourceSizeBytes, Endian.little),
      'velocity':
          bd.getFloat32(offset + _keySourceSizeBytes + 4, Endian.little),
      'pressure':
          bd.getFloat32(offset + _keySourceSizeBytes + 8, Endian.little),
      'bend':
          bd.getFloat32(offset + _keySourceSizeBytes + 12, Endian.little),
      'slide':
          bd.getFloat32(offset + _keySourceSizeBytes + 16, Endian.little),
      'row': bd.getFloat32(offset + _keySourceSizeBytes + 20, Endian.little),
      'column':
          bd.getFloat32(offset + _keySourceSizeBytes + 24, Endian.little),
    };
  }

  /// Purpose:
  /// Decode one rich shared `VOICE_MESSAGE` payload from raw bytes.
  ///
  /// Parameters:
  /// - [bd]: Source byte buffer.
  /// - [offset]: Starting byte offset for this message.
  ///
  /// Return value:
  /// - Map containing the rich logical-voice transport payload.
  ///
  /// Requirements/Preconditions:
  /// - [bd] contains a complete encoded `VoiceMessage` at [offset].
  ///
  /// Guarantees/Postconditions:
  /// - Member arrays are truncated to the declared `memberCount`.
  ///
  /// Invariants:
  /// - Returned field names mirror the shared `VoiceMessage` meaning.
  Map<String, dynamic> _deserializeVoiceMessage(ByteData bd, int offset) {
    final int memberCount = bd.getUint32(offset + 80, Endian.little);
    final int clampedMemberCount =
        memberCount.clamp(0, _maxVoiceMembers).toInt();
    final List<Map<String, dynamic>> members = <Map<String, dynamic>>[];
    for (int memberIndex = 0; memberIndex < clampedMemberCount; memberIndex++) {
      members.add(
        _deserializeVoiceMember(
          bd,
          offset + 84 + memberIndex * _voiceMemberSizeBytes,
        ),
      );
    }
    return <String, dynamic>{
      'kind': bd.getInt32(offset, Endian.little),
      'voice': _deserializeVoiceRef(bd, offset + 4),
      'relatedVoice': _deserializeVoiceRef(bd, offset + 20),
      'hasRelatedMember': bd.getUint8(offset + 36) != 0,
      'relatedMember': _deserializeVoiceMember(bd, offset + 40),
      'memberCount': clampedMemberCount,
      'members': members,
    };
  }

  // Helper: Serialize a single element at an offset
  void _serializeElement(
      ByteData bd, int offset, dynamic value, DataType type) {
    switch (type) {
      case DataType.float:
        bd.setFloat32(offset, (value as num).toDouble(), Endian.little);
        break;
      case DataType.float2:
        final list = (value as List).map((e) => (e as num).toDouble()).toList();
        bd.setFloat32(offset, list[0], Endian.little);
        bd.setFloat32(offset + 4, list[1], Endian.little);
        break;
      case DataType.float3:
        final list = (value as List).map((e) => (e as num).toDouble()).toList();
        bd.setFloat32(offset, list[0], Endian.little);
        bd.setFloat32(offset + 4, list[1], Endian.little);
        bd.setFloat32(offset + 8, list[2], Endian.little);
        break;
      case DataType.float4:
        final list = (value as List).map((e) => (e as num).toDouble()).toList();
        bd.setFloat32(offset, list[0], Endian.little);
        bd.setFloat32(offset + 4, list[1], Endian.little);
        bd.setFloat32(offset + 8, list[2], Endian.little);
        bd.setFloat32(offset + 12, list[3], Endian.little);
        break;
      case DataType.int_:
        bd.setInt32(offset, (value as num).toInt(), Endian.little);
        break;
      case DataType.int2:
        final list = (value as List).map((e) => (e as num).toInt()).toList();
        bd.setInt32(offset, list[0], Endian.little);
        bd.setInt32(offset + 4, list[1], Endian.little);
        break;
      case DataType.toggle:
        bd.setUint8(offset, (value as bool) ? 1 : 0);
        break;
      case DataType.momentary:
        bd.setUint8(offset, (value as bool) ? 1 : 0);
        break;
      case DataType.enum_:
        bd.setInt32(offset, value as int, Endian.little);
        break;
      case DataType.color:
        bd.setUint32(offset, (value as num).toInt(), Endian.little);
        break;
      case DataType.keyPress:
        final event = value as KeyEvent;
        bd.setUint32(offset, event.timestamp, Endian.little);
        bd.setInt32(offset + 4, event.column, Endian.little);
        bd.setInt32(offset + 8, event.row, Endian.little);
        bd.setFloat32(offset + 12, event.velocity, Endian.little);
        bd.setUint8(offset + 16, event.oldState.index);
        bd.setUint8(offset + 17, event.newState.index);
        break;
      case DataType.nearPress:
        final nearPress = value as NearPressPositionData;
        for (int i = 0; i < 32; i++) {
          bd.setFloat32(offset + i * 4, nearPress.sensorData[i], Endian.little);
        }
        bd.setUint32(
            offset + 32 * 4, nearPress.keyEvent.timestamp, Endian.little);
        bd.setInt32(
            offset + 32 * 4 + 4, nearPress.keyEvent.column, Endian.little);
        bd.setInt32(offset + 32 * 4 + 8, nearPress.keyEvent.row, Endian.little);
        bd.setFloat32(
            offset + 32 * 4 + 12, nearPress.keyEvent.velocity, Endian.little);
        bd.setUint8(offset + 32 * 4 + 16, nearPress.keyEvent.oldState.index);
        bd.setUint8(offset + 32 * 4 + 17, nearPress.keyEvent.newState.index);
        break;
      case DataType.rawSensors:
        final list = (value as List).map((e) => (e as num).toInt()).toList();
        for (int i = 0; i < list.length; i++) {
          bd.setUint16(offset + i * 2, list[i], Endian.little);
        }
        break;
      case DataType.noteControl:
        final map = value as Map<String, dynamic>;
        bd.setInt32(offset, map['type'] as int, Endian.little);
        bd.setFloat32(
            offset + 4, (map['val1'] as num).toDouble(), Endian.little);
        bd.setFloat32(
            offset + 8, (map['val2'] as num).toDouble(), Endian.little);
        break;
      case DataType.audioStream:
        throw UnimplementedError('Audio stream serialization not implemented');
      case DataType.midiMessage:
        final message = value as Map<String, dynamic>;
        bd.setUint8(offset, message['status'] as int);
        bd.setUint8(offset + 1, message['d1'] as int);
        bd.setUint8(offset + 2, message['d2'] as int);
        break;
      case DataType.ledMessage:
        final LEDMessage led = value as LEDMessage;
        final ByteData wire = led.toWireByteData();
        for (int i = 0; i < LedWire.size; i++) {
          bd.setUint8(offset + i, wire.getUint8(i));
        }
        break;
      case DataType.keyPosition:
        final pos = value as PosData;
        bd.setFloat32(offset, pos.vertical, Endian.little);
        bd.setFloat32(offset + 4, pos.horizontal, Endian.little);
        bd.setFloat32(offset + 8, pos.horizBlendAmt, Endian.little);
        break;
      case DataType.voiceMessage:
        _serializeVoiceMessage(bd, offset, value as Map<String, dynamic>);
        break;
      case DataType.voiceOutputValue:
        final map = value as Map<String, dynamic>;
        bd.setInt32(offset, map['region_id'] as int, Endian.little);
        bd.setInt32(
            offset + 4, map['region_instance_id'] as int, Endian.little);
        bd.setInt32(offset + 8, map['logical_voice_id'] as int, Endian.little);
        bd.setInt32(offset + 12, map['slot_idx'] as int, Endian.little);
        bd.setUint32(offset + 16, map['output_index'] as int, Endian.little);
        bd.setFloat32(
            offset + 20, (map['value'] as num).toDouble(), Endian.little);
        break;
      case DataType.globalOutputValue:
        final map = value as Map<String, dynamic>;
        bd.setUint32(offset, map['output_index'] as int, Endian.little);
        bd.setFloat32(
            offset + 4, (map['value'] as num).toDouble(), Endian.little);
        break;
      case DataType.dppEditorMessage:
        final map = value as Map<String, dynamic>;
        bd.setUint8(offset, map['type'] as int);
        bd.setUint8(offset + 1, map['channel'] as int? ?? 0);
        bd.setUint8(offset + 2, map['note'] as int? ?? 0);
        bd.setUint8(offset + 3, 0);
        bd.setUint16(offset + 4, map['param_index'] as int? ?? 0, Endian.little);
        bd.setUint16(offset + 6, 0, Endian.little);
        bd.setFloat64(
          offset + 8,
          (map['value'] as num).toDouble(),
          Endian.little,
        );
        bd.setFloat64(
          offset + 16,
          ((map['value2'] as num?) ?? 0.0).toDouble(),
          Endian.little,
        );
        break;
      case DataType.custom:
        final jsonStr = jsonEncode(value);
        final bytes = Uint8List.fromList(utf8.encode(jsonStr));
        for (int i = 0; i < bytes.length; i++) {
          bd.setUint8(offset + i, bytes[i]);
        }
        break;
      case DataType.scopeBuffer:
        {
          final scope = value as ScopeBufferData;
          bd.setUint64(offset, scope.sampleCount, Endian.little);
          bd.setUint32(offset + 8, scope.sampleRateHz, Endian.little);
          bd.setUint32(offset + 12, scope.framesPerPayload, Endian.little);
          for (int i = 0; i < ScopeBufferData.maxSamplesPerChannel; i++) {
            bd.setFloat32(
                offset + 16 + i * 4,
                (i < scope.leftSamples.length ? scope.leftSamples[i] : 0.0)
                    .toDouble(),
                Endian.little);
          }
          for (int i = 0; i < ScopeBufferData.maxSamplesPerChannel; i++) {
            bd.setFloat32(
                offset + 16 + ScopeBufferData.maxSamplesPerChannel * 4 + i * 4,
                (i < scope.rightSamples.length ? scope.rightSamples[i] : 0.0)
                    .toDouble(),
                Endian.little);
          }
          break;
        }
    }
  }

  Uint8List? _serializeData(
      dynamic data, DataTypeSpec typeSpec, EndpointCategory category) {
    final elementSize = _getElementSize(typeSpec.baseType);

    // AppLogger.info('Endpoint: Serializing data: $data for type: ${typeSpec.baseType}, category: $category, elementSize: $elementSize');

    if (category == EndpointCategory.continuous) {
      // simply get the count and iterate over the data
      final count = typeSpec.indexSpec.count;
      final bd = ByteData(count * elementSize);
      if (count == 1 && (data is! List)) {
        // single element, not a list
        _serializeElement(bd, 0, data, typeSpec.baseType);
      } else {
        for (int i = 0; i < count; i++) {
          _serializeElement(bd, i * elementSize, data[i], typeSpec.baseType);
        }
      }
      return bd.buffer.asUint8List();
    } else {
      if (typeSpec.indexSpec.type == IndexType.none) {
        final bd = ByteData(elementSize);
        _serializeElement(bd, 0, data, typeSpec.baseType);
        return bd.buffer.asUint8List();
      } else if (typeSpec.indexSpec.type == IndexType.voice) {
        // data should be a pair (int, element)
        // (in c++ it's std::pair<int, T>)
        final index = data[0] as int;
        final element = data[1] as dynamic;
        final bd = ByteData(elementSize + 4);
        bd.setInt32(0, index, Endian.little);
        _serializeElement(bd, 4, element, typeSpec.baseType);
        return bd.buffer.asUint8List();
      } else if (typeSpec.indexSpec.type == IndexType.key) {
        // data should be a pair (pair<int, int>, element)
        // (in c++ it's std::pair<std::pair<int, int>, T>)
        final index = data[0] as List<int>;
        final column = index[0];
        final row = index[1];
        final element = data[1] as dynamic;
        final bd = ByteData(elementSize + 8);
        bd.setInt32(0, column, Endian.little);
        bd.setInt32(4, row, Endian.little);
        _serializeElement(bd, 8, element, typeSpec.baseType);
        return bd.buffer.asUint8List();
      } else {
        throw UnimplementedError(
            'Serialization not implemented for type: $typeSpec');
      }
    }
  }

  // Helper: Deserialize a single element from a ByteData at an offset
  dynamic _deserializeElement(ByteData bd, int offset, DataType type) {
    switch (type) {
      case DataType.float:
        return bd.getFloat32(offset, Endian.little);
      case DataType.float2:
        return [
          bd.getFloat32(offset, Endian.little),
          bd.getFloat32(offset + 4, Endian.little),
        ];
      case DataType.float3:
        return [
          bd.getFloat32(offset, Endian.little),
          bd.getFloat32(offset + 4, Endian.little),
          bd.getFloat32(offset + 8, Endian.little),
        ];
      case DataType.float4:
        return [
          bd.getFloat32(offset, Endian.little),
          bd.getFloat32(offset + 4, Endian.little),
          bd.getFloat32(offset + 8, Endian.little),
          bd.getFloat32(offset + 12, Endian.little),
        ];
      case DataType.int_:
        return bd.getInt32(offset, Endian.little);
      case DataType.int2:
        return [
          bd.getInt32(offset, Endian.little),
          bd.getInt32(offset + 4, Endian.little),
        ];
      case DataType.toggle:
        return bd.getUint8(offset) != 0;
      case DataType.momentary:
        return bd.getUint8(offset) != 0;
      case DataType.enum_:
        return bd.getInt32(offset, Endian.little);
      case DataType.color:
        return bd.getUint32(offset, Endian.little);
      case DataType.keyPress:
        int timestamp = bd.getUint32(offset, Endian.little);
        int col = bd.getInt32(offset + 4, Endian.little);
        int row = bd.getInt32(offset + 8, Endian.little);
        double velocity = bd.getFloat32(offset + 12, Endian.little);
        int oldStateVal = bd.getUint8(offset + 16);
        int newStateVal = bd.getUint8(offset + 17);

        // Determine event type from state transition
        KeyEventType type = KeyEventType.pressed;
        if (oldStateVal == KeyState.rest.index &&
            newStateVal == KeyState.activated.index) {
          type = KeyEventType.activated;
        } else if (oldStateVal == KeyState.activated.index &&
            newStateVal == KeyState.pressed.index) {
          type = KeyEventType.pressed;
        } else if (oldStateVal == KeyState.pressed.index &&
            newStateVal == KeyState.activated.index) {
          type = KeyEventType.unpressed;
        } else if (oldStateVal == KeyState.activated.index &&
            newStateVal == KeyState.rest.index) {
          type = KeyEventType.released;
        } else {
          // Fallback logic based on newState
          if (newStateVal == KeyState.pressed.index) {
            type = KeyEventType.pressed;
          } else if (newStateVal == KeyState.rest.index) {
            type = KeyEventType.released;
          } else if (newStateVal == KeyState.activated.index) {
            type = KeyEventType.activated;
          }
        }

        return KeyEvent(
            type: type,
            column: col,
            row: row,
            velocity: velocity,
            oldState: KeyState
                .values[oldStateVal < KeyState.values.length ? oldStateVal : 0],
            newState: KeyState
                .values[newStateVal < KeyState.values.length ? newStateVal : 0],
            timestamp: timestamp);
      case DataType.nearPress:
        // Read sensor data (32 floats)
        final sensorData = <double>[];
        for (int i = 0; i < 32; i++) {
          sensorData.add(bd.getFloat32(offset + i * 4, Endian.little));
        }

        // Read KeyEvent at offset + 128
        int timestamp = bd.getUint32(offset + 128, Endian.little);
        int col = bd.getInt32(offset + 132, Endian.little);
        int row = bd.getInt32(offset + 136, Endian.little);
        double velocity = bd.getFloat32(offset + 140, Endian.little);
        int oldStateVal = bd.getUint8(offset + 144);
        int newStateVal = bd.getUint8(offset + 145);

        KeyEventType eventType = KeyEventType.pressed;
        if (oldStateVal == KeyState.rest.index &&
            newStateVal == KeyState.activated.index) {
          eventType = KeyEventType.activated;
        } else if (oldStateVal == KeyState.activated.index &&
            newStateVal == KeyState.pressed.index) {
          eventType = KeyEventType.pressed;
        } else if (oldStateVal == KeyState.pressed.index &&
            newStateVal == KeyState.activated.index) {
          eventType = KeyEventType.unpressed;
        } else if (oldStateVal == KeyState.activated.index &&
            newStateVal == KeyState.rest.index) {
          eventType = KeyEventType.released;
        }

        return NearPressPositionData(
          sensorData: sensorData,
          keyEvent: KeyEvent(
            type: eventType,
            column: col,
            row: row,
            velocity: velocity,
            oldState: KeyState
                .values[oldStateVal < KeyState.values.length ? oldStateVal : 0],
            newState: KeyState
                .values[newStateVal < KeyState.values.length ? newStateVal : 0],
            timestamp: timestamp,
          ),
        );
      case DataType.rawSensors:
        return [
          bd.getUint16(offset, Endian.little),
          bd.getUint16(offset + 2, Endian.little)
        ];
      case DataType.ledMessage:
        {
          final ByteData slice = ByteData(LedWire.size);
          for (int i = 0; i < LedWire.size; i++) {
            slice.setUint8(i, bd.getUint8(offset + i));
          }
          return LEDMessage.fromWireByteData(slice);
        }
      case DataType.keyPosition:
        return PosData(
          vertical: bd.getFloat32(offset, Endian.little),
          horizontal: bd.getFloat32(offset + 4, Endian.little),
          horizBlendAmt: bd.getFloat32(offset + 8, Endian.little),
        );
      case DataType.noteControl:
        return {
          'type': bd.getInt32(offset, Endian.little),
          'val1': bd.getFloat32(offset + 4, Endian.little),
          'val2': bd.getFloat32(offset + 8, Endian.little),
        };
      case DataType.midiMessage:
        return {
          'status': bd.getUint8(offset),
          'd1': bd.getUint8(offset + 1),
          'd2': bd.getUint8(offset + 2),
        };
      case DataType.voiceMessage:
        return _deserializeVoiceMessage(bd, offset);
      case DataType.voiceOutputValue:
        return {
          'region_id': bd.getInt32(offset, Endian.little),
          'region_instance_id': bd.getInt32(offset + 4, Endian.little),
          'logical_voice_id': bd.getInt32(offset + 8, Endian.little),
          'slot_idx': bd.getInt32(offset + 12, Endian.little),
          'output_index': bd.getUint32(offset + 16, Endian.little),
          'value': bd.getFloat32(offset + 20, Endian.little),
        };
      case DataType.globalOutputValue:
        return {
          'output_index': bd.getUint32(offset, Endian.little),
          'value': bd.getFloat32(offset + 4, Endian.little),
        };
      case DataType.dppEditorMessage:
        return {
          'type': bd.getUint8(offset),
          'channel': bd.getUint8(offset + 1),
          'note': bd.getUint8(offset + 2),
          'param_index': bd.getUint16(offset + 4, Endian.little),
          'value': bd.getFloat64(offset + 8, Endian.little),
          'value2': bd.getFloat64(offset + 16, Endian.little),
        };
      case DataType.custom:
        throw UnimplementedError(
            'Custom data deserialization not implemented in _deserializeElement');
      case DataType.audioStream:
        throw UnimplementedError(
            'Audio stream deserialization not implemented in _deserializeElement');
      case DataType.scopeBuffer:
        {
          final sampleCount = bd.getUint64(offset, Endian.little);
          final sampleRateHz = bd.getUint32(offset + 8, Endian.little);
          final framesPerPayload = bd.getUint32(offset + 12, Endian.little);
          final int clampedFrameCount = framesPerPayload
              .clamp(
                0,
                ScopeBufferData.maxSamplesPerChannel,
              )
              .toInt();
          final left = <double>[];
          for (int i = 0; i < clampedFrameCount; i++) {
            left.add(bd.getFloat32(offset + 16 + i * 4, Endian.little));
          }
          final right = <double>[];
          for (int i = 0; i < clampedFrameCount; i++) {
            right.add(bd.getFloat32(
              offset + 16 + ScopeBufferData.maxSamplesPerChannel * 4 + i * 4,
              Endian.little,
            ));
          }
          return ScopeBufferData(
            sampleCount: sampleCount,
            sampleRateHz: sampleRateHz,
            framesPerPayload: clampedFrameCount,
            leftSamples: left,
            rightSamples: right,
          );
        }
    }
  }

  dynamic _deserializeData(Uint8List bytes, DataType baseType,
      IndexSpec indexSpec, EndpointCategory category) {
    final bd = ByteData.sublistView(bytes);
    final elementSize = _getElementSize(baseType);

    if (category == EndpointCategory.continuous) {
      // Deserialize multiple elements based on count
      final count = indexSpec.count;
      final result = [];
      for (int i = 0; i < count; i++) {
        result.add(_deserializeElement(bd, i * elementSize, baseType));
      }
      return result;
    } else {
      if (indexSpec.type == IndexType.none) {
        // Single element without index
        return _deserializeElement(bd, 0, baseType);
      } else if (indexSpec.type == IndexType.voice) {
        // Deserialize pair: (int index, element)
        final index = bd.getInt32(0, Endian.little);
        final element = _deserializeElement(bd, 4, baseType);
        return [index, element];
      } else if (indexSpec.type == IndexType.key) {
        // Deserialize pair: ([column, row], element)
        final column = bd.getInt32(0, Endian.little);
        final row = bd.getInt32(4, Endian.little);
        final element = _deserializeElement(bd, 8, baseType);
        return [
          [column, row],
          element
        ];
      } else {
        throw UnimplementedError(
            'Deserialization not implemented for indexSpec type: ${indexSpec.type}');
      }
    }
  }
}
