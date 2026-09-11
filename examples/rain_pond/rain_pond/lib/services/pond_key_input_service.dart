import 'dart:async';

import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/dogpaw.dart' as dp;

import '../models/ripple_key_source.dart';
import '../models/ripple_note_event.dart';

// =============================================================================
// Rain Pond — Dog Paw key input service
//
// Read this file top-to-bottom as the intermediate teaching step after hello.
// The first method that "does Dog Paw" is [PondKeyInputService.connect]:
//   connect → create key_press + key_position endpoints → poll.
// Pure helpers used by tests live at the bottom of this file.
// =============================================================================

typedef EndpointPollCallback = List<dynamic> Function();

/// Connects to Epiphany and forwards BladeHW key input to Rain Pond visuals.
///
/// Emits [RippleNoteEvent] transitions for key presses/releases and normalized
/// held-key expression updates for pressure and bend.
class PondKeyInputService {
  static const String entityLogTag = 'RainPond';

  final dp.DogPawEntity _entity;
  final void Function(RippleNoteEvent event) onNoteEvent;
  final void Function({
    required RippleKeySource source,
    required double pressure,
    required double bend,
  }) onHeldNoteExpression;

  dp.LocalEndpoint? _keyInputEndpoint;
  dp.LocalEndpoint? _keyPositionEndpoint;
  Timer? _pollTimer;
  final Set<_KeyPosition> _activeKeyPositions = <_KeyPosition>{};

  /// Creates a service that drives Dog Paw I/O for the pond controller.
  ///
  /// Parameters:
  /// - [entity]: Live [dp.DogPawEntity] owned by `main.dart`.
  /// - [onNoteEvent]: Press/release events for the shared ripple path.
  /// - [onHeldNoteExpression]: Continuous pressure/bend while a key is held.
  PondKeyInputService({
    required dp.DogPawEntity entity,
    required this.onNoteEvent,
    required this.onHeldNoteExpression,
  }) : _entity = entity {
    _entity.setErrorCallback((Object error) {
      AppLogger.error('PondKeyInputService entity error: $error');
    });
  }

  // ---------------------------------------------------------------------------
  // connect() — first real Dog Paw screenful in this file
  //
  // Join Epiphany, declare queue + continuous inputs with stock helpers, then
  // poll. Returns a ConnectionHandle for the screen to complete after first frame.
  // ---------------------------------------------------------------------------

  /// Connect to Epiphany and create both key input endpoints.
  ///
  /// @return A [dp.ConnectionHandle] to complete after the first frame, or
  ///         `null` when connection setup fails (caller may stay keyboard-only).
  /// @pre [entity] is disconnected for this service's lifetime.
  /// @post On success: polling may start once the key_press endpoint exists.
  Future<dp.ConnectionHandle?> connect() async {
    try {
      AppLogger.info('RainPond: connecting…');

      // 1) Join the Dog Paw runtime (Epiphany).
      final dp.ConnectionResult result = await _entity.connect();
      if (!result.success) {
        AppLogger.error('RainPond: connect failed: ${result.error}');
        return null;
      }

      // 2) Message-queue input → BladeHW::key_press (press / release).
      await _setupKeyInputEndpoint();

      // 3) Continuous input → BladeHW::key_position (held pressure / bend).
      await _setupKeyPositionEndpoint();

      return result.handle;
    } catch (e) {
      AppLogger.error('RainPond: connect error: $e');
      return null;
    }
  }

  /// Creates the message-queue `key_press` input and starts the poll timer.
  Future<void> _setupKeyInputEndpoint() async {
    final dp.EndpointInfo ep = dp.EndpointInfo.forKeyPressInput(
      name: 'rain_pond_key_input',
      displayName: 'Key Input',
      description: 'Receives key_press from BladeHW',
    );
    final dp.Result<dp.LocalEndpoint> created =
        await _entity.createEndpoint(ep);
    if (created.isSuccess) {
      _keyInputEndpoint = created.getValue();
      _startPolling();
      AppLogger.info('RainPond: key input endpoint ready');
    } else {
      AppLogger.error('RainPond: key endpoint failed: ${created.getError()}');
    }
  }

  /// Creates the continuous `key_position` input for held pressure/bend.
  ///
  /// @pre [_entity.connect] has already succeeded.
  Future<void> _setupKeyPositionEndpoint() async {
    final dp.EndpointInfo ep = dp.EndpointInfo.forKeyPositionInput(
      name: 'rain_pond_key_position_input',
      displayName: 'Key Position Input',
      description: 'Receives key_position from BladeHW',
    );
    final dp.Result<dp.LocalEndpoint> created =
        await _entity.createEndpoint(ep);
    if (created.isSuccess) {
      _keyPositionEndpoint = created.getValue();
      AppLogger.info('RainPond: key position endpoint ready');
    } else {
      AppLogger.error(
        'RainPond: key position endpoint failed: ${created.getError()}',
      );
    }
  }

  // --- Polling: queue drain vs continuous sample -----------------------------

  void _startPolling() {
    if (_pollTimer != null && _pollTimer!.isActive) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      _pollKeyMessages();
      _pollKeyPositions();
    });
  }

  /// Drain queued `key_press` messages (message-queue: read until empty).
  void _pollKeyMessages() {
    if (_keyInputEndpoint == null) {
      return;
    }
    final List<dynamic> batch =
        collectQueuedPollResults(_keyInputEndpoint!.poll);
    for (final dynamic message in batch) {
      if (message is dp.KeyEvent) {
        _processKeyMessage(message);
      }
    }
  }

  /// Sample one `key_position` snapshot (continuous: do not drain-until-empty).
  void _pollKeyPositions() {
    if (_keyPositionEndpoint == null || _activeKeyPositions.isEmpty) {
      return;
    }
    final List<dynamic> batch = collectContinuousPollSnapshot(
      _keyPositionEndpoint!.poll,
    );
    for (final dynamic message in batch) {
      _processKeyPositionPacket(message);
    }
  }

  /// Map one hardware [message] to [RippleNoteEvent] and forward to [onNoteEvent].
  void _processKeyMessage(dp.KeyEvent message) {
    try {
      final bool down = isRippleNoteDownEvent(message);
      final bool up = isRippleNoteUpEvent(message);
      if (down) {
        _activeKeyPositions.add(_KeyPosition(message.column, message.row));
        onNoteEvent(RippleNoteEvent(
          source: RippleKeySource.internalGrid(
            col: message.column,
            row: message.row,
          ),
          velocity: message.velocity,
          isDown: true,
        ));
      } else if (up) {
        _activeKeyPositions.remove(_KeyPosition(message.column, message.row));
        onNoteEvent(RippleNoteEvent(
          source: RippleKeySource.internalGrid(
            col: message.column,
            row: message.row,
          ),
          velocity: 0,
          isDown: false,
        ));
      }
    } catch (e) {
      AppLogger.error('RainPond: key message error: $e');
    }
  }

  /// Map held `key_position` samples to pressure/bend callbacks.
  void _processKeyPositionPacket(dynamic packet) {
    for (final _KeyPosition key in _activeKeyPositions) {
      final dp.PosData? pos = extractKeyPositionSample(
        packet,
        col: key.col,
        row: key.row,
      );
      if (pos == null) {
        continue;
      }
      final double pressure = _pressureFromVertical(pos.vertical);
      final double bend = heldBendFromPosData(pos);
      onHeldNoteExpression(
        source: RippleKeySource.internalGrid(col: key.col, row: key.row),
        pressure: pressure,
        bend: bend,
      );
    }
  }

  /// Normalize raw vertical position into pressure in `0..1`.
  double _pressureFromVertical(double vertical) {
    if (vertical >= 0.0 && vertical <= 1.0) {
      return (1.0 - vertical).clamp(0.0, 1.0);
    }
    final double clamped = vertical.clamp(-1.0, 1.0);
    return ((1.0 - clamped) * 0.5).clamp(0.0, 1.0);
  }

  /// Stops polling and disconnects the entity.
  ///
  /// @pre Safe to call once or multiple times.
  /// @post Timers cancelled; entity disconnected.
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _entity.disconnect();
  }
}

// =============================================================================
// Private types
// =============================================================================

/// One cell on the BladeHW key grid (column, row).
class _KeyPosition {
  final int col;
  final int row;

  const _KeyPosition(this.col, this.row);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _KeyPosition && col == other.col && row == other.row;

  @override
  int get hashCode => col.hashCode ^ row.hashCode;
}

// =============================================================================
// Pure helpers (production + unit tests)
// =============================================================================

/// True when a hardware key transition should spawn or reinforce a press ripple.
///
/// Returns `true` for explicit `pressed` events and for transitions entering
/// `KeyState.pressed`. Does not mutate [message] or service state.
bool isRippleNoteDownEvent(dp.KeyEvent message) {
  if (message.type == dp.KeyEventType.pressed) {
    return true;
  }
  return message.newState == dp.KeyState.pressed &&
      message.oldState != dp.KeyState.pressed;
}

/// True when a hardware key transition should spawn a release ripple.
///
/// Returns `true` for explicit `released` events and for transitions ending at
/// `KeyState.rest`. Does not mutate [message] or service state.
bool isRippleNoteUpEvent(dp.KeyEvent message) {
  if (message.type == dp.KeyEventType.released) {
    return true;
  }
  return message.newState == dp.KeyState.rest &&
      message.oldState != dp.KeyState.rest;
}

/// Drain all currently queued payloads from a message-queue poller.
///
/// Call [poll] until it returns an empty list; preserves batch order.
List<dynamic> collectQueuedPollResults(EndpointPollCallback poll) {
  final List<dynamic> results = <dynamic>[];
  List<dynamic> batch;
  do {
    batch = poll();
    results.addAll(batch);
  } while (batch.isNotEmpty);
  return results;
}

/// Read exactly one current snapshot from a continuous endpoint poller.
///
/// Continuous endpoints expose latest state each poll — do not drain-until-empty.
List<dynamic> collectContinuousPollSnapshot(EndpointPollCallback poll) {
  return poll();
}

/// Packet index for one Dog Paw grid coordinate in an 8x8 `List<PosData>`.
///
/// Matches `DPCommon::getKeyedBufferOffset()` ordering used by BladeHW.
///
/// Parameters: [col] / [row] in `0..7`. Returns index in `0..63`.
int keyPositionPacketIndex({required int col, required int row}) {
  return (7 - row) + 8 * (7 - col);
}

/// Map one BladeHW [pos] sample to held-note bend in `[-1, 1]`.
///
/// Uses the pre-corrected `bend` field (does not multiply by `rawHorizontal`).
double heldBendFromPosData(dp.PosData pos) {
  return pos.bend.clamp(-1.0, 1.0);
}

/// Extract one key-position sample from a continuous poll [payload].
///
/// Supports `List<PosData>` (current runtime shape) and `KeyPositionBuffer`.
/// Returns `null` when the shape is unrecognized (does not throw).
dp.PosData? extractKeyPositionSample(
  dynamic payload, {
  required int col,
  required int row,
}) {
  if (payload is dp.KeyPositionBuffer) {
    return payload.getPos(col, row);
  }
  if (payload is List<dynamic>) {
    final int index = keyPositionPacketIndex(col: col, row: row);
    if (index < 0 || index >= payload.length) {
      return null;
    }
    final dynamic sample = payload[index];
    if (sample is dp.PosData) {
      return sample;
    }
  }
  return null;
}
