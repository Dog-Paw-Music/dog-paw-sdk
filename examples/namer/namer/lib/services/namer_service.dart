import 'dart:async';
import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw/dogpaw.dart';
import 'package:namer/services/namer_highlight_tracker.dart';

/// Service that handles all communication with the Epiphany system.
///
/// Responsibilities:
/// - Managing DogPawEntity connection
/// - Creating and managing endpoints (key input, LED output, scoped layout view)
/// - Tracking the shared layout view and maintaining key-to-note mapping
/// - Sending LED messages
/// - Providing callbacks for key events and layout updates
///
/// The DogPawEntity is injected via constructor for testability.
/// Callbacks are also injected to allow the controller to handle state updates.
class NamerService {
  final dp.DogPawEntity _entity;
  final void Function(int col, int row, int noteVal, dp.KeyState state) onKeyEvent;
  final void Function() onLayoutUpdate;

  // Endpoints
  dp.LocalEndpoint? _keyInputEndpoint;
  dp.LocalEndpoint? _ledOutputEndpoint;

  // State
  Timer? _pollTimer;

  // Layout tracking: Maps (col, row) pairs to MIDI note values
  final Map<_KeyPosition, int> _keyToNoteVal = {};
  final NamerHighlightTracker _highlightTracker = NamerHighlightTracker();

  /// Creates a NamerService with injected dependencies.
  /// 
  /// @param entity The DogPawEntity to use for communication
  /// @param onKeyEvent Callback for key press/release events
  /// @param onLayoutUpdate Callback when layout changes
  NamerService({
    required dp.DogPawEntity entity,
    required this.onKeyEvent,
    required this.onLayoutUpdate,
  }) : _entity = entity {
    _entity.setErrorCallback((error) {
      AppLogger.error('Namer NamerService Error: $error');
    });
  }

  /// Get the local directory from the entity for persistent data storage
  String getLocalDirectory() {
    return _entity.getPersistentAppDataDirectory();
  }

  /// Get the MIDI note value for a given key position, or null if not mapped
  int? getNoteForKey(int col, int row) {
    return _keyToNoteVal[_KeyPosition(col, row)];
  }

  /// Get all key positions (as (col, row) tuples) that map to a given MIDI note value
  List<(int, int)> getKeysForNote(int noteVal) {
    return _keyToNoteVal.entries
        .where((entry) => entry.value == noteVal)
        .map((entry) => (entry.key.col, entry.key.row))
        .toList();
  }

  /// Initialize connection to Epiphany and set up endpoints.
  /// 
  /// Returns a ConnectionHandle that should be completed by the caller
  /// after the UI is ready (after first frame).
  /// 
  /// @return ConnectionHandle if successful, null if connection failed
  Future<dp.ConnectionHandle?> connect() async {
    try {
      AppLogger.info('Namer: Connecting to DogPaw server...');
      final connectionResult = await _entity.connect();

      if (connectionResult.success) {
        AppLogger.info('Namer: Connected successfully!');
        await _setupEndpoints();
        return connectionResult.handle;
      } else {
        AppLogger.error('Namer: Connection failed: ${connectionResult.error}');
        return null;
      }
    } catch (e) {
      AppLogger.error('Namer: Connection error: $e');
      return null;
    }
  }

  /// Set up all required endpoints
  Future<void> _setupEndpoints() async {
    await _setupKeyInputEndpoint();
    await _setupLEDOutputEndpoint();
    await _setupLayoutSubscription();
  }

  /// Create endpoint for receiving key press events from BladeHW
  Future<void> _setupKeyInputEndpoint() async {
    final keyInputCriteria = dp.SearchCriteria.andCombination([
      dp.SearchCriteria.fromCondition('direction', 'equals', 'output'),
      dp.SearchCriteria.fromCondition('name', 'equals', 'key_press'),
      dp.SearchCriteria.fromCondition('sourceEntity', 'equals', 'BladeHW'),
      dp.SearchCriteria.fromCondition('baseType', 'equals', 'key_press'),
    ]);

    final keyInputSpec = dp.EndpointSpec(
      displayName: 'Key Press Input',
      description: 'Receives key press events from BladeHW',
      direction: dp.EndpointDirection.input,
      dataType: const dp.DataTypeSpec(dp.DataType.keyPress),
      category: dp.EndpointCategory.messageQueue,
      connectionPolicy: dp.ConnectionPolicy(
        endpointConnectionRule: keyInputCriteria,
      ),
    );

    final keyInputEp = dp.EndpointInfo(name: 'key_input', spec: keyInputSpec);
    AppLogger.info('Namer: Creating key input endpoint...');
    final keyInputResult = await _entity.createEndpoint(keyInputEp);

    if (keyInputResult.isSuccess) {
      _keyInputEndpoint = keyInputResult.getValue();
      AppLogger.info('Namer: ✓ Key input endpoint created');
      _startPolling();
    } else {
      AppLogger.error('Namer: Failed to create key input endpoint: ${keyInputResult.getError()}');
    }
  }

  /// Create endpoint for sending LED messages to LEDComms
  Future<void> _setupLEDOutputEndpoint() async {
    final ledOutputCriteria = dp.SearchCriteria.andCombination([
      dp.SearchCriteria.fromCondition('direction', 'equals', 'input'),
      dp.SearchCriteria.fromCondition('name', 'equals', 'led_message_input'),
      dp.SearchCriteria.fromCondition('sourceEntity', 'equals', 'LEDComms'),
      dp.SearchCriteria.fromCondition('baseType', 'equals', 'led_message'),
    ]);

    final ledOutputSpec = dp.EndpointSpec(
      displayName: 'LED Message Output',
      description: 'Sends LED messages to LEDComms',
      direction: dp.EndpointDirection.output,
      dataType: const dp.DataTypeSpec(dp.DataType.ledMessage),
      category: dp.EndpointCategory.messageQueue,
      connectionPolicy: dp.ConnectionPolicy(
        endpointConnectionRule: ledOutputCriteria,
      ),
    );

    final ledOutputEp = dp.EndpointInfo(name: 'led_output', spec: ledOutputSpec);
    AppLogger.info('Namer: Creating LED output endpoint...');
    final ledOutputResult = await _entity.createEndpoint(ledOutputEp);

    if (ledOutputResult.isSuccess) {
      _ledOutputEndpoint = ledOutputResult.getValue();
      AppLogger.info('Namer: ✓ LED output endpoint created');
    } else {
      AppLogger.error('Namer: Failed to create LED output endpoint: ${ledOutputResult.getError()}');
    }
  }

  /// Subscribe to the shared scoped layout view.
  Future<void> _setupLayoutSubscription() async {
    AppLogger.info('Namer: Subscribing to shared scoped layout view...');

    final result = await _entity.subscribeToScopedLayoutView(
      (dp.ScopedLayoutView view) {
        _handleLayoutUpdate(view);
      },
      policy: const dp.LayoutViewPolicy(
        strategy: dp.LayoutViewStrategy.sharedOnly,
      ),
      sendImmediately: true,
    );

    if (result.success) {
      AppLogger.info('Namer: ✓ Subscribed to shared scoped layout view');
    } else {
      AppLogger.error('Namer: Failed to subscribe to layout: ${result.error}');
    }
  }

  /// Start polling for key press events
  void _startPolling() {
    if (_pollTimer != null && _pollTimer!.isActive) {
      return;
    }

    AppLogger.info('Namer: Starting poll timer for key input...');
    _pollTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_keyInputEndpoint == null) return;

      List<dynamic> messages = [];
      do {
        messages = _keyInputEndpoint!.poll();
        for (final message in messages) {
          _processKeyMessage(message);
        }
      } while (messages.isNotEmpty);
    });
  }

  /// Process incoming key press message
  void _processKeyMessage(dp.KeyEvent message) {
    AppLogger.info('Namer: Processing key message: ${message.toJson()}');
    try {
      final noteVal = _keyToNoteVal[_KeyPosition(message.column, message.row)];

      // Only notify if this key maps to a note
      if (noteVal != null) {
        onKeyEvent(message.column, message.row, noteVal, message.newState);
      }
    } catch (e) {
      AppLogger.error('Namer: Error processing key message: $e');
    }
  }

  /// Handle a new shared scoped layout view from Dog Paw.
  void _handleLayoutUpdate(dp.ScopedLayoutView view) {
    try {
      AppLogger.info('Namer: Received scoped layout view update');

      // Clear existing mappings
      _keyToNoteVal.clear();

      for (final MapEntry<String, int> entry
          in view.effectiveMidiNotesByKey().entries) {
        final String keyId = entry.key;
        final parts = keyId.split(',');
        if (parts.length != 2) continue;

        final int? col = int.tryParse(parts[0]);
        final int? row = int.tryParse(parts[1]);
        if (col == null || row == null) continue;

        _keyToNoteVal[_KeyPosition(col, row)] = entry.value;
      }

      AppLogger.info('Namer: Layout applied with ${_keyToNoteVal.length} key mappings');
      onLayoutUpdate();
    } catch (e) {
      AppLogger.error('Namer: Error handling layout update: $e');
    }
  }

  /// Send one or more LED messages over the Namer LED output endpoint.
  ///
  /// Parameters:
  /// - [messages]: LED messages already encoded for the public animation
  ///   surface.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - The LED output endpoint must have been created successfully.
  ///
  /// Guarantees/Postconditions:
  /// - Each message is offered to the endpoint in order until a write fails.
  ///
  /// Invariants:
  /// - This helper does not mutate the caller's message objects.
  void _sendLedMessages(Iterable<dp.LEDMessage> messages) {
    if (_ledOutputEndpoint == null) {
      AppLogger.error('Namer: LED output endpoint is null');
      return;
    }
    for (final dp.LEDMessage message in messages) {
      try {
        final bool result = _ledOutputEndpoint!.write(message);
        if (!result) {
          AppLogger.error('Namer: Failed to send LED message');
          return;
        }
      } catch (e) {
        AppLogger.error('Namer: Error sending LED message: $e');
        return;
      }
    }
  }

  /// Send retained key highlight messages for the selected notes.
  ///
  /// Highlights are owned by the app and can later be removed with
  /// [clearHighlights].
  void highlightNotes(Set<int> noteValues) {
    final Set<(int, int)> desiredKeys = <(int, int)>{};
    for (final noteVal in noteValues) {
      desiredKeys.addAll(getKeysForNote(noteVal));
    }
    _sendLedMessages(
      _highlightTracker.replaceHighlightsForKeys(
        keys: desiredKeys,
        colorArgb: 0xffffffff,
      ),
    );
  }

  /// Cancel every retained highlight currently owned by the Namer app.
  void clearHighlights() {
    _sendLedMessages(_highlightTracker.clearHighlights());
  }

  /// Disconnect and clean up
  void disconnect() {
    clearHighlights();
    _pollTimer?.cancel();
    _entity.disconnect();
  }
}

/// Helper class to use as map key for (col, row) pairs
class _KeyPosition {
  final int col;
  final int row;

  const _KeyPosition(this.col, this.row);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _KeyPosition && col == other.col && row == other.row;

  @override
  int get hashCode => col.hashCode ^ row.hashCode;
}
