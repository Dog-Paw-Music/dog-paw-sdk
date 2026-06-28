import 'dart:async';

import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/dogpaw.dart' as dp;

import '../models/ripple_key_source.dart';
import '../models/ripple_note_event.dart';

typedef EndpointPollCallback = List<dynamic> Function();

/// True when a hardware key transition should spawn or reinforce a press ripple.
///
/// Purpose:
///     Makes Rain Pond's key-down semantics explicit and testable for both
///     manual taps and deterministic simulator playback.
/// Parameters:
///     message: One decoded Dog Paw key transition from `BladeHW::key_press`.
/// Return value:
///     `true` when the transition represents a press-like event that should
///     create a note-on ripple; otherwise `false`.
/// Requirements:
///     `message` must be a valid `dp.KeyEvent` produced by the Dog Paw package.
/// Guarantees:
///     Returns `true` for explicit `pressed` events and for transitions entering
///     `KeyState.pressed`.
/// Invariants:
///     Does not mutate the message, service state, or controller state.
bool isRippleNoteDownEvent(dp.KeyEvent message) {
  if (message.type == dp.KeyEventType.pressed) {
    return true;
  }
  return message.newState == dp.KeyState.pressed &&
      message.oldState != dp.KeyState.pressed;
}

/// True when a hardware key transition should spawn a release ripple.
///
/// Purpose:
///     Makes Rain Pond's key-up semantics explicit and testable for both
///     manual taps and deterministic simulator playback.
/// Parameters:
///     message: One decoded Dog Paw key transition from `BladeHW::key_press`.
/// Return value:
///     `true` when the transition represents a return-to-rest release that
///     should create a note-off ripple; otherwise `false`.
/// Requirements:
///     `message` must be a valid `dp.KeyEvent` produced by the Dog Paw package.
/// Guarantees:
///     Returns `true` for explicit `released` events and for transitions ending
///     at `KeyState.rest`.
/// Invariants:
///     Does not mutate the message, service state, or controller state.
bool isRippleNoteUpEvent(dp.KeyEvent message) {
  if (message.type == dp.KeyEventType.released) {
    return true;
  }
  return message.newState == dp.KeyState.rest &&
      message.oldState != dp.KeyState.rest;
}

/// Drain all currently queued payloads from a message-queue endpoint poller.
///
/// Purpose:
///     Centralizes the "poll until empty" behavior used by message queues so it
///     stays separate from continuous shared-data polling.
/// Parameters:
///     poll: Callback that returns the next decoded poll batch.
/// Return value:
///     Flattened list of all queued payloads observed before the first empty poll.
/// Requirements:
///     `poll` must be safe to call repeatedly until it returns an empty list.
/// Guarantees:
///     Preserves the batch order emitted by the endpoint runtime.
/// Invariants:
///     Does not inspect or transform payload values.
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
/// Purpose:
///     Shared-data endpoints expose the latest state on every poll, so callers
///     should sample once per timer tick instead of draining until empty.
/// Parameters:
///     poll: Callback that returns the latest decoded snapshot batch.
/// Return value:
///     One decoded poll batch.
/// Requirements:
///     `poll` must be safe to call once for the current sampling interval.
/// Guarantees:
///     Never loops waiting for an empty result.
/// Invariants:
///     Does not inspect or transform payload values.
List<dynamic> collectContinuousPollSnapshot(EndpointPollCallback poll) {
  return poll();
}

/// Return the keyed-buffer packet index for one Dog Paw grid coordinate.
///
/// Purpose:
///     Matches the `DPCommon::getKeyedBufferOffset()` ordering used by
///     `BladeHW::key_position` so Rain Pond can read one key from a continuous
///     `List<PosData>` packet.
/// Parameters:
///     col: Grid column in the range `0..7`.
///     row: Grid row in the range `0..7`.
/// Return value:
///     Zero-based packet index for that key.
/// Requirements:
///     `col` and `row` must be valid Dog Paw key-grid coordinates.
/// Guarantees:
///     Returns an index in the range `0..63`.
/// Invariants:
///     Pure function; does not inspect endpoint or controller state.
int keyPositionPacketIndex({required int col, required int row}) {
  return (7 - row) + 8 * (7 - col);
}

/// Extract one key-position sample from a continuous poll payload.
///
/// Purpose:
///     Supports the runtime Dog Paw shape for continuous `key_position`
///     endpoints, which currently arrives as a `List<PosData>`, while keeping
///     compatibility with `KeyPositionBuffer` if that representation appears in
///     future bridge revisions.
/// Parameters:
///     payload: One decoded item returned by `LocalEndpoint.poll()`.
///     col: Grid column in the range `0..7`.
///     row: Grid row in the range `0..7`.
/// Return value:
///     The matching `PosData` sample, or `null` when the payload shape is not
///     recognized.
/// Requirements:
///     `payload` should come from a continuous `BladeHW::key_position` endpoint.
/// Guarantees:
///     Never throws for unsupported payload shapes; returns `null` instead.
/// Invariants:
///     Does not mutate `payload` or service state.
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

/// Build Rain Pond's `key_position` input endpoint contract.
///
/// Purpose:
///     Centralizes the continuous key-position endpoint shape so production code
///     and tests stay aligned on the required `8x8` key-grid index spec.
/// Parameters:
///     None.
/// Return value:
///     Endpoint definition for `BladeHW::key_position`.
/// Requirements:
///     None.
/// Guarantees:
///     Returns an input continuous key-position endpoint that declares endpoint-owned connection rules for
///     `BladeHW`.
/// Invariants:
///     Does not create endpoints or perform network I/O.
dp.EndpointInfo buildRainPondKeyPositionEndpointInfo() {
  final dp.SearchCriteria criteria = dp.SearchCriteria.andCombination([
    dp.SearchCriteria.fromCondition('direction', 'equals', 'output'),
    dp.SearchCriteria.fromCondition('name', 'equals', 'key_position'),
    dp.SearchCriteria.fromCondition('sourceEntity', 'equals', 'BladeHW'),
    dp.SearchCriteria.fromCondition('baseType', 'equals', 'key_position'),
  ]);

  final dp.EndpointSpec spec = dp.EndpointSpec(
    displayName: 'Rain Pond Key Position Input',
    description: 'Receives key_position from BladeHW',
    direction: dp.EndpointDirection.input,
    dataType: const dp.DataTypeSpec(
      dp.DataType.keyPosition,
      indexSpec: dp.IndexSpecKey(8, 8),
    ),
    category: dp.EndpointCategory.continuous,
    connectionPolicy: dp.ConnectionPolicy(endpointConnectionRule: criteria),
  );
  return dp.EndpointInfo(name: 'rain_pond_key_position_input', spec: spec);
}

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

  PondKeyInputService({
    required dp.DogPawEntity entity,
    required this.onNoteEvent,
    required this.onHeldNoteExpression,
  }) : _entity = entity {
    _entity.setErrorCallback((Object error) {
      AppLogger.error('PondKeyInputService entity error: $error');
    });
  }

  /// Connects to Epiphany and prepares Rain Pond's input endpoints.
  ///
  /// Purpose:
  ///     Brings up the message-queue and continuous endpoints Rain Pond uses for
  ///     press/release input plus held pressure and bend updates.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     A [dp.ConnectionHandle] to complete after the first frame, or `null`
  ///     when connection setup fails.
  /// Requirements:
  ///     The wrapped [dp.DogPawEntity] must be in a disconnected state.
  /// Guarantees:
  ///     On success, polling may start as soon as the key input endpoint exists.
  /// Invariants:
  ///     Does not subscribe to layout state or derive note numbers.
  Future<dp.ConnectionHandle?> connect() async {
    try {
      AppLogger.info('RainPond: connecting…');
      final dp.ConnectionResult result = await _entity.connect();
      if (!result.success) {
        AppLogger.error('RainPond: connect failed: ${result.error}');
        return null;
      }
      await _setupKeyInputEndpoint();
      await _setupKeyPositionEndpoint();
      return result.handle;
    } catch (e) {
      AppLogger.error('RainPond: connect error: $e');
      return null;
    }
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

  Future<void> _setupKeyInputEndpoint() async {
    final dp.SearchCriteria criteria = dp.SearchCriteria.andCombination([
      dp.SearchCriteria.fromCondition('direction', 'equals', 'output'),
      dp.SearchCriteria.fromCondition('name', 'equals', 'key_press'),
      dp.SearchCriteria.fromCondition('sourceEntity', 'equals', 'BladeHW'),
      dp.SearchCriteria.fromCondition('baseType', 'equals', 'key_press'),
    ]);

    final dp.EndpointSpec spec = dp.EndpointSpec(
      displayName: 'Rain Pond Key Input',
      description: 'Receives key_press from BladeHW',
      direction: dp.EndpointDirection.input,
      dataType: const dp.DataTypeSpec(dp.DataType.keyPress),
      category: dp.EndpointCategory.messageQueue,
      connectionPolicy: dp.ConnectionPolicy(endpointConnectionRule: criteria),
    );

    final dp.EndpointInfo ep =
        dp.EndpointInfo(name: 'rain_pond_key_input', spec: spec);
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

  /// Creates the continuous `key_position` endpoint for held pressure/bend data.
  ///
  /// Purpose:
  ///     Lets Rain Pond observe live key pressure and bend so sustained notes can
  ///     keep producing ripples after the initial press.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     Completes when endpoint creation succeeds or fails.
  /// Requirements:
  ///     `_entity.connect()` must already have succeeded.
  /// Guarantees:
  ///     On success, `_keyPositionEndpoint` is ready for polling.
  /// Invariants:
  ///     Does not start a second polling timer.
  Future<void> _setupKeyPositionEndpoint() async {
    final dp.EndpointInfo ep = buildRainPondKeyPositionEndpointInfo();
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

  void _startPolling() {
    if (_pollTimer != null && _pollTimer!.isActive) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      _pollKeyMessages();
      _pollKeyPositions();
    });
  }

  /// Drains queued `key_press` messages and forwards note on/off events.
  ///
  /// Purpose:
  ///     Keeps message-queue polling separate from continuous buffer polling so
  ///     each data path can be debugged independently.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     Safe when `_keyInputEndpoint` is null.
  /// Guarantees:
  ///     Processes every queued `dp.KeyEvent` currently available.
  /// Invariants:
  ///     Leaves `_keyPositionEndpoint` untouched.
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

  /// Poll one current `key_position` snapshot and forwards held-expression updates.
  ///
  /// Purpose:
  ///     Samples the continuous endpoint once per timer tick so sustained-note
  ///     visuals update without trying to drain shared data like a queue.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     Safe when `_keyPositionEndpoint` is null.
  /// Guarantees:
  ///     Processes at most one `dp.KeyPositionBuffer` snapshot per timer tick.
  /// Invariants:
  ///     Does not emit note-on or note-off events directly.
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

  /// Maps hardware [message] to [RippleNoteEvent] and forwards to [onNoteEvent].
  ///
  /// Purpose:
  ///     Converts Dog Paw key transitions into the smaller input contract used by
  ///     [PondController], keeping hardware transport details out of the visual
  ///     layer.
  /// Parameters:
  ///     message: One decoded `dp.KeyEvent` from the `BladeHW::key_press`
  ///     message queue.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `message` must describe one valid hardware key transition.
  /// Guarantees:
  ///     Press-like events add the key to `_activeKeyPositions`; release-like
  ///     events remove it. Matching callbacks may run synchronously.
  /// Invariants:
  ///     Does not consult layout state or synthesize note numbers.
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

  /// Maps held `key_position` data to normalized pressure and bend updates.
  ///
  /// Purpose:
  ///     Converts one continuous poll payload into the simpler expression values
  ///     that [PondController] needs for sustained ripple timing and shimmer.
  /// Parameters:
  ///     packet: Latest decoded `BladeHW::key_position` payload.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `_activeKeyPositions` should contain only keys that are currently held.
  /// Guarantees:
  ///     Emits one `onHeldNoteExpression` callback per active held key.
  /// Invariants:
  ///     Does not synthesize note-on/off transitions.
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
      final double bend = (pos.horizontal * pos.horizBlendAmt).clamp(-1.0, 1.0);
      onHeldNoteExpression(
        source: RippleKeySource.internalGrid(col: key.col, row: key.row),
        pressure: pressure,
        bend: bend,
      );
    }
  }

  /// Normalizes raw Dog Paw vertical position into a simple `0..1` pressure value.
  ///
  /// Purpose:
  ///     Hides the raw position encoding differences between simulator-style
  ///     `-1..1` values and the older `0..1` convention seen in some tooling.
  /// Parameters:
  ///     vertical: Raw vertical position sample from `dp.PosData`.
  /// Return value:
  ///     Normalized pressure where `0` means resting and `1` means deepest press.
  /// Requirements:
  ///     `vertical` should be a finite number from the Dog Paw stack.
  /// Guarantees:
  ///     Returns a clamped value in the range `0..1`.
  /// Invariants:
  ///     Pure function; does not read or mutate service state.
  double _pressureFromVertical(double vertical) {
    if (vertical >= 0.0 && vertical <= 1.0) {
      return (1.0 - vertical).clamp(0.0, 1.0);
    }
    final double clamped = vertical.clamp(-1.0, 1.0);
    return ((1.0 - clamped) * 0.5).clamp(0.0, 1.0);
  }
}
