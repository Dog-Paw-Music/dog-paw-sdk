import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import '../app_logger.dart';
import '../connection.dart';
import '../data_types.dart';
import '../endpoint.dart';
import '../json_constants.dart';
import '../kv.dart';
import '../layout.dart';
import '../layout_stack.dart';
import '../namespace_selector.dart';
import '../result.dart';
import '../scale.dart';
import '../search_criteria.dart';
import '../subscription_utils.dart';
import '../theme.dart';
import '../data_item_ref.dart';
import 'native_bridge.dart';

/// Purpose: Native-side ready message types for the connection-start handle.
///
/// Parameters: None.
///
/// Return value: Enum values used when completing the native connection-start
/// handle.
///
/// Requirements/Preconditions: None.
///
/// Guarantees/Postconditions: Enum indexes remain aligned with the native
/// bridge's `ready_message_type` contract where `0` is ready and `1` is error.
///
/// Invariants: The ordering of enum values must remain stable across the FFI
/// boundary.
enum NativeConnectionReadyMessageType {
  ready,
  error,
}

/// Purpose: Track one native-backed entity lifecycle callback registration.
///
/// Parameters:
/// - [watchEntityName]: optional `String` entity filter, or `null` for all
///   entities.
/// - [callback]: local Dart callback invoked for matching lifecycle events.
///
/// Return value: Immutable subscription record used only for local dispatch.
///
/// Requirements/Preconditions:
/// - [watchEntityName], when present, should already be normalized so empty
///   strings become `null`.
///
/// Guarantees/Postconditions:
/// - The stored callback and filter remain available until removed from the
///   owning list.
///
/// Invariants:
/// - This record does not perform native I/O on its own.
class _NativeEntityLifecycleSubscription {
  const _NativeEntityLifecycleSubscription(
    this.watchEntityName,
    this.callback,
  );

  final String? watchEntityName;
  final void Function(String notificationType, String entityName) callback;
}

/// Purpose: Native runtime shape for one realized local-endpoint connection.
///
/// Parameters:
/// - [indexSpec]: `IndexSpec` currently used for this connection's payloads.
/// - [payloadSize]: serialized payload size in bytes for this connection.
///
/// Return value: Immutable helper record for synchronous runtime polling.
///
/// Requirements/Preconditions:
/// - [payloadSize] is zero or positive.
///
/// Guarantees/Postconditions:
/// - Instances are pure value objects with no native ownership.
///
/// Invariants:
/// - Shape metadata is only as fresh as the native query that produced it.
class _NativeConnectionShape {
  const _NativeConnectionShape({
    required this.indexSpec,
    required this.payloadSize,
  });

  final IndexSpec indexSpec;
  final int payloadSize;
}

/// Purpose: Internal Dart wrapper around the phase-2 native DogPawEntity bridge.
///
/// Parameters:
/// - [entityName]: `String` entity name used by the native DogPawEntity.
/// - [serverUrl]: `String` websocket URL forwarded to the native DogPawEntity.
/// - [timeout]: `Duration` default native request timeout.
///
/// Return value: Constructed wrapper ready to launch native-backed requests.
///
/// Requirements/Preconditions:
/// - [entityName] must be non-empty.
/// - [timeout] must be zero or positive.
///
/// Guarantees/Postconditions:
/// - A native handle is allocated and an internal `ReceivePort` is registered
///   for async request-result and error envelopes.
///
/// Invariants:
/// - Each pending Dart completer is keyed by a bridge-local request id.
/// - Async native responses always arrive through the internal `ReceivePort`.
class NativeDogPawEntityClient {
  /// Purpose: Create a native-backed DogPawEntity wrapper and event channel.
  ///
  /// Parameters:
  /// - [entityName]: `String` entity name for the native DogPawEntity.
  /// - [serverUrl]: `String` websocket URL for the native DogPawEntity.
  /// - [timeout]: `Duration` default request timeout for native requests.
  ///
  /// Return value: Constructed [NativeDogPawEntityClient].
  ///
  /// Requirements/Preconditions:
  /// - [entityName] must be non-empty.
  /// - [timeout] must be zero or positive.
  ///
  /// Guarantees/Postconditions:
  /// - The native bridge handle exists and is registered to post events to this
  ///   instance's `ReceivePort`.
  ///
  /// Invariants:
  /// - The native handle remains valid until [dispose] is called.
  NativeDogPawEntityClient(
    String entityName, {
    String serverUrl = 'ws://localhost:8080',
    Duration timeout = const Duration(seconds: 5),
  })  : _entityName = entityName,
        _bridge = DogPawBridge(),
        _receivePort = ReceivePort(),
        _nativeHandle = DogPawBridge().dpeCreateManaged(
          entityName,
          serverUrl: serverUrl,
          timeoutMs: timeout.inMilliseconds,
        ) {
    if (_nativeHandle == nullptr) {
      throw StateError('Failed to create native DogPawEntity bridge handle.');
    }

    final bool eventPortRegistered = _bridge.dpeSetEventPortManaged(
      _nativeHandle,
      _receivePort.sendPort.nativePort,
    );
    if (!eventPortRegistered) {
      _bridge.dpeDestroyManaged(_nativeHandle);
      throw StateError('Failed to register native DogPawEntity event port.');
    }

    _eventSubscription = _receivePort.listen(_handleNativeEvent);

    if (Platform.environment['DPE_FFI_TRACE'] == '1') {
      AppLogger.info(
        'DPE_FFI: NativeDogPawEntityClient ready entity=$entityName '
            'serverUrl=$serverUrl timeoutMs=${timeout.inMilliseconds} '
            'eventPort=${_receivePort.sendPort.nativePort}',
        'DPE_FFI',
      );
    }
  }

  final String _entityName;
  final DogPawBridge _bridge;
  final ReceivePort _receivePort;
  final Pointer<Void> _nativeHandle;
  late final StreamSubscription<dynamic> _eventSubscription;

  bool _disposed = false;
  int _requestCounter = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests =
      <int, Completer<Map<String, dynamic>>>{};
  final List<CallbackInfo> _savedCallbacks = <CallbackInfo>[];
  final List<_NativeEntityLifecycleSubscription> _entityLifecycleSubscriptions =
      <_NativeEntityLifecycleSubscription>[];
  void Function(Map<String, dynamic> message)? _endpointNotificationCallback;
  void Function(Map<String, dynamic> message)? _layoutStackNotificationCallback;
  Function(String error)? _errorCallback;
  Function(String senderEntity, Map<String, dynamic> content)?
      _directMessageCallback;
  Function(String senderEntity, String command, Map<String, dynamic> params,
      String commandId)? _commandCallback;
  Future<bool> Function(String serverRequestId, Map<String, dynamic> content)?
      _presetRequestCallback;
  void Function(Map<String, dynamic> event)? _debugProbeEventCallback;
  final Map<int, OnAcceptedCallback> _pendingCommandAcceptedCallbacks =
      <int, OnAcceptedCallback>{};

  /// Purpose: Synchronous snapshot of the wrapped native connection state.
  ///
  /// Parameters: None.
  ///
  /// Return value: `bool` indicating whether the wrapped native entity currently
  /// reports itself as connected.
  ///
  /// Requirements/Preconditions: None.
  ///
  /// Guarantees/Postconditions:
  /// - Returns `false` after disposal.
  /// - Otherwise reflects the bridge's current native `isConnected()` state.
  ///
  /// Invariants:
  /// - The getter does not mutate wrapper state.
  bool get isConnected =>
      !_disposed && _bridge.dpeIsConnectedManaged(_nativeHandle);

  /// Purpose: Register one raw endpoint-notification callback for internal
  /// facade synchronization.
  ///
  /// Parameters:
  /// - [callback]: callback receiving the full native endpoint notification
  ///   payload, or `null` to clear it.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Later native endpoint subscription notifications invoke [callback]
  ///   best-effort before generic item extraction.
  ///
  /// Invariants:
  /// - Missing callbacks are ignored.
  void setEndpointNotificationCallback(
    void Function(Map<String, dynamic> message)? callback,
  ) {
    _endpointNotificationCallback = callback;
  }

  /// Purpose: Register one raw layout-stack notification callback for internal
  /// facade cache synchronization.
  ///
  /// Parameters:
  /// - [callback]: callback receiving the full native layout-stack
  ///   notification payload, or `null` to clear it.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Later native layout-stack subscription notifications invoke [callback]
  ///   best-effort before generic item extraction.
  ///
  /// Invariants:
  /// - Missing callbacks are ignored.
  void setLayoutStackNotificationCallback(
    void Function(Map<String, dynamic> message)? callback,
  ) {
    _layoutStackNotificationCallback = callback;
  }

  /// Purpose: Launch a native-backed connect request and await its result.
  ///
  /// Return value: `Future<Result<bool>>` indicating connect success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, [isConnected] becomes true and the native side stores a
  ///   pending connection-start handle until [completeConnectionStart] is
  ///   called.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the server response.
  Future<Result<bool>> connect() async {
    try {
      if (Platform.environment['DPE_FFI_TRACE'] == '1') {
        AppLogger.info(
          'DPE_FFI: connect() awaiting native result entity=$_entityName',
          'DPE_FFI',
        );
      }
      final Map<String, dynamic> response = await _invokeRequest(
        'connect',
        (int requestId) => _bridge.dpeConnectAsyncManaged(
          _nativeHandle,
          requestId,
        ),
      );
      if (response['success'] == true) {
        if (Platform.environment['DPE_FFI_TRACE'] == '1') {
          AppLogger.info(
            'DPE_FFI: connect() succeeded entity=$_entityName '
                'isConnected=$isConnected',
            'DPE_FFI',
          );
        }
        return Result<bool>.success(true);
      }
      final String err = response['error'] as String? ?? 'Connect failed';
      AppLogger.warning(
        'DPE_FFI: connect() failed entity=$_entityName error=$err',
        'DPE_FFI',
      );
      return Result<bool>.error(err);
    } catch (exception) {
      AppLogger.warning(
        'DPE_FFI: connect() threw entity=$_entityName exception=$exception',
        'DPE_FFI',
      );
      return Result<bool>.error(exception.toString());
    }
  }

  /// Purpose: Complete the pending native connection-start handle.
  ///
  /// Parameters:
  /// - [messageType]: [NativeConnectionReadyMessageType] determining whether the
  ///   native entity reports ready or error.
  ///
  /// Return value: `Future<void>` that completes once Dart has issued the
  /// native completion call.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - A successful [connect] call has already completed and has not yet had its
  ///   connection-start handle consumed.
  ///
  /// Guarantees/Postconditions:
  /// - The native pending connection-start handle is consumed exactly once on
  ///   success.
  ///
  /// Invariants:
  /// - This call itself is synchronous on the native side; it does not await a
  ///   server response.
  Future<void> completeConnectionStart({
    NativeConnectionReadyMessageType messageType =
        NativeConnectionReadyMessageType.ready,
  }) async {
    _ensureNotDisposed();
    final bool completed = _bridge.dpeCompleteConnectionStartManaged(
      _nativeHandle,
      messageType.index,
    );
    if (!completed) {
      throw StateError(
          'No pending native connection-start handle was available to complete.');
    }
  }

  /// Purpose: Disconnect the native-backed entity immediately.
  ///
  /// Parameters: None.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions: The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - The native entity disconnects and [isConnected] becomes false.
  ///
  /// Invariants:
  /// - This method does not dispose the wrapper itself.
  void disconnect() {
    _ensureNotDisposed();
    _bridge.dpeDisconnectManaged(_nativeHandle);
  }

  /// Purpose: Store the Dart callback that receives native async error events.
  ///
  /// Parameters:
  /// - [callback]: optional `Function(String)` invoked for each native error
  ///   envelope, or `null` to clear the callback.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Future native `error` envelopes are forwarded to [callback] when set.
  ///
  /// Invariants:
  /// - Setting this callback does not launch native work.
  void setErrorCallback(Function(String error)? callback) {
    _ensureNotDisposed();
    _errorCallback = callback;
  }

  /// Purpose: Store the Dart callback that receives native direct messages.
  ///
  /// Parameters:
  /// - [callback]: optional callback invoked with sender entity and message
  ///   content, or `null` to clear the callback.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Future native direct-message events are forwarded to [callback] when set.
  ///
  /// Invariants:
  /// - Setting this callback does not launch native work.
  void setDirectMessageCallback(
    Function(String senderEntity, Map<String, dynamic> content)? callback,
  ) {
    _ensureNotDisposed();
    _directMessageCallback = callback;
  }

  /// Purpose: Store the Dart callback that receives native incoming commands.
  ///
  /// Parameters:
  /// - [callback]: optional callback invoked with sender entity, command,
  ///   params, and command id, or `null` to clear the callback.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Future native incoming-command events are forwarded to [callback] when
  ///   set.
  ///
  /// Invariants:
  /// - Setting this callback does not launch native work.
  void setCommandCallback(
    Function(String senderEntity, String command, Map<String, dynamic> params,
            String commandId)?
        callback,
  ) {
    _ensureNotDisposed();
    _commandCallback = callback;
  }

  /// Purpose: Store the Dart callback that receives native preset requests.
  ///
  /// Parameters:
  /// - [callback]: optional async callback invoked with preset request id and
  ///   content, or `null` to restore the default auto-success behavior.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Future native preset-request events are forwarded to [callback] when set.
  /// - When [callback] is `null`, preset requests auto-complete successfully.
  ///
  /// Invariants:
  /// - Setting this callback does not launch native work.
  void setPresetRequestCallback(
    Future<bool> Function(String serverRequestId, Map<String, dynamic> content)?
        callback,
  ) {
    _ensureNotDisposed();
    _presetRequestCallback = callback;
  }

  /// Purpose: Store the Dart callback that receives synthetic bridge probe
  /// events.
  ///
  /// Parameters:
  /// - [callback]: optional callback invoked with the full debug-probe event
  ///   envelope, or `null` to clear it.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Future native `debugProbe` envelopes are forwarded to [callback] when
  ///   set.
  ///
  /// Invariants:
  /// - This test hook is for bridge integration probes only.
  void setDebugProbeEventCallback(
    void Function(Map<String, dynamic> event)? callback,
  ) {
    _ensureNotDisposed();
    _debugProbeEventCallback = callback;
  }

  /// Purpose: Normalize entity lifecycle filters for native requests and local
  /// matching.
  ///
  /// Parameters:
  /// - [watchEntityName]: optional `String` entity filter supplied by the
  ///   caller.
  ///
  /// Return value: Normalized entity filter, or `null` for the all-entities
  /// subscription.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Empty strings are normalized to `null`.
  ///
  /// Invariants:
  /// - This helper does not perform native I/O.
  String? _normalizeWatchEntityName(String? watchEntityName) {
    if (watchEntityName == null || watchEntityName.isEmpty) {
      return null;
    }
    return watchEntityName;
  }

  /// Purpose: Resolve wildcard/current namespace selectors for local callback
  /// matching.
  ///
  /// Parameters:
  /// - [selector]: `NamespaceSelector` originally provided by the caller.
  ///
  /// Return value: `NamespaceSelector?` normalized for subscription matching,
  /// or `null` when the selector should behave as a wildcard.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - `currentEntity` resolves to this wrapper's entity name.
  /// - `allEntities` resolves to `null` for wildcard matching.
  ///
  /// Invariants:
  /// - This helper does not perform native I/O.
  NamespaceSelector? _resolveNamespaceForKey(NamespaceSelector selector) {
    switch (selector.type) {
      case NamespaceSelectorType.global:
        return const NamespaceSelector.global();
      case NamespaceSelectorType.specificEntity:
        return selector;
      case NamespaceSelectorType.currentEntity:
        return NamespaceSelector.specificEntity(_entityName);
      case NamespaceSelectorType.allEntities:
        return null;
    }
  }

  /// Purpose: Register one ordinary item subscription through the native bridge.
  ///
  /// Parameters:
  /// - [methodName]: `String` diagnostic method name.
  /// - [notificationTopic]: `String` topic used to match posted notifications.
  /// - [callback]: local Dart callback wrapper that receives decoded items.
  /// - [launchRequest]: native launcher invoked with the allocated request id.
  /// - [name]: optional `String` item name to watch, or `null` for all items.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  /// - [responseField]: `String` JSON field that carries the changed item.
  ///
  /// Return value: `Future<Result<bool>>` indicating subscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - [launchRequest] must launch the corresponding native subscribe request.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching notifications are dispatched to [callback] until
  ///   the subscription is removed.
  /// - On failure, the provisional callback registration is removed.
  ///
  /// Invariants:
  /// - Callback matching uses the same `SubscriptionKey` semantics as the
  ///   websocket-backed Dart client.
  Future<Result<bool>> _subscribeToItem(
    String methodName,
    String notificationTopic,
    Function(String, DataItemRef, dynamic) callback, {
    String? name,
    NamespaceSelector? namespaceSelector,
    required String responseField,
    required bool Function(int requestId) launchRequest,
  }) async {
    final NamespaceSelector effectiveNamespace =
        namespaceSelector ?? const NamespaceSelector.currentEntity();
    final NamespaceSelector? resolvedNamespace =
        _resolveNamespaceForKey(effectiveNamespace);
    final SubscriptionKey subscriptionKey = SubscriptionKey(
      notificationTopic,
      namespaceSelector: resolvedNamespace,
      name: name,
    );
    final CallbackInfo callbackInfo = CallbackInfo(
      key: subscriptionKey,
      valueJsonKey: responseField,
      handler: callback,
    );
    _savedCallbacks.add(callbackInfo);

    final Result<bool> result =
        await _runBooleanRequest(methodName, launchRequest);
    if (!result.success) {
      _savedCallbacks.remove(callbackInfo);
    }
    return result;
  }

  /// Purpose: Remove one ordinary item subscription through the native bridge.
  ///
  /// Parameters:
  /// - [methodName]: `String` diagnostic method name.
  /// - [notificationTopic]: `String` topic used to match stored callbacks.
  /// - [name]: optional `String` item name to stop watching, or `null` for all
  ///   items.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  /// - [launchRequest]: native launcher invoked with the allocated request id.
  ///
  /// Return value: `Future<Result<bool>>` indicating unsubscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - [launchRequest] must launch the corresponding native unsubscribe
  ///   request.
  ///
  /// Guarantees/Postconditions:
  /// - Matching local callbacks are removed before the unsubscribe request is
  ///   launched.
  ///
  /// Invariants:
  /// - Callback matching uses the same `SubscriptionKey` semantics as the
  ///   websocket-backed Dart client.
  Future<Result<bool>> _unsubscribeFromItem(
    String methodName,
    String notificationTopic, {
    String? name,
    NamespaceSelector? namespaceSelector,
    required bool Function(int requestId) launchRequest,
  }) async {
    final NamespaceSelector effectiveNamespace =
        namespaceSelector ?? const NamespaceSelector.currentEntity();
    final NamespaceSelector? resolvedNamespace =
        _resolveNamespaceForKey(effectiveNamespace);
    final SubscriptionKey subscriptionKey = SubscriptionKey(
      notificationTopic,
      namespaceSelector: resolvedNamespace,
      name: name,
    );
    _savedCallbacks.removeWhere(
      (CallbackInfo callbackInfo) => callbackInfo.matches(subscriptionKey),
    );
    return _runBooleanRequest(methodName, launchRequest);
  }

  /// Purpose: Register one current-item subscription through the native bridge.
  ///
  /// Parameters:
  /// - [methodName]: `String` diagnostic method name.
  /// - [notificationTopic]: `String` topic used to match posted notifications.
  /// - [callback]: local Dart callback wrapper that receives decoded items.
  /// - [responseField]: `String` JSON field that carries the changed item.
  /// - [launchRequest]: native launcher invoked with the allocated request id.
  ///
  /// Return value: `Future<Result<bool>>` indicating subscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - [launchRequest] must launch the corresponding native subscribe request.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching current-item notifications are dispatched to
  ///   [callback] until the subscription is removed.
  /// - On failure, the provisional callback registration is removed.
  ///
  /// Invariants:
  /// - Current subscriptions match by topic only, mirroring the websocket
  ///   client's wildcard behavior.
  Future<Result<bool>> _subscribeToCurrentItem(
    String methodName,
    String notificationTopic,
    Function(String, DataItemRef, dynamic) callback, {
    required String responseField,
    required bool Function(int requestId) launchRequest,
  }) async {
    final CallbackInfo callbackInfo = CallbackInfo(
      key: SubscriptionKey(notificationTopic),
      valueJsonKey: responseField,
      handler: callback,
    );
    _savedCallbacks.add(callbackInfo);

    final Result<bool> result =
        await _runBooleanRequest(methodName, launchRequest);
    if (!result.success) {
      _savedCallbacks.remove(callbackInfo);
    }
    return result;
  }

  /// Purpose: Remove one current-item subscription through the native bridge.
  ///
  /// Parameters:
  /// - [methodName]: `String` diagnostic method name.
  /// - [notificationTopic]: `String` topic used to match stored callbacks.
  /// - [launchRequest]: native launcher invoked with the allocated request id.
  ///
  /// Return value: `Future<Result<bool>>` indicating unsubscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - [launchRequest] must launch the corresponding native unsubscribe
  ///   request.
  ///
  /// Guarantees/Postconditions:
  /// - Matching local callbacks are removed before the unsubscribe request is
  ///   launched.
  ///
  /// Invariants:
  /// - Current subscriptions match by topic only, mirroring the websocket
  ///   client's wildcard behavior.
  Future<Result<bool>> _unsubscribeFromCurrentItem(
    String methodName,
    String notificationTopic, {
    required bool Function(int requestId) launchRequest,
  }) async {
    final SubscriptionKey subscriptionKey = SubscriptionKey(notificationTopic);
    _savedCallbacks.removeWhere(
      (CallbackInfo callbackInfo) => callbackInfo.matches(subscriptionKey),
    );
    return _runBooleanRequest(methodName, launchRequest);
  }

  /// Purpose: Subscribe to entity connect/disconnect notifications through the
  /// native bridge.
  ///
  /// Parameters:
  /// - [callback]: callback invoked for each matching entity lifecycle event.
  /// - [watchEntityName]: optional `String` entity filter, or `null` for all
  ///   entities.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching lifecycle notifications are dispatched to
  ///   [callback] until the subscription is removed.
  /// - On failure, the provisional callback registration is removed.
  ///
  /// Invariants:
  /// - Callback matching uses the same normalized watch-entity filter as the
  ///   native C++ client.
  Future<Result<bool>> subscribeToEntityLifecycle(
    void Function(String notificationType, String entityName) callback, {
    String? watchEntityName,
    bool sendImmediately = true,
  }) async {
    final String? normalizedWatch = _normalizeWatchEntityName(watchEntityName);
    final _NativeEntityLifecycleSubscription subscription =
        _NativeEntityLifecycleSubscription(normalizedWatch, callback);
    _entityLifecycleSubscriptions.add(subscription);

    final Result<bool> result = await _runBooleanRequest(
      'subscribeToEntityLifecycle',
      (int requestId) => _bridge.dpeSubscribeEntityLifecycleAsyncManaged(
        _nativeHandle,
        requestId,
        entityName: normalizedWatch,
        sendImmediately: sendImmediately,
      ),
    );
    if (!result.success) {
      _entityLifecycleSubscriptions.remove(subscription);
    }
    return result;
  }

  /// Purpose: Remove one entity lifecycle subscription through the native
  /// bridge.
  ///
  /// Parameters:
  /// - [watchEntityName]: optional `String` entity filter that must match the
  ///   original subscription.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - The first matching local lifecycle callback is removed before the native
  ///   unsubscribe request is launched, mirroring the C++ client behavior.
  ///
  /// Invariants:
  /// - `null` and empty-string filters both refer to the all-entities
  ///   subscription.
  Future<Result<bool>> unsubscribeFromEntityLifecycle({
    String? watchEntityName,
  }) async {
    final String? normalizedWatch = _normalizeWatchEntityName(watchEntityName);
    final int existingIndex = _entityLifecycleSubscriptions.indexWhere(
      (_NativeEntityLifecycleSubscription subscription) =>
          subscription.watchEntityName == normalizedWatch,
    );
    if (existingIndex != -1) {
      _entityLifecycleSubscriptions.removeAt(existingIndex);
    }

    return _runBooleanRequest(
      'unsubscribeFromEntityLifecycle',
      (int requestId) => _bridge.dpeUnsubscribeEntityLifecycleAsyncManaged(
        _nativeHandle,
        requestId,
        entityName: normalizedWatch,
      ),
    );
  }

  /// Purpose: Send one direct message through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [targetEntity]: `String` target entity name.
  /// - [content]: `Map<String, dynamic>` direct-message payload.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has routed the direct message request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> sendDirectMessage(
    String targetEntity,
    Map<String, dynamic> content,
  ) async {
    return _runBooleanRequest(
      'sendDirectMessage',
      (int requestId) => _bridge.dpeSendDirectMessageAsyncManaged(
        _nativeHandle,
        requestId,
        targetEntity,
        jsonEncode(content),
      ),
    );
  }

  /// Purpose: Send one command through the native DogPawEntity bridge and wait
  /// for the native result envelope.
  ///
  /// Parameters:
  /// - [targetEntity]: `String` target entity name.
  /// - [command]: `String` command name.
  /// - [params]: `Map<String, dynamic>` command parameters.
  /// - [timeout]: `Duration` native timeout for the command request.
  /// - [waitForCompletion]: whether to wait for completed/error rather than
  ///   routing success.
  /// - [onAccepted]: optional callback for accepted notifications while waiting
  ///   for completion.
  /// - [deliveryPolicy]: optional server-side delivery policy.
  ///
  /// Return value: `Future<CommandResponseResult>` describing the native command
  /// outcome.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - [timeout] is zero or positive.
  ///
  /// Guarantees/Postconditions:
  /// - On success, returns the final native command result.
  /// - When [waitForCompletion] is true, [onAccepted] may run before the final
  ///   result completes.
  ///
  /// Invariants:
  /// - Command in-flight state remains owned by the native C++ client.
  Future<CommandResponseResult> sendCommand(
    String targetEntity,
    String command, {
    Map<String, dynamic> params = const <String, dynamic>{},
    Duration timeout = const Duration(seconds: 5),
    bool waitForCompletion = true,
    OnAcceptedCallback? onAccepted,
    CommandDeliveryPolicy? deliveryPolicy,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'sendCommand',
        (int requestId) => _bridge.dpeSendCommandAsyncManaged(
          _nativeHandle,
          requestId,
          targetEntity,
          command,
          jsonEncode(params),
          timeoutMs: timeout.inMilliseconds,
          waitForCompletion: waitForCompletion,
          deliveryPolicyJson: deliveryPolicy != null
              ? jsonEncode(deliveryPolicy.toJson())
              : null,
        ),
        onRequestStarted: (int requestId) {
          if (waitForCompletion && onAccepted != null) {
            _pendingCommandAcceptedCallbacks[requestId] = onAccepted;
          }
        },
      );
      final Map<String, dynamic> resultPayload = Map<String, dynamic>.from(
        response[JsonFields.RESULT] as Map? ?? <String, dynamic>{},
      );
      if (response[JsonFields.SUCCESS] == true) {
        return CommandResponseResult.completed(resultPayload);
      }
      return CommandResponseResult.errorResult(
        response[JsonFields.ERROR] as String? ?? 'sendCommand failed',
        resultPayload,
      );
    } catch (exception) {
      return CommandResponseResult.errorResult(exception.toString());
    }
  }

  /// Purpose: Send one completed/error command response through the native
  /// bridge.
  ///
  /// Parameters:
  /// - [targetEntity]: `String` entity that originally sent the command.
  /// - [commandId]: `String` command correlation id.
  /// - [success]: whether the command completed successfully.
  /// - [result]: optional result payload object.
  /// - [errorMessage]: optional failure message.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - The wrapped native C++ client attempts to forward the response
  ///   immediately.
  ///
  /// Invariants:
  /// - This helper does not allocate a Dart async request id.
  void sendCommandResponse(
    String targetEntity,
    String commandId, {
    required bool success,
    Map<String, dynamic> result = const <String, dynamic>{},
    String errorMessage = '',
  }) {
    _ensureNotDisposed();
    _bridge.dpeSendCommandResponseManaged(
      _nativeHandle,
      targetEntity,
      commandId,
      success: success,
      resultJson: jsonEncode(result),
      errorMessage: errorMessage,
    );
  }

  /// Purpose: Send one accepted acknowledgement through the native bridge.
  ///
  /// Parameters:
  /// - [targetEntity]: `String` entity that originally sent the command.
  /// - [commandId]: `String` command correlation id.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - The wrapped native C++ client attempts to forward the accepted message
  ///   immediately.
  ///
  /// Invariants:
  /// - This helper does not allocate a Dart async request id.
  void sendCommandAccepted(String targetEntity, String commandId) {
    _ensureNotDisposed();
    _bridge.dpeSendCommandAcceptedManaged(
      _nativeHandle,
      targetEntity,
      commandId,
    );
  }

  /// Purpose: Complete one deferred preset request through the native bridge.
  ///
  /// Parameters:
  /// - [serverRequestId]: `String` preset request correlation id from Epiphany.
  /// - [success]: `bool` outcome flag.
  /// - [errorMessage]: `String` error text when [success] is false; may be
  ///   empty.
  ///
  /// Return value: `Future<void>` that completes after issuing the native call.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - The wrapped native C++ client attempts to forward the preset completion
  ///   immediately.
  ///
  /// Invariants:
  /// - This helper does not allocate a Dart async request id.
  Future<void> completePresetRequest(
    String serverRequestId, {
    bool success = true,
    String errorMessage = '',
  }) async {
    _ensureNotDisposed();
    _bridge.dpeCompletePresetRequestManaged(
      _nativeHandle,
      serverRequestId,
      success: success,
      errorMessage: errorMessage,
    );
  }

  /// Purpose: Launch the native dispatcher-order probe for bridge integration
  /// tests.
  ///
  /// Parameters: None.
  ///
  /// Return value:
  /// - `bool` indicating whether the native probe started successfully.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - A debug-probe callback should already be registered if the caller needs
  ///   to observe the emitted events.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native bridge will emit synthetic `debugProbe` events.
  ///
  /// Invariants:
  /// - This helper is reserved for bridge integration probes.
  bool runDebugDispatcherOrderProbe() {
    _ensureNotDisposed();
    return _bridge.dpeDebugRunDispatcherOrderProbeManaged(_nativeHandle);
  }

  /// Purpose: Launch the native shutdown-drain probe for bridge integration
  /// tests.
  ///
  /// Parameters: None.
  ///
  /// Return value:
  /// - `bool` indicating whether the native probe started successfully.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - A debug-probe callback should already be registered if the caller needs
  ///   to observe the emitted events.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native bridge runs its shutdown path before returning.
  ///
  /// Invariants:
  /// - This helper is reserved for bridge integration probes.
  bool runDebugShutdownDrainProbe() {
    _ensureNotDisposed();
    return _bridge.dpeDebugRunShutdownDrainProbeManaged(_nativeHandle);
  }

  /// Purpose: Save one global preset through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [presetName]: `String` preset name to save.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the save-global-state
  ///   request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> saveGlobalState(String presetName) async {
    return _runBooleanRequest(
      'saveGlobalState',
      (int requestId) => _bridge.dpeSaveGlobalStateAsyncManaged(
        _nativeHandle,
        requestId,
        presetName,
      ),
    );
  }

  /// Purpose: Load one global preset through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [presetName]: `String` preset name to load.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the load-global-state
  ///   request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> loadGlobalState(String presetName) async {
    return _runBooleanRequest(
      'loadGlobalState',
      (int requestId) => _bridge.dpeLoadGlobalStateAsyncManaged(
        _nativeHandle,
        requestId,
        presetName,
      ),
    );
  }

  /// Purpose: Send one utility log message through the native DogPawEntity
  /// bridge.
  ///
  /// Parameters:
  /// - [message]: `String` log text to forward to Epiphany.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, Epiphany has accepted the log request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> log(String message) async {
    return _runBooleanRequest(
      'log',
      (int requestId) => _bridge.dpeLogAsyncManaged(
        _nativeHandle,
        requestId,
        message,
      ),
    );
  }

  /// Purpose: Start one suppressed log section through the native DogPawEntity
  /// bridge.
  ///
  /// Parameters:
  /// - [sectionTitle]: `String` optional label for the buffered section.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, Epiphany is buffering log output for the current section.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> startLogSection([String sectionTitle = '']) async {
    return _runBooleanRequest(
      'startLogSection',
      (int requestId) => _bridge.dpeStartLogSectionAsyncManaged(
        _nativeHandle,
        requestId,
        sectionTitle,
      ),
    );
  }

  /// Purpose: Flush the current suppressed log section through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, Epiphany flushes buffered logs while keeping the section
  ///   active.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> flushLogSection() async {
    return _runBooleanRequest(
      'flushLogSection',
      (int requestId) => _bridge.dpeFlushLogSectionAsyncManaged(
        _nativeHandle,
        requestId,
      ),
    );
  }

  /// Purpose: End the current suppressed log section through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [flush]: `bool` indicating whether Epiphany should print buffered logs.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, Epiphany stops buffering for the current section.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> endLogSection([bool flush = false]) async {
    return _runBooleanRequest(
      'endLogSection',
      (int requestId) => _bridge.dpeEndLogSectionAsyncManaged(
        _nativeHandle,
        requestId,
        flush,
      ),
    );
  }

  /// Purpose: Request debug system information through the native DogPawEntity
  /// bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<Result<Map<String, dynamic>>>` containing Epiphany's
  /// raw response payload.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, returns the JSON object reported by the wrapped C++ call.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<Map<String, dynamic>>> getSystemInfo() async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'getSystemInfo',
        (int requestId) => _bridge.dpeGetSystemInfoAsyncManaged(
          _nativeHandle,
          requestId,
        ),
      );
      if (response[JsonFields.SUCCESS] == true) {
        final dynamic resultPayload = response[JsonFields.RESULT];
        final Map<String, dynamic> typedResult = resultPayload is Map
            ? Map<String, dynamic>.from(resultPayload)
            : <String, dynamic>{};
        return Result<Map<String, dynamic>>.success(typedResult);
      }
      return Result<Map<String, dynamic>>.error(
        response[JsonFields.ERROR] as String? ?? 'getSystemInfo failed',
      );
    } catch (exception) {
      return Result<Map<String, dynamic>>.error(exception.toString());
    }
  }

  /// Purpose: Request launcher-owned app metadata through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<Result<Map<String, dynamic>>>` containing an `apps`
  /// array on success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, returns the JSON object reported by Epiphany's `app/list`
  ///   handler.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<Map<String, dynamic>>> listApps() async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'listApps',
        (int requestId) => _bridge.dpeListAppsAsyncManaged(
          _nativeHandle,
          requestId,
        ),
      );
      if (response[JsonFields.SUCCESS] == true) {
        final dynamic resultPayload = response[JsonFields.RESULT];
        final Map<String, dynamic> typedResult = resultPayload is Map
            ? Map<String, dynamic>.from(resultPayload)
            : <String, dynamic>{};
        return Result<Map<String, dynamic>>.success(typedResult);
      }
      return Result<Map<String, dynamic>>.error(
        response[JsonFields.ERROR] as String? ?? 'listApps failed',
      );
    } catch (exception) {
      return Result<Map<String, dynamic>>.error(exception.toString());
    }
  }

  /// Purpose: Request the currently running runtime entities through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<Result<Map<String, dynamic>>>` containing an
  /// `entities` array on success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, returns the JSON object reported by Epiphany's `entity/list`
  ///   handler.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<Map<String, dynamic>>> listRunningEntities() async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'listRunningEntities',
        (int requestId) => _bridge.dpeListRunningEntitiesAsyncManaged(
          _nativeHandle,
          requestId,
        ),
      );
      if (response[JsonFields.SUCCESS] == true) {
        final dynamic resultPayload = response[JsonFields.RESULT];
        final Map<String, dynamic> typedResult = resultPayload is Map
            ? Map<String, dynamic>.from(resultPayload)
            : <String, dynamic>{};
        return Result<Map<String, dynamic>>.success(typedResult);
      }
      return Result<Map<String, dynamic>>.error(
        response[JsonFields.ERROR] as String? ?? 'listRunningEntities failed',
      );
    } catch (exception) {
      return Result<Map<String, dynamic>>.error(exception.toString());
    }
  }

  /// Purpose: Launch one app through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [appName]: app template name (must match a registered `dogpawapp.json`).
  /// - [launchMetadata]: optional JSON-compatible metadata forwarded to the
  ///   launched app via its launch metadata file.
  ///
  /// Return value: `Future<Result<String>>` containing the runtime entity name
  /// assigned by Epiphany. Singleton apps return their stable manifest name;
  /// multi-instance apps return the generated per-instance name.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, Epiphany has accepted the app launch request and the
  ///   resulting entity name is returned.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<String>> launchApp(
    String appName, {
    Map<String, dynamic>? launchMetadata,
  }) async {
    try {
      final String? metadataJson =
          launchMetadata != null ? jsonEncode(launchMetadata) : null;
      final Map<String, dynamic> response = await _invokeRequest(
        'launchApp',
        (int requestId) => _bridge.dpeLaunchAppAsyncManaged(
          _nativeHandle,
          requestId,
          appName,
          launchMetadataJson: metadataJson,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<String>.error(
          response[JsonFields.ERROR] as String? ?? 'launchApp failed',
        );
      }
      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final String? entityName = result[JsonFields.ENTITY_NAME] as String?;
      if (entityName == null || entityName.isEmpty) {
        return Result<String>.error(
          'launchApp missing entityName in result payload',
        );
      }
      return Result<String>.success(entityName);
    } catch (exception) {
      return Result<String>.error(exception.toString());
    }
  }

  /// Purpose: Stop one app through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [appName]: `String` app name to stop.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, Epiphany has accepted the app stop request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> stopApp(String appName) async {
    return _runBooleanRequest(
      'stopApp',
      (int requestId) => _bridge.dpeStopAppAsyncManaged(
        _nativeHandle,
        requestId,
        appName,
      ),
    );
  }

  /// Purpose: Stop all apps through the native DogPawEntity bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<Result<String>>` containing Epiphany's status message.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, returns the message from the wrapped C++ `killAllApps()`
  ///   result.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<String>> killAllApps() async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'killAllApps',
        (int requestId) => _bridge.dpeKillAllAppsAsyncManaged(
          _nativeHandle,
          requestId,
        ),
      );
      if (response[JsonFields.SUCCESS] == true) {
        final dynamic resultPayload = response[JsonFields.RESULT];
        final Map<String, dynamic> typedResult = resultPayload is Map
            ? Map<String, dynamic>.from(resultPayload)
            : <String, dynamic>{};
        return Result<String>.success(
          typedResult[JsonFields.MESSAGE] as String? ?? '',
        );
      }
      return Result<String>.error(
        response[JsonFields.ERROR] as String? ?? 'killAllApps failed',
      );
    } catch (exception) {
      return Result<String>.error(exception.toString());
    }
  }

  /// Purpose: Store a theme through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [theme]: `Theme` payload to store.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the set-theme request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> setTheme(Theme theme) async {
    return _runBooleanRequest(
      'setTheme',
      (int requestId) => _bridge.dpeSetThemeAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(theme.toJson()),
      ),
    );
  }

  /// Purpose: Create a theme through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [theme]: `Theme` payload to create.
  /// - [autoSuffix]: `bool` forwarded to the native create request.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the create-theme request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> createTheme(
    Theme theme, {
    bool autoSuffix = false,
  }) async {
    return _runBooleanRequest(
      'createTheme',
      (int requestId) => _bridge.dpeCreateThemeAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(theme.toJson()),
        autoSuffix: autoSuffix,
      ),
    );
  }

  /// Purpose: Update a theme through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [theme]: `Theme` payload to update.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the update-theme request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> updateTheme(Theme theme) async {
    return _runBooleanRequest(
      'updateTheme',
      (int requestId) => _bridge.dpeUpdateThemeAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(theme.toJson()),
      ),
    );
  }

  /// Purpose: Read one theme through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [name]: `String` theme name to read.
  /// - [namespaceSelector]: `NamespaceSelector` scope for the read request.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<Theme?>>` with a typed `Theme` or `null`.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned theme is decoded from the native C++ DPE
  ///   result, or `null` if absent.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<Theme?>> readTheme(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readTheme',
        (int requestId) => _bridge.dpeReadThemeAsyncManaged(
          _nativeHandle,
          requestId,
          name,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<Theme?>.error(
          response[JsonFields.ERROR] as String? ?? 'readTheme failed',
        );
      }
      return Result<Theme?>.success(
        _decodeThemeFromResultPayload(response),
      );
    } catch (exception) {
      return Result<Theme?>.error(exception.toString());
    }
  }

  /// Purpose: Delete one theme through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [name]: `String` theme name to delete.
  /// - [namespaceSelector]: `NamespaceSelector` scope for the delete request.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the delete-theme request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> deleteTheme(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _runBooleanRequest(
      'deleteTheme',
      (int requestId) => _bridge.dpeDeleteThemeAsyncManaged(
        _nativeHandle,
        requestId,
        name,
        jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Push one theme onto the current-theme stack through the native bridge.
  ///
  /// Parameters:
  /// - [name]: `String` theme name to set current.
  /// - [namespaceSelector]: `NamespaceSelector` scope that owns the named theme.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native current-theme stack has been updated.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> setCurrentTheme(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _runBooleanRequest(
      'setCurrentTheme',
      (int requestId) => _bridge.dpeSetCurrentThemeAsyncManaged(
        _nativeHandle,
        requestId,
        name,
        jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Read the current theme through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<Theme?>>` with a typed current `Theme` or
  /// `null`.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned theme is decoded from the native C++ current
  ///   theme result, or `null` if absent.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<Theme?>> readCurrentTheme({
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readCurrentTheme',
        (int requestId) => _bridge.dpeReadCurrentThemeAsyncManaged(
          _nativeHandle,
          requestId,
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<Theme?>.error(
          response[JsonFields.ERROR] as String? ?? 'readCurrentTheme failed',
        );
      }
      return Result<Theme?>.success(
        _decodeThemeFromResultPayload(response),
      );
    } catch (exception) {
      return Result<Theme?>.error(exception.toString());
    }
  }

  /// Purpose: Pop the current-theme stack through the native DogPawEntity bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native current-theme stack has been popped.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> removeCurrentTheme() async {
    return _runBooleanRequest(
      'removeCurrentTheme',
      (int requestId) => _bridge.dpeRemoveCurrentThemeAsyncManaged(
        _nativeHandle,
        requestId,
      ),
    );
  }

  /// Purpose: Request the list of themes through the native DogPawEntity.
  ///
  /// Parameters:
  /// - [namespaceSelector]: `NamespaceSelector` scope for the list request.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<List<Theme>>>` with typed Dart `Theme`
  /// instances on success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned list is decoded from the native C++ DPE result.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<List<Theme>>> listThemes({
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'listThemes',
        (int requestId) => _bridge.dpeListThemesAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<List<Theme>>.error(
          response[JsonFields.ERROR] as String? ?? 'listThemes failed',
        );
      }

      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final List<dynamic> themesJson =
          List<dynamic>.from(result[JsonFields.THEMES] as List);
      final List<Theme> themes = themesJson
          .map((dynamic themeJson) =>
              Theme.fromJson(Map<String, dynamic>.from(themeJson as Map)))
          .toList();
      return Result<List<Theme>>.success(themes);
    } catch (exception) {
      return Result<List<Theme>>.error(exception.toString());
    }
  }

  /// Purpose: Subscribe to ordinary theme notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each matching theme notification.
  /// - [themeName]: optional `String` theme name to watch, or `null` for all
  ///   themes in the selected namespace.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<bool>>` indicating subscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching native theme notifications are decoded to Dart
  ///   `Theme` values and delivered to [callback] until unsubscribed.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> subscribeToThemes(
    Function(String, DataItemRef, Theme) callback, {
    String? themeName,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _subscribeToItem(
      'subscribeToThemes',
      JsonFields.THEME_NOTIFICATION,
      (String notificationType, DataItemRef dataItemRef, dynamic data) {
        if (data is Map<String, dynamic>) {
          callback(notificationType, dataItemRef, Theme.fromJson(data));
        }
      },
      name: themeName,
      namespaceSelector: namespaceSelector,
      responseField: JsonFields.THEME,
      launchRequest: (int requestId) => _bridge.dpeSubscribeThemesAsyncManaged(
        _nativeHandle,
        requestId,
        name: themeName,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Purpose: Unsubscribe from ordinary theme notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [themeName]: optional `String` theme name to stop watching, or `null`
  ///   for all themes in the selected namespace.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  ///
  /// Return value: `Future<Result<bool>>` indicating unsubscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Matching local theme callbacks are removed before the native unsubscribe
  ///   request is launched.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> unsubscribeFromThemes({
    String? themeName,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _unsubscribeFromItem(
      'unsubscribeFromThemes',
      JsonFields.THEME_NOTIFICATION,
      name: themeName,
      namespaceSelector: namespaceSelector,
      launchRequest: (int requestId) =>
          _bridge.dpeUnsubscribeThemesAsyncManaged(
        _nativeHandle,
        requestId,
        name: themeName,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Subscribe to current-theme notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each matching current-theme
  ///   notification.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<bool>>` indicating subscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching native current-theme notifications are decoded to
  ///   Dart `Theme` values and delivered to [callback] until unsubscribed.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> subscribeToCurrentTheme(
    Function(String, DataItemRef, Theme) callback, {
    bool includeResolved = true,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _subscribeToCurrentItem(
      'subscribeToCurrentTheme',
      JsonFields.THEME_NOTIFICATION,
      (String notificationType, DataItemRef dataItemRef, dynamic data) {
        if (data is Map<String, dynamic>) {
          callback(notificationType, dataItemRef, Theme.fromJson(data));
        }
      },
      responseField: JsonFields.THEME,
      launchRequest: (int requestId) =>
          _bridge.dpeSubscribeCurrentThemeAsyncManaged(
        _nativeHandle,
        requestId,
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Purpose: Unsubscribe from current-theme notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<Result<bool>>` indicating unsubscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Matching local current-theme callbacks are removed before the native
  ///   unsubscribe request is launched.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> unsubscribeFromCurrentTheme() async {
    return _unsubscribeFromCurrentItem(
      'unsubscribeFromCurrentTheme',
      JsonFields.THEME_NOTIFICATION,
      launchRequest: (int requestId) =>
          _bridge.dpeUnsubscribeCurrentThemeAsyncManaged(
        _nativeHandle,
        requestId,
      ),
    );
  }

  /// Purpose: Store a scale through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [scale]: `Scale` payload to store.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the set-scale request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> setScale(Scale scale) async {
    return _runBooleanRequest(
      'setScale',
      (int requestId) => _bridge.dpeSetScaleAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(scale.toJson()),
      ),
    );
  }

  /// Purpose: Create a scale through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [scale]: `Scale` payload to create.
  /// - [autoSuffix]: `bool` forwarded to the native create request.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the create-scale request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> createScale(
    Scale scale, {
    bool autoSuffix = false,
  }) async {
    return _runBooleanRequest(
      'createScale',
      (int requestId) => _bridge.dpeCreateScaleAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(scale.toJson()),
        autoSuffix: autoSuffix,
      ),
    );
  }

  /// Purpose: Update a scale through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [scale]: `Scale` payload to update.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the update-scale request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> updateScale(Scale scale) async {
    return _runBooleanRequest(
      'updateScale',
      (int requestId) => _bridge.dpeUpdateScaleAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(scale.toJson()),
      ),
    );
  }

  /// Purpose: Read one scale through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [name]: `String` scale name to read.
  /// - [namespaceSelector]: `NamespaceSelector` scope for the read request.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<Scale?>>` with a typed `Scale` or `null`.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned scale is decoded from the native C++ DPE
  ///   result, or `null` if absent.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<Scale?>> readScale(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readScale',
        (int requestId) => _bridge.dpeReadScaleAsyncManaged(
          _nativeHandle,
          requestId,
          name,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<Scale?>.error(
          response[JsonFields.ERROR] as String? ?? 'readScale failed',
        );
      }
      return Result<Scale?>.success(
        _decodeScaleFromResultPayload(response),
      );
    } catch (exception) {
      return Result<Scale?>.error(exception.toString());
    }
  }

  /// Purpose: Delete one scale through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [name]: `String` scale name to delete.
  /// - [namespaceSelector]: `NamespaceSelector` scope for the delete request.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the delete-scale request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> deleteScale(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _runBooleanRequest(
      'deleteScale',
      (int requestId) => _bridge.dpeDeleteScaleAsyncManaged(
        _nativeHandle,
        requestId,
        name,
        jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Push one scale onto the current-scale stack through the native bridge.
  ///
  /// Parameters:
  /// - [name]: `String` scale name to set current.
  /// - [namespaceSelector]: `NamespaceSelector` scope that owns the named scale.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native current-scale stack has been updated.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> setCurrentScale(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _runBooleanRequest(
      'setCurrentScale',
      (int requestId) => _bridge.dpeSetCurrentScaleAsyncManaged(
        _nativeHandle,
        requestId,
        name,
        jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Read the current scale through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<Scale?>>` with a typed current `Scale` or
  /// `null`.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned scale is decoded from the native C++ current
  ///   scale result, or `null` if absent.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<Scale?>> readCurrentScale({
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readCurrentScale',
        (int requestId) => _bridge.dpeReadCurrentScaleAsyncManaged(
          _nativeHandle,
          requestId,
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<Scale?>.error(
          response[JsonFields.ERROR] as String? ?? 'readCurrentScale failed',
        );
      }
      return Result<Scale?>.success(
        _decodeScaleFromResultPayload(response),
      );
    } catch (exception) {
      return Result<Scale?>.error(exception.toString());
    }
  }

  /// Purpose: Pop the current-scale stack through the native DogPawEntity bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native current-scale stack has been popped.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> removeCurrentScale() async {
    return _runBooleanRequest(
      'removeCurrentScale',
      (int requestId) => _bridge.dpeRemoveCurrentScaleAsyncManaged(
        _nativeHandle,
        requestId,
      ),
    );
  }

  /// Purpose: Request the list of scales through the native DogPawEntity.
  ///
  /// Parameters:
  /// - [namespaceSelector]: `NamespaceSelector` scope for the list request.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<List<Scale>>>` with typed Dart `Scale`
  /// instances on success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned list is decoded from the native C++ DPE result.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<List<Scale>>> listScales({
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'listScales',
        (int requestId) => _bridge.dpeListScalesAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<List<Scale>>.error(
          response[JsonFields.ERROR] as String? ?? 'listScales failed',
        );
      }

      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final List<dynamic> scalesJson =
          List<dynamic>.from(result[JsonFields.SCALES] as List);
      final List<Scale> scales = scalesJson
          .map((dynamic scaleJson) =>
              Scale.fromJson(Map<String, dynamic>.from(scaleJson as Map)))
          .toList();
      return Result<List<Scale>>.success(scales);
    } catch (exception) {
      return Result<List<Scale>>.error(exception.toString());
    }
  }

  /// Purpose: Subscribe to ordinary scale notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each matching scale notification.
  /// - [scaleName]: optional `String` scale name to watch, or `null` for all
  ///   scales in the selected namespace.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<bool>>` indicating subscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching native scale notifications are decoded to Dart
  ///   `Scale` values and delivered to [callback] until unsubscribed.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> subscribeToScales(
    Function(String, DataItemRef, Scale) callback, {
    String? scaleName,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _subscribeToItem(
      'subscribeToScales',
      JsonFields.SCALE_NOTIFICATION,
      (String notificationType, DataItemRef dataItemRef, dynamic data) {
        if (data is Map<String, dynamic>) {
          callback(notificationType, dataItemRef, Scale.fromJson(data));
        }
      },
      name: scaleName,
      namespaceSelector: namespaceSelector,
      responseField: JsonFields.SCALE,
      launchRequest: (int requestId) => _bridge.dpeSubscribeScalesAsyncManaged(
        _nativeHandle,
        requestId,
        name: scaleName,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Purpose: Unsubscribe from ordinary scale notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [scaleName]: optional `String` scale name to stop watching, or `null`
  ///   for all scales in the selected namespace.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  ///
  /// Return value: `Future<Result<bool>>` indicating unsubscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Matching local scale callbacks are removed before the native unsubscribe
  ///   request is launched.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> unsubscribeFromScales({
    String? scaleName,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _unsubscribeFromItem(
      'unsubscribeFromScales',
      JsonFields.SCALE_NOTIFICATION,
      name: scaleName,
      namespaceSelector: namespaceSelector,
      launchRequest: (int requestId) =>
          _bridge.dpeUnsubscribeScalesAsyncManaged(
        _nativeHandle,
        requestId,
        name: scaleName,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Subscribe to current-scale notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each matching current-scale
  ///   notification.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<bool>>` indicating subscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching native current-scale notifications are decoded to
  ///   Dart `Scale` values and delivered to [callback] until unsubscribed.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> subscribeToCurrentScale(
    Function(String, DataItemRef, Scale) callback, {
    bool includeResolved = true,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _subscribeToCurrentItem(
      'subscribeToCurrentScale',
      JsonFields.SCALE_NOTIFICATION,
      (String notificationType, DataItemRef dataItemRef, dynamic data) {
        if (data is Map<String, dynamic>) {
          callback(notificationType, dataItemRef, Scale.fromJson(data));
        }
      },
      responseField: JsonFields.SCALE,
      launchRequest: (int requestId) =>
          _bridge.dpeSubscribeCurrentScaleAsyncManaged(
        _nativeHandle,
        requestId,
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Purpose: Unsubscribe from current-scale notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<Result<bool>>` indicating unsubscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Matching local current-scale callbacks are removed before the native
  ///   unsubscribe request is launched.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> unsubscribeFromCurrentScale() async {
    return _unsubscribeFromCurrentItem(
      'unsubscribeFromCurrentScale',
      JsonFields.SCALE_NOTIFICATION,
      launchRequest: (int requestId) =>
          _bridge.dpeUnsubscribeCurrentScaleAsyncManaged(
        _nativeHandle,
        requestId,
      ),
    );
  }

  /// Purpose: Store a layout through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [layout]: `Layout` payload to store.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the set-layout request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> setLayout(Layout layout) async {
    return _runBooleanRequest(
      'setLayout',
      (int requestId) => _bridge.dpeSetLayoutAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(layout.toJson()),
      ),
    );
  }

  /// Purpose: Create a layout through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [layout]: `Layout` payload to create.
  /// - [autoSuffix]: `bool` forwarded to the native create request.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the create-layout request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> createLayout(
    Layout layout, {
    bool autoSuffix = false,
  }) async {
    return _runBooleanRequest(
      'createLayout',
      (int requestId) => _bridge.dpeCreateLayoutAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(layout.toJson()),
        autoSuffix: autoSuffix,
      ),
    );
  }

  /// Purpose: Update a layout through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [layout]: `Layout` payload to update.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the update-layout request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> updateLayout(Layout layout) async {
    return _runBooleanRequest(
      'updateLayout',
      (int requestId) => _bridge.dpeUpdateLayoutAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(layout.toJson()),
      ),
    );
  }

  /// Purpose: Read one layout through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [name]: `String` layout name to read.
  /// - [namespaceSelector]: `NamespaceSelector` scope for the read request.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<Layout?>>` with a typed `Layout` or `null`.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned layout is decoded from the native C++ DPE
  ///   result, or `null` if absent.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<Layout?>> readLayout(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readLayout',
        (int requestId) => _bridge.dpeReadLayoutAsyncManaged(
          _nativeHandle,
          requestId,
          name,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<Layout?>.error(
          response[JsonFields.ERROR] as String? ?? 'readLayout failed',
        );
      }
      return Result<Layout?>.success(
        _decodeLayoutFromResultPayload(response),
      );
    } catch (exception) {
      return Result<Layout?>.error(exception.toString());
    }
  }

  /// Purpose: Delete one layout through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [name]: `String` layout name to delete.
  /// - [namespaceSelector]: `NamespaceSelector` scope for the delete request.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the delete-layout request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> deleteLayout(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _runBooleanRequest(
      'deleteLayout',
      (int requestId) => _bridge.dpeDeleteLayoutAsyncManaged(
        _nativeHandle,
        requestId,
        name,
        jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Push one layout onto the current-layout stack through the native bridge.
  ///
  /// Parameters:
  /// - [name]: `String` layout name to set current.
  /// - [namespaceSelector]: `NamespaceSelector` scope that owns the named layout.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native current-layout stack has been updated.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  /// Purpose: Request the list of layouts through the native DogPawEntity.
  ///
  /// Parameters:
  /// - [namespaceSelector]: `NamespaceSelector` scope for the list request.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<List<Layout>>>` with typed Dart `Layout`
  /// instances on success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned list is decoded from the native C++ DPE result.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<List<Layout>>> listLayouts({
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'listLayouts',
        (int requestId) => _bridge.dpeListLayoutsAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<List<Layout>>.error(
          response[JsonFields.ERROR] as String? ?? 'listLayouts failed',
        );
      }

      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final List<dynamic> layoutsJson =
          List<dynamic>.from(result[JsonFields.LAYOUTS] as List);
      final List<Layout> layouts = layoutsJson
          .map((dynamic layoutJson) =>
              Layout.fromJson(Map<String, dynamic>.from(layoutJson as Map)))
          .toList();
      return Result<List<Layout>>.success(layouts);
    } catch (exception) {
      return Result<List<Layout>>.error(exception.toString());
    }
  }

  /// Purpose: Subscribe to ordinary layout notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each matching layout notification.
  /// - [layoutName]: optional `String` layout name to watch, or `null` for all
  ///   layouts in the selected namespace.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<bool>>` indicating subscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching native layout notifications are decoded to Dart
  ///   `Layout` values and delivered to [callback] until unsubscribed.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> subscribeToLayouts(
    Function(String, DataItemRef, Layout) callback, {
    String? layoutName,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _subscribeToItem(
      'subscribeToLayouts',
      JsonFields.LAYOUT_NOTIFICATION,
      (String notificationType, DataItemRef dataItemRef, dynamic data) {
        if (data is Map<String, dynamic>) {
          callback(notificationType, dataItemRef, Layout.fromJson(data));
        }
      },
      name: layoutName,
      namespaceSelector: namespaceSelector,
      responseField: JsonFields.LAYOUT,
      launchRequest: (int requestId) => _bridge.dpeSubscribeLayoutsAsyncManaged(
        _nativeHandle,
        requestId,
        name: layoutName,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Purpose: Unsubscribe from ordinary layout notifications through the
  /// native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [layoutName]: optional `String` layout name to stop watching, or `null`
  ///   for all layouts in the selected namespace.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  ///
  /// Return value: `Future<Result<bool>>` indicating unsubscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Matching local layout callbacks are removed before the native unsubscribe
  ///   request is launched.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> unsubscribeFromLayouts({
    String? layoutName,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _unsubscribeFromItem(
      'unsubscribeFromLayouts',
      JsonFields.LAYOUT_NOTIFICATION,
      name: layoutName,
      namespaceSelector: namespaceSelector,
      launchRequest: (int requestId) =>
          _bridge.dpeUnsubscribeLayoutsAsyncManaged(
        _nativeHandle,
        requestId,
        name: layoutName,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  // ==========================================================================
  // Layout Stack
  // ==========================================================================

  /// Add an entry to the persistent layout stack. Returns the new entry id.
  Future<Result<String>> addLayoutStackEntry(
    DataItemRef layoutRef, {
    int? index,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'addLayoutStackEntry',
        (int requestId) => _bridge.dpeAddLayoutStackEntryAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(layoutRef.toJson()),
          index: index,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<String>.error(
          response[JsonFields.ERROR] as String? ?? 'addLayoutStackEntry failed',
        );
      }
      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final String? entryId = result[JsonFields.ENTRY_ID] as String?;
      if (entryId == null || entryId.isEmpty) {
        return Result<String>.error(
          'addLayoutStackEntry missing entryId in result payload',
        );
      }
      return Result<String>.success(entryId);
    } catch (exception) {
      return Result<String>.error(exception.toString());
    }
  }

  /// Remove a layout-stack entry by id.
  Future<Result<bool>> removeLayoutStackEntry(String entryId) async {
    return _runBooleanRequest(
      'removeLayoutStackEntry',
      (int requestId) => _bridge.dpeRemoveLayoutStackEntryAsyncManaged(
        _nativeHandle,
        requestId,
        entryId,
      ),
    );
  }

  /// Move a layout-stack entry to [newIndex].
  Future<Result<bool>> moveLayoutStackEntry(
    String entryId,
    int newIndex,
  ) async {
    return _runBooleanRequest(
      'moveLayoutStackEntry',
      (int requestId) => _bridge.dpeMoveLayoutStackEntryAsyncManaged(
        _nativeHandle,
        requestId,
        entryId,
        newIndex,
      ),
    );
  }

  /// Read a full layout-stack snapshot.
  Future<Result<LayoutStackSnapshot>> readLayoutStack({
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readLayoutStack',
        (int requestId) => _bridge.dpeReadLayoutStackAsyncManaged(
          _nativeHandle,
          requestId,
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<LayoutStackSnapshot>.error(
          response[JsonFields.ERROR] as String? ?? 'readLayoutStack failed',
        );
      }
      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final dynamic snapshotJson = result[JsonFields.LAYOUT_STACK];
      if (snapshotJson is! Map) {
        return Result<LayoutStackSnapshot>.error(
          'readLayoutStack missing layoutStack payload',
        );
      }
      final LayoutStackSnapshot snapshot = LayoutStackSnapshot.fromJson(
        Map<String, dynamic>.from(snapshotJson),
      );
      return Result<LayoutStackSnapshot>.success(snapshot);
    } catch (exception) {
      return Result<LayoutStackSnapshot>.error(exception.toString());
    }
  }

  /// Subscribe to layout-stack notifications. The callback receives the
  /// `notificationType` string, the `DataItemRef` (name: `layout_stack`,
  /// namespace: `global`), and the latest [LayoutStackSnapshot].
  ///
  /// The layout stack is a single global entity in Epiphany, so subscriptions
  /// are always registered with `global` namespace matching.
  Future<Result<bool>> subscribeToLayoutStack(
    Function(String, DataItemRef, LayoutStackSnapshot) callback, {
    bool includeResolved = true,
    bool includeSpec = false,
    bool sendImmediately = false,
  }) async {
    return _subscribeToItem(
      'subscribeToLayoutStack',
      JsonFields.LAYOUT_STACK_NOTIFICATION,
      (String notificationType, DataItemRef dataItemRef, dynamic data) {
        if (data is Map<String, dynamic>) {
          callback(
            notificationType,
            dataItemRef,
            LayoutStackSnapshot.fromJson(data),
          );
        }
      },
      namespaceSelector: const NamespaceSelector.global(),
      responseField: JsonFields.LAYOUT_STACK,
      launchRequest: (int requestId) =>
          _bridge.dpeSubscribeLayoutStackAsyncManaged(
        _nativeHandle,
        requestId,
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Remove the entity's layout-stack subscription.
  Future<Result<bool>> unsubscribeFromLayoutStack() async {
    return _unsubscribeFromItem(
      'unsubscribeFromLayoutStack',
      JsonFields.LAYOUT_STACK_NOTIFICATION,
      namespaceSelector: const NamespaceSelector.global(),
      launchRequest: (int requestId) =>
          _bridge.dpeUnsubscribeLayoutStackAsyncManaged(
        _nativeHandle,
        requestId,
      ),
    );
  }

  /// Purpose: Subscribe to current-layout notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each matching current-layout
  ///   notification.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<bool>>` indicating subscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching native current-layout notifications are decoded to
  ///   Dart `Layout` values and delivered to [callback] until unsubscribed.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  /// Purpose: Store a KV through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [kv]: `KV` payload to store.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the set-kv request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> setKV(KV kv) async {
    return _runBooleanRequest(
      'setKV',
      (int requestId) => _bridge.dpeSetKVAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(kv.toJson()),
      ),
    );
  }

  /// Purpose: Create a KV through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [kv]: `KV` payload to create.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the create-kv request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> createKV(KV kv) async {
    return _runBooleanRequest(
      'createKV',
      (int requestId) => _bridge.dpeCreateKVAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(kv.toJson()),
      ),
    );
  }

  /// Purpose: Update a KV through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [kv]: `KV` payload to update.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the update-kv request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> updateKV(KV kv) async {
    return _runBooleanRequest(
      'updateKV',
      (int requestId) => _bridge.dpeUpdateKVAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(kv.toJson()),
      ),
    );
  }

  /// Purpose: Read one KV through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [name]: `String` KV name to read.
  /// - [namespaceSelector]: `NamespaceSelector` scope for the read request.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<KV?>>` with a typed `KV` or `null`.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned KV is decoded from the native C++ DPE
  ///   result, or `null` if absent.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<KV?>> readKV(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = true,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readKV',
        (int requestId) => _bridge.dpeReadKVAsyncManaged(
          _nativeHandle,
          requestId,
          name,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<KV?>.error(
          response[JsonFields.ERROR] as String? ?? 'readKV failed',
        );
      }
      return Result<KV?>.success(
        _decodeKVFromResultPayload(response),
      );
    } catch (exception) {
      return Result<KV?>.error(exception.toString());
    }
  }

  /// Purpose: Delete one KV through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [name]: `String` KV name to delete.
  /// - [namespaceSelector]: `NamespaceSelector` scope for the delete request.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ DPE has processed the delete-kv request.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> deleteKV(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _runBooleanRequest(
      'deleteKV',
      (int requestId) => _bridge.dpeDeleteKVAsyncManaged(
        _nativeHandle,
        requestId,
        name,
        jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Request the list of KVs through the native DogPawEntity.
  ///
  /// Parameters:
  /// - [namespaceSelector]: `NamespaceSelector` scope for the list request.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<List<KV>>>` with typed Dart `KV`
  /// instances on success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned list is decoded from the native C++ DPE result.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<List<KV>>> listKVs({
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'listKVs',
        (int requestId) => _bridge.dpeListKVsAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<List<KV>>.error(
          response[JsonFields.ERROR] as String? ?? 'listKVs failed',
        );
      }

      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final List<dynamic> kvsJson =
          List<dynamic>.from(result[JsonFields.KVS] as List);
      final List<KV> kvs = kvsJson
          .map((dynamic kvJson) =>
              KV.fromJson(Map<String, dynamic>.from(kvJson as Map)))
          .toList();
      return Result<List<KV>>.success(kvs);
    } catch (exception) {
      return Result<List<KV>>.error(exception.toString());
    }
  }

  /// Purpose: Create an endpoint through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [endpoint]: `EndpointInfo` payload to create.
  /// - [autoSuffix]: `bool` forwarded to the native `createEndpoint()` call.
  ///
  /// Return value: `Future<Result<EndpointInfo>>` with the created endpoint on
  /// success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned endpoint is decoded from the native result JSON.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<EndpointInfo>> createEndpoint(
    EndpointInfo endpoint, {
    bool autoSuffix = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'createEndpoint',
        (int requestId) => _bridge.dpeCreateEndpointAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(endpoint.toJson()),
          autoSuffix: autoSuffix,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<EndpointInfo>.error(
          response[JsonFields.ERROR] as String? ?? 'createEndpoint failed',
        );
      }
      final EndpointInfo? decoded = _decodeEndpointFromResultPayload(response);
      if (decoded == null) {
        return Result<EndpointInfo>.error(
            'createEndpoint missing endpoint payload');
      }
      return Result<EndpointInfo>.success(decoded);
    } catch (exception) {
      return Result<EndpointInfo>.error(exception.toString());
    }
  }

  /// Purpose: Update an endpoint through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [endpoint]: `EndpointInfo` payload to update.
  ///
  /// Return value: `Future<Result<EndpointInfo>>` with the updated endpoint on
  /// success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned endpoint is decoded from the native result JSON.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<EndpointInfo>> updateEndpoint(EndpointInfo endpoint) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'updateEndpoint',
        (int requestId) => _bridge.dpeUpdateEndpointAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(endpoint.toJson()),
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<EndpointInfo>.error(
          response[JsonFields.ERROR] as String? ?? 'updateEndpoint failed',
        );
      }
      final EndpointInfo? decoded = _decodeEndpointFromResultPayload(response);
      if (decoded == null) {
        return Result<EndpointInfo>.error(
            'updateEndpoint missing endpoint payload');
      }
      return Result<EndpointInfo>.success(decoded);
    } catch (exception) {
      return Result<EndpointInfo>.error(exception.toString());
    }
  }

  /// Purpose: Set (store) an endpoint through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [endpoint]: `EndpointInfo` payload to set.
  ///
  /// Return value: `Future<Result<EndpointInfo>>` with the stored endpoint on
  /// success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned endpoint is decoded from the native result JSON.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<EndpointInfo>> setEndpoint(EndpointInfo endpoint) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'setEndpoint',
        (int requestId) => _bridge.dpeSetEndpointAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(endpoint.toJson()),
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<EndpointInfo>.error(
          response[JsonFields.ERROR] as String? ?? 'setEndpoint failed',
        );
      }
      final EndpointInfo? decoded = _decodeEndpointFromResultPayload(response);
      if (decoded == null) {
        return Result<EndpointInfo>.error(
            'setEndpoint missing endpoint payload');
      }
      return Result<EndpointInfo>.success(decoded);
    } catch (exception) {
      return Result<EndpointInfo>.error(exception.toString());
    }
  }

  /// Purpose: Read one endpoint through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [name]: `String` endpoint name to read.
  /// - [namespaceSelector]: `NamespaceSelector` scope for the read request.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<EndpointInfo?>>` with a typed `EndpointInfo` or
  /// `null` when the read succeeds but no endpoint is present.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned value is decoded from the native C++ result, or
  ///   `null` if absent.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<EndpointInfo?>> readEndpoint(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readEndpoint',
        (int requestId) => _bridge.dpeReadEndpointAsyncManaged(
          _nativeHandle,
          requestId,
          name,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<EndpointInfo?>.error(
          response[JsonFields.ERROR] as String? ?? 'readEndpoint failed',
        );
      }
      return Result<EndpointInfo?>.success(
        _decodeEndpointFromResultPayload(response),
      );
    } catch (exception) {
      return Result<EndpointInfo?>.error(exception.toString());
    }
  }

  /// Purpose: Delete one endpoint by name through the native DogPawEntity
  /// bridge.
  ///
  /// Parameters:
  /// - [name]: `String` endpoint name to delete.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native C++ `deleteEndpoint()` request completed; the
  ///   native implementation applies the current-entity namespace on the wire.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> deleteEndpoint(String name) async {
    return _runBooleanRequest(
      'deleteEndpoint',
      (int requestId) => _bridge.dpeDeleteEndpointAsyncManaged(
        _nativeHandle,
        requestId,
        name,
      ),
    );
  }

  /// Purpose: Search endpoints through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [criteria]: `SearchCriteria` describing the native search.
  ///
  /// Return value: `Future<Result<List<EndpointInfo>>>` with typed endpoints on
  /// success.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned list is decoded from the native C++ result.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<List<EndpointInfo>>> searchEndpoints(
    SearchCriteria criteria,
  ) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'searchEndpoints',
        (int requestId) => _bridge.dpeSearchEndpointsAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(criteria.toJson()),
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<List<EndpointInfo>>.error(
          response[JsonFields.ERROR] as String? ?? 'searchEndpoints failed',
        );
      }

      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final List<dynamic> endpointsJson =
          List<dynamic>.from(result[JsonFields.ENDPOINTS] as List);
      final List<EndpointInfo> endpoints = endpointsJson
          .map(
            (dynamic item) => EndpointInfo.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      return Result<List<EndpointInfo>>.success(endpoints);
    } catch (exception) {
      return Result<List<EndpointInfo>>.error(exception.toString());
    }
  }

  /// Purpose: Subscribe to endpoint notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [callback]: callback invoked for endpoint notifications that include an
  ///   endpoint payload.
  /// - [endpointName]: optional endpoint name to watch, or `null` for all
  ///   endpoints in the selected namespace.
  /// - [namespaceSelector]: subscription namespace scope.
  /// - [includeResolved]: whether resolved endpoint data should be included.
  /// - [includeSpec]: whether spec endpoint data should be included.
  /// - [sendImmediately]: whether matching current endpoints should be replayed
  ///   immediately after subscribing.
  ///
  /// Return value:
  /// - `Future<Result<bool>>` indicating subscribe success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, endpoint CRUD notifications with endpoint payloads are
  ///   decoded to `EndpointInfo` values and delivered to [callback].
  ///
  /// Invariants:
  /// - Raw connection/index notifications may also be observed separately via
  ///   [setEndpointNotificationCallback].
  Future<Result<bool>> subscribeToEndpoints(
    Function(String, DataItemRef, EndpointInfo) callback, {
    String? endpointName,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _subscribeToItem(
      'subscribeToEndpoints',
      Topics.ENDPOINT_NOTIFICATION,
      (String notificationType, DataItemRef dataItemRef, dynamic data) {
        if (data is Map<String, dynamic>) {
          callback(notificationType, dataItemRef, EndpointInfo.fromJson(data));
        }
      },
      name: endpointName,
      namespaceSelector: namespaceSelector,
      responseField: JsonFields.ENDPOINT,
      launchRequest: (int requestId) =>
          _bridge.dpeSubscribeEndpointsAsyncManaged(
        _nativeHandle,
        requestId,
        name: endpointName,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Purpose: Unsubscribe from endpoint notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [endpointName]: optional endpoint name to stop watching, or `null` for
  ///   all endpoints in the selected namespace.
  /// - [namespaceSelector]: subscription namespace scope.
  ///
  /// Return value:
  /// - `Future<Result<bool>>` indicating unsubscribe success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Matching local endpoint callbacks are removed before the native
  ///   unsubscribe request is launched.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> unsubscribeFromEndpoints({
    String? endpointName,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _unsubscribeFromItem(
      'unsubscribeFromEndpoints',
      Topics.ENDPOINT_NOTIFICATION,
      name: endpointName,
      namespaceSelector: namespaceSelector,
      launchRequest: (int requestId) =>
          _bridge.dpeUnsubscribeEndpointsAsyncManaged(
        _nativeHandle,
        requestId,
        name: endpointName,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Write serialized bytes through one native-owned local endpoint.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  /// - [bytes]: serialized endpoint payload to forward to native runtime.
  /// - [immediate]: `bool` forwarded to native message-queue writes.
  ///
  /// Return value:
  /// - `bool` indicating whether the native runtime accepted the payload.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  /// - [bytes] already match the endpoint's current wire format.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the payload is forwarded through the native-owned endpoint
  ///   runtime.
  ///
  /// Invariants:
  /// - This call is synchronous and does not mutate endpoint metadata caches.
  bool writeLocalEndpointBytes(
    String endpointName,
    Uint8List bytes, {
    bool immediate = true,
  }) {
    _ensureNotDisposed();
    final Pointer<Uint8> dataPtr = malloc<Uint8>(bytes.length);
    try {
      dataPtr.asTypedList(bytes.length).setAll(0, bytes);
      return _bridge.dpeLocalEndpointWriteManaged(
        _nativeHandle,
        endpointName: endpointName,
        data: dataPtr.cast<Void>(),
        size: bytes.length,
        immediate: immediate,
      );
    } finally {
      malloc.free(dataPtr);
    }
  }

  /// Purpose: Read the native retained-state snapshot for one owned local
  /// endpoint.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  ///
  /// Return value:
  /// - `EndpointRetainedStateSnapshot` reported by the native local endpoint
  ///   runtime, or `hasState: false` when the snapshot cannot be read.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - The returned snapshot comes directly from the native runtime rather than
  ///   a Dart-side mirror.
  ///
  /// Invariants:
  /// - This helper does not mutate wrapper state.
  EndpointRetainedStateSnapshot queryLocalEndpointRetainedState(
      String endpointName) {
    _ensureNotDisposed();
    final int requiredSize = _bridge.dpeLocalEndpointGetRetainedStateJsonManaged(
      _nativeHandle,
      endpointName: endpointName,
      maxSize: 0,
    );
    if (requiredSize <= 0) {
      return const EndpointRetainedStateSnapshot(hasState: false);
    }

    final Pointer<Utf8> bufferPtr = malloc<Uint8>(requiredSize).cast<Utf8>();
    try {
      final int writeResult = _bridge.dpeLocalEndpointGetRetainedStateJsonManaged(
        _nativeHandle,
        endpointName: endpointName,
        outJson: bufferPtr,
        maxSize: requiredSize,
      );
      if (writeResult <= 0) {
        return const EndpointRetainedStateSnapshot(hasState: false);
      }
      final String jsonText = bufferPtr.toDartString();
      final dynamic decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        return const EndpointRetainedStateSnapshot(hasState: false);
      }
      return EndpointRetainedStateSnapshot.fromJson(decoded);
    } catch (_) {
      return const EndpointRetainedStateSnapshot(hasState: false);
    } finally {
      malloc.free(bufferPtr);
    }
  }

  /// Purpose: Adopt one retained-state snapshot into the native runtime for one
  /// owned local endpoint.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  /// - [snapshot]: `EndpointRetainedStateSnapshot` to commit into native
  ///   retained state.
  /// - [publishMatchedOutput]: `bool` controlling whether any linked matched
  ///   output publishes the committed state immediately.
  /// - [senderInfo]: optional `EndpointSenderInfo` describing the upstream
  ///   request identity associated with this accepted commit.
  ///
  /// Return value:
  /// - `true` when the native runtime accepted and applied [snapshot],
  ///   otherwise `false`.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, future native retained-state reads for [endpointName]
  ///   reflect [snapshot].
  /// - When [publishMatchedOutput] is `true`, linked matched output publication
  ///   follows the native endpoint path.
  ///
  /// Invariants:
  /// - This helper does not mutate Dart-side metadata caches directly.
  bool adoptLocalEndpointRetainedState(
    String endpointName,
    EndpointRetainedStateSnapshot snapshot, {
    bool publishMatchedOutput = true,
    EndpointSenderInfo? senderInfo,
  }) {
    _ensureNotDisposed();
    final String? senderInfoJson = senderInfo == null
        ? null
        : jsonEncode(<String, dynamic>{
            JsonFields.NAME: senderInfo.connectionName,
            JsonFields.TARGET: senderInfo.sourceEndpointRef.toJson(),
          });
    return _bridge.dpeLocalEndpointAdoptRetainedStateJsonManaged(
      _nativeHandle,
      endpointName: endpointName,
      snapshotJson: jsonEncode(snapshot.toJson()),
      publishMatchedOutput: publishMatchedOutput,
      senderInfoJson: senderInfoJson,
    );
  }

  /// Purpose: Poll serialized bytes from the native-owned runtime for one local
  /// endpoint.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  /// - [connectionName]: optional `String` limiting the poll to one realized
  ///   connection.
  ///
  /// Return value:
  /// - `List<LocalEndpointPollPacket>` containing one packet per connection that
  ///   produced data during this poll pass.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Returned packets reflect the current native connection list and shape.
  ///
  /// Invariants:
  /// - This method does not perform JSON decoding.
  List<LocalEndpointPollPacket> pollLocalEndpointBytes(
    String endpointName, {
    String? connectionName,
  }) {
    _ensureNotDisposed();
    final List<String> connectionNames = connectionName != null
        ? <String>[connectionName]
        : _listLocalEndpointConnections(endpointName);
    final List<LocalEndpointPollPacket> packets = <LocalEndpointPollPacket>[];

    for (final String currentConnectionName in connectionNames) {
      final _NativeConnectionShape? shape = _getLocalEndpointConnectionShape(
        endpointName,
        currentConnectionName,
      );
      if (shape == null || shape.payloadSize <= 0) {
        continue;
      }

      final Pointer<Uint8> bufferPtr = malloc<Uint8>(shape.payloadSize);
      try {
        final int bytesRead = _bridge.dpeLocalEndpointPollConnectionManaged(
          _nativeHandle,
          endpointName: endpointName,
          connectionName: currentConnectionName,
          outData: bufferPtr.cast<Void>(),
          maxSize: shape.payloadSize,
        );
        if (bytesRead > 0) {
          packets.add(LocalEndpointPollPacket(
            connectionName: currentConnectionName,
            bytes: Uint8List.fromList(bufferPtr.asTypedList(bytesRead)),
            indexSpec: shape.indexSpec,
          ));
        }
      } finally {
        malloc.free(bufferPtr);
      }
    }

    return packets;
  }

  /// Purpose: Read or poll variable-size bytes for native-owned file-backed
  /// local endpoint connections.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  /// - [connectionName]: optional `String` limiting the operation to one
  ///   realized connection.
  /// - [requireChange]: `true` to poll for a new file-backed notification before
  ///   reading, or `false` to read current contents immediately.
  ///
  /// Return value:
  /// - `List<LocalEndpointPollPacket>` containing one packet per connection that
  ///   produced readable bytes for this operation.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Returned packets use the native runtime's current connection list.
  /// - Each packet's `bytes` are the full current file contents for that
  ///   connection.
  ///
  /// Invariants:
  /// - Packet `indexSpec` is always `IndexSpecNone` for file-backed payloads.
  List<LocalEndpointPollPacket> _readLocalEndpointFileBackedBytes(
    String endpointName, {
    String? connectionName,
    required bool requireChange,
  }) {
    _ensureNotDisposed();
    final List<String> connectionNames = connectionName != null
        ? <String>[connectionName]
        : _listLocalEndpointConnections(endpointName);
    final List<LocalEndpointPollPacket> packets = <LocalEndpointPollPacket>[];

    for (final String currentConnectionName in connectionNames) {
      final int requiredSize = _bridge.dpeLocalEndpointReadFileBackedManaged(
        _nativeHandle,
        endpointName: endpointName,
        connectionName: currentConnectionName,
        maxSize: 0,
      );
      if (requiredSize <= 0) {
        continue;
      }

      final Pointer<Uint8> bufferPtr = malloc<Uint8>(requiredSize);
      try {
        final int bytesRead = requireChange
            ? _bridge.dpeLocalEndpointPollFileBackedManaged(
                _nativeHandle,
                endpointName: endpointName,
                connectionName: currentConnectionName,
                outData: bufferPtr.cast<Void>(),
                maxSize: requiredSize,
              )
            : _bridge.dpeLocalEndpointReadFileBackedManaged(
                _nativeHandle,
                endpointName: endpointName,
                connectionName: currentConnectionName,
                outData: bufferPtr.cast<Void>(),
                maxSize: requiredSize,
              );
        if (bytesRead > 0) {
          packets.add(LocalEndpointPollPacket(
            connectionName: currentConnectionName,
            bytes: Uint8List.fromList(bufferPtr.asTypedList(bytesRead)),
            indexSpec: const IndexSpecNone(),
          ));
        }
      } finally {
        malloc.free(bufferPtr);
      }
    }

    return packets;
  }

  /// Purpose: Poll native-owned file-backed endpoint connections for changes and
  /// return the changed file bytes.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  /// - [connectionName]: optional `String` limiting the poll to one realized
  ///   connection.
  ///
  /// Return value:
  /// - `List<LocalEndpointPollPacket>` containing one packet per connection that
  ///   observed a file-backed change.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Returned bytes are the latest file contents for each changed connection.
  ///
  /// Invariants:
  /// - Connections with no observed change are omitted.
  List<LocalEndpointPollPacket> pollFileBackedLocalEndpointBytes(
    String endpointName, {
    String? connectionName,
  }) {
    return _readLocalEndpointFileBackedBytes(
      endpointName,
      connectionName: connectionName,
      requireChange: true,
    );
  }

  /// Purpose: Read current bytes from native-owned file-backed endpoint
  /// connections without requiring a change notification.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  /// - [connectionName]: optional `String` limiting the read to one realized
  ///   connection.
  ///
  /// Return value:
  /// - `List<LocalEndpointPollPacket>` containing one packet per connection with
  ///   readable file contents.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Returned bytes reflect the current file contents at read time.
  ///
  /// Invariants:
  /// - This method does not require or consume a file-backed change
  ///   notification.
  List<LocalEndpointPollPacket> readFileBackedLocalEndpointBytes(
    String endpointName, {
    String? connectionName,
  }) {
    return _readLocalEndpointFileBackedBytes(
      endpointName,
      connectionName: connectionName,
      requireChange: false,
    );
  }

  /// Purpose: List realized native input connection names for one local
  /// endpoint.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  ///
  /// Return value:
  /// - `List<String>` of currently realized native connection names.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Returns the native runtime's current connection list.
  ///
  /// Invariants:
  /// - This helper does not mutate wrapper state.
  List<String> listLocalEndpointConnectionNames(String endpointName) {
    _ensureNotDisposed();
    return _listLocalEndpointConnections(endpointName);
  }

  /// Purpose: Create a connection request through the native DogPawEntity
  /// bridge.
  ///
  /// Parameters:
  /// - [connectionRequest]: typed connection request payload.
  ///
  /// Return value: `Future<Result<bool>>` indicating whether the native
  /// operation succeeded.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Guarantees/Postconditions: on success, Epiphany accepted the create.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<bool>> createConnectionRequest(
    ConnectionRequest connectionRequest,
  ) async {
    return _runBooleanRequest(
      'createConnectionRequest',
      (int requestId) => _bridge.dpeCreateConnectionRequestAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(connectionRequest.toJson()),
      ),
    );
  }

  /// Purpose: Set (upsert) a connection request through the native bridge.
  ///
  /// Parameters:
  /// - [connectionRequest]: typed connection request payload.
  ///
  /// Return value: `Future<Result<bool>>`.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<bool>> setConnectionRequest(
    ConnectionRequest connectionRequest,
  ) async {
    return _runBooleanRequest(
      'setConnectionRequest',
      (int requestId) => _bridge.dpeSetConnectionRequestAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(connectionRequest.toJson()),
      ),
    );
  }

  /// Purpose: Update an existing connection request through the native bridge.
  ///
  /// Parameters:
  /// - [connectionRequest]: typed connection request payload.
  ///
  /// Return value: `Future<Result<bool>>`.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<bool>> updateConnectionRequest(
    ConnectionRequest connectionRequest,
  ) async {
    return _runBooleanRequest(
      'updateConnectionRequest',
      (int requestId) => _bridge.dpeUpdateConnectionRequestAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(connectionRequest.toJson()),
      ),
    );
  }

  /// Purpose: Read one connection request through the native bridge.
  ///
  /// Parameters:
  /// - [name]: request name.
  /// - [namespaceSelector]: namespace scope.
  /// - [includeResolved], [includeSpec]: forwarded to native read.
  ///
  /// Return value: `Future<Result<ConnectionRequest?>>` with decoded data or
  /// null when absent.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<ConnectionRequest?>> readConnectionRequest(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readConnectionRequest',
        (int requestId) => _bridge.dpeReadConnectionRequestAsyncManaged(
          _nativeHandle,
          requestId,
          name,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<ConnectionRequest?>.error(
          response[JsonFields.ERROR] as String? ??
              'readConnectionRequest failed',
        );
      }
      return Result<ConnectionRequest?>.success(
        _decodeConnectionRequestFromResultPayload(response),
      );
    } catch (exception) {
      return Result<ConnectionRequest?>.error(exception.toString());
    }
  }

  /// Purpose: Delete a connection request through the native bridge.
  ///
  /// Parameters:
  /// - [name]: request name.
  /// - [namespaceSelector]: namespace scope.
  ///
  /// Return value: `Future<Result<bool>>`.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<bool>> deleteConnectionRequest(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _runBooleanRequest(
      'deleteConnectionRequest',
      (int requestId) => _bridge.dpeDeleteConnectionRequestAsyncManaged(
        _nativeHandle,
        requestId,
        name,
        jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: List connection requests in a namespace through the native
  /// bridge.
  ///
  /// Parameters:
  /// - [namespaceSelector]: namespace scope.
  /// - [includeResolved], [includeSpec]: forwarded to native list.
  ///
  /// Return value: `Future<Result<List<ConnectionRequest>>>`.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<List<ConnectionRequest>>> listConnectionRequests({
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'listConnectionRequests',
        (int requestId) => _bridge.dpeListConnectionRequestsAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<List<ConnectionRequest>>.error(
          response[JsonFields.ERROR] as String? ??
              'listConnectionRequests failed',
        );
      }
      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final List<dynamic> items =
          List<dynamic>.from(result[JsonFields.CONNECTION_REQUESTS] as List);
      return Result<List<ConnectionRequest>>.success(
        items
            .map(
              (dynamic e) => ConnectionRequest.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
    } catch (exception) {
      return Result<List<ConnectionRequest>>.error(exception.toString());
    }
  }

  /// Purpose: Create a follow request through the native DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [followRequest]: typed follow request payload.
  ///
  /// Return value: `Future<Result<bool>>` for native operation success.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Guarantees/Postconditions: on success, Epiphany accepted the create.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<bool>> createFollowRequest(FollowRequest followRequest) async {
    return _runBooleanRequest(
      'createFollowRequest',
      (int requestId) => _bridge.dpeCreateFollowRequestAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(followRequest.toJson()),
      ),
    );
  }

  /// Purpose: Set (upsert) a follow request through the native bridge.
  ///
  /// Parameters:
  /// - [followRequest]: typed follow request payload.
  ///
  /// Return value: `Future<Result<bool>>`.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<bool>> setFollowRequest(FollowRequest followRequest) async {
    return _runBooleanRequest(
      'setFollowRequest',
      (int requestId) => _bridge.dpeSetFollowRequestAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(followRequest.toJson()),
      ),
    );
  }

  /// Purpose: Update a follow request through the native bridge.
  ///
  /// Parameters:
  /// - [followRequest]: typed follow request payload.
  ///
  /// Return value: `Future<Result<bool>>`.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<bool>> updateFollowRequest(FollowRequest followRequest) async {
    return _runBooleanRequest(
      'updateFollowRequest',
      (int requestId) => _bridge.dpeUpdateFollowRequestAsyncManaged(
        _nativeHandle,
        requestId,
        jsonEncode(followRequest.toJson()),
      ),
    );
  }

  /// Purpose: Read one follow request through the native bridge.
  ///
  /// Parameters:
  /// - [name]: request name.
  /// - [namespaceSelector]: namespace scope.
  /// - [includeResolved], [includeSpec]: forwarded to native read.
  ///
  /// Return value: `Future<Result<FollowRequest?>>` or null when absent.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<FollowRequest?>> readFollowRequest(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readFollowRequest',
        (int requestId) => _bridge.dpeReadFollowRequestAsyncManaged(
          _nativeHandle,
          requestId,
          name,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<FollowRequest?>.error(
          response[JsonFields.ERROR] as String? ?? 'readFollowRequest failed',
        );
      }
      return Result<FollowRequest?>.success(
        _decodeFollowRequestFromResultPayload(response),
      );
    } catch (exception) {
      return Result<FollowRequest?>.error(exception.toString());
    }
  }

  /// Purpose: Delete a follow request through the native bridge.
  ///
  /// Parameters:
  /// - [name]: request name.
  /// - [namespaceSelector]: namespace scope.
  ///
  /// Return value: `Future<Result<bool>>`.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<bool>> deleteFollowRequest(
    String name, {
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _runBooleanRequest(
      'deleteFollowRequest',
      (int requestId) => _bridge.dpeDeleteFollowRequestAsyncManaged(
        _nativeHandle,
        requestId,
        name,
        jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: List follow requests through the native bridge.
  ///
  /// Parameters:
  /// - [namespaceSelector]: namespace scope.
  /// - [includeResolved], [includeSpec]: forwarded to native list.
  ///
  /// Return value: `Future<Result<List<FollowRequest>>>`.
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<List<FollowRequest>>> listFollowRequests({
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'listFollowRequests',
        (int requestId) => _bridge.dpeListFollowRequestsAsyncManaged(
          _nativeHandle,
          requestId,
          jsonEncode(namespaceSelector.toJson()),
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<List<FollowRequest>>.error(
          response[JsonFields.ERROR] as String? ?? 'listFollowRequests failed',
        );
      }
      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final List<dynamic> items =
          List<dynamic>.from(result[JsonFields.FOLLOW_REQUESTS] as List);
      return Result<List<FollowRequest>>.success(
        items
            .map(
              (dynamic e) => FollowRequest.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
    } catch (exception) {
      return Result<List<FollowRequest>>.error(exception.toString());
    }
  }

  /// Purpose: Read one realized connection through the native bridge.
  ///
  /// Parameters:
  /// - [name]: connection name.
  /// - [includeResolved], [includeSpec]: forwarded to native read.
  ///
  /// Return value: `Future<Result<Connection?>>`; native stack uses global
  /// namespace on the wire (matches public Dart API).
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<Connection?>> readConnection(
    String name, {
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'readConnection',
        (int requestId) => _bridge.dpeReadConnectionAsyncManaged(
          _nativeHandle,
          requestId,
          name,
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<Connection?>.error(
          response[JsonFields.ERROR] as String? ?? 'readConnection failed',
        );
      }
      return Result<Connection?>.success(
        _decodeConnectionFromResultPayload(response),
      );
    } catch (exception) {
      return Result<Connection?>.error(exception.toString());
    }
  }

  /// Purpose: List realized connections through the native bridge.
  ///
  /// Parameters:
  /// - [includeResolved], [includeSpec]: forwarded to native list.
  ///
  /// Return value: `Future<Result<List<Connection>>>`; native stack uses global
  /// namespace on the wire (matches public Dart API).
  ///
  /// Requirements/Preconditions: wrapper not disposed.
  ///
  /// Invariants: isolate not blocked on server I/O.
  Future<Result<List<Connection>>> listConnections({
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    try {
      final Map<String, dynamic> response = await _invokeRequest(
        'listConnections',
        (int requestId) => _bridge.dpeListConnectionsAsyncManaged(
          _nativeHandle,
          requestId,
          includeResolved: includeResolved,
          includeSpec: includeSpec,
        ),
      );
      if (response[JsonFields.SUCCESS] != true) {
        return Result<List<Connection>>.error(
          response[JsonFields.ERROR] as String? ?? 'listConnections failed',
        );
      }
      final Map<String, dynamic> result =
          Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
      final List<dynamic> items =
          List<dynamic>.from(result[JsonFields.CONNECTIONS] as List);
      return Result<List<Connection>>.success(
        items
            .map(
              (dynamic e) => Connection.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
    } catch (exception) {
      return Result<List<Connection>>.error(exception.toString());
    }
  }

  /// Purpose: Subscribe to KV change notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [callback]: callback invoked with each matching KV notification.
  /// - [key]: optional `String` key to watch, or `null` for all keys in the
  ///   selected namespace.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value: `Future<Result<bool>>` indicating subscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - On success, matching native KV notifications are decoded to Dart `KV`
  ///   values and delivered to [callback] until unsubscribed.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> subscribeToKV(
    Function(String, DataItemRef, KV) callback, {
    String? key,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
    bool includeResolved = false,
    bool includeSpec = false,
    bool sendImmediately = true,
  }) async {
    return _subscribeToItem(
      'subscribeToKV',
      JsonFields.KV_NOTIFICATION,
      (String notificationType, DataItemRef dataItemRef, dynamic data) {
        if (data is Map<String, dynamic>) {
          callback(notificationType, dataItemRef, KV.fromJson(data));
        }
      },
      name: key,
      namespaceSelector: namespaceSelector,
      responseField: JsonFields.KV,
      launchRequest: (int requestId) => _bridge.dpeSubscribeKVAsyncManaged(
        _nativeHandle,
        requestId,
        key: key,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
        includeResolved: includeResolved,
        includeSpec: includeSpec,
        sendImmediately: sendImmediately,
      ),
    );
  }

  /// Purpose: Unsubscribe from KV change notifications through the native
  /// DogPawEntity bridge.
  ///
  /// Parameters:
  /// - [key]: optional `String` key to stop watching, or `null` for all keys in
  ///   the selected namespace.
  /// - [namespaceSelector]: optional `NamespaceSelector` scope for the
  ///   subscription. Defaults to current entity.
  ///
  /// Return value: `Future<Result<bool>>` indicating unsubscribe success or
  /// failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Matching local KV callbacks are removed before the native unsubscribe
  ///   request is launched.
  ///
  /// Invariants:
  /// - The calling Dart isolate is not blocked waiting for the Epiphany
  ///   response.
  Future<Result<bool>> unsubscribeFromKV({
    String? key,
    NamespaceSelector namespaceSelector =
        const NamespaceSelector.currentEntity(),
  }) async {
    return _unsubscribeFromItem(
      'unsubscribeFromKV',
      JsonFields.KV_NOTIFICATION,
      name: key,
      namespaceSelector: namespaceSelector,
      launchRequest: (int requestId) => _bridge.dpeUnsubscribeKVAsyncManaged(
        _nativeHandle,
        requestId,
        key: key,
        namespaceSelectorJson: jsonEncode(namespaceSelector.toJson()),
      ),
    );
  }

  /// Purpose: Dispose the wrapper and release its native resources.
  ///
  /// Parameters: None.
  ///
  /// Return value: `Future<void>` that completes after the event subscription is
  /// cancelled and the native handle is destroyed.
  ///
  /// Requirements/Preconditions: None. Calling more than once is allowed.
  ///
  /// Guarantees/Postconditions:
  /// - The internal `ReceivePort` is closed.
  /// - The native handle is destroyed.
  /// - Any still-pending Dart completers are completed with an error.
  ///
  /// Invariants:
  /// - After disposal, no further native requests may be launched.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    for (final Completer<Map<String, dynamic>> completer
        in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer
            .completeError(StateError('Native DogPawEntity was disposed.'));
      }
    }
    _pendingRequests.clear();

    _bridge.dpeDestroyManaged(_nativeHandle);
    await _eventSubscription.cancel();
    _receivePort.close();
    _savedCallbacks.clear();
    _entityLifecycleSubscriptions.clear();
    _pendingCommandAcceptedCallbacks.clear();
    _endpointNotificationCallback = null;
    _layoutStackNotificationCallback = null;
    _errorCallback = null;
    _directMessageCallback = null;
    _commandCallback = null;
    _presetRequestCallback = null;
    _debugProbeEventCallback = null;
  }

  /// Purpose: Run one native request that returns only success or failure.
  ///
  /// Parameters:
  /// - [methodName]: `String` logical method name used for diagnostics.
  /// - [launchRequest]: callback that launches the native request.
  ///
  /// Return value: `Future<Result<bool>>` indicating success or failure.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - [launchRequest] must launch a matching native request for the provided
  ///   id.
  ///
  /// Guarantees/Postconditions:
  /// - The returned result mirrors the native success/error outcome.
  ///
  /// Invariants:
  /// - One unique bridge request id is allocated per invocation.
  Future<Result<bool>> _runBooleanRequest(
    String methodName,
    bool Function(int requestId) launchRequest,
  ) async {
    try {
      final Map<String, dynamic> response =
          await _invokeRequest(methodName, launchRequest);
      if (response[JsonFields.SUCCESS] == true) {
        return Result<bool>.success(true);
      }
      return Result<bool>.error(
        response[JsonFields.ERROR] as String? ?? '$methodName failed',
      );
    } catch (exception) {
      return Result<bool>.error(exception.toString());
    }
  }

  /// Purpose: Decode an optional `Theme` from the standard bridge result
  /// payload.
  ///
  /// Parameters:
  /// - [response]: `Map<String, dynamic>` bridge request-result envelope.
  ///
  /// Return value: `Theme?` decoded from `result.theme`, or `null`.
  ///
  /// Requirements/Preconditions:
  /// - [response] follows the native bridge request-result envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - Returns a typed `Theme` when the payload contains one.
  ///
  /// Invariants:
  /// - This helper does not mutate [response].
  Theme? _decodeThemeFromResultPayload(Map<String, dynamic> response) {
    final Map<String, dynamic> result =
        Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
    if (!result.containsKey(JsonFields.THEME) ||
        result[JsonFields.THEME] == null) {
      return null;
    }
    return Theme.fromJson(
      Map<String, dynamic>.from(result[JsonFields.THEME] as Map),
    );
  }

  /// Purpose: Decode an optional `Layout` from the standard bridge result
  /// payload.
  ///
  /// Parameters:
  /// - [response]: `Map<String, dynamic>` bridge request-result envelope.
  ///
  /// Return value: `Layout?` decoded from `result.layout`, or `null`.
  ///
  /// Requirements/Preconditions:
  /// - [response] follows the native bridge request-result envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - Returns a typed `Layout` when the payload contains one.
  ///
  /// Invariants:
  /// - This helper does not mutate [response].
  Layout? _decodeLayoutFromResultPayload(Map<String, dynamic> response) {
    final Map<String, dynamic> result =
        Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
    if (!result.containsKey(JsonFields.LAYOUT) ||
        result[JsonFields.LAYOUT] == null) {
      return null;
    }
    return Layout.fromJson(
      Map<String, dynamic>.from(result[JsonFields.LAYOUT] as Map),
    );
  }

  /// Purpose: Decode an optional `KV` from the standard bridge result
  /// payload.
  ///
  /// Parameters:
  /// - [response]: `Map<String, dynamic>` bridge request-result envelope.
  ///
  /// Return value: `KV?` decoded from `result.kv`, or `null`.
  ///
  /// Requirements/Preconditions:
  /// - [response] follows the native bridge request-result envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - Returns a typed `KV` when the payload contains one.
  ///
  /// Invariants:
  /// - This helper does not mutate [response].
  KV? _decodeKVFromResultPayload(Map<String, dynamic> response) {
    final Map<String, dynamic> result =
        Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
    if (!result.containsKey(JsonFields.KV) || result[JsonFields.KV] == null) {
      return null;
    }
    return KV.fromJson(
      Map<String, dynamic>.from(result[JsonFields.KV] as Map),
    );
  }

  /// Purpose: Decode an optional `EndpointInfo` from the standard bridge result
  /// payload.
  ///
  /// Parameters:
  /// - [response]: `Map<String, dynamic>` bridge request-result envelope.
  ///
  /// Return value: `EndpointInfo?` decoded from `result.endpoint`, or `null`.
  ///
  /// Requirements/Preconditions:
  /// - [response] follows the native bridge request-result envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - Returns a typed `EndpointInfo` when the payload contains one.
  ///
  /// Invariants:
  /// - This helper does not mutate [response].
  EndpointInfo? _decodeEndpointFromResultPayload(
      Map<String, dynamic> response) {
    final Map<String, dynamic> result =
        Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
    if (!result.containsKey(JsonFields.ENDPOINT) ||
        result[JsonFields.ENDPOINT] == null) {
      return null;
    }
    return EndpointInfo.fromJson(
      Map<String, dynamic>.from(result[JsonFields.ENDPOINT] as Map),
    );
  }

  /// Purpose: Decode optional `ConnectionRequest` from bridge result payload.
  ///
  /// Parameters: [response] request-result envelope from native.
  ///
  /// Return value: decoded item or null.
  ///
  /// Requirements/Preconditions: envelope shape matches other read-* bridges.
  ///
  /// Invariants: does not mutate [response].
  ConnectionRequest? _decodeConnectionRequestFromResultPayload(
    Map<String, dynamic> response,
  ) {
    final Map<String, dynamic> result =
        Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
    if (!result.containsKey(JsonFields.CONNECTION_REQUEST_ITEM) ||
        result[JsonFields.CONNECTION_REQUEST_ITEM] == null) {
      return null;
    }
    return ConnectionRequest.fromJson(
      Map<String, dynamic>.from(
        result[JsonFields.CONNECTION_REQUEST_ITEM] as Map,
      ),
    );
  }

  /// Purpose: Decode optional `FollowRequest` from bridge result payload.
  ///
  /// Parameters: [response] request-result envelope from native.
  ///
  /// Return value: decoded item or null.
  ///
  /// Invariants: does not mutate [response].
  FollowRequest? _decodeFollowRequestFromResultPayload(
    Map<String, dynamic> response,
  ) {
    final Map<String, dynamic> result =
        Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
    if (!result.containsKey(JsonFields.FOLLOW_REQUEST_ITEM) ||
        result[JsonFields.FOLLOW_REQUEST_ITEM] == null) {
      return null;
    }
    return FollowRequest.fromJson(
      Map<String, dynamic>.from(result[JsonFields.FOLLOW_REQUEST_ITEM] as Map),
    );
  }

  /// Purpose: Decode optional realized `Connection` from bridge result.
  ///
  /// Parameters: [response] request-result envelope from native.
  ///
  /// Return value: decoded connection or null.
  ///
  /// Invariants: does not mutate [response].
  Connection? _decodeConnectionFromResultPayload(
    Map<String, dynamic> response,
  ) {
    final Map<String, dynamic> result =
        Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
    if (!result.containsKey(JsonFields.CONNECTION) ||
        result[JsonFields.CONNECTION] == null) {
      return null;
    }
    return Connection.fromJson(
      Map<String, dynamic>.from(result[JsonFields.CONNECTION] as Map),
    );
  }

  /// Purpose: Decode an optional `Scale` from the standard bridge result
  /// payload.
  ///
  /// Parameters:
  /// - [response]: `Map<String, dynamic>` bridge request-result envelope.
  ///
  /// Return value: `Scale?` decoded from `result.scale`, or `null`.
  ///
  /// Requirements/Preconditions:
  /// - [response] follows the native bridge request-result envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - Returns a typed `Scale` when the payload contains one.
  ///
  /// Invariants:
  /// - This helper does not mutate [response].
  Scale? _decodeScaleFromResultPayload(Map<String, dynamic> response) {
    final Map<String, dynamic> result =
        Map<String, dynamic>.from(response[JsonFields.RESULT] as Map);
    if (!result.containsKey(JsonFields.SCALE) ||
        result[JsonFields.SCALE] == null) {
      return null;
    }
    return Scale.fromJson(
      Map<String, dynamic>.from(result[JsonFields.SCALE] as Map),
    );
  }

  /// Purpose: Launch one bridge request and await its posted response envelope.
  ///
  /// Parameters:
  /// - [methodName]: `String` logical method name used for diagnostics.
  /// - [launchRequest]: callback that starts the native async request using the
  ///   allocated bridge request id.
  /// - [onRequestStarted]: optional callback invoked after the request id is
  ///   allocated and before the native launch attempt.
  ///
  /// Return value: `Future<Map<String, dynamic>>` resolving with the posted
  /// request-result envelope.
  ///
  /// Requirements/Preconditions:
  /// - The wrapper has not been disposed.
  /// - [launchRequest] must launch a matching native request for the provided
  ///   id.
  ///
  /// Guarantees/Postconditions:
  /// - The returned future completes when the matching native request-result
  ///   envelope arrives.
  ///
  /// Invariants:
  /// - One unique bridge request id is allocated per invocation.
  Future<Map<String, dynamic>> _invokeRequest(
    String methodName,
    bool Function(int requestId) launchRequest, {
    void Function(int requestId)? onRequestStarted,
  }) async {
    _ensureNotDisposed();
    final int requestId = _requestCounter++;
    onRequestStarted?.call(requestId);
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;

    final bool launched = launchRequest(requestId);
    if (!launched) {
      AppLogger.warning(
        'DPE_FFI: native request not launched method=$methodName '
            'requestId=$requestId entity=$_entityName',
        'DPE_FFI',
      );
      _pendingRequests.remove(requestId);
      _pendingCommandAcceptedCallbacks.remove(requestId);
      return <String, dynamic>{
        JsonFields.EVENT_TYPE: 'requestResult',
        JsonFields.REQUEST_ID: requestId,
        JsonFields.METHOD: methodName,
        JsonFields.SUCCESS: false,
        JsonFields.ERROR: 'Failed to launch native $methodName request.',
        JsonFields.RESULT: <String, dynamic>{},
      };
    }

    return completer.future;
  }

  /// Purpose: Dispatch one native subscription notification to local Dart
  /// callbacks.
  ///
  /// Parameters:
  /// - [event]: `Map<String, dynamic>` decoded native event envelope.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - [event] follows the native subscription-notification envelope shape with
  ///   `topic` and `result` fields.
  ///
  /// Guarantees/Postconditions:
  /// - Matching callbacks in [_savedCallbacks] are invoked with decoded item
  ///   payloads.
  ///
  /// Invariants:
  /// - Unknown or malformed subscription envelopes are ignored.
  void _handleSubscriptionNotification(Map<String, dynamic> event) {
    final String topic = event[JsonFields.TOPIC] as String? ?? '';
    if (topic.isEmpty) {
      return;
    }

    final dynamic rawResult = event[JsonFields.RESULT];
    if (rawResult is! Map) {
      return;
    }
    final Map<String, dynamic> messageContent =
        Map<String, dynamic>.from(rawResult);

    if (topic == Topics.ENDPOINT_NOTIFICATION) {
      final void Function(Map<String, dynamic> message)? callback =
          _endpointNotificationCallback;
      if (callback != null) {
        try {
          callback(messageContent);
        } catch (_) {
          // Keep native event dispatch resilient to callback failures.
        }
      }
    }

    if (topic == Topics.LAYOUT_STACK_NOTIFICATION) {
      final void Function(Map<String, dynamic> message)? callback =
          _layoutStackNotificationCallback;
      if (callback != null) {
        try {
          callback(messageContent);
        } catch (_) {
          // Keep native event dispatch resilient to callback failures.
        }
      }
    }

    SubscriptionKey subscriptionKey;
    try {
      final DataItemRef itemRef = DataItemRef.fromJson(messageContent);
      subscriptionKey = SubscriptionKey.fromDataItemRef(topic, itemRef);
    } catch (_) {
      subscriptionKey = SubscriptionKey(topic);
    }

    final List<CallbackInfo> callbacksToRemove = <CallbackInfo>[];
    final List<dynamic> values = <dynamic>[];
    final List<DataItemRef> dataItemRefs = <DataItemRef>[];
    bool valuesInitialized = false;
    final String notificationType =
        messageContent[JsonFields.NOTIFICATION_TYPE] as String? ?? '';

    for (final CallbackInfo callbackInfo in _savedCallbacks) {
      if (!callbackInfo.matchesAndRemove(subscriptionKey)) {
        continue;
      }

      if (!valuesInitialized) {
        if (messageContent.containsKey(callbackInfo.valueJsonKey)) {
          values.add(messageContent[callbackInfo.valueJsonKey]);
          dataItemRefs.add(
              DataItemRef.fromJson(messageContent[callbackInfo.valueJsonKey]));
        } else if (messageContent
            .containsKey('${callbackInfo.valueJsonKey}s')) {
          for (final dynamic value
              in messageContent['${callbackInfo.valueJsonKey}s'] as List) {
            values.add(value);
            dataItemRefs
                .add(DataItemRef.fromJson(value as Map<String, dynamic>));
          }
        }
        valuesInitialized = true;
      }

      try {
        for (int index = 0; index < values.length; index++) {
          callbackInfo.handler(
              notificationType, dataItemRefs[index], values[index]);
        }
      } catch (_) {
        // Keep native event dispatch resilient to callback failures.
      }

      if (callbackInfo.keys.isEmpty) {
        callbacksToRemove.add(callbackInfo);
      }
    }

    for (final CallbackInfo callbackInfo in callbacksToRemove) {
      _savedCallbacks.remove(callbackInfo);
    }
  }

  /// Purpose: Dispatch one native entity lifecycle envelope to matching Dart
  /// callbacks.
  ///
  /// Parameters:
  /// - [event]: `Map<String, dynamic>` bridge event containing `result` with
  ///   `notificationType` and `entityName`.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - [event] follows the native entity-lifecycle event envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - Matching stored lifecycle callbacks are invoked once each.
  ///
  /// Invariants:
  /// - Malformed events are ignored rather than throwing into the event loop.
  void _handleEntityLifecycleNotification(Map<String, dynamic> event) {
    final Map<String, dynamic> result = Map<String, dynamic>.from(
        event[JsonFields.RESULT] as Map? ?? <String, dynamic>{});
    final String? notificationType =
        result[JsonFields.NOTIFICATION_TYPE] as String?;
    final String? entityName = result[JsonFields.ENTITY_NAME] as String?;
    if (notificationType == null || entityName == null) {
      return;
    }

    final List<void Function(String, String)> callbacksToInvoke =
        <void Function(String, String)>[];
    for (final _NativeEntityLifecycleSubscription subscription
        in _entityLifecycleSubscriptions) {
      final bool watchAll = subscription.watchEntityName == null;
      if (watchAll || subscription.watchEntityName == entityName) {
        callbacksToInvoke.add(subscription.callback);
      }
    }

    for (final void Function(String, String) callback in callbacksToInvoke) {
      try {
        callback(notificationType, entityName);
      } catch (_) {
        // Keep native event dispatch resilient to callback failures.
      }
    }
  }

  /// Purpose: Forward one native direct-message envelope to the configured Dart
  /// callback.
  ///
  /// Parameters:
  /// - [event]: `Map<String, dynamic>` bridge event containing `result` with
  ///   `senderEntity` and `message`.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - [event] follows the native direct-message event envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - When a direct-message callback is configured, it receives the sender and
  ///   message payload.
  ///
  /// Invariants:
  /// - Missing callbacks or malformed payloads are ignored.
  void _handleDirectMessageEvent(Map<String, dynamic> event) {
    final Function(String senderEntity, Map<String, dynamic> content)?
        callback = _directMessageCallback;
    if (callback == null) {
      return;
    }

    final Map<String, dynamic> result = Map<String, dynamic>.from(
      event[JsonFields.RESULT] as Map? ?? <String, dynamic>{},
    );
    final String? senderEntity = result[JsonFields.SENDER_ENTITY] as String?;
    final dynamic rawMessage = result[JsonFields.MESSAGE];
    if (senderEntity == null || rawMessage is! Map) {
      return;
    }

    callback(senderEntity, Map<String, dynamic>.from(rawMessage));
  }

  /// Purpose: Forward one native incoming-command envelope to the configured
  /// Dart callback or issue the default error response when none is configured.
  ///
  /// Parameters:
  /// - [event]: `Map<String, dynamic>` bridge event containing `result` with
  ///   sender, command, params, and command id.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - [event] follows the native incoming-command event envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - Matching command handlers are invoked with the posted payload.
  /// - When no handler is configured, a failure response is sent back to the
  ///   original sender when possible.
  ///
  /// Invariants:
  /// - Malformed payloads are ignored instead of throwing into the event loop.
  void _handleIncomingCommandEvent(Map<String, dynamic> event) {
    final Map<String, dynamic> result = Map<String, dynamic>.from(
      event[JsonFields.RESULT] as Map? ?? <String, dynamic>{},
    );
    final String senderEntity =
        result[JsonFields.SENDER_ENTITY] as String? ?? '';
    final String command = result[JsonFields.COMMAND] as String? ?? '';
    final String commandId = result[JsonFields.COMMAND_ID] as String? ?? '';
    final Map<String, dynamic> params = Map<String, dynamic>.from(
      result[JsonFields.PARAMS] as Map? ?? <String, dynamic>{},
    );

    if (command.isEmpty) {
      if (commandId.isNotEmpty && senderEntity.isNotEmpty) {
        sendCommandResponse(
          senderEntity,
          commandId,
          success: false,
          errorMessage: 'Empty command name',
        );
      }
      return;
    }

    final Function(
        String senderEntity,
        String command,
        Map<String, dynamic> params,
        String commandId)? callback = _commandCallback;
    if (callback != null) {
      callback(senderEntity, command, params, commandId);
      return;
    }

    if (commandId.isNotEmpty && senderEntity.isNotEmpty) {
      sendCommandResponse(
        senderEntity,
        commandId,
        success: false,
        errorMessage: 'No command handler registered',
      );
    }
  }

  /// Purpose: Forward one native preset-request envelope to the configured Dart
  /// callback and auto-complete it according to the existing Dart contract.
  ///
  /// Parameters:
  /// - [event]: `Map<String, dynamic>` bridge event containing `result` with the
  ///   preset request payload.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - [event] follows the native preset-request event envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - When no preset callback is configured, the request is auto-completed with
  ///   success.
  /// - When the callback returns `true`, the request is auto-completed with
  ///   success.
  /// - When the callback throws, the request is auto-completed with failure.
  ///
  /// Invariants:
  /// - Callback work runs asynchronously so the native event loop is not
  ///   blocked on Dart awaiting logic.
  void _handlePresetRequestEvent(Map<String, dynamic> event) {
    final Map<String, dynamic> content = Map<String, dynamic>.from(
      event[JsonFields.RESULT] as Map? ?? <String, dynamic>{},
    );
    final String? serverRequestId =
        content[JsonFields.SERVER_REQUEST_ID] as String?;
    if (serverRequestId == null) {
      return;
    }

    final Future<bool> Function(String, Map<String, dynamic>)? callback =
        _presetRequestCallback;
    if (callback == null) {
      unawaited(completePresetRequest(serverRequestId, success: true));
      return;
    }

    unawaited(Future<void>(() async {
      try {
        final bool shouldCompleteNow = await callback(serverRequestId, content);
        if (shouldCompleteNow) {
          await completePresetRequest(serverRequestId, success: true);
        }
      } catch (exception) {
        await completePresetRequest(
          serverRequestId,
          success: false,
          errorMessage: exception.toString(),
        );
      }
    }));
  }

  /// Purpose: Forward one native accepted notification to the stored Dart
  /// callback for the originating `sendCommand()` request.
  ///
  /// Parameters:
  /// - [event]: `Map<String, dynamic>` bridge event containing `requestId` and
  ///   accepted `result`.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - [event] follows the native command-accepted event envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - When an accepted callback is registered for the request id, it receives
  ///   the accepted result payload.
  ///
  /// Invariants:
  /// - Missing callbacks or malformed payloads are ignored.
  void _handleCommandAcceptedEvent(Map<String, dynamic> event) {
    final int? requestId = event[JsonFields.REQUEST_ID] as int?;
    if (requestId == null) {
      return;
    }

    final OnAcceptedCallback? callback =
        _pendingCommandAcceptedCallbacks[requestId];
    if (callback == null) {
      return;
    }

    final Map<String, dynamic> resultPayload = Map<String, dynamic>.from(
      event[JsonFields.RESULT] as Map? ?? <String, dynamic>{},
    );
    callback(resultPayload);
  }

  /// Purpose: Forward one native async error envelope to the configured Dart
  /// error callback.
  ///
  /// Parameters:
  /// - [event]: `Map<String, dynamic>` bridge event containing `message`.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - [event] follows the native error-event envelope shape.
  ///
  /// Guarantees/Postconditions:
  /// - When an error callback is configured, it receives the bridge message.
  ///
  /// Invariants:
  /// - Missing callbacks or malformed messages are ignored.
  void _handleErrorEvent(Map<String, dynamic> event) {
    final String? message = event[JsonFields.MESSAGE] as String?;
    if (Platform.environment['DPE_FFI_TRACE'] == '1' &&
        message != null &&
        message.isNotEmpty) {
      AppLogger.warning(
        'DPE_FFI: native async error event entity=$_entityName message=$message',
        'DPE_FFI',
      );
    }
    final Function(String error)? callback = _errorCallback;
    if (message == null || callback == null) {
      return;
    }

    try {
      callback(message);
    } catch (_) {
      // Keep native event dispatch resilient to callback failures.
    }
  }

  /// Purpose: Process one JSON envelope posted from the native bridge.
  ///
  /// Parameters:
  /// - [event]: `dynamic` message received from the internal `ReceivePort`.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions:
  /// - [event] is expected to be a JSON string emitted by the native bridge.
  ///
  /// Guarantees/Postconditions:
  /// - Matching pending completers are resolved for `requestResult` envelopes.
  ///
  /// Invariants:
  /// - Unknown event types are ignored rather than throwing into the event loop.
  void _handleNativeEvent(dynamic event) {
    if (event is! String) {
      return;
    }

    final Map<String, dynamic> decoded =
        Map<String, dynamic>.from(jsonDecode(event) as Map);
    final String eventType = decoded[JsonFields.EVENT_TYPE] as String? ?? '';
    if (eventType == 'requestResult') {
      final int requestId = decoded[JsonFields.REQUEST_ID] as int;
      _pendingCommandAcceptedCallbacks.remove(requestId);
      final Completer<Map<String, dynamic>>? completer =
          _pendingRequests.remove(requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(decoded);
      }
      return;
    }

    if (eventType == 'subscriptionNotification') {
      _handleSubscriptionNotification(decoded);
      return;
    }

    if (eventType == 'entityLifecycleNotification') {
      _handleEntityLifecycleNotification(decoded);
      return;
    }

    if (eventType == 'directMessage') {
      _handleDirectMessageEvent(decoded);
      return;
    }

    if (eventType == 'incomingCommand') {
      _handleIncomingCommandEvent(decoded);
      return;
    }

    if (eventType == 'commandAccepted') {
      _handleCommandAcceptedEvent(decoded);
      return;
    }

    if (eventType == 'presetRequest') {
      _handlePresetRequestEvent(decoded);
      return;
    }

    if (eventType == 'debugProbe') {
      final void Function(Map<String, dynamic> event)? callback =
          _debugProbeEventCallback;
      if (callback != null) {
        callback(decoded);
      }
      return;
    }

    if (eventType == 'error') {
      _handleErrorEvent(decoded);
    }
  }

  /// Purpose: Enumerate realized native input connection names for one local
  /// endpoint.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  ///
  /// Return value:
  /// - `List<String>` of currently realized connection names.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Returns an empty list when the native endpoint reports no connections or
  ///   an error.
  ///
  /// Invariants:
  /// - This helper does not mutate wrapper state.
  List<String> _listLocalEndpointConnections(String endpointName) {
    final int connectionCount =
        _bridge.dpeLocalEndpointGetConnectionCountManaged(
      _nativeHandle,
      endpointName: endpointName,
    );
    if (connectionCount <= 0) {
      return <String>[];
    }

    final List<String> connectionNames = <String>[];
    for (int index = 0; index < connectionCount; index++) {
      final int requiredSize = _bridge.dpeLocalEndpointGetConnectionNameManaged(
        _nativeHandle,
        endpointName: endpointName,
        index: index,
        maxSize: 0,
      );
      if (requiredSize <= 0) {
        continue;
      }

      final Pointer<Utf8> namePtr = malloc<Uint8>(requiredSize).cast<Utf8>();
      try {
        final int writeResult =
            _bridge.dpeLocalEndpointGetConnectionNameManaged(
          _nativeHandle,
          endpointName: endpointName,
          index: index,
          outName: namePtr,
          maxSize: requiredSize,
        );
        if (writeResult > 0) {
          connectionNames.add(namePtr.toDartString());
        }
      } finally {
        malloc.free(namePtr);
      }
    }

    return connectionNames;
  }

  /// Purpose: Query the current native payload shape for one realized local
  /// endpoint connection.
  ///
  /// Parameters:
  /// - [endpointName]: `String` owned endpoint name in the current entity.
  /// - [connectionName]: `String` realized connection identifier.
  ///
  /// Return value:
  /// - `_NativeConnectionShape` on success, or `null` on error.
  ///
  /// Requirements/Preconditions:
  /// - This wrapper has not been disposed.
  ///
  /// Guarantees/Postconditions:
  /// - Returned shape matches the native endpoint runtime at call time.
  ///
  /// Invariants:
  /// - This helper does not mutate wrapper state.
  _NativeConnectionShape? _getLocalEndpointConnectionShape(
    String endpointName,
    String connectionName,
  ) {
    final Pointer<Int32> indexTypePtr = malloc<Int32>();
    final Pointer<Int32> indexDim1Ptr = malloc<Int32>();
    final Pointer<Int32> indexDim2Ptr = malloc<Int32>();
    final Pointer<Int32> payloadSizePtr = malloc<Int32>();
    try {
      final bool success = _bridge.dpeLocalEndpointGetConnectionShapeManaged(
        _nativeHandle,
        endpointName: endpointName,
        connectionName: connectionName,
        outIndexType: indexTypePtr,
        outIndexDim1: indexDim1Ptr,
        outIndexDim2: indexDim2Ptr,
        outPayloadSize: payloadSizePtr,
      );
      if (!success) {
        return null;
      }

      final int indexType = indexTypePtr.value;
      final int indexDim1 = indexDim1Ptr.value;
      final int indexDim2 = indexDim2Ptr.value;
      final int payloadSize = payloadSizePtr.value;

      final IndexSpec indexSpec;
      switch (indexType) {
        case DPPBIndexType.key:
          indexSpec = IndexSpecKey(indexDim1, indexDim2);
          break;
        case DPPBIndexType.voice:
          indexSpec = IndexSpecVoice(indexDim1);
          break;
        default:
          indexSpec = const IndexSpecNone();
          break;
      }

      return _NativeConnectionShape(
        indexSpec: indexSpec,
        payloadSize: payloadSize,
      );
    } finally {
      malloc.free(indexTypePtr);
      malloc.free(indexDim1Ptr);
      malloc.free(indexDim2Ptr);
      malloc.free(payloadSizePtr);
    }
  }

  /// Purpose: Guard methods against use-after-dispose.
  ///
  /// Parameters: None.
  ///
  /// Return value: None.
  ///
  /// Requirements/Preconditions: None.
  ///
  /// Guarantees/Postconditions:
  /// - Throws `StateError` when the wrapper has already been disposed.
  ///
  /// Invariants:
  /// - This helper never mutates the wrapper state.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('NativeDogPawEntityClient has already been disposed.');
    }
  }
}
