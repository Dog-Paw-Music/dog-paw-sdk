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
import 'scope_buffer_data.dart';

/// How a JACK-capable endpoint binds to the JACK graph.
enum JackBindingMode {
  registerNewPort,
  adoptExistingPort,
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

  const EndpointSpec({
    required this.direction,
    required this.dataType,
    this.displayName = '',
    this.description = '',
    this.connectionPolicy = const ConnectionPolicy(),
    this.category = EndpointCategory.messageQueue,
    this.jackClientName,
    this.fullJackPortName,
    this.jackBindingMode = JackBindingMode.registerNewPort,
    this.flags = const <String>[],
    this.groupKey,
    this.shimTargetRef,
  });

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
      JsonFields.JACK_CLIENT_NAME: jackClientName,
      JsonFields.FULL_JACK_PORT_NAME: fullJackPortName,
      JsonFields.JACK_BINDING_MODE: jackBindingModeStr,
      JsonFields.FLAGS: flags,
      JsonFields.GROUP_KEY: groupKey,
      JsonFields.SHIM_TARGET_REF: shimTargetRef?.toJson(),
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
    name = other.name;
    namespaceSelector = other.namespaceSelector;
    spec = other.spec;
    resolved = other.resolved;
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
  /// The number of input handles currently tracked for this local endpoint.
  int get inputHandlesCount => _runtimeDelegate?.inputConnectionCount ?? 0;

  LocalEndpointRuntimeDelegate? _runtimeDelegate;
  void Function(LocalEndpointConnectionAddedEvent event)?
      _connectionAddedCallback;
  void Function(LocalEndpointConnectionRemovedEvent event)?
      _connectionRemovedCallback;
  void Function(LocalEndpointConnectionIndexSpecChangedEvent event)?
      _connectionIndexSpecChangedCallback;
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

  /// Write data to a file-backed endpoint
  Future<bool> writeFileBacked(dynamic data) async {
    // 1. Check if this is an output file-backed endpoint
    final currentSpec = resolved ?? spec;
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
    final currentSpec = resolved ?? spec;
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
    final currentSpec = resolved ?? spec;
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
    final effectiveSpec = resolved ?? spec;
    if (effectiveSpec == null) return false;

    try {
      final bytes =
          _serializeData(data, effectiveSpec.dataType, effectiveSpec.category);
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
    final effectiveSpec = resolved ?? spec;
    if (effectiveSpec == null) return [];
    if (effectiveSpec.direction != EndpointDirection.input) return [];
    final List<dynamic> results = <dynamic>[];
    final List<LocalEndpointPollPacket> packets =
        _requireRuntimeDelegate('poll')
            .pollBytes(connectionName: connectionName);
    for (final LocalEndpointPollPacket packet in packets) {
      final dynamic data = _deserializeData(
        packet.bytes,
        effectiveSpec.dataType.baseType,
        packet.indexSpec,
        effectiveSpec.category,
      );
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
    final EndpointSpec? effectiveSpec = resolved ?? spec;
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
      final dynamic data = _deserializeData(
        packet.bytes,
        effectiveSpec.dataType.baseType,
        packet.indexSpec,
        effectiveSpec.category,
      );
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
        return 12;
      case DataType.voiceOutputValue:
        return 24;
      case DataType.globalOutputValue:
        return 8;
      case DataType.dppParamQueue:
        return 16;
      case DataType.custom:
        return -1; // Custom data is handled by file-backed endpoints
      case DataType.audioStream:
        return -1; // Audio stream is handled by file-backed endpoints
      case DataType.scopeBuffer:
        return 16 + ScopeBufferData.maxSamplesPerChannel * 4 * 2;
    }
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
        final map = value as Map<String, dynamic>;
        bd.setInt32(offset, map['type'] as int, Endian.little);
        bd.setInt32(offset + 4, map['voiceIdx'] as int, Endian.little);
        bd.setInt32(offset + 8, map['voiceId'] as int, Endian.little);
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
      case DataType.dppParamQueue:
        final map = value as Map<String, dynamic>;
        bd.setUint16(offset, map['param_index'] as int, Endian.little);
        bd.setUint16(
          offset + 2,
          (map['reserved'] as int?) ?? 0,
          Endian.little,
        );
        bd.setFloat64(
          offset + 8,
          (map['value'] as num).toDouble(),
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
        return {
          'type': bd.getInt32(offset, Endian.little),
          'voiceIdx': bd.getInt32(offset + 4, Endian.little),
          'voiceId': bd.getInt32(offset + 8, Endian.little),
        };
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
      case DataType.dppParamQueue:
        return {
          'param_index': bd.getUint16(offset, Endian.little),
          'reserved': bd.getUint16(offset + 2, Endian.little),
          'value': bd.getFloat64(offset + 8, Endian.little),
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
