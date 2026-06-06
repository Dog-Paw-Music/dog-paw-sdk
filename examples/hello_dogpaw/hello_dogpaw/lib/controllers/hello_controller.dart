import 'dart:async';

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/foundation.dart';

/// Purpose:
///     UI-selectable highlight state families for the hello example.
/// Parameters:
///     None.
/// Return value:
///     Enum values naming the active and pressed retained-highlight colors.
/// Requirements:
///     None.
/// Guarantees:
///     Keeps controller/UI state mapping explicit without exposing raw key-state
///     details to the widget tree.
/// Invariants:
///     `rest` is intentionally absent because rest clears highlights instead of
///     owning a configurable color.
enum HelloHighlightState {
  active,
  pressed,
}

/// Purpose:
///     Immutable swatch metadata for the hello example's small color picker.
/// Parameters:
///     label: User-facing swatch name.
///     colorArgb: Packed AARRGGBB color sent through the LED wire surface.
/// Return value:
///     One selectable swatch description.
/// Requirements:
///     `colorArgb` must be a valid 32-bit packed ARGB value.
/// Guarantees:
///     Instances are safe to reuse across controller and widget rebuilds.
/// Invariants:
///     Swatches carry no runtime endpoint state.
class HelloColorSwatch {
  /// Purpose:
  ///     Construct one named hello-example color swatch.
  /// Parameters:
  ///     label: User-facing swatch name.
  ///     colorArgb: Packed AARRGGBB color value.
  /// Return value:
  ///     New immutable swatch instance.
  /// Requirements:
  ///     `label` should be non-empty for readable UI copy.
  /// Guarantees:
  ///     Stores the supplied label and color unchanged.
  /// Invariants:
  ///     Instances are immutable after construction.
  const HelloColorSwatch({
    required this.label,
    required this.colorArgb,
  });

  final String label;
  final int colorArgb;
}

/// Purpose:
///     Build the hello example's auto-connected key-message endpoint metadata.
/// Parameters:
///     None.
/// Return value:
///     EndpointInfo describing an input message queue connected to
///     `BladeHW::key_press`.
/// Requirements:
///     None.
/// Guarantees:
///     The returned endpoint follows the same auto-connect search pattern used by
///     other key-driven apps.
/// Invariants:
///     This helper is pure and does not contact the runtime.
dp.EndpointInfo buildHelloKeyInputEndpointInfo() {
  final dp.SearchCriteria criteria = dp.SearchCriteria.andCombination([
    dp.SearchCriteria.fromCondition('direction', 'equals', 'output'),
    dp.SearchCriteria.fromCondition('name', 'equals', 'key_press'),
    dp.SearchCriteria.fromCondition('sourceEntity', 'equals', 'BladeHW'),
    dp.SearchCriteria.fromCondition('baseType', 'equals', 'key_press'),
  ]);

  final dp.EndpointSpec spec = dp.EndpointSpec(
    displayName: 'Hello Key Input',
    description: 'Receives key_press events from BladeHW',
    direction: dp.EndpointDirection.input,
    dataType: const dp.DataTypeSpec(dp.DataType.keyPress),
    category: dp.EndpointCategory.messageQueue,
    connectionPolicy: dp.ConnectionPolicy(autoConnectCriteria: criteria),
  );

  return dp.EndpointInfo(name: 'key_input', spec: spec);
}

/// Purpose:
///     Build the hello example's auto-connected LED output endpoint metadata.
/// Parameters:
///     None.
/// Return value:
///     EndpointInfo describing an output message queue connected to
///     `LEDComms::led_message_input`.
/// Requirements:
///     None.
/// Guarantees:
///     The returned endpoint speaks the public `DataType.ledMessage` contract.
/// Invariants:
///     This helper is pure and does not contact the runtime.
dp.EndpointInfo buildHelloLedOutputEndpointInfo() {
  final dp.SearchCriteria criteria = dp.SearchCriteria.andCombination([
    dp.SearchCriteria.fromCondition('direction', 'equals', 'input'),
    dp.SearchCriteria.fromCondition('name', 'equals', 'led_message_input'),
    dp.SearchCriteria.fromCondition('sourceEntity', 'equals', 'LEDComms'),
    dp.SearchCriteria.fromCondition('baseType', 'equals', 'led_message'),
  ]);

  final dp.EndpointSpec spec = dp.EndpointSpec(
    displayName: 'Hello LED Output',
    description: 'Sends LED messages to LEDComms',
    direction: dp.EndpointDirection.output,
    dataType: const dp.DataTypeSpec(dp.DataType.ledMessage),
    category: dp.EndpointCategory.messageQueue,
    connectionPolicy: dp.ConnectionPolicy(autoConnectCriteria: criteria),
  );

  return dp.EndpointInfo(name: 'led_output', spec: spec);
}

/// Purpose:
///     Controller for the hello example's startup connection and LED demo logic.
/// Parameters:
///     client: Runtime adapter used for connect/create-endpoint/disconnect work.
///     pollInterval: Queue polling cadence for the key-message endpoint.
/// Return value:
///     Controller ready to auto-start and react to key events.
/// Requirements:
///     `client` must remain valid for the lifetime of this controller.
/// Guarantees:
///     Keeps runtime work, LED state tracking, and color selection out of the
///     widget layer.
/// Invariants:
///     Each key owns at most one retained highlight animation id at a time.
class HelloController extends ChangeNotifier {
  /// Purpose:
  ///     Construct the hello-example controller with its runtime dependencies.
  /// Parameters:
  ///     client: Runtime adapter used by `start()`.
  ///     pollInterval: Queue polling cadence for key-message input.
  /// Return value:
  ///     New `HelloController` instance.
  /// Requirements:
  ///     `pollInterval` should be positive.
  /// Guarantees:
  ///     The controller starts disconnected with default active/pressed colors.
  /// Invariants:
  ///     The injected client reference never changes after construction.
  HelloController({
    required HelloDogPawClient client,
    Duration pollInterval = const Duration(milliseconds: 30),
  }) : _client = client,
       _pollInterval = pollInterval;

  static const List<HelloColorSwatch> _availableSwatches = <HelloColorSwatch>[
    HelloColorSwatch(label: 'Black', colorArgb: 0xFF000000),
    HelloColorSwatch(label: 'Deep Purple', colorArgb: 0xFF673AB7),
    HelloColorSwatch(label: 'Teal', colorArgb: 0xFF009688),
    HelloColorSwatch(label: 'Amber', colorArgb: 0xFFFFC107),
  ];

  final HelloDogPawClient _client;
  final Duration _pollInterval;
  final dp.LedClientAnimIdAllocator _animIdAllocator =
      dp.LedClientAnimIdAllocator();
  final Map<_HelloKeyPosition, _HelloAnimationEntry> _animations =
      <_HelloKeyPosition, _HelloAnimationEntry>{};

  dp.LocalEndpoint? _keyInputEndpoint;
  dp.LocalEndpoint? _ledOutputEndpoint;
  Timer? _pollTimer;

  bool _isStarting = false;
  bool _isReady = false;
  String _statusMessage = 'Starting Dog Paw connection...';
  int _activeColorArgb = 0xFF673AB7;
  int _pressedColorArgb = 0xFF009688;

  /// Purpose:
  ///     Whether startup connection and endpoint setup are still in progress.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     `true` while `start()` is running.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Read-only snapshot of controller startup state.
  /// Invariants:
  ///     Accessing this getter causes no side effects.
  bool get isStarting => _isStarting;

  /// Purpose:
  ///     Whether the hello example is ready to process key messages.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     `true` after connect and both endpoint creations succeed.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Read-only snapshot of runtime readiness.
  /// Invariants:
  ///     Accessing this getter causes no side effects.
  bool get isReady => _isReady;

  /// Purpose:
  ///     User-facing startup or error text for the hello example.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     Current status line shown by the UI.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Always returns a non-empty string.
  /// Invariants:
  ///     Accessing this getter causes no side effects.
  String get statusMessage => _statusMessage;

  /// Purpose:
  ///     Shared list of selectable swatches for the active/pressed rows.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     Immutable swatch list reused by the UI.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Returns the same four-swatch palette for each call.
  /// Invariants:
  ///     Callers must treat the returned list as read-only.
  List<HelloColorSwatch> get availableSwatches => _availableSwatches;

  /// Purpose:
  ///     Return the currently selected highlight color for one UI row.
  /// Parameters:
  ///     state: Highlight family whose configured color is requested.
  /// Return value:
  ///     Packed AARRGGBB color for the requested row.
  /// Requirements:
  ///     `state` must be one of the supported hello-example highlight families.
  /// Guarantees:
  ///     Returns the live controller value reflected in the UI.
  /// Invariants:
  ///     Accessing this getter causes no side effects.
  int colorForState(HelloHighlightState state) {
    return switch (state) {
      HelloHighlightState.active => _activeColorArgb,
      HelloHighlightState.pressed => _pressedColorArgb,
    };
  }

  /// Purpose:
  ///     Start the hello example by connecting and creating its two endpoints.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     Completes when startup succeeds or the failure status is recorded.
  /// Requirements:
  ///     Safe to call more than once; concurrent or already-ready calls are
  ///     ignored.
  /// Guarantees:
  ///     On success, polling starts and the connection ready handle is completed.
  ///     On failure, the ready handle is completed with an error when present.
  /// Invariants:
  ///     Leaves the controller in a non-starting state before returning.
  Future<void> start() async {
    if (_isStarting || _isReady) {
      return;
    }

    _isStarting = true;
    _statusMessage = 'Connecting to Dog Paw...';
    notifyListeners();

    dp.ConnectionHandle? handle;
    try {
      final dp.ConnectionResult result = await _client.connect();
      if (!result.success) {
        _statusMessage = 'Connection failed: ${result.error}';
        return;
      }

      handle = result.handle;
      final dp.Result<dp.LocalEndpoint> keyInputResult =
          await _client.createEndpoint(buildHelloKeyInputEndpointInfo());
      if (!keyInputResult.isSuccess) {
        throw StateError(
          'Failed to create key input endpoint: ${keyInputResult.getError()}',
        );
      }
      _keyInputEndpoint = keyInputResult.getValue();

      final dp.Result<dp.LocalEndpoint> ledOutputResult =
          await _client.createEndpoint(buildHelloLedOutputEndpointInfo());
      if (!ledOutputResult.isSuccess) {
        throw StateError(
          'Failed to create LED output endpoint: ${ledOutputResult.getError()}',
        );
      }
      _ledOutputEndpoint = ledOutputResult.getValue();

      _startPolling();
      _isReady = true;
      _statusMessage = 'Connected and listening for key events.';
      if (handle != null) {
        await handle.complete();
      }
    } catch (error) {
      _statusMessage = 'Startup failed: $error';
      if (handle != null) {
        handle.setReadyMessage(dp.ConnectionReadyMessageType.error);
        await handle.complete();
      }
    } finally {
      _isStarting = false;
      notifyListeners();
    }
  }

  /// Purpose:
  ///     Process every queued key event currently waiting on the input endpoint.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     Safe to call before startup finishes; such calls become no-ops.
  /// Guarantees:
  ///     Each queued `dp.KeyEvent` is consumed exactly once and translated into
  ///     retained LED create/update/cancel commands.
  /// Invariants:
  ///     Ignores non-key payloads instead of throwing.
  void processPendingKeyEvents() {
    final dp.LocalEndpoint? endpoint = _keyInputEndpoint;
    if (endpoint == null) {
      return;
    }

    List<dynamic> batch;
    do {
      batch = endpoint.poll();
      for (final dynamic message in batch) {
        if (message is dp.KeyEvent) {
          _processKeyEvent(message);
        }
      }
    } while (batch.isNotEmpty);
  }

  /// Purpose:
  ///     Update one UI-controlled highlight color and refresh matching live keys.
  /// Parameters:
  ///     state: Highlight family being edited.
  ///     colorArgb: New packed AARRGGBB color to use.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `colorArgb` must be a valid 32-bit packed ARGB color.
  /// Guarantees:
  ///     Future key events use the new color, and any currently matching retained
  ///     highlights are updated in place.
  /// Invariants:
  ///     Does not create or remove key animations by itself.
  void selectColor(HelloHighlightState state, int colorArgb) {
    final int currentColor = colorForState(state);
    if (currentColor == colorArgb) {
      return;
    }

    switch (state) {
      case HelloHighlightState.active:
        _activeColorArgb = colorArgb;
        break;
      case HelloHighlightState.pressed:
        _pressedColorArgb = colorArgb;
        break;
    }

    for (final _HelloAnimationEntry entry in _animations.values) {
      if (_highlightStateForKeyState(entry.keyState) != state) {
        continue;
      }
      entry.colorArgb = colorArgb;
      _writeLedMessage(
        dp.AnimationColorUpdateLEDMessage(
          clientInstanceId: entry.animationId,
          colorArgb: colorArgb,
        ),
      );
    }

    notifyListeners();
  }

  /// Purpose:
  ///     Cancel polling and release the runtime adapter during app teardown.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     Safe to call once through Flutter's dispose lifecycle.
  /// Guarantees:
  ///     Polling stops, tracked animations are discarded, and the client
  ///     disconnects before superclass cleanup.
  /// Invariants:
  ///     Does not notify listeners during disposal.
  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _animations.clear();
    _client.disconnect();
    super.dispose();
  }

  /// Purpose:
  ///     Start the periodic poll loop once the key input endpoint exists.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     Safe to call more than once.
  /// Guarantees:
  ///     At most one active timer exists after this method returns.
  /// Invariants:
  ///     The timer only delegates to `processPendingKeyEvents()`.
  void _startPolling() {
    if (_pollTimer != null && _pollTimer!.isActive) {
      return;
    }

    _pollTimer = Timer.periodic(_pollInterval, (_) {
      processPendingKeyEvents();
    });
  }

  /// Purpose:
  ///     Translate one decoded Dog Paw key event into LED state changes.
  /// Parameters:
  ///     message: One queued key event from `BladeHW::key_press`.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `message` must describe one valid key coordinate and new state.
  /// Guarantees:
  ///     Activated/pressed states ensure a retained highlight exists, while rest
  ///     clears any tracked highlight for that key.
  /// Invariants:
  ///     Uses only the key's latest state and stored animation id.
  void _processKeyEvent(dp.KeyEvent message) {
    final _HelloKeyPosition key = _HelloKeyPosition(
      message.column,
      message.row,
    );

    switch (message.newState) {
      case dp.KeyState.activated:
        _ensureHighlight(
          key: key,
          keyState: dp.KeyState.activated,
          colorArgb: _activeColorArgb,
        );
        break;
      case dp.KeyState.pressed:
        _ensureHighlight(
          key: key,
          keyState: dp.KeyState.pressed,
          colorArgb: _pressedColorArgb,
        );
        break;
      case dp.KeyState.rest:
        _clearHighlight(key);
        break;
    }
  }

  /// Purpose:
  ///     Ensure one key has a retained highlight with the requested state color.
  /// Parameters:
  ///     key: Grid coordinate whose retained animation should exist.
  ///     keyState: Latest semantic key state for that animation.
  ///     colorArgb: Packed AARRGGBB highlight color for the retained animation.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `colorArgb` must be valid and `_ledOutputEndpoint` must already exist to
  ///     emit runtime effects.
  /// Guarantees:
  ///     Creates a highlight when none exists, otherwise updates the retained
  ///     animation color in place.
  /// Invariants:
  ///     Reuses the existing animation id for a key whenever possible.
  void _ensureHighlight({
    required _HelloKeyPosition key,
    required dp.KeyState keyState,
    required int colorArgb,
  }) {
    final _HelloAnimationEntry? existing = _animations[key];
    if (existing == null) {
      final int animationId = _animIdAllocator.next();
      _animations[key] = _HelloAnimationEntry(
        animationId: animationId,
        keyState: keyState,
        colorArgb: colorArgb,
      );
      _writeLedMessage(
        dp.KeyHighlightLEDMessage(
          column: key.column,
          row: key.row,
          colorArgb: colorArgb,
          clientInstanceId: animationId,
        ),
      );
      return;
    }

    if (existing.keyState == keyState && existing.colorArgb == colorArgb) {
      return;
    }

    existing.keyState = keyState;
    existing.colorArgb = colorArgb;
    _writeLedMessage(
      dp.AnimationColorUpdateLEDMessage(
        clientInstanceId: existing.animationId,
        colorArgb: colorArgb,
      ),
    );
  }

  /// Purpose:
  ///     Remove one tracked retained highlight and emit its cancel message.
  /// Parameters:
  ///     key: Grid coordinate whose retained animation should be cleared.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     Safe even when the key currently has no retained animation.
  /// Guarantees:
  ///     After return, the key is no longer tracked in `_animations`.
  /// Invariants:
  ///     Emits at most one cancel message per clear call.
  void _clearHighlight(_HelloKeyPosition key) {
    final _HelloAnimationEntry? existing = _animations.remove(key);
    if (existing == null) {
      return;
    }

    _writeLedMessage(
      dp.AnimationCancelLEDMessage(clientInstanceId: existing.animationId),
    );
  }

  /// Purpose:
  ///     Best-effort write of one LED message to the hello example's output.
  /// Parameters:
  ///     message: Typed LED wire record to enqueue.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     Safe to call before startup; such calls become no-ops.
  /// Guarantees:
  ///     Attempts one endpoint write when the LED output endpoint exists.
  /// Invariants:
  ///     Does not throw when the endpoint is absent.
  void _writeLedMessage(dp.LEDMessage message) {
    final dp.LocalEndpoint? endpoint = _ledOutputEndpoint;
    if (endpoint == null) {
      return;
    }
    endpoint.write(message);
  }

  /// Purpose:
  ///     Map one runtime key state onto the corresponding UI-configurable row.
  /// Parameters:
  ///     keyState: Runtime key state currently stored for a retained animation.
  /// Return value:
  ///     Matching hello-example highlight state.
  /// Requirements:
  ///     `keyState` must be a state that keeps a retained highlight alive.
  /// Guarantees:
  ///     Activated maps to the active row and pressed maps to the pressed row.
  /// Invariants:
  ///     Does not consult live endpoint state.
  HelloHighlightState _highlightStateForKeyState(dp.KeyState keyState) {
    return switch (keyState) {
      dp.KeyState.activated => HelloHighlightState.active,
      dp.KeyState.pressed => HelloHighlightState.pressed,
      dp.KeyState.rest => HelloHighlightState.active,
    };
  }
}

/// Purpose:
///     Small runtime abstraction that keeps `HelloController` easy to unit test.
/// Parameters:
///     None.
/// Return value:
///     Interface implemented by the real Dog Paw adapter and test doubles.
/// Requirements:
///     Implementations must obey the documented connect/create/disconnect
///     contracts.
/// Guarantees:
///     Callers can exercise hello-example startup and LED behavior without a
///     native Epiphany runtime.
/// Invariants:
///     The interface surface stays intentionally small for the teaching example.
abstract class HelloDogPawClient {
  /// Purpose:
  ///     Attempt a Dog Paw connection for the hello example.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     `ConnectionResult` describing success plus any ready handle.
  /// Requirements:
  ///     Safe to call once per startup attempt.
  /// Guarantees:
  ///     Completes with either a success result or an error result.
  /// Invariants:
  ///     Does not mutate controller state directly.
  Future<dp.ConnectionResult> connect();

  /// Purpose:
  ///     Create one local endpoint owned by the hello example.
  /// Parameters:
  ///     endpoint: Endpoint metadata to register with the runtime.
  /// Return value:
  ///     `Result<LocalEndpoint>` describing creation success or failure.
  /// Requirements:
  ///     `connect()` should already have succeeded for real runtime adapters.
  /// Guarantees:
  ///     Successful results return a local endpoint ready for `write()` or
  ///     `poll()`.
  /// Invariants:
  ///     Does not mutate controller state directly.
  Future<dp.Result<dp.LocalEndpoint>> createEndpoint(dp.EndpointInfo endpoint);

  /// Purpose:
  ///     Release any native or runtime resources owned by the adapter.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     Safe to call during controller disposal.
  /// Guarantees:
  ///     Subsequent runtime work from this adapter should stop.
  /// Invariants:
  ///     Does not notify Flutter listeners directly.
  void disconnect();
}

/// Purpose:
///     Real Dog Paw runtime adapter for the hello example.
/// Parameters:
///     entity: Dog Paw entity used to connect this app to Epiphany.
/// Return value:
///     Adapter that satisfies `HelloDogPawClient`.
/// Requirements:
///     `entity` must outlive this adapter.
/// Guarantees:
///     All runtime calls delegate directly to the underlying Dog Paw entity.
/// Invariants:
///     Does not add extra runtime policy beyond the hello example's needs.
class EntityHelloDogPawClient implements HelloDogPawClient {
  /// Purpose:
  ///     Wrap one Dog Paw entity for the hello example.
  /// Parameters:
  ///     entity: Runtime entity owned by the app composition root.
  /// Return value:
  ///     New `EntityHelloDogPawClient` instance.
  /// Requirements:
  ///     `entity` must already be configured with the intended app name.
  /// Guarantees:
  ///     Stores the entity for later delegation.
  /// Invariants:
  ///     The wrapped entity reference never changes after construction.
  EntityHelloDogPawClient(this._entity);

  final dp.DogPawEntity _entity;

  /// Purpose:
  ///     Delegate the hello-example connection attempt to Dog Paw.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     `ConnectionResult` from the wrapped Dog Paw entity.
  /// Requirements:
  ///     The wrapped entity must be usable for one startup attempt.
  /// Guarantees:
  ///     Preserves the native Dog Paw connection semantics.
  /// Invariants:
  ///     Adds no extra transformation to the result.
  @override
  Future<dp.ConnectionResult> connect() {
    return _entity.connect();
  }

  /// Purpose:
  ///     Delegate local-endpoint creation to the wrapped Dog Paw entity.
  /// Parameters:
  ///     endpoint: Endpoint metadata to create.
  /// Return value:
  ///     `Result<LocalEndpoint>` from the wrapped Dog Paw entity.
  /// Requirements:
  ///     The wrapped entity must already be connected.
  /// Guarantees:
  ///     Returns the native-backed local endpoint without extra transformation.
  /// Invariants:
  ///     Does not cache or rename endpoints.
  @override
  Future<dp.Result<dp.LocalEndpoint>> createEndpoint(dp.EndpointInfo endpoint) {
    return _entity.createEndpoint(endpoint);
  }

  /// Purpose:
  ///     Disconnect the wrapped Dog Paw entity during app teardown.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     Safe to call even if connect() never succeeded.
  /// Guarantees:
  ///     Delegates directly to `DogPawEntity.disconnect()`.
  /// Invariants:
  ///     Leaves adapter structure unchanged.
  @override
  void disconnect() {
    _entity.disconnect();
  }
}

/// Purpose:
///     Value object for one key-grid coordinate tracked by the hello example.
/// Parameters:
///     column: Grid column in the range `0..7`.
///     row: Grid row in the range `0..7`.
/// Return value:
///     Immutable coordinate suitable for map keys.
/// Requirements:
///     `column` and `row` must identify one valid Dog Paw key.
/// Guarantees:
///     Supports stable equality and hashing for controller state maps.
/// Invariants:
///     Instances are immutable after construction.
class _HelloKeyPosition {
  /// Purpose:
  ///     Construct one tracked key-grid coordinate.
  /// Parameters:
  ///     column: Grid column in the range `0..7`.
  ///     row: Grid row in the range `0..7`.
  /// Return value:
  ///     New immutable coordinate.
  /// Requirements:
  ///     `column` and `row` must be valid Dog Paw key coordinates.
  /// Guarantees:
  ///     Stores the supplied coordinate unchanged.
  /// Invariants:
  ///     Instances remain immutable after construction.
  const _HelloKeyPosition(this.column, this.row);

  final int column;
  final int row;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _HelloKeyPosition &&
          column == other.column &&
          row == other.row;

  @override
  int get hashCode => Object.hash(column, row);
}

/// Purpose:
///     Mutable tracked state for one retained per-key highlight animation.
/// Parameters:
///     animationId: Retained client instance id currently owned by the key.
///     keyState: Latest semantic key state for that animation.
///     colorArgb: Latest packed AARRGGBB color sent for that animation.
/// Return value:
///     One tracked animation entry stored in the controller's key map.
/// Requirements:
///     `animationId` must be the id of the live retained animation for the key.
/// Guarantees:
///     Carries enough state to decide when create, update, or cancel is needed.
/// Invariants:
///     One entry corresponds to exactly one key coordinate.
class _HelloAnimationEntry {
  /// Purpose:
  ///     Construct one tracked retained-animation record.
  /// Parameters:
  ///     animationId: Retained client instance id for the key.
  ///     keyState: Latest semantic key state represented by the animation.
  ///     colorArgb: Latest packed AARRGGBB color sent for the animation.
  /// Return value:
  ///     New mutable tracked entry.
  /// Requirements:
  ///     `animationId` must match the live retained animation for the key.
  /// Guarantees:
  ///     Stores the provided animation id, state, and color.
  /// Invariants:
  ///     The `animationId` does not change after construction.
  _HelloAnimationEntry({
    required this.animationId,
    required this.keyState,
    required this.colorArgb,
  });

  final int animationId;
  dp.KeyState keyState;
  int colorArgb;
}
