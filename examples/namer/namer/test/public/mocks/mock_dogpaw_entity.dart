import 'package:dogpaw/dogpaw.dart';

/// Mock implementation of DogPawEntity for unit testing.
/// 
/// Simulates connection, endpoint creation, subscriptions, and disconnection
/// without requiring a real Epiphany server. Allows configuring success/failure
/// responses and tracking method calls for test verification.
class MockDogPawEntity implements DogPawEntity {
  bool _isConnected = false;
  
  // Configuration
  bool shouldConnectSucceed = true;
  bool shouldCreateEndpointSucceed = true;
  bool shouldSubscribeSucceed = true;
  String localDirectory = '/tmp/namer_test';
  
  // Call tracking
  bool connectCalled = false;
  bool disconnectCalled = false;
  final List<String> createEndpointCalls = [];
  final List<String> subscriptionCalls = [];
  final Map<String, MockLocalEndpoint> createdEndpoints =
      <String, MockLocalEndpoint>{};
  
  // Stored callbacks
  void Function(ScopedLayoutView)? layoutCallback;

  @override
  Future<ConnectionResult> connect() async {
    connectCalled = true;
    if (shouldConnectSucceed) {
      _isConnected = true;
      return ConnectionResult.success(MockConnectionHandle());
    }
    return ConnectionResult.error('Mock connection failed');
  }

  @override
  Future<Result<LocalEndpoint>> createEndpoint(EndpointInfo endpoint) async {
    createEndpointCalls.add(endpoint.name);
    
    if (shouldCreateEndpointSucceed) {
      final MockLocalEndpoint createdEndpoint =
          MockLocalEndpoint.fromEndpointInfo(endpoint);
      createdEndpoints[endpoint.name] = createdEndpoint;
      return Result.success(createdEndpoint);
    }
    return Result.error('Mock createEndpoint failed');
  }

  @override
  Future<Result<bool>> subscribeToScopedLayoutView(
    void Function(ScopedLayoutView) callback, {
    required LayoutViewPolicy policy,
    bool sendImmediately = false,
  }) async {
    subscriptionCalls.add('scopedLayoutView');
    layoutCallback = callback;
    
    if (shouldSubscribeSucceed) {
      // Optionally send immediately if requested
      if (sendImmediately) {
        final ScopedLayoutView mockView = ScopedLayoutView.fromResolvedLayout(
          Layout.full(
            name: 'test_layout',
            resolved: const LayoutData(displayName: 'Test Layout'),
          ),
          policy,
        );
        callback(mockView);
      }
      return Result.success(true);
    }
    return Result.error('Mock subscription failed');
  }

  @override
  String getPersistentAppDataDirectory() {
    return localDirectory;
  }

  @override
  void disconnect() {
    disconnectCalled = true;
    _isConnected = false;
  }

  @override
  bool isConnected() => _isConnected;
  
  @override
  void setErrorCallback(void Function(String) callback) {
    // Store error callback if needed
  }

  /// Reset all tracking state for reuse between tests.
  void reset() {
    _isConnected = false;
    shouldConnectSucceed = true;
    shouldCreateEndpointSucceed = true;
    shouldSubscribeSucceed = true;
    localDirectory = '/tmp/namer_test';
    connectCalled = false;
    disconnectCalled = false;
    createEndpointCalls.clear();
    subscriptionCalls.clear();
    createdEndpoints.clear();
    layoutCallback = null;
  }

  // =========================================================================
  // Stub implementations for unused DogPawEntity methods
  // These throw if called, indicating the test needs updating
  // =========================================================================

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'MockDogPawEntity.${invocation.memberName} is not implemented. '
      'Add implementation if your test needs this method.'
    );
  }
}

/// Mock ConnectionHandle for testing.
class MockConnectionHandle implements ConnectionHandle {
  bool _completed = false;
  ConnectionReadyMessageType _messageType = ConnectionReadyMessageType.ready;
  
  @override
  bool get isCompleted => _completed;
  
  @override
  void setReadyMessage(ConnectionReadyMessageType messageType) {
    _messageType = messageType;
  }
  
  @override
  Future<void> complete() async {
    _completed = true;
  }
  
  /// Getter for tests to verify the message type.
  ConnectionReadyMessageType get messageType => _messageType;
}

/// Mock local endpoint for unit tests that need endpoint APIs without native
/// runtime wiring.
///
/// Purpose:
/// Replaces production `LocalEndpoint` runtime behavior with predictable in-test
/// `poll()` and `write()` behavior so service/controller tests do not depend on
/// a native runtime delegate.
///
/// Parameters:
/// - Construct from endpoint metadata via [fromEndpointInfo].
///
/// Return value:
/// - Concrete `LocalEndpoint` subclass safe for unit tests.
///
/// Requirements/Preconditions:
/// - The supplied endpoint info includes at least one of `spec` or `resolved`.
///
/// Guarantees/Postconditions:
/// - `write()` records values and always succeeds.
/// - `poll()` returns queued batches without requiring a native delegate.
///
/// Invariants:
/// - No real transport or shared-memory work occurs.
class MockLocalEndpoint extends LocalEndpoint {
  /// Values written through [write], in call order.
  final List<dynamic> writtenValues = <dynamic>[];

  /// Queued poll batches returned one at a time from [poll].
  final List<List<dynamic>> _queuedPollBatches = <List<dynamic>>[];

  MockLocalEndpoint._({
    required super.name,
    required super.spec,
    super.namespaceSelector,
  });

  /// Purpose: Create one mock endpoint from endpoint metadata.
  ///
  /// Parameters:
  /// - [info]: endpoint metadata returned by the mocked entity.
  ///
  /// Return value:
  /// - `MockLocalEndpoint` preserving the provided metadata.
  ///
  /// Requirements/Preconditions:
  /// - [info] includes `spec` or `resolved`.
  ///
  /// Guarantees/Postconditions:
  /// - The returned endpoint is safe to use in unit tests without a native
  ///   runtime delegate.
  ///
  /// Invariants:
  /// - Metadata matches [info] after construction.
  factory MockLocalEndpoint.fromEndpointInfo(EndpointInfo info) {
    final EndpointSpec? initialSpec = info.spec ?? info.resolved;
    if (initialSpec == null) {
      throw StateError(
        'MockLocalEndpoint requires spec or resolved metadata to initialize.',
      );
    }

    final MockLocalEndpoint endpoint = MockLocalEndpoint._(
      name: info.name,
      spec: initialSpec,
      namespaceSelector: info.namespaceSelector,
    );
    endpoint.copyMetadataFrom(info);
    return endpoint;
  }

  /// Purpose: Queue one poll batch for the next [poll] call.
  ///
  /// Parameters:
  /// - [values]: values that the next `poll()` should return.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - A subsequent `poll()` returns [values] before moving on to later queued
  ///   batches.
  ///
  /// Invariants:
  /// - Queuing values does not contact any native runtime.
  void queuePollBatch(List<dynamic> values) {
    _queuedPollBatches.add(List<dynamic>.from(values));
  }

  /// Purpose: Simulate a successful local-endpoint write in unit tests.
  ///
  /// Parameters:
  /// - [data]: payload value supplied by the caller.
  ///
  /// Return value:
  /// - Always `true`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - [data] is appended to [writtenValues].
  ///
  /// Invariants:
  /// - No native runtime delegate is required.
  @override
  bool write(dynamic data) {
    writtenValues.add(data);
    return true;
  }

  /// Purpose: Return the next queued poll batch without requiring native
  /// runtime state.
  ///
  /// Parameters:
  /// - [connectionName]: ignored by the mock.
  ///
  /// Return value:
  /// - Next queued batch, or an empty list when none are queued.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Each queued batch is returned at most once.
  ///
  /// Invariants:
  /// - No native runtime delegate is required.
  @override
  List<dynamic> poll({String? connectionName}) {
    if (_queuedPollBatches.isEmpty) {
      return <dynamic>[];
    }
    return _queuedPollBatches.removeAt(0);
  }
}
