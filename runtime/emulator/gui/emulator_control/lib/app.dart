import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'models/emulator_bridge_models.dart';
import 'services/emulator_bridge_client.dart';

typedef KeyStateChangeHandler = Future<void> Function(
  KeyInteractionRequest request,
);
typedef KeyPatternPathHandler = Future<void> Function(String path);
typedef KeyPatternStopHandler = Future<void> Function();
typedef BakButtonTapHandler = Future<void> Function(int index);
typedef BakKnobRotateHandler = Future<void> Function(int index, int delta);
typedef BakKnobSetRawHandler = Future<void> Function(int index, int raw);
typedef BakKnobSetNormalizedHandler = Future<void> Function(
  int index,
  double value,
);

/// Translate one displayed raw knob value into simulator hardware position.
///
/// Purpose: keeps the GUI's raw slider aligned with the post-processed raw
/// values shown in BAK snapshots, even though the simulator hardware path still
/// uses the pre-inversion encoder direction.
/// Parameters: [displayedRawValue] is the raw value currently shown in the GUI.
/// Return value: raw position to send through the bridge to the simulator.
/// Requirements: [displayedRawValue] should be within the GUI raw slider range.
/// Guarantees: preserves magnitude and flips only direction.
/// Invariants: pure mapping; does not inspect widget or bridge state.
int bakDisplayedRawValueToSimulatorRaw(int displayedRawValue) {
  return -displayedRawValue;
}

/// Translate one displayed rotation direction into simulator hardware steps.
///
/// Purpose: keeps the left/right knob buttons moving the displayed raw value in
/// the same direction the user clicked.
/// Parameters: [displayedDelta] is the desired displayed step delta.
/// Return value: hardware delta to send through the bridge.
/// Requirements: callers should pass a small signed step count.
/// Guarantees: preserves magnitude and flips only direction.
/// Invariants: pure mapping; does not inspect widget or bridge state.
int bakDisplayedRotationDeltaToSimulatorDelta(int displayedDelta) {
  return -displayedDelta;
}

const Color _defaultKeyTileFillColor = Color(0xFF22303B);
const Duration _bridgeStatusPollInterval = Duration(milliseconds: 750);
const Duration _ledSnapshotPollInterval = Duration(milliseconds: 33);

/// Convert one optional LED layer into the key tile fill color.
///
/// Purpose: centralizes the color mapping used by the key-grid renderer.
/// Parameters: [layer] is the visible LED layer for one key half, if present.
/// Return value: display color for that key half.
/// Requirements: none.
/// Guarantees: missing layers render as the default dark key color.
/// Invariants: color conversion does not mutate [layer].
Color ledLayerToKeyTileColor(LedKeyLayer? layer) {
  if (layer == null) {
    return _defaultKeyTileFillColor;
  }
  return Color.fromARGB(layer.alpha, layer.red, layer.green, layer.blue);
}

/// Runtime root widget that polls the emulator bridge.
///
/// Purpose: owns live bridge state for the desktop emulator control GUI.
/// Parameters: [client] is the local bridge API client.
/// Return value: stateful widget that renders [EmulatorControlApp].
/// Requirements: the bridge should be reachable at [client.baseUri].
/// Guarantees: stops polling when disposed.
/// Invariants: simulator commands always go through [EmulatorBridgeClient].
class EmulatorControlRoot extends StatefulWidget {
  const EmulatorControlRoot({required this.client, super.key});

  final EmulatorBridgeClient client;

  @override
  State<EmulatorControlRoot> createState() => _EmulatorControlRootState();
}

class _EmulatorControlRootState extends State<EmulatorControlRoot> {
  BridgeHealth? _health;
  LedSnapshot? _snapshot;
  BakSnapshot? _bakSnapshot;
  String? _error;
  Timer? _statusPollTimer;
  Timer? _ledPollTimer;
  String? _lastLoggedBridgeError;
  bool _statusRefreshInFlight = false;
  bool _ledRefreshInFlight = false;

  /// Start bridge polling when the widget enters the tree.
  ///
  /// Purpose: keeps health and LED state fresh while the GUI is open.
  /// Parameters: none.
  /// Return value: none.
  /// Requirements: [widget.client] has been constructed.
  /// Guarantees: schedules periodic refreshes until [dispose].
  /// Invariants: no simulator command is sent from initialization.
  @override
  void initState() {
    super.initState();
    _refreshStatusAndBak();
    _statusPollTimer = Timer.periodic(_bridgeStatusPollInterval, (_) {
      _refreshStatusAndBak();
    });
    _ledPollTimer = Timer.periodic(_ledSnapshotPollInterval, (_) {
      _refreshLedSnapshot();
    });
  }

  /// Stop bridge polling when the widget leaves the tree.
  ///
  /// Purpose: prevents background timers after the GUI closes.
  /// Parameters: none.
  /// Return value: none.
  /// Requirements: none.
  /// Guarantees: cancels the polling timer if present.
  /// Invariants: bridge state objects are not modified after disposal.
  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _ledPollTimer?.cancel();
    super.dispose();
  }

  /// Refresh bridge health and BAK snapshot state from the bridge.
  ///
  /// Purpose: updates the GUI with current simulator readiness and non-LED
  /// control state on a slower cadence than the LED view.
  /// Parameters: none.
  /// Return value: future completed after the bridge reads are attempted.
  /// Requirements: the bridge may or may not be running.
  /// Guarantees: errors are stored for display instead of escaping the widget.
  /// Invariants: does not send simulator control commands or overlap itself.
  Future<void> _refreshStatusAndBak() async {
    if (_statusRefreshInFlight) {
      return;
    }
    _statusRefreshInFlight = true;
    try {
      final health = await widget.client.fetchHealth();
      BakSnapshot? bakSnapshot;
      if (health.socketAvailable('buttonsAndKnobs')) {
        bakSnapshot = await widget.client.fetchBakSnapshot();
      }
      if (!mounted) {
        return;
      }
      final bool ledCommsAvailable = health.socketAvailable('ledComms');
      setState(() {
        _health = health;
        _bakSnapshot = bakSnapshot;
        if (!ledCommsAvailable) {
          _snapshot = null;
        }
        _error = null;
      });
      _lastLoggedBridgeError = null;
      if (ledCommsAvailable) {
        await _refreshLedSnapshot();
      }
    } catch (error) {
      _logBridgeError(error);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      _statusRefreshInFlight = false;
    }
  }

  /// Refresh the LED snapshot state from the bridge.
  ///
  /// Purpose: keeps the key-grid colors responsive without re-fetching slower
  /// bridge health or BAK data on every frame.
  /// Parameters: none.
  /// Return value: future completed after the LED snapshot read is attempted.
  /// Requirements: bridge health must already show the LED socket as available.
  /// Guarantees: errors are stored for display instead of escaping the widget.
  /// Invariants: does not overlap itself or mutate non-LED bridge state.
  Future<void> _refreshLedSnapshot() async {
    final BridgeHealth? health = _health;
    if (_ledRefreshInFlight ||
        health == null ||
        !health.socketAvailable('ledComms')) {
      return;
    }
    _ledRefreshInFlight = true;
    try {
      final LedSnapshot snapshot = await widget.client.fetchLedSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });
      _lastLoggedBridgeError = null;
    } catch (error) {
      _logBridgeError(error);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      _ledRefreshInFlight = false;
    }
  }

  /// Emit one deduplicated bridge error line for terminal inspection.
  ///
  /// Purpose: makes GUI-side polling and JSON parse failures visible in the same
  /// terminal stream as the emulator control process so agent debugging does not
  /// depend on reading the window chrome.
  /// Parameters: [error] is the exception raised during bridge polling or a
  /// bridge-backed command.
  /// Return value: none.
  /// Requirements: [error] should be safe to stringify for developer logs.
  /// Guarantees: identical consecutive error messages are logged only once.
  /// Invariants: does not mutate widget state beyond the dedupe cache.
  void _logBridgeError(Object error) {
    final String message = error.toString();
    if (_lastLoggedBridgeError == message) {
      return;
    }
    _lastLoggedBridgeError = message;
    debugPrint('GUI_BRIDGE_ERROR $message');
  }

  /// Run one bridge command and surface failures as UI state.
  ///
  /// Purpose: prevents simulator command failures from escaping as uncaught
  /// asynchronous exceptions in the control GUI.
  /// Parameters: [command] performs one bridge-backed action and may refresh
  /// local state before it completes.
  /// Return value: future completed after the command succeeds or the error is
  /// stored for display.
  /// Requirements: safe to call only while the widget is mounted.
  /// Guarantees: successful commands clear any stale error text; failed commands
  /// update [_error] instead of rethrowing.
  /// Invariants: does not bypass [widget.client] or mutate simulator state
  /// directly.
  Future<void> _runBridgeCommand(Future<void> Function() command) async {
    try {
      await command();
      if (!mounted) {
        return;
      }
      setState(() {
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  /// Build the live emulator control app.
  ///
  /// Purpose: adapts nullable async bridge state into renderable app inputs.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: configured [EmulatorControlApp].
  /// Requirements: may be called before bridge data arrives.
  /// Guarantees: always returns a valid widget.
  /// Invariants: build does not perform bridge I/O directly.
  @override
  Widget build(BuildContext context) {
    return EmulatorControlApp(
      health: _health,
      snapshot: _snapshot,
      bakSnapshot: _bakSnapshot,
      error: _error,
      onKeyStateChange: (request) async {
        await _runBridgeCommand(() async {
          await widget.client.setKeyState(request);
          await _refreshLedSnapshot();
        });
      },
      onKeyPatternPlay: (path) async {
        await _runBridgeCommand(() async {
          await widget.client.playKeyPattern(path: path);
        });
      },
      onKeyPatternLoop: (path) async {
        await _runBridgeCommand(() async {
          await widget.client.loopKeyPattern(path: path);
        });
      },
      onKeyPatternStop: () async {
        await _runBridgeCommand(() async {
          await widget.client.stopKeyPattern();
        });
      },
      onBakButtonTap: (index) async {
        await _runBridgeCommand(() async {
          await widget.client.tapBakButton(index: index);
          await _refreshStatusAndBak();
        });
      },
      onBakKnobRotate: (index, delta) async {
        await _runBridgeCommand(() async {
          await widget.client.rotateBakKnob(index: index, delta: delta);
          await _refreshStatusAndBak();
        });
      },
      onBakKnobSetRaw: (index, raw) async {
        await _runBridgeCommand(() async {
          await widget.client.setBakKnobRaw(index: index, raw: raw);
          await _refreshStatusAndBak();
        });
      },
      onBakKnobSetNormalized: (index, value) async {
        await _runBridgeCommand(() async {
          await widget.client.setBakKnobNormalized(index: index, value: value);
          await _refreshStatusAndBak();
        });
      },
    );
  }
}

/// Material app for the emulator control GUI.
///
/// Purpose: provides theme and top-level screen composition for emulator tools.
/// Parameters: [health] and [snapshot] are latest bridge states; callbacks send
/// simulator commands; [error] is an optional bridge failure message.
/// Return value: stateless app widget.
/// Requirements: callbacks must be safe to call from UI taps.
/// Guarantees: does not perform network I/O during build.
/// Invariants: this app remains outside Dog Paw app registry ownership.
class EmulatorControlApp extends StatelessWidget {
  const EmulatorControlApp({
    required this.health,
    required this.snapshot,
    required this.bakSnapshot,
    required this.onKeyStateChange,
    required this.onKeyPatternPlay,
    required this.onKeyPatternLoop,
    required this.onKeyPatternStop,
    required this.onBakButtonTap,
    required this.onBakKnobRotate,
    required this.onBakKnobSetRaw,
    required this.onBakKnobSetNormalized,
    this.error,
    super.key,
  });

  final BridgeHealth? health;
  final LedSnapshot? snapshot;
  final BakSnapshot? bakSnapshot;
  final String? error;
  final KeyStateChangeHandler onKeyStateChange;
  final KeyPatternPathHandler onKeyPatternPlay;
  final KeyPatternPathHandler onKeyPatternLoop;
  final KeyPatternStopHandler onKeyPatternStop;
  final BakButtonTapHandler onBakButtonTap;
  final BakKnobRotateHandler onBakKnobRotate;
  final BakKnobSetRawHandler onBakKnobSetRaw;
  final BakKnobSetNormalizedHandler onBakKnobSetNormalized;

  /// Build the themed emulator control UI.
  ///
  /// Purpose: renders the title, bridge status, key grid, and BAK controls.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: [MaterialApp] containing the emulator control screen.
  /// Requirements: none.
  /// Guarantees: does not mutate bridge state.
  /// Invariants: visual layout remains desktop-tool oriented.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dog Paw Emulator Control',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF86D7FF),
          secondary: Color(0xFFFFD166),
          surface: Color(0xFF17212B),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F151B),
      ),
      home: EmulatorControlScreen(
        health: health,
        snapshot: snapshot,
        bakSnapshot: bakSnapshot,
        error: error,
        onKeyStateChange: onKeyStateChange,
        onKeyPatternPlay: onKeyPatternPlay,
        onKeyPatternLoop: onKeyPatternLoop,
        onKeyPatternStop: onKeyPatternStop,
        onBakButtonTap: onBakButtonTap,
        onBakKnobRotate: onBakKnobRotate,
        onBakKnobSetRaw: onBakKnobSetRaw,
        onBakKnobSetNormalized: onBakKnobSetNormalized,
      ),
    );
  }
}

/// Main screen for emulator simulator controls.
///
/// Purpose: groups bridge status, 8x8 key-grid controls, and BAK controls.
/// Parameters: [health], [snapshot], [error], and callbacks mirror
/// [EmulatorControlApp].
/// Return value: stateless screen widget.
/// Requirements: callbacks must tolerate unavailable simulator sockets.
/// Guarantees: displays unavailable backend state visibly.
/// Invariants: key grid uses Dog Paw logical row orientation.
class EmulatorControlScreen extends StatelessWidget {
  const EmulatorControlScreen({
    required this.health,
    required this.snapshot,
    required this.bakSnapshot,
    required this.onKeyStateChange,
    required this.onKeyPatternPlay,
    required this.onKeyPatternLoop,
    required this.onKeyPatternStop,
    required this.onBakButtonTap,
    required this.onBakKnobRotate,
    required this.onBakKnobSetRaw,
    required this.onBakKnobSetNormalized,
    this.error,
    super.key,
  });

  final BridgeHealth? health;
  final LedSnapshot? snapshot;
  final BakSnapshot? bakSnapshot;
  final String? error;
  final KeyStateChangeHandler onKeyStateChange;
  final KeyPatternPathHandler onKeyPatternPlay;
  final KeyPatternPathHandler onKeyPatternLoop;
  final KeyPatternStopHandler onKeyPatternStop;
  final BakButtonTapHandler onBakButtonTap;
  final BakKnobRotateHandler onBakKnobRotate;
  final BakKnobSetRawHandler onBakKnobSetRaw;
  final BakKnobSetNormalizedHandler onBakKnobSetNormalized;

  /// Build the emulator control screen.
  ///
  /// Purpose: lays out all first-pass emulator hardware controls.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: screen scaffold.
  /// Requirements: none.
  /// Guarantees: all interactive elements have touch-friendly sizes.
  /// Invariants: layout does not depend on Dog Paw app launcher state.
  @override
  Widget build(BuildContext context) {
    final health = this.health;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dog Paw Emulator Control',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open control guide',
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (dialogContext) {
                          return AlertDialog(
                            title: const Text('Emulator control guide'),
                            content: const SizedBox(
                              width: 420,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Left click presses a key. Right click sends the active state.',
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'The main Run workflow starts the screen, bridge, and controls together.',
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Use Screen when you want only the emulator display without the control GUI.',
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Buttons and knobs stay disabled until the bridge reports that backend as online.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dialogContext).pop(),
                                child: const Text('Close'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    icon: const Icon(Icons.help_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _BridgeStatus(health: health, error: error),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _Panel(
                        title: 'Key Grid',
                        child: _KeyGrid(
                          snapshot: snapshot,
                          enabled: health?.socketAvailable('keyGrid') == true,
                          onKeyStateChange: onKeyStateChange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Offstage(
                            offstage: true,
                            child: _KeyPatternControls(
                              enabled: health?.socketAvailable('keyGrid') ==
                                  true,
                              onPlay: onKeyPatternPlay,
                              onLoop: onKeyPatternLoop,
                              onStop: onKeyPatternStop,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: _Panel(
                              title: 'BAK Controls',
                              child: _BakControls(
                                snapshot: bakSnapshot,
                                enabled:
                                    health?.socketAvailable('buttonsAndKnobs') ==
                                        true,
                                onButtonTap: onBakButtonTap,
                                onKnobRotate: onBakKnobRotate,
                                onKnobSetRaw: onBakKnobSetRaw,
                                onKnobSetNormalized: onBakKnobSetNormalized,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BridgeStatus extends StatelessWidget {
  const _BridgeStatus({required this.health, required this.error});

  final BridgeHealth? health;
  final String? error;

  /// Build bridge and simulator readiness labels.
  ///
  /// Purpose: makes connection state obvious before users press controls.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: wrapping row of status chips.
  /// Requirements: none.
  /// Guarantees: renders loading and error states.
  /// Invariants: does not poll or send bridge requests.
  @override
  Widget build(BuildContext context) {
    final health = this.health;
    if (health == null) {
      return Text(error == null ? 'Bridge: loading' : 'Bridge: $error');
    }
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _StatusChip(
            label: 'Bridge: ${health.emulatorName} / ${health.instanceName}'),
        _StatusChip(
          label: 'KeyGrid: ${_availabilityLabel(health, 'keyGrid')}',
        ),
        _StatusChip(
          label:
              'ButtonsAndKnobs: ${_availabilityLabel(health, 'buttonsAndKnobs')}',
        ),
        _StatusChip(
          label: 'LEDComms: ${_availabilityLabel(health, 'ledComms')}',
        ),
        if (error != null && error!.isNotEmpty)
          _StatusChip(label: 'Error: $error'),
      ],
    );
  }

  /// Convert socket readiness into a short status label.
  ///
  /// Purpose: keeps bridge status wording consistent.
  /// Parameters: [health] is the decoded bridge health; [name] is a socket key.
  /// Return value: `online` or `offline`.
  /// Requirements: [name] should be one of the bridge socket names.
  /// Guarantees: missing sockets render as offline.
  /// Invariants: [health] is not mutated.
  String _availabilityLabel(BridgeHealth health, String name) {
    return health.socketAvailable(name) ? 'online' : 'offline';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  /// Build one status chip.
  ///
  /// Purpose: visually groups a single bridge readiness value.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: decorated label widget.
  /// Requirements: [label] should be concise.
  /// Guarantees: uses readable padding and contrast.
  /// Invariants: chip is display-only.
  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  /// Build a titled control panel.
  ///
  /// Purpose: gives major emulator control groups a consistent container.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: decorated panel widget.
  /// Requirements: [child] should fit within available panel space.
  /// Guarantees: includes the panel title above content.
  /// Invariants: panel does not own control state.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _KeyGrid extends StatefulWidget {
  const _KeyGrid({
    required this.snapshot,
    required this.enabled,
    required this.onKeyStateChange,
  });

  final LedSnapshot? snapshot;
  final bool enabled;
  final KeyStateChangeHandler onKeyStateChange;

  @override
  State<_KeyGrid> createState() => _KeyGridState();
}

class _PointerSession {
  const _PointerSession({
    required this.col,
    required this.row,
    required this.state,
    required this.tileSize,
    required this.lastLocalPosition,
  });

  final int col;
  final int row;
  final EmulatorKeyState state;
  final Size tileSize;
  final Offset lastLocalPosition;

  _PointerSession copyWith({
    EmulatorKeyState? state,
    Size? tileSize,
    Offset? lastLocalPosition,
  }) {
    return _PointerSession(
      col: col,
      row: row,
      state: state ?? this.state,
      tileSize: tileSize ?? this.tileSize,
      lastLocalPosition: lastLocalPosition ?? this.lastLocalPosition,
    );
  }
}

class _KeyGridState extends State<_KeyGrid> {
  final Map<int, _PointerSession> _pointerSessions = <int, _PointerSession>{};
  final Map<String, EmulatorKeyState> _visualStates = <String, EmulatorKeyState>{};

  /// Build the 8x8 Dog Paw key grid.
  ///
  /// Purpose: renders LED state and interactive key-state controls for the
  /// PicoComms simulator.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: grid widget with logical row 7 at the top.
  /// Requirements: [widget.onKeyStateChange] must accept logical coordinates.
  /// Guarantees: disabled grid ignores pointer input when backend is unavailable.
  /// Invariants: column 0 remains player-left and row 0 remains bottom.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.84,
        child: AspectRatio(
          aspectRatio: 1,
          child: Column(
            children: List<Widget>.generate(8, (visualRow) {
              final int row = 7 - visualRow;
              return Expanded(
                child: Row(
                  children: List<Widget>.generate(8, (col) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _KeyTile(
                          col: col,
                          row: row,
                          leftLayer: widget.snapshot?.leftKeyLayerAt(
                            col: col,
                            row: row,
                          ),
                          rightLayer: widget.snapshot?.rightKeyLayerAt(
                            col: col,
                            row: row,
                          ),
                          visualState:
                              _visualStates[_keyId(col, row)] ??
                              EmulatorKeyState.rest,
                          enabled: widget.enabled,
                          onPointerDown: _handlePointerDown,
                          onPointerMove: _handlePointerMove,
                          onPointerUp: _handlePointerUp,
                          onPointerCancel: _handlePointerCancel,
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  /// Handle the start of one key-pointer interaction.
  ///
  /// Purpose: chooses active-only or pressed mode from the mouse button and
  /// forwards the initial key-state request to the bridge callback.
  /// Parameters: [col], [row], and [event] identify the key tile and pointer.
  /// Return value: future completed after any bridge callback finishes.
  /// Requirements: [event.localPosition] must be relative to the tile bounds.
  /// Guarantees: primary button overrules secondary button when both are down.
  /// Invariants: disabled grids do not create pointer sessions.
  Future<void> _handlePointerDown(
    int col,
    int row,
    PointerDownEvent event,
    Size tileSize,
  ) async {
    if (!widget.enabled) {
      return;
    }
    final EmulatorKeyState? state = _stateForButtons(event.buttons);
    if (state == null) {
      return;
    }
    final _PointerSession session = _PointerSession(
      col: col,
      row: row,
      state: state,
      tileSize: tileSize,
      lastLocalPosition: event.localPosition,
    );
    _pointerSessions[event.pointer] = session;
    await _sendSessionState(session);
  }

  /// Handle pointer motion for one held key.
  ///
  /// Purpose: keeps pressure, bend, and left-overrides-right semantics updated
  /// while the mouse is held over one key tile.
  /// Parameters: [col], [row], and [event] identify the tile and pointer.
  /// Return value: future completed after any bridge callback finishes.
  /// Requirements: pointer must already have an active session.
  /// Guarantees: state upgrades to pressed when the primary button becomes active.
  /// Invariants: coordinates are validated when the session starts.
  Future<void> _handlePointerMove(
    int col,
    int row,
    PointerMoveEvent event,
    Size tileSize,
  ) async {
    final _PointerSession? currentSession = _pointerSessions[event.pointer];
    if (currentSession == null || currentSession.col != col || currentSession.row != row) {
      return;
    }
    final EmulatorKeyState nextState =
        _stateForButtons(event.buttons) ?? currentSession.state;
    final _PointerSession updatedSession = currentSession.copyWith(
      state: nextState,
      tileSize: tileSize,
      lastLocalPosition: event.localPosition,
    );
    _pointerSessions[event.pointer] = updatedSession;
    await _sendSessionState(updatedSession);
  }

  /// Handle the end of one key-pointer interaction.
  ///
  /// Purpose: sends the final release request so the simulator returns the key
  /// to rest using the last release-position-derived velocity.
  /// Parameters: [col], [row], and [event] identify the tile and pointer.
  /// Return value: future completed after any bridge callback finishes.
  /// Requirements: pointer must already have an active session.
  /// Guarantees: removes the pointer session after sending the release update.
  /// Invariants: release always clears the local visual state for that key.
  Future<void> _handlePointerUp(
    int col,
    int row,
    PointerUpEvent event,
    Size tileSize,
  ) async {
    final _PointerSession? currentSession = _pointerSessions.remove(event.pointer);
    if (currentSession == null || currentSession.col != col || currentSession.row != row) {
      return;
    }
    final _PointerSession releasedSession = currentSession.copyWith(
      tileSize: tileSize,
      lastLocalPosition: event.localPosition,
    );
    await _sendState(
      releasedSession,
      EmulatorKeyState.rest,
      clearVisualState: true,
    );
  }

  /// Handle a cancelled pointer sequence for one key.
  ///
  /// Purpose: clears local key state when Flutter cancels an in-progress mouse
  /// interaction before a normal pointer-up arrives.
  /// Parameters: [col], [row], and [event] identify the tile and pointer.
  /// Return value: future completed after local cleanup finishes.
  /// Requirements: none.
  /// Guarantees: clears any stored session and visual state for that key.
  /// Invariants: does not attempt a bridge request after cancellation.
  Future<void> _handlePointerCancel(
    int col,
    int row,
    PointerCancelEvent event,
    Size tileSize,
  ) async {
    _pointerSessions.remove(event.pointer);
    if (!mounted) {
      return;
    }
    setState(() {
      _visualStates.remove(_keyId(col, row));
    });
  }

  /// Send the current state for one active pointer session.
  ///
  /// Purpose: keeps the bridge callback call site small while preserving the
  /// local visual state that mirrors the requested key state.
  /// Parameters: [session] describes the held pointer interaction.
  /// Return value: future completed after the bridge callback finishes.
  /// Requirements: [session] must contain valid key coordinates.
  /// Guarantees: updates the tile's local visual state before awaiting the bridge.
  /// Invariants: local visual state uses [EmulatorKeyState.rest] removal instead
  /// of storing redundant rest entries.
  Future<void> _sendSessionState(_PointerSession session) async {
    await _sendState(session, session.state);
  }

  /// Send one desired state for the current pointer session.
  ///
  /// Purpose: converts local pointer coordinates into normalized bend, pressure,
  /// and velocity values for the bridge callback.
  /// Parameters: [session] holds the current pointer location and key identity;
  /// [state] is the target logical key state; [clearVisualState] removes the
  /// local state badge after the callback when true.
  /// Return value: future completed after the bridge callback finishes.
  /// Requirements: [session.lastLocalPosition] must be relative to one key tile.
  /// Guarantees: uses the same normalized value mapping for down, move, and up.
  /// Invariants: local state remains `pressed` when both primary and secondary
  /// buttons are held.
  Future<void> _sendState(
    _PointerSession session,
    EmulatorKeyState state, {
    bool clearVisualState = false,
  }) async {
    if (!mounted) {
      return;
    }
    final KeyInteractionRequest request = _requestFromSession(session, state);
    setState(() {
      if (clearVisualState || state == EmulatorKeyState.rest) {
        _visualStates.remove(_keyId(session.col, session.row));
      } else {
        _visualStates[_keyId(session.col, session.row)] = state;
      }
    });
    await widget.onKeyStateChange(request);
  }

  /// Build one bridge request from the local pointer session.
  ///
  /// Purpose: centralizes the pointer-to-key-position mapping used for active,
  /// pressed, drag, and release updates.
  /// Parameters: [session] identifies the key and local pointer position;
  /// [state] is the desired logical key state.
  /// Return value: normalized bridge request payload model.
  /// Requirements: [session.lastLocalPosition] must use key-tile local
  /// coordinates.
  /// Guarantees: horizontal bend and velocity remain in range -1..1 and 0..1.
  /// Invariants: release requests still include the last pointer-derived
  /// velocity, but their vertical position returns to rest.
  KeyInteractionRequest _requestFromSession(
    _PointerSession session,
    EmulatorKeyState state,
  ) {
    final double xFraction =
        (session.lastLocalPosition.dx / session.tileSize.width).clamp(0.0, 1.0);
    final double yFraction =
        (session.lastLocalPosition.dy / session.tileSize.height).clamp(0.0, 1.0);
    return KeyInteractionRequest(
      col: session.col,
      row: session.row,
      state: state,
      velocity: yFraction,
      vertical: _verticalForState(state, yFraction),
      horizontal: (xFraction * 2.0) - 1.0,
    );
  }

  /// Map normalized pointer height to one vertical key position.
  ///
  /// Purpose: keeps active-only and pressed interactions in their respective
  /// vertical travel ranges while still using one pointer coordinate.
  /// Parameters: [state] is the desired key state; [yFraction] is the pointer
  /// height normalized to 0..1 from top to bottom.
  /// Return value: normalized key vertical position in range -1..1.
  /// Requirements: [yFraction] must already be clamped to 0..1.
  /// Guarantees: rest maps to `1.0`, active maps to `1..0`, and pressed maps to
  /// `0..-1`.
  /// Invariants: top-of-tile always represents the shallowest interaction.
  double _verticalForState(EmulatorKeyState state, double yFraction) {
    switch (state) {
      case EmulatorKeyState.rest:
        return 1.0;
      case EmulatorKeyState.active:
        return 1.0 - yFraction;
      case EmulatorKeyState.pressed:
        return -yFraction;
    }
  }

  /// Choose the desired key state from one mouse-button bitmask.
  ///
  /// Purpose: implements the phase rule that left click presses while right
  /// click activates, and that left click overrules right click.
  /// Parameters: [buttons] is the Flutter pointer button mask.
  /// Return value: desired [EmulatorKeyState], or null when no relevant button
  /// is active.
  /// Requirements: [buttons] must come from a Flutter pointer event.
  /// Guarantees: primary wins when both primary and secondary are present.
  /// Invariants: only primary and secondary buttons affect key state.
  EmulatorKeyState? _stateForButtons(int buttons) {
    if ((buttons & kPrimaryMouseButton) != 0) {
      return EmulatorKeyState.pressed;
    }
    if ((buttons & kSecondaryMouseButton) != 0) {
      return EmulatorKeyState.active;
    }
    return null;
  }

  /// Build the stable map key for one logical key coordinate.
  ///
  /// Purpose: keeps local visual-state storage independent from Flutter widget
  /// identity and pointer IDs.
  /// Parameters: [col] and [row] are logical Dog Paw coordinates.
  /// Return value: stable string key for local maps.
  /// Requirements: coordinates should be in range 0..7.
  /// Guarantees: same coordinate pair always yields the same string.
  /// Invariants: returned key is used only for local widget state.
  String _keyId(int col, int row) {
    return '$col,$row';
  }
}

typedef _KeyPointerDownHandler =
    Future<void> Function(int col, int row, PointerDownEvent event, Size tileSize);
typedef _KeyPointerMoveHandler =
    Future<void> Function(int col, int row, PointerMoveEvent event, Size tileSize);
typedef _KeyPointerUpHandler =
    Future<void> Function(int col, int row, PointerUpEvent event, Size tileSize);
typedef _KeyPointerCancelHandler =
    Future<void> Function(int col, int row, PointerCancelEvent event, Size tileSize);

class _KeyTile extends StatelessWidget {
  const _KeyTile({
    required this.col,
    required this.row,
    required this.leftLayer,
    required this.rightLayer,
    required this.visualState,
    required this.enabled,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  final int col;
  final int row;
  final LedKeyLayer? leftLayer;
  final LedKeyLayer? rightLayer;
  final EmulatorKeyState visualState;
  final bool enabled;
  final _KeyPointerDownHandler onPointerDown;
  final _KeyPointerMoveHandler onPointerMove;
  final _KeyPointerUpHandler onPointerUp;
  final _KeyPointerCancelHandler onPointerCancel;

  /// Build one key-grid tile.
  ///
  /// Purpose: shows split left/right LED colors plus active or pressed state
  /// indicators for one logical key.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: pointer-aware key tile widget.
  /// Requirements: [col] and [row] should be valid Dog Paw coordinates.
  /// Guarantees: unavailable LEDs render as dark halves.
  /// Invariants: local visual state badges do not mutate simulator state on
  /// their own.
  @override
  Widget build(BuildContext context) {
    final Color leftColor = _layerColor(leftLayer);
    final Color rightColor = _layerColor(rightLayer);
    final Color borderColor = switch (visualState) {
      EmulatorKeyState.rest => const Color(0xFF31414F),
      EmulatorKeyState.active => const Color(0xFFFFD166),
      EmulatorKeyState.pressed => const Color(0xFF86D7FF),
    };
    final String? badgeLabel = switch (visualState) {
      EmulatorKeyState.rest => null,
      EmulatorKeyState.active => 'A',
      EmulatorKeyState.pressed => 'P',
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size tileSize = constraints.biggest;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 3),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: enabled
                  ? (event) {
                      unawaited(onPointerDown(col, row, event, tileSize));
                    }
                  : null,
              onPointerMove: enabled
                  ? (event) {
                      unawaited(onPointerMove(col, row, event, tileSize));
                    }
                  : null,
              onPointerUp: enabled
                  ? (event) {
                      unawaited(onPointerUp(col, row, event, tileSize));
                    }
                  : null,
              onPointerCancel: enabled
                  ? (event) {
                      unawaited(onPointerCancel(col, row, event, tileSize));
                    }
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ColoredBox(
                          color: enabled ? leftColor : const Color(0xFF20262C),
                        ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color:
                              enabled ? rightColor : const Color(0xFF20262C),
                        ),
                      ),
                    ],
                  ),
                  Center(
                    child: Text(
                      '$col,$row',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (badgeLabel != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F151B).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            badgeLabel,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Convert one optional LED layer into the tile-half background color.
  ///
  /// Purpose: keeps split left/right LED rendering readable when a half has no
  /// visible retained color.
  /// Parameters: [layer] is the visible LED layer for one key half, if present.
  /// Return value: display color for that key half.
  /// Requirements: none.
  /// Guarantees: missing layers render as the default dark key color.
  /// Invariants: color conversion does not mutate [layer].
  Color _layerColor(LedKeyLayer? layer) {
    return ledLayerToKeyTileColor(layer);
  }
}

class _KeyPatternControls extends StatefulWidget {
  const _KeyPatternControls({
    required this.enabled,
    required this.onPlay,
    required this.onLoop,
    required this.onStop,
  });

  final bool enabled;
  final KeyPatternPathHandler onPlay;
  final KeyPatternPathHandler onLoop;
  final KeyPatternStopHandler onStop;

  @override
  State<_KeyPatternControls> createState() => _KeyPatternControlsState();
}

class _KeyPatternControlsState extends State<_KeyPatternControls> {
  late final TextEditingController _pathController;
  String? _loadedPath;

  /// Initialize the editable path controller for key patterns.
  ///
  /// Purpose: lets the widget hold a pending path before users press Load.
  /// Parameters: none.
  /// Return value: none.
  /// Requirements: none.
  /// Guarantees: starts with an empty editable path.
  /// Invariants: controller lifetime matches the widget state lifetime.
  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController();
  }

  /// Dispose the pattern-path controller when the widget is removed.
  ///
  /// Purpose: frees the text-editing resources owned by this widget state.
  /// Parameters: none.
  /// Return value: none.
  /// Requirements: none.
  /// Guarantees: controller is disposed before the state object is discarded.
  /// Invariants: does not send bridge requests during disposal.
  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  /// Build the saved key-pattern controls.
  ///
  /// Purpose: gives the GUI a simple local-file workflow for loading, playing,
  /// looping, and stopping saved key patterns.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: column of path and playback controls.
  /// Requirements: callbacks must tolerate invalid file paths being rejected by
  /// the bridge.
  /// Guarantees: Load stores the current path locally without reading the file in
  /// Flutter.
  /// Invariants: Play and Loop use the last loaded path instead of the raw text
  /// field contents.
  @override
  Widget build(BuildContext context) {
    final String? loadedPath = _loadedPath;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pathController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Pattern path',
              hintText: '/path/to/pattern.json',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: widget.enabled ? _loadPatternPath : null,
                child: const Text('Load'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loadedPath == null || loadedPath.isEmpty
                      ? 'No pattern loaded'
                      : loadedPath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: widget.enabled && loadedPath != null
                    ? () {
                        unawaited(widget.onPlay(loadedPath));
                      }
                    : null,
                child: const Text('Play'),
              ),
              FilledButton(
                onPressed: widget.enabled && loadedPath != null
                    ? () {
                        unawaited(widget.onLoop(loadedPath));
                      }
                    : null,
                child: const Text('Loop'),
              ),
              OutlinedButton(
                onPressed: widget.enabled
                    ? () {
                        unawaited(widget.onStop());
                      }
                    : null,
                child: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Store the current text-field value as the loaded key-pattern path.
  ///
  /// Purpose: makes the load step explicit so play and loop commands use one
  /// stable chosen path until the user loads another one.
  /// Parameters: none.
  /// Return value: none.
  /// Requirements: widget must still be mounted.
  /// Guarantees: blank or whitespace-only paths clear the loaded path.
  /// Invariants: does not read files or send bridge requests.
  void _loadPatternPath() {
    final String trimmedPath = _pathController.text.trim();
    setState(() {
      _loadedPath = trimmedPath.isEmpty ? null : trimmedPath;
    });
  }
}

class _BakControls extends StatelessWidget {
  const _BakControls({
    required this.snapshot,
    required this.enabled,
    required this.onButtonTap,
    required this.onKnobRotate,
    required this.onKnobSetRaw,
    required this.onKnobSetNormalized,
  });

  final BakSnapshot? snapshot;
  final bool enabled;
  final BakButtonTapHandler onButtonTap;
  final BakKnobRotateHandler onKnobRotate;
  final BakKnobSetRawHandler onKnobSetRaw;
  final BakKnobSetNormalizedHandler onKnobSetNormalized;

  /// Build buttons-and-knobs simulator controls.
  ///
  /// Purpose: exposes BAK button state plus raw and normalized knob controls.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: scrollable list of BAK controls.
  /// Requirements: callbacks should send bridge commands.
  /// Guarantees: controls are disabled when the backend is unavailable.
  /// Invariants: raw and normalized controls both route through the bridge.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              for (var index = 0; index < 6; index++)
                _BakControlRow(
                  index: index,
                  button: snapshot?.buttonAt(index) ??
                      BakButtonState(index: index, pressed: false),
                  knob: snapshot?.knobAt(index) ??
                      BakKnobState(index: index, raw: 0, normalized: 0.5),
                  enabled: enabled,
                  onButtonTap: onButtonTap,
                  onKnobRotate: onKnobRotate,
                  onKnobSetRaw: onKnobSetRaw,
                  onKnobSetNormalized: onKnobSetNormalized,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BakControlRow extends StatelessWidget {
  const _BakControlRow({
    required this.index,
    required this.button,
    required this.knob,
    required this.enabled,
    required this.onButtonTap,
    required this.onKnobRotate,
    required this.onKnobSetRaw,
    required this.onKnobSetNormalized,
  });

  final int index;
  final BakButtonState button;
  final BakKnobState knob;
  final bool enabled;
  final BakButtonTapHandler onButtonTap;
  final BakKnobRotateHandler onKnobRotate;
  final BakKnobSetRawHandler onKnobSetRaw;
  final BakKnobSetNormalizedHandler onKnobSetNormalized;

  /// Build one BAK button/knob control row.
  ///
  /// Purpose: combines current pressed state, raw encoder controls, and a
  /// normalized 0..1 slider for one BAK control index.
  /// Parameters: [context] is the Flutter build context.
  /// Return value: row widget for one BAK index.
  /// Requirements: callbacks should send bridge commands for [index].
  /// Guarantees: disabled rows do not issue bridge requests.
  /// Invariants: raw control changes do not directly edit normalized state.
  @override
  Widget build(BuildContext context) {
    final normalizedPercent = (knob.normalized * 100).round();
    final rawSliderValue = knob.raw.clamp(-100, 100).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF202A34),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: enabled ? () => onButtonTap(index) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            button.pressed ? const Color(0xFF2E7D32) : null,
                      ),
                      child: Text(
                        button.pressed ? 'Button $index down' : 'Button $index',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Raw: ${knob.raw}'),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: enabled
                        ? () => onKnobRotate(
                              index,
                              bakDisplayedRotationDeltaToSimulatorDelta(-1),
                            )
                        : null,
                    icon: const Icon(Icons.remove),
                    tooltip: 'Rotate knob $index left',
                  ),
                  IconButton.filled(
                    onPressed: enabled
                        ? () => onKnobRotate(
                              index,
                              bakDisplayedRotationDeltaToSimulatorDelta(1),
                            )
                        : null,
                    icon: const Icon(Icons.add),
                    tooltip: 'Rotate knob $index right',
                  ),
                ],
              ),
              Slider(
                value: rawSliderValue,
                min: -100,
                max: 100,
                divisions: 200,
                label: knob.raw.toString(),
                onChanged: enabled
                    ? (value) => onKnobSetRaw(
                          index,
                          bakDisplayedRawValueToSimulatorRaw(value.round()),
                        )
                    : null,
              ),
              Row(
                children: [
                  SizedBox(width: 42, child: Text('$normalizedPercent%')),
                  Expanded(
                    child: Slider(
                      value: knob.normalized.clamp(0.0, 1.0),
                      min: 0,
                      max: 1,
                      divisions: 100,
                      label: knob.normalized.toStringAsFixed(2),
                      onChanged: enabled
                          ? (value) => onKnobSetNormalized(index, value)
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
