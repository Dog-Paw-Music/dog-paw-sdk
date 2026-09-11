import 'dart:async';

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/foundation.dart';

// =============================================================================
// Hello Dog Paw — controller
//
// Read this file top-to-bottom as a teaching walkthrough. The first method that
// "does Dog Paw" is [HelloController.start]: connect → create endpoints → poll.
// Everything above that is just UI-facing types and field setup.
// =============================================================================

/// Which on-screen color row the user is editing.
///
/// Hardware keys have three states (rest / active / pressed). Only active and
/// pressed get a color here — rest clears the highlight instead.
enum HelloHighlightState {
  active,
  pressed,
}

/// One named color chip shown in the UI.
class HelloColorSwatch {
  const HelloColorSwatch({
    required this.label,
    required this.colorArgb,
  });

  final String label;

  /// Packed AARRGGBB value, the same format LED messages use on the wire.
  final int colorArgb;
}

/// Owns startup, key polling, and retained per-key LED highlights.
///
/// The widget tree only reads status/colors and calls [selectColor] / [start].
class HelloController extends ChangeNotifier {
  /// Creates a controller that drives Dog Paw through [entity].
  ///
  /// Parameters:
  /// - [entity]: Live [dp.DogPawEntity] owned by `main.dart` (unique name).
  /// - [pollInterval]: How often to drain the key_input message queue.
  ///
  /// @pre [entity] is not already connected for another controller's lifetime.
  /// @post Controllers fields are idle until [start] succeeds.
  HelloController({
    required dp.DogPawEntity entity,
    Duration pollInterval = const Duration(milliseconds: 30),
  }) : _entity = entity,
       _pollInterval = pollInterval;

  static const List<HelloColorSwatch> _availableSwatches = <HelloColorSwatch>[
    HelloColorSwatch(label: 'Black', colorArgb: 0xFF000000),
    HelloColorSwatch(label: 'Deep Purple', colorArgb: 0xFF673AB7),
    HelloColorSwatch(label: 'Teal', colorArgb: 0xFF009688),
    HelloColorSwatch(label: 'Amber', colorArgb: 0xFFFFC107),
  ];

  final dp.DogPawEntity _entity;
  final Duration _pollInterval;

  /// Allocates unique IDs so we can update/cancel one key's highlight later.
  final dp.LedClientAnimIdAllocator _animIdAllocator =
      dp.LedClientAnimIdAllocator();

  /// Live highlights keyed by grid position.
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

  bool get isStarting => _isStarting;
  bool get isReady => _isReady;
  String get statusMessage => _statusMessage;
  List<HelloColorSwatch> get availableSwatches => _availableSwatches;

  /// Returns the ARGB color currently chosen for [state].
  int colorForState(HelloHighlightState state) {
    return switch (state) {
      HelloHighlightState.active => _activeColorArgb,
      HelloHighlightState.pressed => _pressedColorArgb,
    };
  }

  // ---------------------------------------------------------------------------
  // start() — first real Dog Paw screenful
  //
  // Connect to Epiphany, declare key + LED endpoints (with stock auto-connect
  // helpers from the dogpaw package), then poll for key events.
  // ---------------------------------------------------------------------------

  /// Connect to Epiphany, create both endpoints, then begin reading key events.
  ///
  /// Safe to call more than once: later calls no-op while starting or ready.
  ///
  /// @pre Flutter has mounted a listener that will call [notifyListeners].
  /// @post On success: [isReady] is true and key polling is active.
  /// @post On failure: [statusMessage] explains the error; entity may be
  ///       partially connected — dispose still disconnects cleanly.
  Future<void> start() async {
    if (_isStarting || _isReady) {
      return;
    }

    _isStarting = true;
    _statusMessage = 'Connecting to Dog Paw...';
    notifyListeners();

    dp.ConnectionHandle? handle;
    try {
      // 1) Join the Dog Paw runtime (Epiphany).
      final dp.ConnectionResult result = await _entity.connect();
      if (!result.success) {
        _statusMessage = 'Connection failed: ${result.error}';
        return;
      }
      handle = result.handle;

      // 2) Key input mailbox → auto-connect to BladeHW::key_press.
      final dp.Result<dp.LocalEndpoint> keyInputResult =
          await _entity.createEndpoint(
        dp.EndpointInfo.forKeyPressInput(
          name: 'key_input',
          displayName: 'Hello Key Input',
          description: 'Receives key_press events from BladeHW',
        ),
      );
      if (!keyInputResult.isSuccess) {
        throw StateError(
          'Failed to create key input endpoint: ${keyInputResult.getError()}',
        );
      }
      _keyInputEndpoint = keyInputResult.getValue();

      // 3) LED output mailbox → auto-connect to LEDComms::led_overlay_input.
      final dp.Result<dp.LocalEndpoint> ledOutputResult =
          await _entity.createEndpoint(
        dp.EndpointInfo.forLedOverlayOutput(
          name: 'led_output',
          displayName: 'Hello LED Output',
          description: 'Sends LED messages to LEDComms',
        ),
      );
      if (!ledOutputResult.isSuccess) {
        throw StateError(
          'Failed to create LED output endpoint: ${ledOutputResult.getError()}',
        );
      }
      _ledOutputEndpoint = ledOutputResult.getValue();

      // 4) Poll the input queue on a timer (message-queue endpoints are pull).
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

  // --- Key presses: drain the input queue ------------------------------------

  /// Read every pending key event (call from the poll timer or tests).
  ///
  /// @pre [_keyInputEndpoint] may be null (no-op) or a connected local input.
  /// @post Queued [dp.KeyEvent]s are applied to retained LED highlights.
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

  void _startPolling() {
    if (_pollTimer != null && _pollTimer!.isActive) {
      return;
    }
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      processPendingKeyEvents();
    });
  }

  /// Map one key state change onto start/update/clear of a retained LED.
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

  // --- LED animations: retained highlights per key ---------------------------

  /// Start or recolor the retained highlight for one key.
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

  /// Cancel the retained highlight when the key returns to rest.
  void _clearHighlight(_HelloKeyPosition key) {
    final _HelloAnimationEntry? existing = _animations.remove(key);
    if (existing == null) {
      return;
    }
    _writeLedMessage(
      dp.AnimationCancelLEDMessage(clientInstanceId: existing.animationId),
    );
  }

  void _writeLedMessage(dp.LEDMessage message) {
    final dp.LocalEndpoint? endpoint = _ledOutputEndpoint;
    if (endpoint == null) {
      return;
    }
    endpoint.write(message);
  }

  // --- UI: change colors for keys that are already held down -----------------

  /// Update one row's color and push live recolors to matching held keys.
  ///
  /// Parameters:
  /// - [state]: Which highlight row (active vs pressed) to recolor.
  /// - [colorArgb]: Packed AARRGGBB color to apply.
  ///
  /// @post Matching live highlights receive [dp.AnimationColorUpdateLEDMessage].
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

  HelloHighlightState _highlightStateForKeyState(dp.KeyState keyState) {
    return switch (keyState) {
      dp.KeyState.activated => HelloHighlightState.active,
      dp.KeyState.pressed => HelloHighlightState.pressed,
      dp.KeyState.rest => HelloHighlightState.active,
    };
  }

  // --- Teardown --------------------------------------------------------------

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _animations.clear();
    _entity.disconnect();
    super.dispose();
  }
}

// =============================================================================
// Private helpers
// =============================================================================

/// One cell on the key grid (column, row).
class _HelloKeyPosition {
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

/// Tracks the retained LED animation currently shown for one key.
class _HelloAnimationEntry {
  _HelloAnimationEntry({
    required this.animationId,
    required this.keyState,
    required this.colorArgb,
  });

  final int animationId;
  dp.KeyState keyState;
  int colorArgb;
}
