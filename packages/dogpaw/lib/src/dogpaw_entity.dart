import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'data_types.dart';
import 'endpoint.dart';
import 'connection.dart';
import 'theme.dart';
import 'scale.dart';
import 'layout.dart';
import 'kv.dart';
import 'result.dart';
import 'json_constants.dart';
import 'namespace_selector.dart';
import 'search_criteria.dart';
import 'data_item_ref.dart';
import 'layout_query.dart';
import 'layout_stack.dart';
import 'ffi/native_dogpaw_entity.dart';
import 'app_logger.dart';

//=============================================================================
// CONNECTION HANDLE
//=============================================================================

/// Message types that can be sent when completing connection
enum ConnectionReadyMessageType {
  ready,
  error,
}

/// Result type for connection operations
class ConnectionResult {
  final bool success;
  final ConnectionHandle? handle;
  final String error;

  ConnectionResult.success(this.handle)
      : success = true,
        error = '';
  ConnectionResult.error(this.error)
      : success = false,
        handle = null;
}

/// Purpose: Bundle the created stateful input and its matched committed-state
/// output so callers can use both runtime handles without extra lookups.
///
/// Parameters:
/// - [input]: Owned writable stateful input endpoint.
/// - [matchedOutput]: Owned output endpoint that publishes committed state.
///
/// Return value:
/// - None. This is a simple immutable data holder.
///
/// Requirements/Preconditions:
/// - Both endpoints belong to the same owning `DogPawEntity`.
///
/// Guarantees/Postconditions:
/// - Stores the two runtime handles exactly as provided.
///
/// Invariants:
/// - [input] is the writable input surface and [matchedOutput] is the public
///   committed-state publication surface.
class StatefulEndpointPair {
  final LocalEndpoint input;
  final LocalEndpoint matchedOutput;

  const StatefulEndpointPair({
    required this.input,
    required this.matchedOutput,
  });
}

/// Purpose: Native-backed runtime adapter for one owned `LocalEndpoint`.
///
/// Parameters:
/// - [client]: `NativeDogPawEntityClient` that already owns the native runtime.
/// - [endpointName]: `String` owned endpoint name within that native client.
///
/// Return value: Internal adapter used only by `DogPawEntity`.
///
/// Requirements/Preconditions:
/// - [endpointName] names an endpoint owned by [client]'s current entity.
///
/// Guarantees/Postconditions:
/// - `writeBytes()` and `pollBytes()` forward directly to the native local
///   endpoint runtime.
///
/// Invariants:
/// - This adapter owns no transport resources beyond the wrapped client
///   reference.
class _NativeLocalEndpointRuntimeDelegate
    implements LocalEndpointRuntimeDelegate {
  _NativeLocalEndpointRuntimeDelegate(this._client, this._endpointName);

  final NativeDogPawEntityClient _client;
  final String _endpointName;

  @override
  int get inputConnectionCount =>
      _client.listLocalEndpointConnectionNames(_endpointName).length;

  @override
  EndpointRetainedStateSnapshot getRetainedStateSnapshot() =>
      _client.queryLocalEndpointRetainedState(_endpointName);

  @override
  bool adoptRetainedStateSnapshot(
    EndpointRetainedStateSnapshot snapshot, {
    bool publishMatchedOutput = true,
    EndpointSenderInfo? senderInfo,
  }) {
    return _client.adoptLocalEndpointRetainedState(
      _endpointName,
      snapshot,
      publishMatchedOutput: publishMatchedOutput,
      senderInfo: senderInfo,
    );
  }

  @override
  bool writeBytes(Uint8List bytes, {bool immediate = true}) {
    return _client.writeLocalEndpointBytes(
      _endpointName,
      bytes,
      immediate: immediate,
    );
  }

  @override
  List<LocalEndpointPollPacket> pollBytes({String? connectionName}) {
    return _client.pollLocalEndpointBytes(
      _endpointName,
      connectionName: connectionName,
    );
  }

  @override
  List<LocalEndpointPollPacket> pollFileBackedBytes({String? connectionName}) {
    return _client.pollFileBackedLocalEndpointBytes(
      _endpointName,
      connectionName: connectionName,
    );
  }

  @override
  List<LocalEndpointPollPacket> readFileBackedBytes({String? connectionName}) {
    return _client.readFileBackedLocalEndpointBytes(
      _endpointName,
      connectionName: connectionName,
    );
  }

  @override
  void dispose() {}
}

/// Token passed to finalizer (can't capture 'this')
class _FinalizerToken {
  final Future<void> Function(ConnectionReadyMessageType) callback;
  final ConnectionReadyMessageType messageType;
  final bool Function() completed;

  _FinalizerToken(this.callback, this.messageType, this.completed);
}

class _ScopedLayoutViewSubscription {
  final LayoutViewPolicy policy;
  final void Function(ScopedLayoutView view) callback;

  const _ScopedLayoutViewSubscription({
    required this.policy,
    required this.callback,
  });
}

/// RAII-style handle for managing connection ready status
///
/// This handle ensures the ready message is ALWAYS sent to the server,
/// either explicitly via complete() or automatically via Finalizer.
///
/// Usage patterns:
///
/// 1. Automatic (using Finalizer):
/// ```dart
/// final result = await dogPaw.connect();
/// if (!result.success) return;
/// final handle = result.handle!;
///
/// // Do setup work...
/// await setupEndpoints();
///
/// // handle will automatically send ready when no longer referenced
/// ```
///
/// 2. Explicit control (RECOMMENDED):
/// ```dart
/// final result = await dogPaw.connect();
/// final handle = result.handle!;
///
/// try {
///   await setupEndpoints();
///   await handle.complete(); // Manual completion
/// } catch (e) {
///   handle.setReadyMessage(ConnectionReadyMessageType.error);
///   await handle.complete();
/// }
/// ```
///
/// 3. Transfer ownership (defer completion):
/// ```dart
/// final result = await dogPaw.connect();
/// myObject.handle = result.handle; // Store in object
/// // handle is transferred, completion deferred until myObject is cleaned up
/// ```
class ConnectionHandle {
  final Future<void> Function(ConnectionReadyMessageType) _readyCallback;
  ConnectionReadyMessageType _readyMessageType =
      ConnectionReadyMessageType.ready;
  bool _completed = false;

  static final _finalizer = Finalizer<_FinalizerToken>((token) {
    // Called by GC when handle is no longer referenced
    if (!token.completed()) {
      AppLogger.warning('ConnectionHandle: Auto-completing via finalizer. '
          'Consider calling handle.complete() explicitly for better control.');
      token.callback(token.messageType);
    }
  });

  ConnectionHandle(this._readyCallback) {
    // Register with finalizer for automatic cleanup
    final token = _FinalizerToken(
      _readyCallback,
      _readyMessageType,
      () => _completed,
    );
    _finalizer.attach(this, token, detach: this);
  }

  /// Set the message type to send (default: ready)
  void setReadyMessage(ConnectionReadyMessageType messageType) {
    _readyMessageType = messageType;
  }

  /// Manually complete the connection (send ready message)
  /// Safe to call multiple times - only sends once
  Future<void> complete() async {
    if (!_completed) {
      _completed = true;
      _finalizer.detach(this); // Prevent finalizer from running
      await _readyCallback(_readyMessageType);
    }
  }

  /// Check if already completed
  bool get isCompleted => _completed;
}

/// Main API class for interacting with the Epiphany system
///
/// WARNING: This Dart implementation must be kept in sync with the C++ implementation
/// located at dogPawEntity/cpp/DogPawEntity.hpp.
/// Any changes to the public API, data structures, or protocols must be reflected in both.
///
/// This class is the public Dart facade over the native C++ `DogPawEntity`
/// implementation. It provides the high-level Dog Paw API while routing
/// transport and request execution through the native bridge. It handles:
/// - Native-backed connection lifecycle
/// - Type-safe serialization/deserialization
/// - Subscription management for real-time updates
/// - Dart-side callback and local endpoint tracking

class DogPawEntity {
  static const String _internalRetainedStateQueryCommand =
      '__dogpaw_query_endpoint_retained_state';
  static const String _retainedStateQueryEndpointNameField = 'endpointName';
  //=========================================================================
  // TEST INFRASTRUCTURE OVERRIDES
  //=========================================================================

  /// Override for runtime entity-name resolution in tests and non-launched tools.
  /// When non-null, takes priority over DOGPAW_ENTITY_NAME env var.
  /// Null in production (falls through to DOGPAW_ENTITY_NAME env var).
  static String? entityNameOverride;
  static final Map<String, String> environmentOverrides = <String, String>{};

  //=========================================================================
  // DEBUG FLAGS
  //=========================================================================

  //=========================================================================
  // PRIVATE FIELDS
  //=========================================================================

  final String _entityName;

  /// Returns the entity name used for this instance
  String get entityName => _entityName;
  bool _disconnecting = false;
  final String _serverUrl;
  final Duration _timeout;
  NativeDogPawEntityClient? _nativeClient;
  Future<void> _nativeClientDisposeFuture = Future<void>.value();
  bool _nativeEndpointNotificationsSubscribed = false;
  Future<Result<bool>>? _nativeEndpointNotificationSubscriptionFuture;
  bool _layoutQuerySnapshotsSubscribed = false;
  Future<Result<bool>>? _layoutQuerySnapshotSubscriptionFuture;
  LayoutStackSnapshot? _cachedLayoutStackSnapshot;
  LayoutQuerySnapshot? _cachedLayoutQuerySnapshot;
  final Map<String, ScopedLayoutView> _cachedScopedLayoutViews =
      <String, ScopedLayoutView>{};
  String? _layoutQuerySnapshotError;
  Completer<void>? _layoutQuerySnapshotReadyCompleter;
  final List<void Function(LayoutQuerySnapshot)> _layoutQuerySnapshotCallbacks =
      <void Function(LayoutQuerySnapshot)>[];
  final List<_ScopedLayoutViewSubscription> _scopedLayoutViewCallbacks =
      <_ScopedLayoutViewSubscription>[];

  // Callbacks
  Function(String)? _errorCallback;
  Function(String senderEntity, Map<String, dynamic> content)?
      _directMessageCallback;
  Function(String senderEntity, String command, Map<String, dynamic> params,
      String requestId)? _commandCallback;
  Future<bool> Function(String serverRequestId, Map<String, dynamic> content)?
      _presetRequestCallback;
  final Map<String, Function(String connectionName, IndexSpec newIndexSpec)>
      _indexSpecChangeCallbacks = {};
  final Map<String, EndpointRetainedStateSnapshot Function(LocalEndpoint endpoint)>
      _endpointRetainedStateQueryCallbacks =
      <String, EndpointRetainedStateSnapshot Function(LocalEndpoint endpoint)>{};

  // Endpoint registry (live local endpoints created by this entity)
  // Maps endpoint name to LocalEndpoint object
  final Map<String, LocalEndpoint> _myEndpoints = {};

  /// Get a cached local endpoint by name.
  LocalEndpoint? getEndpoint(String name) {
    return _myEndpoints[name];
  }

  /// Purpose: Return the cached local endpoint for one endpoint metadata object.
  ///
  /// Parameters:
  /// - [endpoint]: `EndpointInfo` metadata snapshot for an owned endpoint.
  ///
  /// Return value:
  /// - The cached `LocalEndpoint` when this facade already owns a live runtime
  ///   endpoint with the same name, otherwise `null`.
  ///
  /// Requirements/Preconditions:
  /// - None. The endpoint may or may not be owned by this facade.
  ///
  /// Guarantees/Postconditions:
  /// - Does not create, destroy, or mutate local endpoint runtime state.
  ///
  /// Invariants:
  /// - Lookup is keyed by endpoint name inside this facade's owned-endpoint
  ///   registry.
  LocalEndpoint? getLocalEndpoint(EndpointInfo endpoint) {
    return _myEndpoints[endpoint.name];
  }

  /// Purpose: Return the cached local endpoint for one owned endpoint name.
  ///
  /// Parameters:
  /// - [name]: `String` endpoint name to look up in this facade's local runtime
  ///   registry.
  ///
  /// Return value:
  /// - The cached `LocalEndpoint` when present, otherwise `null`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Does not create, destroy, or mutate local endpoint runtime state.
  ///
  /// Invariants:
  /// - Lookup is scoped to endpoints owned by this `DogPawEntity` instance.
  LocalEndpoint? getLocalEndpointByName(String name) {
    return _myEndpoints[name];
  }

  /// Purpose: Merge one endpoint metadata snapshot into the owned local-endpoint
  /// registry and return the live runtime object.
  ///
  /// Parameters:
  /// - [endpointInfo]: `EndpointInfo` snapshot returned by the native bridge.
  ///
  /// Return value:
  /// - `LocalEndpoint` representing the owned endpoint runtime for this facade.
  ///
  /// Requirements/Preconditions:
  /// - [endpointInfo] belongs to this entity's namespace.
  ///
  /// Guarantees/Postconditions:
  /// - Reuses an existing `LocalEndpoint` when present so runtime handles remain
  ///   stable across metadata refreshes.
  /// - Creates and initializes a new `LocalEndpoint` when first encountering an
  ///   owned endpoint.
  ///
  /// Invariants:
  /// - Only owned endpoints are stored in `_myEndpoints`.
  LocalEndpoint _materializeOwnedEndpoint(EndpointInfo endpointInfo) {
    final LocalEndpoint? existing = _myEndpoints[endpointInfo.name];
    if (existing != null) {
      existing.attachRuntimeDelegate(
        _NativeLocalEndpointRuntimeDelegate(
          _requireNativeClient(),
          endpointInfo.name,
        ),
      );
      existing.update(endpointInfo);
      AppLogger.debug(
          'DogPawEntity: Refreshed existing local endpoint: ${existing.name}');
      return existing;
    }

    final LocalEndpoint localEndpoint =
        LocalEndpoint.fromEndpointInfo(endpointInfo);
    localEndpoint.attachRuntimeDelegate(
      _NativeLocalEndpointRuntimeDelegate(
        _requireNativeClient(),
        endpointInfo.name,
      ),
    );
    _myEndpoints[localEndpoint.name] = localEndpoint;
    AppLogger.debug(
        'DogPawEntity: Created new local endpoint: ${localEndpoint.name} '
        '(queueShmName=${localEndpoint.queueShmName}, '
        'socketPath=${localEndpoint.socketPath}, '
        'sharedDataName=${localEndpoint.sharedDataName})');
    return localEndpoint;
  }

  /// Purpose: Refresh cached local endpoint metadata from a metadata-only
  /// endpoint snapshot without changing the public return type.
  ///
  /// Parameters:
  /// - [endpointInfo]: `EndpointInfo` snapshot returned by the native bridge.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None. Non-owned endpoints are ignored.
  ///
  /// Guarantees/Postconditions:
  /// - If this facade already owns the endpoint, its cached `LocalEndpoint`
  ///   metadata is updated to match [endpointInfo].
  ///
  /// Invariants:
  /// - Does not create new local endpoints from read/list/search paths.
  void _syncOwnedEndpointMetadata(EndpointInfo endpointInfo) {
    final bool isMine = endpointInfo.namespaceSelector.isSpecificEntity &&
        endpointInfo.namespaceSelector.sourceEntity == _entityName;
    if (!isMine) {
      return;
    }
    final LocalEndpoint? existing = _myEndpoints[endpointInfo.name];
    existing?.update(endpointInfo);
  }

  //=========================================================================
  // CONSTRUCTOR
  //=========================================================================

  /// Constructor
  ///
  /// [entityName] - Optional explicit entity-name override. When null, the
  /// name is resolved via [entityNameOverride] (for tests), then the
  /// `DOGPAW_ENTITY_NAME` environment variable (for launched apps).
  DogPawEntity([
    String? entityName,
  ])  : _entityName = _resolveEntityName(entityName),
        _serverUrl = "ws://localhost:8080",
        _timeout = const Duration(seconds: 5);

  /// Resolve the entity name for this client instance.
  ///
  /// Resolution order:
  ///   1. Explicit constructor argument
  ///   2. [entityNameOverride] for tests
  ///   3. `DOGPAW_ENTITY_NAME` env var
  ///
  /// Throws [StateError] if no runtime entity name is available.
  static String _resolveEntityName(String? explicitEntityName) {
    if (explicitEntityName != null && explicitEntityName.isNotEmpty) {
      return explicitEntityName;
    }

    final overrideEntityName = entityNameOverride;
    if (overrideEntityName != null && overrideEntityName.isNotEmpty) {
      return overrideEntityName;
    }

    final envEntityName = _env('DOGPAW_ENTITY_NAME');
    if (envEntityName != null && envEntityName.isNotEmpty) {
      return envEntityName;
    }

    throw StateError(
      'DogPawEntity requires an explicit entity name or DOGPAW_ENTITY_NAME',
    );
  }

  /// Look up an environment value with test overrides.
  ///
  /// Purpose: Lets unit tests validate runtime path behavior without mutating
  /// Dart's immutable [Platform.environment] snapshot.
  ///
  /// Parameters:
  /// - [name]: Environment variable name to resolve.
  /// Return value: override value, process environment value, or `null`.
  /// Requirements/Preconditions: [name] is non-empty.
  /// Guarantees/Postconditions: No environment state is modified.
  /// Invariants: [environmentOverrides] takes precedence.
  static String? _env(String name) {
    return environmentOverrides[name] ?? Platform.environment[name];
  }

  /// Resolve Dog Paw's persistent data root.
  ///
  /// Purpose: Mirrors Epiphany RuntimePaths data-root selection so apps can ask
  /// DogPawEntity for stable directories.
  ///
  /// Parameters: none.
  /// Return value: persistent data root path.
  /// Requirements/Preconditions: one of `DOGPAW_DATA_DIR`, `XDG_DATA_HOME`, or
  /// `HOME` is set.
  /// Guarantees/Postconditions: no filesystem state is modified.
  /// Invariants: `DOGPAW_DATA_DIR` takes precedence over XDG defaults.
  static String _resolveDataRoot() {
    final dogpawData = _env('DOGPAW_DATA_DIR');
    if (dogpawData != null && dogpawData.isNotEmpty) {
      return dogpawData;
    }
    final xdgDataHome = _env('XDG_DATA_HOME');
    if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
      return '$xdgDataHome/dogpaw';
    }
    final home = _env('HOME');
    if (home != null && home.isNotEmpty) {
      return '$home/.local/share/dogpaw';
    }
    throw StateError(
        'Cannot resolve Dog Paw data root; set DOGPAW_DATA_DIR, XDG_DATA_HOME, or HOME');
  }

  /// Resolve Dog Paw's persistent cache root.
  ///
  /// Purpose: Mirrors the XDG cache-root selection so apps can store evictable
  /// derived artifacts without mixing them into durable app files.
  ///
  /// Parameters: none.
  /// Return value: persistent cache root path.
  /// Requirements/Preconditions: one of `DOGPAW_CACHE_DIR`, `XDG_CACHE_HOME`,
  /// or `HOME` is set.
  /// Guarantees/Postconditions: no filesystem state is modified.
  /// Invariants: `DOGPAW_CACHE_DIR` takes precedence over XDG defaults.
  static String _resolveCacheRoot() {
    final dogpawCache = _env('DOGPAW_CACHE_DIR');
    if (dogpawCache != null && dogpawCache.isNotEmpty) {
      return dogpawCache;
    }
    final xdgCacheHome = _env('XDG_CACHE_HOME');
    if (xdgCacheHome != null && xdgCacheHome.isNotEmpty) {
      return '$xdgCacheHome/dogpaw';
    }
    final home = _env('HOME');
    if (home != null && home.isNotEmpty) {
      return '$home/.cache/dogpaw';
    }
    throw StateError(
        'Cannot resolve Dog Paw cache root; set DOGPAW_CACHE_DIR, XDG_CACHE_HOME, or HOME');
  }

  /// Resolve the optional emulator name.
  ///
  /// Purpose: Selects emulator-scoped persistent app-file roots when an emulator
  /// profile is active.
  ///
  /// Parameters: none.
  /// Return value: emulator name when `DOGPAW_EMULATOR_NAME` is non-empty;
  /// otherwise `null`.
  /// Requirements/Preconditions: none.
  /// Guarantees/Postconditions: no filesystem state is modified.
  /// Invariants: empty environment values are treated as unset.
  static String? _resolveEmulatorName() {
    final emulatorName = _env('DOGPAW_EMULATOR_NAME');
    if (emulatorName != null && emulatorName.isNotEmpty) {
      return emulatorName;
    }
    return null;
  }

  /// Resolve the installed app registry root.
  ///
  /// Purpose: Computes where installed app bundles live for the current runtime,
  /// honoring explicit app-root and emulator-root selection.
  ///
  /// Parameters:
  /// - [dataRoot]: resolved persistent data root used for defaults.
  /// Return value: installed app registry root path.
  /// Requirements/Preconditions: [dataRoot] is non-empty.
  /// Guarantees/Postconditions: no filesystem state is modified.
  /// Invariants: `DOGPAW_APP_DIR` takes precedence over defaults.
  static String _resolveAppRoot(String dataRoot) {
    final dogpawAppDir = _env('DOGPAW_APP_DIR');
    if (dogpawAppDir != null && dogpawAppDir.isNotEmpty) {
      return dogpawAppDir;
    }
    final emulatorName = _resolveEmulatorName();
    if (emulatorName != null) {
      return '$dataRoot/emulators/$emulatorName/apps';
    }
    return '$dataRoot/apps';
  }

  /// Resolve Dog Paw's runtime root.
  ///
  /// Purpose: Mirrors the port-file/runtime-root convention used by Epiphany so
  /// client scratch directories are scoped to the same runtime base.
  ///
  /// Parameters: none.
  /// Return value: runtime root path before the instance-name component.
  /// Requirements/Preconditions: `DOGPAW_RUNTIME_DIR` or `XDG_RUNTIME_DIR` is
  /// set.
  /// Guarantees/Postconditions: no filesystem state is modified.
  /// Invariants: `DOGPAW_RUNTIME_DIR` takes precedence over `XDG_RUNTIME_DIR`.
  static String _resolveRuntimeRoot() {
    final dogpawRuntime = _env('DOGPAW_RUNTIME_DIR');
    if (dogpawRuntime != null && dogpawRuntime.isNotEmpty) {
      return dogpawRuntime;
    }
    final xdgRuntime = _env('XDG_RUNTIME_DIR');
    if (xdgRuntime != null && xdgRuntime.isNotEmpty) {
      return '$xdgRuntime/dogpaw';
    }
    throw StateError(
        'Cannot resolve Dog Paw runtime root; set DOGPAW_RUNTIME_DIR or XDG_RUNTIME_DIR');
  }

  /// Ensure a directory exists and return its path.
  ///
  /// Purpose: Gives public directory APIs a shared postcondition that the
  /// returned path is usable immediately.
  ///
  /// Parameters:
  /// - [path]: directory path to create if needed.
  /// Return value: [path] as returned by [Directory.path].
  /// Requirements/Preconditions: parent filesystem is writable when the
  /// directory does not already exist.
  /// Guarantees/Postconditions: directory exists.
  /// Invariants: existing directories are preserved.
  static String _ensureDirectory(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Purpose: Convert the public connection ready enum into the native bridge
  /// enum.
  ///
  /// Parameters:
  /// - [messageType]: `ConnectionReadyMessageType` selected by the public
  ///   caller.
  ///
  /// Return value:
  /// - `NativeConnectionReadyMessageType` with the same semantic meaning.
  ///
  /// Requirements/Preconditions:
  /// - [messageType] must be a valid public ready enum value.
  ///
  /// Guarantees/Postconditions:
  /// - The returned enum matches the requested ready/error meaning.
  ///
  /// Invariants:
  /// - The mapping preserves the public connection-handle contract exactly.
  NativeConnectionReadyMessageType _mapNativeReadyMessageType(
      ConnectionReadyMessageType messageType) {
    switch (messageType) {
      case ConnectionReadyMessageType.ready:
        return NativeConnectionReadyMessageType.ready;
      case ConnectionReadyMessageType.error:
        return NativeConnectionReadyMessageType.error;
    }
  }

  /// Purpose: Return the active native client backing this public facade.
  ///
  /// Parameters: None.
  ///
  /// Return value:
  /// - `NativeDogPawEntityClient` currently backing this public facade.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - Returns the live native client when available.
  ///
  /// Invariants:
  /// - Throws `StateError` instead of returning null when the public facade is
  ///   not connected through the native bridge.
  NativeDogPawEntityClient _requireNativeClient() {
    final NativeDogPawEntityClient? client = _nativeClient;
    if (client == null) {
      throw StateError(
          'DogPawEntity is not connected through the native DogPawEntity bridge.');
    }
    return client;
  }

  /// Purpose: Ensure the public facade is subscribed to native endpoint
  /// notifications needed for owned-endpoint metadata refresh and runtime
  /// observation callbacks.
  ///
  /// Parameters: None.
  ///
  /// Return value:
  /// - `Future<Result<bool>>` indicating whether the internal subscription is
  ///   active.
  ///
  /// Requirements/Preconditions:
  /// - The facade is connected through the native bridge.
  ///
  /// Guarantees/Postconditions:
  /// - On success, owned endpoint CRUD and runtime notifications are forwarded
  ///   from the native client into `_handleEndpointNotification`.
  ///
  /// Invariants:
  /// - At most one internal subscribe request is in flight at a time.
  Future<Result<bool>> _ensureNativeEndpointNotificationSubscription() async {
    if (_nativeEndpointNotificationsSubscribed) {
      return Result<bool>.success(true);
    }

    final Future<Result<bool>>? existingFuture =
        _nativeEndpointNotificationSubscriptionFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    final NativeDogPawEntityClient client = _requireNativeClient();
    client.setEndpointNotificationCallback(_handleEndpointNotification);

    final Future<Result<bool>> subscriptionFuture = client.subscribeToEndpoints(
      (_, __, ___) {},
      namespaceSelector: const NamespaceSelector.currentEntity(),
      includeResolved: true,
      includeSpec: true,
      sendImmediately: true,
    );
    _nativeEndpointNotificationSubscriptionFuture = subscriptionFuture;

    final Result<bool> result = await subscriptionFuture;
    _nativeEndpointNotificationSubscriptionFuture = null;
    if (result.success) {
      _nativeEndpointNotificationsSubscribed = true;
    } else {
      client.setEndpointNotificationCallback(null);
    }
    return result;
  }

  /// Purpose: Update the cached layout-query snapshot from one raw layout-stack
  /// notification payload.
  ///
  /// Parameters:
  /// - [message]: raw layout-stack notification content from the native client.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - [message] is expected to contain a `layoutStack` payload.
  ///
  /// Guarantees/Postconditions:
  /// - On valid input, `_cachedLayoutQuerySnapshot` is replaced and helper-level
  ///   query callbacks are notified.
  ///
  /// Invariants:
  /// - Malformed notifications are ignored instead of throwing into native event
  ///   dispatch.
  void _handleLayoutStackNotification(Map<String, dynamic> message) {
    final dynamic rawLayoutStack = message[JsonFields.LAYOUT_STACK];
    if (rawLayoutStack is! Map<String, dynamic>) {
      if (_layoutQuerySnapshotReadyCompleter != null &&
          !_layoutQuerySnapshotReadyCompleter!.isCompleted) {
        _layoutQuerySnapshotError =
            'Layout query cache notification missing layoutStack payload.';
        _layoutQuerySnapshotReadyCompleter!.complete();
      }
      return;
    }

    final LayoutStackSnapshot rawSnapshot =
        LayoutStackSnapshot.fromJson(rawLayoutStack);
    final LayoutQuerySnapshot snapshot = LayoutQuerySnapshot(rawSnapshot);
    _cachedLayoutStackSnapshot = rawSnapshot;
    _cachedLayoutQuerySnapshot = snapshot;
    _cachedScopedLayoutViews.clear();
    _layoutQuerySnapshotError = null;
    final Completer<void>? readyCompleter = _layoutQuerySnapshotReadyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.complete();
    }

    final List<void Function(LayoutQuerySnapshot)> callbacks =
        List<void Function(LayoutQuerySnapshot)>.from(
      _layoutQuerySnapshotCallbacks,
    );
    for (final void Function(LayoutQuerySnapshot) callback in callbacks) {
      try {
        callback(snapshot);
      } catch (_) {
        // Keep helper callback dispatch resilient to callback failures.
      }
    }

    if (_scopedLayoutViewCallbacks.isNotEmpty) {
      unawaited(_refreshScopedLayoutViewCallbacks(rawSnapshot));
    }
  }

  /// Purpose: Ensure the layout-query cache has been initialized from a live
  /// internal layout-stack subscription.
  ///
  /// Parameters: None.
  ///
  /// Return value:
  /// - `Future<Result<bool>>` indicating whether the cache is ready.
  ///
  /// Requirements/Preconditions:
  /// - The facade is connected through the native bridge.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the internal raw layout-stack subscription stays active and
  ///   future notifications refresh `_cachedLayoutQuerySnapshot`.
  ///
  /// Invariants:
  /// - At most one internal layout-query subscribe request is in flight at a time.
  Future<Result<bool>> _ensureLayoutQuerySnapshotCache() async {
    if (_layoutQuerySnapshotsSubscribed && _cachedLayoutQuerySnapshot != null) {
      return Result<bool>.success(true);
    }

    final Future<Result<bool>>? existingFuture =
        _layoutQuerySnapshotSubscriptionFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    final NativeDogPawEntityClient client = _requireNativeClient();
    client.setLayoutStackNotificationCallback(_handleLayoutStackNotification);
    _layoutQuerySnapshotReadyCompleter = Completer<void>();
    _layoutQuerySnapshotError = null;

    final Future<Result<bool>> subscriptionFuture =
        (() async {
      final Result<bool> subscribeResult = await client.subscribeToLayoutStack(
        (_, __, ___) {},
        includeResolved: true,
        includeSpec: false,
        sendImmediately: true,
      );
      if (!subscribeResult.success) {
        return Result<bool>.error(subscribeResult.error);
      }

      await _layoutQuerySnapshotReadyCompleter!.future;
      if (_cachedLayoutQuerySnapshot == null) {
        return Result<bool>.error(
          _layoutQuerySnapshotError ??
              'Layout query cache did not receive an initial snapshot.',
        );
      }
      return Result<bool>.success(true);
    })();
    _layoutQuerySnapshotSubscriptionFuture = subscriptionFuture;

    final Result<bool> result = await subscriptionFuture;
    _layoutQuerySnapshotSubscriptionFuture = null;
    if (result.success) {
      _layoutQuerySnapshotsSubscribed = true;
    } else {
      client.setLayoutStackNotificationCallback(null);
    }
    return result;
  }

  String _scopedLayoutViewCacheKey(LayoutViewPolicy policy) {
    final String targetKey = policy.targetKey ?? '';
    return '${policy.strategy.index}::$targetKey';
  }

  String _layoutScopeValue(Layout layout) {
    if (layout.spec != null && layout.spec!.scope.isNotEmpty) {
      return layout.spec!.scope;
    }
    if (layout.resolved != null && layout.resolved!.scope.isNotEmpty) {
      return layout.resolved!.scope;
    }
    return 'shared';
  }

  String? _layoutTargetKeyValue(Layout layout) {
    return layout.spec?.targetKey ?? layout.resolved?.targetKey;
  }

  Future<Result<List<Layout>>> _hydrateLayoutsForSnapshot(
    LayoutStackSnapshot snapshot,
  ) async {
    final List<Layout> hydratedLayouts = <Layout>[];
    for (final LayoutStackEntry entry in snapshot.entries) {
      final Result<Layout?> readResult = await readLayout(
        entry.layoutRef.name,
        namespaceSelector: entry.layoutRef.namespaceSelector,
        includeResolved: true,
        includeSpec: true,
      );
      if (!readResult.success) {
        return Result<List<Layout>>.error(readResult.error);
      }
      final Layout? layout = readResult.value;
      if (layout == null) {
        return Result<List<Layout>>.error(
          'Referenced layout disappeared while building scoped view: ${entry.layoutRef.name}',
        );
      }
      hydratedLayouts.add(layout);
    }
    return Result<List<Layout>>.success(hydratedLayouts);
  }

  Layout _composeResolvedScopedLayout(
    LayoutViewPolicy policy,
    LayoutStackSnapshot snapshot,
    List<Layout> hydratedLayouts,
  ) {
    final List<Layout> sharedLayouts = <Layout>[];
    final List<Layout> matchingTargetedLayouts = <Layout>[];
    for (int index = 0;
        index < snapshot.entries.length && index < hydratedLayouts.length;
        index++) {
      final Layout layout = hydratedLayouts[index];
      final String scope = _layoutScopeValue(layout);
      final String? targetKey = _layoutTargetKeyValue(layout);
      if (scope == 'targeted') {
        if (policy.targetKey != null && targetKey == policy.targetKey) {
          matchingTargetedLayouts.add(layout);
        }
      } else {
        sharedLayouts.add(layout);
      }
    }

    late final List<Layout> selectedLayouts;
    if (policy.strategy == LayoutViewStrategy.sharedOnly) {
      selectedLayouts = sharedLayouts;
    } else if (policy.strategy == LayoutViewStrategy.targetedOnly) {
      selectedLayouts = matchingTargetedLayouts;
    } else if (policy.strategy == LayoutViewStrategy.sharedPlusTargeted) {
      selectedLayouts = <Layout>[
        ...sharedLayouts,
        ...matchingTargetedLayouts,
      ];
    } else {
      selectedLayouts = matchingTargetedLayouts.isNotEmpty
          ? matchingTargetedLayouts
          : sharedLayouts;
    }

    LayoutData merged = const LayoutData(displayName: 'Scoped Layout View');
    for (final Layout layout in selectedLayouts) {
      final LayoutData? sourceData = layout.resolved ?? layout.spec;
      if (sourceData == null) {
        continue;
      }
      final Map<String, dynamic> mergedKeyIntents =
          Map<String, dynamic>.from(merged.keyIntents);
      for (final MapEntry<String, dynamic> entry in sourceData.keyIntents.entries) {
        final List<dynamic> existingIntents =
            List<dynamic>.from(mergedKeyIntents[entry.key] as List<dynamic>? ?? <dynamic>[]);
        final List<dynamic> sourceIntents =
            List<dynamic>.from(entry.value as List<dynamic>? ?? <dynamic>[]);
        mergedKeyIntents[entry.key] = <dynamic>[
          ...existingIntents,
          ...sourceIntents,
        ];
      }
      final Map<String, dynamic> mergedKeyColors =
          Map<String, dynamic>.from(merged.keyColors)
            ..addAll(sourceData.keyColors);
      merged = LayoutData(
        displayName: sourceData.displayName.isNotEmpty
            ? sourceData.displayName
            : merged.displayName,
        scope: 'shared',
        keyIntents: mergedKeyIntents,
        keyColors: mergedKeyColors,
        themeRef: sourceData.themeRef ?? merged.themeRef,
        scaleRef: sourceData.scaleRef ?? merged.scaleRef,
      );
    }

    return Layout.full(
      name: '__SCOPED_LAYOUT_VIEW__',
      namespaceSelector: const NamespaceSelector.currentEntity(),
      resolved: merged,
    );
  }

  Future<Result<ScopedLayoutView>> _buildScopedLayoutView(
    LayoutViewPolicy policy,
  ) async {
    final Result<bool> cacheResult = await _ensureLayoutQuerySnapshotCache();
    if (!cacheResult.success) {
      return Result<ScopedLayoutView>.error(cacheResult.error);
    }

    final String cacheKey = _scopedLayoutViewCacheKey(policy);
    final ScopedLayoutView? cachedView = _cachedScopedLayoutViews[cacheKey];
    if (cachedView != null) {
      return Result<ScopedLayoutView>.success(cachedView);
    }

    final LayoutStackSnapshot? snapshot = _cachedLayoutStackSnapshot;
    if (snapshot == null) {
      return Result<ScopedLayoutView>.error(
        'Layout stack cache is not initialized.',
      );
    }

    final Result<List<Layout>> hydratedLayoutsResult =
        await _hydrateLayoutsForSnapshot(snapshot);
    if (!hydratedLayoutsResult.success) {
      return Result<ScopedLayoutView>.error(hydratedLayoutsResult.error);
    }

    final ScopedLayoutView view = ScopedLayoutView.fromResolvedLayout(
      _composeResolvedScopedLayout(policy, snapshot, hydratedLayoutsResult.value!),
      policy,
    );
    _cachedScopedLayoutViews[cacheKey] = view;
    return Result<ScopedLayoutView>.success(view);
  }

  Future<void> _refreshScopedLayoutViewCallbacks(
    LayoutStackSnapshot snapshot,
  ) async {
    final Result<List<Layout>> hydratedLayoutsResult =
        await _hydrateLayoutsForSnapshot(snapshot);
    if (!hydratedLayoutsResult.success) {
      return;
    }

    final List<_ScopedLayoutViewSubscription> callbacks =
        List<_ScopedLayoutViewSubscription>.from(_scopedLayoutViewCallbacks);
    for (final _ScopedLayoutViewSubscription entry in callbacks) {
      final ScopedLayoutView view = ScopedLayoutView.fromResolvedLayout(
        _composeResolvedScopedLayout(
          entry.policy,
          snapshot,
          hydratedLayoutsResult.value!,
        ),
        entry.policy,
      );
      _cachedScopedLayoutViews[_scopedLayoutViewCacheKey(entry.policy)] = view;
      try {
        entry.callback(view);
      } catch (_) {
        // Keep helper callback dispatch resilient to callback failures.
      }
    }
  }

  /// Purpose: Run one public native-backed operation through the native client.
  ///
  /// Parameters:
  /// - [operation]: callback that performs one native-backed public operation.
  ///
  /// Return value:
  /// - `Future<Result<T>>` mirroring the native client's success or failure.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - Converts thrown bridge-usage errors into public `Result.error` values.
  ///
  /// Invariants:
  /// - This helper does not mutate payloads or public method semantics.
  Future<Result<T>> _runNativeCrudOperation<T>(
    Future<Result<T>> Function(NativeDogPawEntityClient client) operation,
  ) async {
    try {
      return await operation(_requireNativeClient());
    } catch (exception) {
      return Result<T>.error(exception.toString());
    }
  }

  /// Purpose: Run one native endpoint mutation and normalize the returned
  /// endpoint through the public facade's endpoint cache.
  ///
  /// Parameters:
  /// - [operation]: callback that performs one native endpoint mutation and
  ///   returns the typed endpoint payload.
  ///
  /// Return value:
  /// - `Future<Result<LocalEndpoint>>` containing the public facade's usable
  ///   local endpoint instance.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned endpoint metadata has been merged into the
  ///   local endpoint registry so existing handles remain coherent.
  ///
  /// Invariants:
  /// - Native transport details stay hidden behind the public facade.
  Future<Result<LocalEndpoint>> _runNativeEndpointMutation(
    Future<Result<EndpointInfo>> Function(NativeDogPawEntityClient client)
        operation,
  ) async {
    return _runNativeCrudOperation<LocalEndpoint>(
        (NativeDogPawEntityClient client) async {
      final Result<bool> subscriptionResult =
          await _ensureNativeEndpointNotificationSubscription();
      if (!subscriptionResult.success) {
        return Result<LocalEndpoint>.error(subscriptionResult.error);
      }
      final Result<EndpointInfo> result = await operation(client);
      if (!result.success) {
        return Result<LocalEndpoint>.error(result.error);
      }
      final EndpointInfo? endpointInfo = result.value;
      if (endpointInfo == null) {
        return Result<LocalEndpoint>.error(
          'Failed to hydrate endpoint payload from native bridge result.',
        );
      }
      return Result<LocalEndpoint>.success(
        _materializeOwnedEndpoint(endpointInfo),
      );
    });
  }

  /// Purpose: Run one native endpoint read and normalize the optional endpoint
  /// through the public facade's endpoint cache.
  ///
  /// Parameters:
  /// - [operation]: callback that performs one native endpoint read.
  ///
  /// Return value:
  /// - `Future<Result<EndpointInfo?>>` containing endpoint metadata, or `null`
  ///   when absent.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, any returned owned endpoint refreshes cached local metadata
  ///   without changing the metadata-only return type.
  ///
  /// Invariants:
  /// - Native transport details stay hidden behind the public facade.
  Future<Result<EndpointInfo?>> _runNativeEndpointRead(
    Future<Result<EndpointInfo?>> Function(NativeDogPawEntityClient client)
        operation,
  ) async {
    return _runNativeCrudOperation<EndpointInfo?>(
        (NativeDogPawEntityClient client) async {
      final Result<bool> subscriptionResult =
          await _ensureNativeEndpointNotificationSubscription();
      if (!subscriptionResult.success) {
        return Result<EndpointInfo?>.error(subscriptionResult.error);
      }
      final Result<EndpointInfo?> result = await operation(client);
      if (!result.success) {
        return Result<EndpointInfo?>.error(result.error);
      }
      if (result.value == null) {
        return Result<EndpointInfo?>.success(null);
      }
      _syncOwnedEndpointMetadata(result.value!);
      return Result<EndpointInfo?>.success(result.value);
    });
  }

  /// Purpose: Run one native endpoint list/search request and normalize each
  /// returned endpoint through the public facade's endpoint cache.
  ///
  /// Parameters:
  /// - [operation]: callback that performs one native endpoint list-style
  ///   operation.
  ///
  /// Return value:
  /// - `Future<Result<List<EndpointInfo>>>` containing endpoint metadata
  ///   snapshots.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, any owned endpoints refresh cached local metadata without
  ///   changing the metadata-only return type.
  ///
  /// Invariants:
  /// - Native transport details stay hidden behind the public facade.
  Future<Result<List<EndpointInfo>>> _runNativeEndpointList(
    Future<Result<List<EndpointInfo>>> Function(NativeDogPawEntityClient client)
        operation,
  ) async {
    return _runNativeCrudOperation<List<EndpointInfo>>(
        (NativeDogPawEntityClient client) async {
      final Result<bool> subscriptionResult =
          await _ensureNativeEndpointNotificationSubscription();
      if (!subscriptionResult.success) {
        return Result<List<EndpointInfo>>.error(subscriptionResult.error);
      }
      final Result<List<EndpointInfo>> result = await operation(client);
      if (!result.success) {
        return Result<List<EndpointInfo>>.error(result.error);
      }
      final List<EndpointInfo> endpoints = result.value ?? <EndpointInfo>[];
      for (final EndpointInfo endpoint in endpoints) {
        _syncOwnedEndpointMetadata(endpoint);
      }
      return Result<List<EndpointInfo>>.success(endpoints);
    });
  }

  /// Purpose: Connect this public facade through the native DogPawEntity
  /// bridge.
  ///
  /// Return value:
  /// - `Future<ConnectionResult>` containing a public `ConnectionHandle`.
  ///
  /// Requirements/Preconditions: None.
  ///
  /// Guarantees/Postconditions:
  /// - On success, this public facade is backed by a live native client and the
  ///   returned handle completes the native connection-start handle.
  ///
  /// Invariants:
  /// - No websocket connection is created for this connect path.
  Future<ConnectionResult> _connectViaNativeBridge() async {
    try {
      if (Platform.environment['DPE_FFI_TRACE'] == '1') {
        AppLogger.info(
          'DPE_FFI: _connectViaNativeBridge start entity=$_entityName '
              'serverUrl=$_serverUrl timeoutMs=${_timeout.inMilliseconds}',
          'DPE_FFI',
        );
      }
      _disconnecting = false;
      await _nativeClientDisposeFuture;
      _nativeEndpointNotificationsSubscribed = false;
      _nativeEndpointNotificationSubscriptionFuture = null;
      _layoutQuerySnapshotsSubscribed = false;
      _layoutQuerySnapshotSubscriptionFuture = null;
      _cachedLayoutStackSnapshot = null;
      _cachedLayoutQuerySnapshot = null;
      _cachedScopedLayoutViews.clear();
      _layoutQuerySnapshotError = null;
      _layoutQuerySnapshotReadyCompleter = null;
      _layoutQuerySnapshotCallbacks.clear();
      _scopedLayoutViewCallbacks.clear();

      final NativeDogPawEntityClient client = NativeDogPawEntityClient(
        _entityName,
        serverUrl: _serverUrl,
        timeout: _timeout,
      );
      client.setErrorCallback(_errorCallback);
      client.setDirectMessageCallback(_directMessageCallback);
      client.setCommandCallback(_handleIncomingCommand);
      client.setPresetRequestCallback(_presetRequestCallback);
      _nativeClient = client;

      final Result<bool> connectResult = await client.connect();
      if (!connectResult.success) {
        _nativeClient = null;
        _nativeClientDisposeFuture = client.dispose();
        await _nativeClientDisposeFuture;
        return ConnectionResult.error(
            'Failed to create entity: ${connectResult.error}');
      }

      final handle =
          ConnectionHandle((ConnectionReadyMessageType messageType) async {
        final NativeDogPawEntityClient? currentClient = _nativeClient;
        if (currentClient == null) {
          return;
        }
        await currentClient.completeConnectionStart(
          messageType: _mapNativeReadyMessageType(messageType),
        );
      });
      return ConnectionResult.success(handle);
    } catch (e) {
      final NativeDogPawEntityClient? client = _nativeClient;
      _nativeClient = null;
      _nativeEndpointNotificationsSubscribed = false;
      _nativeEndpointNotificationSubscriptionFuture = null;
      _layoutQuerySnapshotsSubscribed = false;
      _layoutQuerySnapshotSubscriptionFuture = null;
      _cachedLayoutStackSnapshot = null;
      _cachedLayoutQuerySnapshot = null;
      _cachedScopedLayoutViews.clear();
      _layoutQuerySnapshotError = null;
      _layoutQuerySnapshotReadyCompleter = null;
      _layoutQuerySnapshotCallbacks.clear();
      _scopedLayoutViewCallbacks.clear();
      if (client != null) {
        _nativeClientDisposeFuture = client.dispose();
        await _nativeClientDisposeFuture;
      }
      if (_errorCallback != null) {
        _errorCallback!('Connection failed: $e');
      }
      return ConnectionResult.error('Connection failed: $e');
    }
  }

  /// Purpose: Disconnect this public facade from the native DogPawEntity
  /// bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions: None.
  ///
  /// Guarantees/Postconditions:
  /// - The active native client is disconnected and scheduled for disposal.
  /// - Public connection state is reset so a later reconnect can create a new
  ///   native client.
  ///
  /// Invariants:
  /// - Calling repeatedly remains safe through the existing `_disconnecting`
  ///   guard.
  void _disconnectViaNativeBridge() {
    if (_disconnecting) {
      AppLogger.debug(
          'DogPawEntity: disconnect() called but already disconnecting/disconnected, skipping');
      return;
    }
    _disconnecting = true;
    _nativeEndpointNotificationsSubscribed = false;
    _nativeEndpointNotificationSubscriptionFuture = null;
    _layoutQuerySnapshotsSubscribed = false;
    _layoutQuerySnapshotSubscriptionFuture = null;
    _cachedLayoutStackSnapshot = null;
    _cachedLayoutQuerySnapshot = null;
    _cachedScopedLayoutViews.clear();
    _layoutQuerySnapshotError = null;
    _layoutQuerySnapshotReadyCompleter = null;
    _layoutQuerySnapshotCallbacks.clear();
    _scopedLayoutViewCallbacks.clear();

    final NativeDogPawEntityClient? client = _nativeClient;
    _nativeClient = null;
    if (client != null) {
      client.disconnect();
      _nativeClientDisposeFuture = client.dispose();
      unawaited(_nativeClientDisposeFuture);
    }

    _disconnecting = false;
  }

  //=========================================================================
  // LIFECYCLE MANAGEMENT
  //=========================================================================

  /// Connect to the Epiphany server
  ///
  /// Returns a ConnectionResult containing a handle that must be managed.
  /// The handle will automatically send the ready message when it goes out
  /// of scope (via finalizer), or you can explicitly call handle.complete().
  ///
  /// IMPORTANT: Store the handle in a variable, otherwise it will immediately
  /// send the ready message. See ConnectionHandle documentation for usage patterns.
  ///
  /// Example usage:
  /// ```dart
  /// final result = await dogPaw.connect();
  /// if (!result.success) {
  ///   print('Connection failed: ${result.error}');
  ///   return;
  /// }
  ///
  /// final handle = result.handle!;
  ///
  /// // Do initialization work...
  /// await setupEndpoints();
  ///
  /// // Explicitly complete when ready
  /// await handle.complete();
  /// ```
  Future<ConnectionResult> connect() async {
    return _connectViaNativeBridge();
  }

  /// Disconnect from the Epiphany server
  void disconnect() {
    _disconnectViaNativeBridge();
  }

  /// Check if currently connected
  bool isConnected() {
    return _nativeClient?.isConnected ?? false;
  }

  /// Get the entity name
  String getEntityName() => _entityName;

  /// Set error callback
  void setErrorCallback(Function(String) callback) {
    _errorCallback = callback;
    _nativeClient?.setErrorCallback(callback);
  }

  /// Set direct message callback
  ///
  /// The callback receives:
  /// - [senderEntity]: The entity name of the sender (a string)
  /// - [content]: The message content as a Map
  void setDirectMessageCallback(
      Function(String senderEntity, Map<String, dynamic> content) callback) {
    _directMessageCallback = callback;
    _nativeClient?.setDirectMessageCallback(callback);
  }

  /// Set command callback for handling incoming commands from other entities.
  ///
  /// The callback receives:
  ///   - senderEntity: The entity name of the sender
  ///   - command: The command name (e.g., 'load_swag', 'set_mute')
  ///   - params: Command parameters object
  ///   - requestId: Correlation ID - use with sendCommandResponse
  ///
  /// The callback is responsible for calling sendCommandResponse to acknowledge
  /// the command and report success/failure.
  void setCommandCallback(
      Function(String senderEntity, String command, Map<String, dynamic> params,
              String commandId)
          callback) {
    _commandCallback = callback;
    _nativeClient?.setCommandCallback(_handleIncomingCommand);
  }

  /// Purpose: Register one manual retained-state query responder for an owned
  /// endpoint.
  ///
  /// Parameters:
  /// - [endpointName]: owned endpoint name whose retained-state queries should
  ///   use [callback].
  /// - [callback]: synchronous responder that receives the live local endpoint
  ///   wrapper and returns the snapshot to send.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [endpointName] identifies a local endpoint when the callback is expected
  ///   to run.
  ///
  /// Guarantees/Postconditions:
  /// - Future retained-state queries for [endpointName] use [callback] before
  ///   the automatic mirrored-state responder.
  ///
  /// Invariants:
  /// - Registration is scoped to this `DogPawEntity` instance only.
  void registerEndpointRetainedStateQueryCallback(
    String endpointName,
    EndpointRetainedStateSnapshot Function(LocalEndpoint endpoint) callback,
  ) {
    _endpointRetainedStateQueryCallbacks[endpointName] = callback;
  }

  /// Purpose: Remove one manual retained-state query responder.
  ///
  /// Parameters:
  /// - [endpointName]: endpoint name previously registered with
  ///   [registerEndpointRetainedStateQueryCallback].
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Future retained-state queries for [endpointName] fall back to the
  ///   automatic mirrored-state responder.
  ///
  /// Invariants:
  /// - Removing one callback does not affect any other endpoint.
  void clearEndpointRetainedStateQueryCallback(String endpointName) {
    _endpointRetainedStateQueryCallbacks.remove(endpointName);
  }

  /// Purpose: Answer one incoming internal retained-state query or forward the
  /// command to the user callback when it is not internal.
  ///
  /// Parameters:
  /// - [senderEntity]: entity that sent the command.
  /// - [command]: command name delivered by the native bridge.
  /// - [params]: command payload.
  /// - [commandId]: response correlation id.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Internal retained-state queries receive one command response when
  ///   possible.
  /// - Other commands are forwarded unchanged to the user callback, if any.
  ///
  /// Invariants:
  /// - Transport details for retained-state queries stay hidden from callers of
  ///   the public query API.
  void _handleIncomingCommand(
    String senderEntity,
    String command,
    Map<String, dynamic> params,
    String commandId,
  ) {
    if (command == _internalRetainedStateQueryCommand) {
      final String endpointName =
          params[_retainedStateQueryEndpointNameField] as String? ?? '';
      final LocalEndpoint? endpoint = _myEndpoints[endpointName];
      final EndpointRetainedStateSnapshot snapshot;
      if (endpoint == null) {
        snapshot = const EndpointRetainedStateSnapshot(hasState: false);
      } else {
        final responder = _endpointRetainedStateQueryCallbacks[endpointName];
        snapshot = responder != null
            ? responder(endpoint)
            : _requireNativeClient().queryLocalEndpointRetainedState(endpointName);
      }
      sendCommandResponse(
        senderEntity,
        commandId,
        success: true,
        result: snapshot.toJson(),
      );
      return;
    }

    _commandCallback?.call(senderEntity, command, params, commandId);
  }

  /// Set preset request callback
  ///
  /// The callback receives:
  ///   - serverRequestId: Unique identifier for this request
  ///   - content: Preset request data (includes requestType, presetName, etc.)
  ///
  /// The callback should return Future<bool>:
  ///   - true: Preset load is complete, send success response immediately
  ///   - false: Preset load is deferred, will call completePresetRequest() later
  /// NOTE: The return value does NOT indicate whether the preset request was handled successfully.
  ///       If the preset fails to load but the server should continue immediately, return true.
  ///       Only return false if the server should wait before assuming the preset load operation is done.
  ///
  /// Usage patterns:
  ///
  /// Synchronous (auto-wrapped in Future):
  /// ```dart
  /// dogPaw.setPresetRequestCallback((requestId, content) {
  ///   doSyncWork();
  ///   return true;
  /// });
  /// ```
  ///
  /// Asynchronous (await work, message processing pauses):
  /// ```dart
  /// dogPaw.setPresetRequestCallback((requestId, content) async {
  ///   await loadFromDatabase();
  ///   return true;
  /// });
  /// ```
  ///
  /// Fire-and-forget (for very long operations):
  /// ```dart
  /// dogPaw.setPresetRequestCallback((requestId, content) {
  ///   _startLongTask(requestId);
  ///   return false; // Manual completion later
  /// });
  /// ```
  void setPresetRequestCallback(
      Future<bool> Function(
              String serverRequestId, Map<String, dynamic> content)
          callback) {
    _presetRequestCallback = callback;
    _nativeClient?.setPresetRequestCallback(callback);
  }

  /// Register callback for IndexSpec changes on an endpoint
  ///
  /// When a connected output endpoint changes its IndexSpec (e.g., number of voices,
  /// grid dimensions), this callback will be invoked with the connection name and new IndexSpec.
  void registerIndexSpecChangeCallback(String endpointName,
      Function(String connectionName, IndexSpec newIndexSpec) callback) {
    _indexSpecChangeCallbacks[endpointName] = callback;
  }

  //=========================================================================
  // INTERNAL NOTIFICATION HANDLING
  //=========================================================================

  void _handleEndpointNotification(dynamic message) {
    // AppLogger.debug('DogPawEntity: Handling endpoint notification');
    try {
      if (message is! Map<String, dynamic>) return;

      final type = message[JsonFields.NOTIFICATION_TYPE];

      // Handle Endpoint CRUD
      if (type == 'create' || type == 'update') {
        if (message.containsKey(JsonFields.ENDPOINT)) {
          final dynamic endpointJson = message[JsonFields.ENDPOINT];
          if (endpointJson is Map<String, dynamic>) {
            _syncOwnedEndpointMetadata(EndpointInfo.fromJson(endpointJson));
          }
        }
      } else if (type == 'delete') {
        // Try to find name in endpoint object or at top level
        String? name;
        if (message.containsKey(JsonFields.ENDPOINT)) {
          final epJson = message[JsonFields.ENDPOINT];
          if (epJson is Map) {
            name = epJson[JsonFields.NAME];
          }
        }
        if (name == null && message.containsKey(JsonFields.NAME)) {
          name = message[JsonFields.NAME];
        }

        if (name != null) {
          _myEndpoints.remove(name);
        }
      }

      // Handle Connections
      if (type == 'endpoint_connection_added' ||
          type == 'endpoint_connection_updated') {
        // AppLogger.debug('DogPawEntity: Handling endpoint connection added/updated notification');
        // Constants not exposed, hardcoding match
        if (message.containsKey(JsonFields.CONNECTION)) {
          final connData = message[JsonFields.CONNECTION];

          // Extract local endpoint info to find which endpoint this connection belongs to
          // The message itself contains the local endpoint spec/ref at top level if it's a targeted notification
          final localName = message[JsonFields.NAME]; // DataItemRef fields

          if (connData is Map<String, dynamic>) {
            final connectionName = connData[JsonFields.NAME] as String?;

            if (connectionName != null) {
              // If we know the local endpoint, update it
              if (localName != null && _myEndpoints.containsKey(localName)) {
                final endpoint = _myEndpoints[localName]!;
                final dynamic targetJson = connData[JsonFields.TARGET];
                DataItemRef? peerEndpointRef;
                if (targetJson is Map<String, dynamic>) {
                  try {
                    peerEndpointRef = DataItemRef.fromJson(targetJson);
                  } catch (_) {}
                }
                if (peerEndpointRef != null) {
                  endpoint.dispatchConnectionAddedEvent(
                    LocalEndpointConnectionAddedEvent(
                      connectionName: connectionName,
                      peerEndpointRef: peerEndpointRef,
                    ),
                  );
                }
              }
            }
          }
        }
      } else if (type == 'endpoint_connection_removed') {
        // Handle removal if needed
        final connData = message[JsonFields.CONNECTION];
        final localName = message[JsonFields.NAME];
        if (connData is Map<String, dynamic> && localName != null) {
          final connectionName = connData[JsonFields.NAME] as String?;
          if (connectionName != null && _myEndpoints.containsKey(localName)) {
            final LocalEndpoint endpoint = _myEndpoints[localName]!;
            final dynamic targetJson = connData[JsonFields.TARGET];
            if (targetJson is Map<String, dynamic>) {
              try {
                endpoint.dispatchConnectionRemovedEvent(
                  LocalEndpointConnectionRemovedEvent(
                    connectionName: connectionName,
                    peerEndpointRef: DataItemRef.fromJson(targetJson),
                  ),
                );
              } catch (_) {}
            }
          }
        }
      } else if (type == 'endpoint_index_spec_changed') {
        // Handle IndexSpec change notification
        final localName = message[JsonFields.NAME];
        final connData = message[JsonFields.CONNECTION];

        if (localName != null && connData is Map<String, dynamic>) {
          final connectionName = connData[JsonFields.NAME] as String?;
          final indexSpecJson = connData[JsonFields.INDEX_SPEC];

          if (connectionName != null && indexSpecJson is Map<String, dynamic>) {
            try {
              final newIndexSpec = IndexSpec.fromJson(indexSpecJson);
              final dynamic targetJson = connData[JsonFields.TARGET];

              AppLogger.info(
                  'DogPawEntity: Handling IndexSpec change for endpoint: $localName, connection: $connectionName');

              if (_myEndpoints.containsKey(localName)) {
                final endpoint = _myEndpoints[localName]!;
                if (targetJson is Map<String, dynamic>) {
                  try {
                    endpoint.dispatchConnectionIndexSpecChangedEvent(
                      LocalEndpointConnectionIndexSpecChangedEvent(
                        connectionName: connectionName,
                        peerEndpointRef: DataItemRef.fromJson(targetJson),
                        newIndexSpec: newIndexSpec,
                      ),
                    );
                  } catch (_) {}
                }
              }

              // Invoke registered callback if any
              final callback = _indexSpecChangeCallbacks[localName];
              if (callback != null) {
                AppLogger.info(
                    'DogPawEntity: Invoking IndexSpec change callback for endpoint: $localName, connection: $connectionName');
                callback(connectionName, newIndexSpec);
              }
            } catch (e) {
              AppLogger.debug('Error parsing IndexSpec from notification: $e');
            }
          }
        }
      } else if (type == 'stateful_input_action') {
        final String? localName = message[JsonFields.NAME] as String?;
        final dynamic connectionData = message[JsonFields.CONNECTION];
        if (localName == null ||
            connectionData is! Map<String, dynamic> ||
            !_myEndpoints.containsKey(localName)) {
          return;
        }

        final LocalEndpoint endpoint = _myEndpoints[localName]!;
        final EndpointSpec? effectiveSpec = endpoint.spec ?? endpoint.resolved;
        if (effectiveSpec == null) {
          return;
        }

        final String connectionName =
            connectionData[JsonFields.NAME] as String? ?? '';
        final dynamic targetJson = connectionData[JsonFields.TARGET];
        final dynamic actionJson = connectionData[JsonFields.ACTION_PAYLOAD];
        if (connectionName.isEmpty ||
            targetJson is! Map<String, dynamic> ||
            actionJson is! Map<String, dynamic>) {
          return;
        }

        final EndpointSenderInfo senderInfo = EndpointSenderInfo(
          connectionName: connectionName,
          sourceEndpointRef: DataItemRef.fromJson(targetJson),
        );

        switch (effectiveSpec.dataType.baseType) {
          case DataType.float:
            final double? retainedValue =
                (connectionData[JsonFields.RETAINED_VALUE] as num?)?.toDouble();
            endpoint.dispatchStatefulFloatActionEvent(
              action: StatefulFloatAction.fromJson(actionJson),
              senderInfo: senderInfo,
              retainedValue: retainedValue,
            );
            break;
          case DataType.int_:
            final int? retainedValue =
                connectionData[JsonFields.RETAINED_VALUE] as int?;
            endpoint.dispatchStatefulIntActionEvent(
              action: StatefulIntAction.fromJson(actionJson),
              senderInfo: senderInfo,
              retainedValue: retainedValue,
            );
            break;
          case DataType.toggle:
            final bool? retainedValue =
                connectionData[JsonFields.RETAINED_VALUE] as bool?;
            endpoint.dispatchStatefulToggleActionEvent(
              action: StatefulToggleAction.fromJson(actionJson),
              senderInfo: senderInfo,
              retainedValue: retainedValue,
            );
            break;
          case DataType.enum_:
            final int? retainedValue =
                connectionData[JsonFields.RETAINED_VALUE] as int?;
            endpoint.dispatchStatefulEnumActionEvent(
              action: StatefulEnumAction.fromJson(actionJson),
              senderInfo: senderInfo,
              retainedValue: retainedValue,
            );
            break;
          case DataType.color:
            final int? retainedValue =
                connectionData[JsonFields.RETAINED_VALUE] as int?;
            endpoint.dispatchStatefulColorActionEvent(
              action: StatefulColorAction.fromJson(actionJson),
              senderInfo: senderInfo,
              retainedValue: retainedValue,
            );
            break;
          default:
            break;
        }
      }
    } catch (e) {
      AppLogger.debug('Error handling endpoint notification: $e');
    }
  }

  //=========================================================================
  // CORE API METHODS
  //=========================================================================

  Future<Result<bool>> log(String message) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.log(message),
    );
  }

  /// Start a suppressed log section on the Epiphany server
  ///
  /// When a suppressed log section is active, all log output on the Epiphany server
  /// is buffered instead of being printed. The buffered logs can be flushed (printed)
  /// or discarded when endLogSection() is called.
  ///
  /// This is useful for tests to suppress verbose output unless a failure occurs.
  /// Fails if already in a suppressed log section.
  ///
  /// [sectionTitle] - Optional title for the log section (logged immediately, not suppressed)
  Future<Result<bool>> startLogSection([String sectionTitle = '']) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.startLogSection(sectionTitle),
    );
  }

  /// Flush buffered logs without ending the log section
  ///
  /// Prints all currently buffered logs but continues buffering.
  /// Useful for debugging mid-test or for periodic log dumps.
  ///
  /// Fails if not currently in a suppressed log section.
  Future<Result<bool>> flushLogSection() async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.flushLogSection(),
    );
  }

  /// End a suppressed log section on the Epiphany server
  ///
  /// Ends log buffering on the server. Use flush=true when a test fails to see
  /// the logs that were captured during the test. Use flush=false (default)
  /// when a test passes to discard the verbose output.
  ///
  /// Fails if not currently in a suppressed log section.
  ///
  /// [flush] - If true, print all buffered logs; if false (default), discard them
  Future<Result<bool>> endLogSection([bool flush = false]) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.endLogSection(flush),
    );
  }

  Future<Result<bool>> sendDirectMessage(
      String targetEntity, Map<String, dynamic> content) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.sendDirectMessage(targetEntity, content),
    );
  }

  /// Send a command to another entity and wait for a response.
  ///
  /// This sends a structured command to the target entity and waits for the
  /// native bridge to report accepted/completed/error status back to Dart.
  ///
  /// [targetEntity] - Target entity name
  /// [command] - Command name (snake_case by convention)
  /// [params] - Optional command parameters (defaults to empty map)
  /// [timeout] - Timeout duration (default 5 seconds)
  /// [waitForCompletion] - If true (default), wait for completed/error status.
  ///                       If false, fire-and-forget (returns immediately after server ack).
  /// [onAccepted] - Optional callback for "accepted" responses (blocking mode only).
  ///                Receives the result payload from the accepted message.
  /// [deliveryPolicy] - Optional server-side delivery behavior controlling
  ///                    launch-if-missing and wait-for-ready routing.
  ///
  /// Returns a CommandResponseResult with success flag, result payload, and error message.
  Future<CommandResponseResult> sendCommand(String targetEntity, String command,
      {Map<String, dynamic> params = const {},
      Duration timeout = const Duration(seconds: 5),
      bool waitForCompletion = true,
      OnAcceptedCallback? onAccepted,
      CommandDeliveryPolicy? deliveryPolicy}) async {
    try {
      return await _requireNativeClient().sendCommand(
        targetEntity,
        command,
        params: params,
        timeout: timeout,
        waitForCompletion: waitForCompletion,
        onAccepted: onAccepted,
        deliveryPolicy: deliveryPolicy,
      );
    } catch (e) {
      return CommandResponseResult.errorResult('Command error: $e');
    }
  }

  /// Purpose: Query one endpoint's retained-state snapshot through DogPawEntity
  /// without exposing the internal command transport.
  ///
  /// Parameters:
  /// - [name]: endpoint name to query.
  /// - [namespaceSelector]: specific owner namespace for the endpoint.
  /// - [timeout]: maximum time to wait for a remote response.
  ///
  /// Return value:
  /// - `Future<Result<EndpointRetainedStateSnapshot>>` describing the current
  ///   retained state, if any.
  ///
  /// Requirements/Preconditions:
  /// - [namespaceSelector] must resolve to one specific entity.
  ///
  /// Guarantees/Postconditions:
  /// - On success, callers receive one typed snapshot rather than raw command
  ///   payload JSON.
  ///
  /// Invariants:
  /// - The query itself does not mutate endpoint metadata or connection state.
  Future<Result<EndpointRetainedStateSnapshot>> queryEndpointRetainedState(
    String name, {
    required NamespaceSelector namespaceSelector,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    NamespaceSelector resolvedSelector = namespaceSelector;
    if (namespaceSelector.isCurrentEntity) {
      resolvedSelector = NamespaceSelector.specificEntity(_entityName);
    }
    if (!resolvedSelector.isSpecificEntity || resolvedSelector.sourceEntity == null) {
      return Result<EndpointRetainedStateSnapshot>.error(
        'Retained-state query requires a specific entity namespace',
      );
    }

    if (resolvedSelector.sourceEntity == _entityName) {
      final LocalEndpoint? endpoint = _myEndpoints[name];
      if (endpoint == null) {
        return Result<EndpointRetainedStateSnapshot>.success(
          const EndpointRetainedStateSnapshot(hasState: false),
        );
      }
      final responder = _endpointRetainedStateQueryCallbacks[name];
      final EndpointRetainedStateSnapshot snapshot = responder != null
          ? responder(endpoint)
          : _requireNativeClient().queryLocalEndpointRetainedState(name);
      return Result<EndpointRetainedStateSnapshot>.success(snapshot);
    }

    final CommandResponseResult commandResult = await sendCommand(
      resolvedSelector.sourceEntity!,
      _internalRetainedStateQueryCommand,
      params: <String, dynamic>{_retainedStateQueryEndpointNameField: name},
      timeout: timeout,
      deliveryPolicy: const CommandDeliveryPolicy(waitForReady: false),
    );
    if (!commandResult.success) {
      return Result<EndpointRetainedStateSnapshot>.error(commandResult.error);
    }
    return Result<EndpointRetainedStateSnapshot>.success(
      EndpointRetainedStateSnapshot.fromJson(commandResult.result),
    );
  }

  /// Send a response to a received command.
  ///
  /// [targetEntity] - The entity that sent the command (from senderEntity)
  /// [commandId] - The commandId from the incoming command (for correlation)
  /// [success] - Whether the command completed successfully
  /// [result] - Optional result payload (for successful commands)
  /// [errorMessage] - Optional error message (for failed commands)
  ///
  /// Note: This is fire-and-forget. The server forwards the response to the original
  /// command sender but does not acknowledge receipt.
  void sendCommandResponse(String targetEntity, String commandId,
      {bool success = true,
      Map<String, dynamic> result = const {},
      String errorMessage = ''}) {
    _nativeClient?.sendCommandResponse(
      targetEntity,
      commandId,
      success: success,
      result: result,
      errorMessage: errorMessage,
    );
  }

  /// Send an "accepted" acknowledgment for a command that will complete asynchronously.
  ///
  /// Use this for commands that take significant time. The sender will receive an
  /// "accepted" status, then await the eventual "completed" or "error" response.
  ///
  /// Note: This is fire-and-forget. The server forwards the message but does not acknowledge receipt.
  void sendCommandAccepted(String targetEntity, String commandId) {
    _nativeClient?.sendCommandAccepted(targetEntity, commandId);
  }

  /// Subscribe to entity connect/disconnect notifications from Epiphany.
  ///
  /// [watchEntityName] if null or empty, receive all entities; otherwise only that name.
  /// [sendImmediately] when true, server sends entity_connected for each currently connected entity matching the filter.
  Future<Result<bool>> subscribeToEntityLifecycle(
    void Function(String notificationType, String entityName) callback, {
    String? watchEntityName,
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.subscribeToEntityLifecycle(
        callback,
        watchEntityName: watchEntityName,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Unsubscribe entity lifecycle for the same filter used in [subscribeToEntityLifecycle].
  Future<Result<bool>> unsubscribeFromEntityLifecycle(
      {String? watchEntityName}) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.unsubscribeFromEntityLifecycle(
        watchEntityName: watchEntityName,
      ),
    );
  }

  Future<Result<Map<String, dynamic>>> getSystemInfo() async {
    return _runNativeCrudOperation<Map<String, dynamic>>(
      (NativeDogPawEntityClient client) => client.getSystemInfo(),
    );
  }

  /// Request launcher-owned app metadata from Epiphany.
  ///
  /// Purpose:
  /// Provides UI apps with available app metadata through the DPE request
  /// channel instead of requiring apps to know runtime file paths.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - `Future<Result<Map<String, dynamic>>>` shaped as `{ "apps": [...] }` on
  ///   success.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, returns the current launcher-owned app list.
  ///
  /// Invariants:
  /// - App metadata ownership stays with EpiphanyLauncher; this method does not
  ///   inspect local filesystem layout.
  Future<Result<Map<String, dynamic>>> listApps() async {
    return _runNativeCrudOperation<Map<String, dynamic>>(
      (NativeDogPawEntityClient client) => client.listApps(),
    );
  }

  /// Request the currently running runtime entities from Epiphany.
  ///
  /// Purpose:
  /// Provides the current runtime entity snapshot, including runtime entity
  /// names and stable app/template names, for UI flows such as target pickers.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - `Future<Result<Map<String, dynamic>>>` shaped as `{ "entities": [...] }`
  ///   on success.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, returns the current runtime entity list.
  ///
  /// Invariants:
  /// - Runtime entity metadata ownership stays with EpiphanyLauncher.
  Future<Result<Map<String, dynamic>>> listRunningEntities() async {
    return _runNativeCrudOperation<Map<String, dynamic>>(
      (NativeDogPawEntityClient client) => client.listRunningEntities(),
    );
  }

  /// Get the installed read-mostly assets directory for this entity.
  ///
  /// Purpose: Provides the stable app install asset location without requiring
  /// apps to know the underlying XDG or emulator-specific filesystem layout.
  ///
  /// Parameters: none.
  /// Return value: path like `<appRoot>/<entityName>/assets`.
  /// Requirements/Preconditions: this entity has a non-empty resolved name.
  /// Guarantees/Postconditions: the directory exists after this call.
  /// Invariants: this directory is for installed/read-mostly inputs, not
  /// writable user state.
  String getInstalledAssetsDirectory() {
    final dataRoot = _resolveDataRoot();
    final appRoot = _resolveAppRoot(dataRoot);
    return _ensureDirectory('$appRoot/$_entityName/assets');
  }

  /// Get the persistent app data directory (shared across instances).
  ///
  /// Purpose: Returns the writable location for user-created content that should
  /// survive app updates and server restarts, such as presets, saved
  /// configurations, and mappings.
  ///
  /// Parameters: none.
  /// Return value: path like `<dataRoot>/appFiles/<entityName>`, or an
  /// emulator-scoped equivalent.
  /// Requirements/Preconditions: this entity has a non-empty resolved name.
  /// Guarantees/Postconditions: the directory exists after this call.
  /// Invariants: installed assets and persistent app files remain separate.
  String getPersistentAppDataDirectory() {
    final dataRoot = _resolveDataRoot();
    final emulatorName = _resolveEmulatorName();
    if (emulatorName != null) {
      return _ensureDirectory(
          '$dataRoot/emulators/$emulatorName/appFiles/$_entityName');
    }
    return _ensureDirectory('$dataRoot/appFiles/$_entityName');
  }

  /// Get the persistent app cache directory (shared across instances).
  ///
  /// Purpose: Returns the writable location for evictable derived artifacts that
  /// can be rebuilt from installed assets or persistent app files.
  ///
  /// Parameters: none.
  /// Return value: path like `<cacheRoot>/appCache/<entityName>`, or an
  /// emulator-scoped equivalent.
  /// Requirements/Preconditions: this entity has a non-empty resolved name.
  /// Guarantees/Postconditions: the directory exists after this call.
  /// Invariants: durable app data and evictable app cache remain separate.
  String getPersistentAppCacheDirectory() {
    final cacheRoot = _resolveCacheRoot();
    final emulatorName = _resolveEmulatorName();
    if (emulatorName != null) {
      return _ensureDirectory(
          '$cacheRoot/emulators/$emulatorName/appCache/$_entityName');
    }
    return _ensureDirectory('$cacheRoot/appCache/$_entityName');
  }

  /// Get the instance-scoped working directory.
  ///
  /// Purpose: Returns the writable persistent location scoped to the current
  /// Epiphany instance for operational state such as runtime databases.
  ///
  /// Parameters: none.
  /// Return value: path like `<dataRoot>/instances/<instance>/appFiles/<entityName>`.
  /// Requirements/Preconditions: this entity has a non-empty resolved name.
  /// Guarantees/Postconditions: the directory exists after this call.
  /// Invariants: data here is scoped to `EPIPHANY_INSTANCE`.
  String getInstanceFileDirectory() {
    final dataRoot = _resolveDataRoot();
    final instance = _env('EPIPHANY_INSTANCE') ?? 'default';
    return _ensureDirectory(
        '$dataRoot/instances/$instance/appFiles/$_entityName');
  }

  /// Get the instance-scoped temporary/runtime directory.
  ///
  /// Purpose: Returns a writable runtime location for scratch data that should
  /// not be treated as durable user content.
  ///
  /// Parameters: none.
  /// Return value: path like `<runtimeRoot>/<instance>/appFiles/<entityName>`.
  /// Requirements/Preconditions: this entity has a non-empty resolved name.
  /// Guarantees/Postconditions: the directory exists after this call.
  /// Invariants: data here may disappear when the user session or runtime ends.
  String getInstanceTempDirectory() {
    final runtimeRoot = _resolveRuntimeRoot();
    final instance = _env('EPIPHANY_INSTANCE') ?? 'default';
    return _ensureDirectory('$runtimeRoot/$instance/appFiles/$_entityName');
  }

  /// Save global state preset
  ///
  /// Sends a request to Epiphany to save the current system state as a preset.
  /// This broadcasts to all entities to save their state and captures system information.
  ///
  /// Input: presetName - name of the preset (no slashes or ..)
  /// Output: Result<bool> - success or error message
  Future<Result<bool>> saveGlobalState(String presetName) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.saveGlobalState(presetName),
    );
  }

  /// Load global state preset
  ///
  /// Sends a request to Epiphany to load a previously saved system state preset.
  /// This loads the preset file and restores system state including launching apps,
  /// positioning windows, and restoring entity state.
  ///
  /// Input: presetName - name of the preset to load
  /// Output: Result<bool> - success or error message
  Future<Result<bool>> loadGlobalState(String presetName) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.loadGlobalState(presetName),
    );
  }

  /// Complete a deferred preset request
  ///
  /// Call this method after your app has finished loading preset data if your
  /// preset callback returned false to defer the response.
  ///
  /// This allows apps with async preset loading (database queries, file I/O, etc.)
  /// to properly signal when they're ready without blocking or timing out.
  ///
  /// Input:
  ///   - serverRequestId: The unique ID passed to your preset callback
  ///   - success: Whether the preset load succeeded (default: true)
  ///   - errorMessage: Error description if success is false
  ///
  /// Output: Future<void>
  ///
  /// Example usage:
  /// ```dart
  /// dogPaw.setPresetRequestCallback((serverRequestId, content) {
  ///   // Start async load
  ///   _loadPresetAsync(serverRequestId, content);
  ///   return false; // Defer response
  /// });
  ///
  /// Future<void> _loadPresetAsync(String requestId, Map<String, dynamic> content) async {
  ///   try {
  ///     await loadDataFromDatabase();
  ///     await dogPaw.completePresetRequest(requestId, success: true);
  ///   } catch (e) {
  ///     await dogPaw.completePresetRequest(requestId, success: false, errorMessage: e.toString());
  ///   }
  /// }
  /// ```
  Future<void> completePresetRequest(String serverRequestId,
      {bool success = true, String errorMessage = ''}) async {
    await _requireNativeClient().completePresetRequest(
      serverRequestId,
      success: success,
      errorMessage: errorMessage,
    );
  }

  //=========================================================================
  // CRUD HELPER TEMPLATE (Simulated via specialized methods)
  //=========================================================================

  // ENDPOINTS

  Future<Result<List<EndpointInfo>>> searchEndpoints(
      SearchCriteria criteria) async {
    return _runNativeEndpointList(
      (NativeDogPawEntityClient client) => client.searchEndpoints(criteria),
    );
  }

  Future<Result<LocalEndpoint>> createEndpoint(EndpointInfo endpoint) async {
    return _runNativeEndpointMutation(
      (NativeDogPawEntityClient client) => client.createEndpoint(endpoint),
    );
  }

  /// Purpose: Create one stateful input and its matched committed-state output.
  ///
  /// Parameters:
  /// - [endpoint]: Input endpoint whose `statefulInput.matchedOutput` declares
  ///   the public output metadata to create alongside it.
  ///
  /// Return value:
  /// - `Future<Result<StatefulEndpointPair>>` with both live owned endpoints on
  ///   success.
  ///
  /// Requirements/Preconditions:
  /// - [endpoint.spec] describes an input `MESSAGE_QUEUE` endpoint.
  /// - [endpoint.spec.statefulInput.matchedOutput] exists and has a non-empty
  ///   name.
  ///
  /// Guarantees/Postconditions:
  /// - On success, both endpoints exist and native auto-reduced input handling
  ///   publishes normalized committed-state updates through the matched output.
  /// - On failure after the input was created, this helper attempts to delete
  ///   the partially created input before returning the error.
  ///
  /// Invariants:
  /// - This helper leaves the existing single-endpoint CRUD APIs unchanged.
  Future<Result<StatefulEndpointPair>> createStatefulInputWithMatchedOutput(
    EndpointInfo endpoint,
  ) async {
    final EndpointSpec? spec = endpoint.spec;
    if (spec == null) {
      return Result<StatefulEndpointPair>.error(
        'Stateful input helper requires endpoint metadata',
      );
    }
    final EndpointStatefulInputSpec? statefulInput = spec.statefulInput;
    final MatchedStateOutputSpec? matchedOutputSpec =
        statefulInput?.matchedOutput;

    if (spec.direction != EndpointDirection.input) {
      return Result<StatefulEndpointPair>.error(
        'Stateful input helper requires an input endpoint',
      );
    }
    if (spec.category != EndpointCategory.messageQueue) {
      return Result<StatefulEndpointPair>.error(
        'Stateful input helper currently supports only message-queue inputs',
      );
    }
    if (statefulInput == null || matchedOutputSpec == null) {
      return Result<StatefulEndpointPair>.error(
        'Stateful input helper requires statefulInput.matchedOutput configuration',
      );
    }
    if (matchedOutputSpec.name.isEmpty) {
      return Result<StatefulEndpointPair>.error(
        'Stateful input helper requires a non-empty matched output name',
      );
    }
    if (statefulInput.consumptionMode ==
        StatefulInputConsumptionMode.callbackOnly) {
      return Result<StatefulEndpointPair>.error(
        'Stateful input helper requires retained state so callback-only consumption is not supported',
      );
    }
    switch (spec.dataType.baseType) {
      case DataType.float:
      case DataType.int_:
      case DataType.toggle:
      case DataType.enum_:
      case DataType.color:
        break;
      default:
        return Result<StatefulEndpointPair>.error(
          'Stateful input helper currently supports FLOAT, INT, TOGGLE, ENUM, and COLOR only',
        );
    }

    final Result<LocalEndpoint> inputResult = await createEndpoint(endpoint);
    if (!inputResult.success || inputResult.value == null) {
      return Result<StatefulEndpointPair>.error(inputResult.error);
    }

    final Result<LocalEndpoint> matchedOutputResult = await createEndpoint(
      EndpointInfo(
        name: matchedOutputSpec.name,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: spec.dataType,
          displayName: matchedOutputSpec.displayName,
          description: matchedOutputSpec.description,
          category: spec.category,
          messageQueuePayloadContract: spec.messageQueuePayloadContract,
          flags: matchedOutputSpec.flags,
          groupKey: matchedOutputSpec.groupKey,
        ),
      ),
    );
    if (!matchedOutputResult.success || matchedOutputResult.value == null) {
      final Result<bool> rollbackResult = await deleteEndpoint(endpoint.name);
      String error = matchedOutputResult.error;
      if (!rollbackResult.success) {
        error = '$error; rollback failed: ${rollbackResult.error}';
      }
      return Result<StatefulEndpointPair>.error(error);
    }

    return Result<StatefulEndpointPair>.success(
      StatefulEndpointPair(
        input: inputResult.value!,
        matchedOutput: matchedOutputResult.value!,
      ),
    );
  }

  Future<Result<LocalEndpoint>> updateEndpoint(EndpointInfo endpoint) async {
    return _runNativeEndpointMutation(
      (NativeDogPawEntityClient client) => client.updateEndpoint(endpoint),
    );
  }

  Future<Result<LocalEndpoint>> setEndpoint(EndpointInfo endpoint) async {
    return _runNativeEndpointMutation(
      (NativeDogPawEntityClient client) => client.setEndpoint(endpoint),
    );
  }

  Future<Result<EndpointInfo?>> readEndpoint(String name,
      {NamespaceSelector? namespaceSelector,
      bool includeResolved = false,
      bool includeSpec = false}) async {
    return _runNativeEndpointRead(
      (NativeDogPawEntityClient client) => client.readEndpoint(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> deleteEndpoint(String name) async {
    return _runNativeCrudOperation<bool>(
        (NativeDogPawEntityClient client) async {
      final Result<bool> result = await client.deleteEndpoint(name);
      if (result.success) {
        _myEndpoints.remove(name);
      }
      return result;
    });
  }

  // Subscriptions for Endpoints
  Future<Result<bool>> subscribeToEndpoints(
    Function(String, DataItemRef, dynamic) callback, {
    String? endpointName,
    NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.subscribeToEndpoints(
        (String notificationType, DataItemRef dataItemRef, EndpointInfo data) {
          callback(notificationType, dataItemRef, data);
        },
        endpointName: endpointName,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  // CONNECTIONS

  Future<Result<bool>> createConnectionRequest(
      ConnectionRequest connectionRequest) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.createConnectionRequest(connectionRequest),
    );
  }

  Future<Result<bool>> setConnectionRequest(
      ConnectionRequest connectionRequest) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.setConnectionRequest(connectionRequest),
    );
  }

  Future<Result<bool>> updateConnectionRequest(
      ConnectionRequest connectionRequest) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.updateConnectionRequest(connectionRequest),
    );
  }

  Future<Result<ConnectionRequest?>> readConnectionRequest(String name,
      {NamespaceSelector? namespaceSelector,
      bool includeResolved = false,
      bool includeSpec = false}) async {
    return _runNativeCrudOperation<ConnectionRequest?>(
      (NativeDogPawEntityClient client) => client.readConnectionRequest(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> deleteConnectionRequest(String name,
      {NamespaceSelector? namespaceSelector}) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.deleteConnectionRequest(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<List<ConnectionRequest>>> listConnectionRequests(
      {NamespaceSelector? namespaceSelector,
      bool includeResolved = false,
      bool includeSpec = false}) async {
    return _runNativeCrudOperation<List<ConnectionRequest>>(
      (NativeDogPawEntityClient client) => client.listConnectionRequests(
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> createFollowRequest(FollowRequest followRequest) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.createFollowRequest(followRequest),
    );
  }

  Future<Result<bool>> setFollowRequest(FollowRequest followRequest) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.setFollowRequest(followRequest),
    );
  }

  Future<Result<bool>> updateFollowRequest(FollowRequest followRequest) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.updateFollowRequest(followRequest),
    );
  }

  Future<Result<FollowRequest?>> readFollowRequest(String name,
      {NamespaceSelector? namespaceSelector,
      bool includeResolved = false,
      bool includeSpec = false}) async {
    return _runNativeCrudOperation<FollowRequest?>(
      (NativeDogPawEntityClient client) => client.readFollowRequest(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> deleteFollowRequest(String name,
      {NamespaceSelector? namespaceSelector}) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.deleteFollowRequest(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<List<FollowRequest>>> listFollowRequests(
      {NamespaceSelector? namespaceSelector,
      bool includeResolved = false,
      bool includeSpec = false}) async {
    return _runNativeCrudOperation<List<FollowRequest>>(
      (NativeDogPawEntityClient client) => client.listFollowRequests(
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<Connection?>> readConnection(String name,
      {bool includeResolved = false, bool includeSpec = false}) async {
    return _runNativeCrudOperation<Connection?>(
      (NativeDogPawEntityClient client) => client.readConnection(
        name,
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<List<Connection>>> listConnections(
      {bool includeResolved = false, bool includeSpec = false}) async {
    return _runNativeCrudOperation<List<Connection>>(
      (NativeDogPawEntityClient client) => client.listConnections(
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  // THEMES

  Future<Result<bool>> createTheme(Theme theme) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.createTheme(theme),
    );
  }

  Future<Result<bool>> setTheme(Theme theme) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.setTheme(theme),
    );
  }

  Future<Result<bool>> updateTheme(Theme theme) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.updateTheme(theme),
    );
  }

  Future<Result<Theme?>> readTheme(
    String name, {
    NamespaceSelector? namespaceSelector,
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    return _runNativeCrudOperation<Theme?>(
      (NativeDogPawEntityClient client) => client.readTheme(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> deleteTheme(String name,
      {NamespaceSelector? namespaceSelector}) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.deleteTheme(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<bool>> setCurrentTheme(String name,
      {NamespaceSelector? namespaceSelector}) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.setCurrentTheme(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<Theme?>> readCurrentTheme() async {
    return _runNativeCrudOperation<Theme?>(
      (NativeDogPawEntityClient client) => client.readCurrentTheme(),
    );
  }

  Future<Result<List<Theme>>> listThemes({
    NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    return _runNativeCrudOperation<List<Theme>>(
      (NativeDogPawEntityClient client) => client.listThemes(
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> subscribeToThemes(
    Function(String, DataItemRef, dynamic) callback, {
    String? themeName,
    NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.subscribeToThemes(
        (String notificationType, DataItemRef dataItemRef, Theme theme) {
          callback(notificationType, dataItemRef, theme);
        },
        themeName: themeName,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  Future<Result<bool>> unsubscribeFromThemes({
    String? themeName,
    NamespaceSelector? namespaceSelector,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.unsubscribeFromThemes(
        themeName: themeName,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<bool>> subscribeToCurrentTheme(
    Function(String, DataItemRef, dynamic) callback, {
    bool includeResolved = true,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.subscribeToCurrentTheme(
        (String notificationType, DataItemRef dataItemRef, Theme theme) {
          callback(notificationType, dataItemRef, theme);
        },
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  Future<Result<bool>> unsubscribeFromCurrentTheme() async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.unsubscribeFromCurrentTheme(),
    );
  }

  // SCALES

  Future<Result<bool>> createScale(Scale scale) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.createScale(scale),
    );
  }

  Future<Result<bool>> setScale(Scale scale) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.setScale(scale),
    );
  }

  Future<Result<bool>> updateScale(Scale scale) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.updateScale(scale),
    );
  }

  Future<Result<Scale?>> readScale(
    String name, {
    NamespaceSelector? namespaceSelector,
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    return _runNativeCrudOperation<Scale?>(
      (NativeDogPawEntityClient client) => client.readScale(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> deleteScale(String name,
      {NamespaceSelector? namespaceSelector}) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.deleteScale(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<bool>> setCurrentScale(String name,
      {NamespaceSelector? namespaceSelector}) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.setCurrentScale(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<Scale?>> readCurrentScale() async {
    return _runNativeCrudOperation<Scale?>(
      (NativeDogPawEntityClient client) => client.readCurrentScale(),
    );
  }

  Future<Result<List<Scale>>> listScales({
    NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    return _runNativeCrudOperation<List<Scale>>(
      (NativeDogPawEntityClient client) => client.listScales(
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> subscribeToScales(
    Function(String, DataItemRef, dynamic) callback, {
    String? scaleName,
    NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.subscribeToScales(
        (String notificationType, DataItemRef dataItemRef, Scale scale) {
          callback(notificationType, dataItemRef, scale);
        },
        scaleName: scaleName,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  Future<Result<bool>> unsubscribeFromScales({
    String? scaleName,
    NamespaceSelector? namespaceSelector,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.unsubscribeFromScales(
        scaleName: scaleName,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<bool>> subscribeToCurrentScale(
    Function(String, DataItemRef, dynamic) callback, {
    bool includeResolved = true,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.subscribeToCurrentScale(
        (String notificationType, DataItemRef dataItemRef, Scale scale) {
          callback(notificationType, dataItemRef, scale);
        },
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  Future<Result<bool>> unsubscribeFromCurrentScale() async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.unsubscribeFromCurrentScale(),
    );
  }

  // LAYOUTS

  /// Create a new layout and optionally add it to the persistent layout stack.
  ///
  /// [autoSuffix]: when true, requests automatic name disambiguation. Not yet
  /// routed through the native bridge (grep FFI_BRIDGE_PORT_PENDING).
  /// [addToLayoutStack]: when true (default), adds the created layout as a
  /// new top-of-stack entry after the create request succeeds.
  Future<Result<bool>> createLayout(
    Layout layout, {
    bool autoSuffix = false,
    bool addToLayoutStack = true,
  }) async {
    if (autoSuffix) {
      return Result.error(
        'FFI_BRIDGE_PORT_PENDING: createLayout(autoSuffix: true) not yet routed through native client',
      );
    }

    final Result<bool> createResult = await _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.createLayout(layout),
    );
    if (!createResult.success || !addToLayoutStack) {
      return createResult;
    }

    final Result<String> addResult = await addLayoutStackEntry(
      DataItemRef.byName(
        name: layout.name,
        namespaceSelector: layout.namespaceSelector,
      ),
    );
    if (!addResult.success) {
      return Result<bool>.error(addResult.error);
    }
    return Result<bool>.success(true);
  }

  Future<Result<bool>> setLayout(Layout layout) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.setLayout(layout),
    );
  }

  Future<Result<bool>> updateLayout(Layout layout) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.updateLayout(layout),
    );
  }

  Future<Result<Layout?>> readLayout(
    String name, {
    NamespaceSelector? namespaceSelector,
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    return _runNativeCrudOperation<Layout?>(
      (NativeDogPawEntityClient client) => client.readLayout(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> deleteLayout(String name,
      {NamespaceSelector? namespaceSelector}) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.deleteLayout(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<List<Layout>>> listLayouts({
    NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    return _runNativeCrudOperation<List<Layout>>(
      (NativeDogPawEntityClient client) => client.listLayouts(
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> subscribeToLayouts(
    Function(String, DataItemRef, dynamic) callback, {
    String? layoutName,
    NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.subscribeToLayouts(
        (String notificationType, DataItemRef dataItemRef, Layout layout) {
          callback(notificationType, dataItemRef, layout);
        },
        layoutName: layoutName,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  Future<Result<bool>> unsubscribeFromLayouts({
    String? layoutName,
    NamespaceSelector? namespaceSelector,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.unsubscribeFromLayouts(
        layoutName: layoutName,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  // LAYOUT STACK

  /// Add an entry to the persistent layout stack.
  ///
  /// [index]: optional insert position. When null, the entry is appended to
  /// the top of the stack.
  Future<Result<String>> addLayoutStackEntry(
    DataItemRef layoutRef, {
    int? index,
  }) async {
    return _runNativeCrudOperation<String>(
      (NativeDogPawEntityClient client) =>
          client.addLayoutStackEntry(layoutRef, index: index),
    );
  }

  /// Remove an entry from the persistent layout stack by id.
  Future<Result<bool>> removeLayoutStackEntry(String entryId) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.removeLayoutStackEntry(entryId),
    );
  }

  /// Move an entry within the persistent layout stack.
  Future<Result<bool>> moveLayoutStackEntry(
    String entryId,
    int newIndex,
  ) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) =>
          client.moveLayoutStackEntry(entryId, newIndex),
    );
  }

  /// Read the current layout stack snapshot.
  Future<Result<LayoutStackSnapshot>> readLayoutStack({
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    return _runNativeCrudOperation<LayoutStackSnapshot>(
      (NativeDogPawEntityClient client) => client.readLayoutStack(
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  /// Subscribe to layout-stack updates. The callback receives the notification
  /// type, the DataItemRef (name: `layout_stack`), and the latest snapshot.
  Future<Result<bool>> subscribeToLayoutStack(
    Function(String notificationType, DataItemRef ref,
            LayoutStackSnapshot snapshot)
        callback, {
    bool includeResolved = true,
    bool includeSpec = false,
    bool sendImmediately = false,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.subscribeToLayoutStack(
        callback,
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Unsubscribe from layout-stack updates.
  Future<Result<bool>> unsubscribeFromLayoutStack() async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.unsubscribeFromLayoutStack(),
    );
  }

  /// Purpose: Return the latest cached layout-query snapshot for this entity.
  ///
  /// Parameters: None.
  ///
  /// Return value:
  /// - `Future<Result<LayoutQuerySnapshot>>` containing the latest cached
  ///   higher-level query snapshot.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the internal raw layout-stack subscription has been lazily
  ///   initialized and the cache is ready.
  ///
  /// Invariants:
  /// - This does not mutate the server-side layout stack.
  Future<Result<LayoutQuerySnapshot>> getLayoutQuerySnapshot() async {
    return _runNativeCrudOperation<LayoutQuerySnapshot>(
        (NativeDogPawEntityClient client) async {
      final Result<bool> cacheResult = await _ensureLayoutQuerySnapshotCache();
      if (!cacheResult.success) {
        return Result<LayoutQuerySnapshot>.error(cacheResult.error);
      }

      final LayoutQuerySnapshot? snapshot = _cachedLayoutQuerySnapshot;
      if (snapshot == null) {
        return Result<LayoutQuerySnapshot>.error(
          'Layout query cache is not initialized.',
        );
      }
      return Result<LayoutQuerySnapshot>.success(snapshot);
    });
  }

  /// Purpose: Return the latest scoped layout view for one consumer policy.
  ///
  /// Parameters:
  /// - [policy]: selection policy describing which shared/targeted view to
  ///   build.
  ///
  /// Return value:
  /// - `Future<Result<ScopedLayoutView>>` containing the latest effective view.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the internal raw layout-stack subscription has been lazily
  ///   initialized and the view cache is ready for [policy].
  ///
  /// Invariants:
  /// - This does not mutate the server-side layout stack.
  Future<Result<ScopedLayoutView>> getScopedLayoutView(
    LayoutViewPolicy policy,
  ) async {
    return _runNativeCrudOperation<ScopedLayoutView>(
      (NativeDogPawEntityClient client) async {
        return _buildScopedLayoutView(policy);
      },
    );
  }

  /// Purpose: Register one helper-level callback for cached layout-query snapshots.
  ///
  /// Parameters:
  /// - [callback]: local callback receiving the latest cached query snapshot.
  /// - [sendImmediately]: whether to invoke [callback] immediately with the
  ///   current cached snapshot after initialization succeeds.
  ///
  /// Return value:
  /// - `Future<Result<bool>>` indicating whether the local callback was registered.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, future layout-stack notifications update the cache before
  ///   [callback] is invoked.
  ///
  /// Invariants:
  /// - Unsubscribing helper callbacks does not clear the internal cache.
  Future<Result<bool>> subscribeToLayoutQuerySnapshots(
    void Function(LayoutQuerySnapshot snapshot) callback, {
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
        (NativeDogPawEntityClient client) async {
      final Result<bool> cacheResult = await _ensureLayoutQuerySnapshotCache();
      if (!cacheResult.success) {
        return Result<bool>.error(cacheResult.error);
      }

      _layoutQuerySnapshotCallbacks.add(callback);
      final LayoutQuerySnapshot? snapshot = _cachedLayoutQuerySnapshot;
      if (sendImmediately && snapshot != null) {
        callback(snapshot);
      }
      return Result<bool>.success(true);
    });
  }

  /// Purpose: Register one helper-level callback for scoped layout views.
  ///
  /// Parameters:
  /// - [callback]: local callback receiving the latest scoped layout view.
  /// - [policy]: selection policy for the scoped view.
  /// - [sendImmediately]: whether to invoke [callback] immediately with the
  ///   current cached view after initialization succeeds.
  ///
  /// Return value:
  /// - `Future<Result<bool>>` indicating whether the local callback was registered.
  ///
  /// Requirements/Preconditions:
  /// - [connect] has already succeeded and [disconnect] has not completed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, future layout-stack notifications update the raw cache before
  ///   [callback] is invoked.
  ///
  /// Invariants:
  /// - Unsubscribing helper callbacks does not clear the internal cache.
  Future<Result<bool>> subscribeToScopedLayoutView(
    void Function(ScopedLayoutView view) callback, {
    required LayoutViewPolicy policy,
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) async {
        final Result<bool> cacheResult = await _ensureLayoutQuerySnapshotCache();
        if (!cacheResult.success) {
          return Result<bool>.error(cacheResult.error);
        }

        _scopedLayoutViewCallbacks.add(
          _ScopedLayoutViewSubscription(policy: policy, callback: callback),
        );
        if (sendImmediately) {
          final Result<ScopedLayoutView> viewResult =
              await _buildScopedLayoutView(policy);
          if (!viewResult.success || viewResult.value == null) {
            return Result<bool>.error(viewResult.error);
          }
          callback(viewResult.value!);
        }
        return Result<bool>.success(true);
      },
    );
  }

  /// Purpose: Remove all helper-level layout-query snapshot callbacks.
  ///
  /// Parameters: None.
  ///
  /// Return value:
  /// - `Future<Result<bool>>` indicating whether the local callback list was cleared.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - No helper-level query callbacks remain registered after success.
  ///
  /// Invariants:
  /// - The internal raw layout-stack subscription stays active once initialized.
  Future<Result<bool>> unsubscribeFromLayoutQuerySnapshots() async {
    return _runNativeCrudOperation<bool>(
        (NativeDogPawEntityClient client) async {
      _layoutQuerySnapshotCallbacks.clear();
      return Result<bool>.success(true);
    });
  }

  // KV STORE

  Future<Result<bool>> createKV(KV kv) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.createKV(kv),
    );
  }

  Future<Result<bool>> setKV(KV kv) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.setKV(kv),
    );
  }

  Future<Result<bool>> updateKV(KV kv) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.updateKV(kv),
    );
  }

  Future<Result<KV?>> readKV(
    String name, {
    NamespaceSelector? namespaceSelector,
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    return _runNativeCrudOperation<KV?>(
      (NativeDogPawEntityClient client) => client.readKV(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> deleteKV(String name,
      {NamespaceSelector? namespaceSelector}) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.deleteKV(
        name,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  Future<Result<List<KV>>> listKVs({
    NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    return _runNativeCrudOperation<List<KV>>(
      (NativeDogPawEntityClient client) => client.listKVs(
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
      ),
    );
  }

  Future<Result<bool>> subscribeToKV(
    Function(String, DataItemRef, dynamic) callback, {
    String? key,
    NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.subscribeToKV(
        (String notificationType, DataItemRef dataItemRef, KV kv) {
          callback(notificationType, dataItemRef, kv);
        },
        key: key,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  Future<Result<bool>> unsubscribeFromKV({
    String? key,
    NamespaceSelector? namespaceSelector,
  }) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.unsubscribeFromKV(
        key: key,
        namespaceSelector:
            namespaceSelector ?? const NamespaceSelector.currentEntity(),
      ),
    );
  }

  /// Launch an application template and receive its runtime entity name.
  ///
  /// Singleton apps return their stable manifest name; multi-instance apps
  /// return the generated per-instance runtime entity name. Optional
  /// [launchMetadata] is forwarded to the launched app via its launch
  /// metadata file.
  Future<Result<String>> launchApp(
    String appName, {
    Map<String, dynamic>? launchMetadata,
  }) async {
    return _runNativeCrudOperation<String>(
      (NativeDogPawEntityClient client) =>
          client.launchApp(appName, launchMetadata: launchMetadata),
    );
  }

  Future<Result<bool>> stopApp(String appName) async {
    return _runNativeCrudOperation<bool>(
      (NativeDogPawEntityClient client) => client.stopApp(appName),
    );
  }

  Future<Result<String>> killAllApps() async {
    return _runNativeCrudOperation<String>(
      (NativeDogPawEntityClient client) => client.killAllApps(),
    );
  }
}
