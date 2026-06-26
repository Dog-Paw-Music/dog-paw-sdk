import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter_test/flutter_test.dart';
import 'package:hello_dogpaw/controllers/hello_controller.dart';

/// Purpose:
///     Small in-test runtime double for `HelloController`.
/// Parameters:
///     None.
/// Return value:
///     Client that records connection and endpoint activity without a native
///     Epiphany runtime.
/// Requirements:
///     Tests should read the recorded fields to verify controller behavior.
/// Guarantees:
///     Returns predictable local endpoints that support queued poll batches and
///     captured LED writes.
/// Invariants:
///     No native runtime or socket work occurs.
class FakeHelloDogPawClient implements HelloDogPawClient {
  bool connectCalled = false;
  bool disconnectCalled = false;
  bool shouldConnectSucceed = true;
  final List<String> createdEndpointNames = <String>[];
  final Map<String, FakeLocalEndpoint> endpointsByName =
      <String, FakeLocalEndpoint>{};
  final FakeConnectionHandle handle = FakeConnectionHandle();

  /// Purpose:
  ///     Simulate `HelloController.start()` connecting to Dog Paw.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     Success with a fake ready handle, or an error result when configured to
  ///     fail.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Records that a connection attempt occurred.
  /// Invariants:
  ///     Does not create endpoints by itself.
  @override
  Future<dp.ConnectionResult> connect() async {
    connectCalled = true;
    if (!shouldConnectSucceed) {
      return dp.ConnectionResult.error('mock connect failure');
    }
    return dp.ConnectionResult.success(handle);
  }

  /// Purpose:
  ///     Simulate local endpoint creation for hello-example tests.
  /// Parameters:
  ///     endpoint: Endpoint metadata that the controller requested.
  /// Return value:
  ///     Successful `FakeLocalEndpoint` preserving the supplied metadata.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Stores the created endpoint by name for later test access.
  /// Invariants:
  ///     One call creates exactly one new fake endpoint instance.
  @override
  Future<dp.Result<dp.LocalEndpoint>> createEndpoint(
    dp.EndpointInfo endpoint,
  ) async {
    createdEndpointNames.add(endpoint.name);
    final FakeLocalEndpoint localEndpoint =
        FakeLocalEndpoint.fromEndpointInfo(endpoint);
    endpointsByName[endpoint.name] = localEndpoint;
    return dp.Result.success(localEndpoint);
  }

  /// Purpose:
  ///     Simulate controller teardown releasing runtime resources.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Records that teardown happened.
  /// Invariants:
  ///     Does not mutate queued endpoint data.
  @override
  void disconnect() {
    disconnectCalled = true;
  }
}

/// Purpose:
///     Minimal `ConnectionHandle` double for hello runtime tests.
/// Parameters:
///     None.
/// Return value:
///     Handle that records completion and ready-message type.
/// Requirements:
///     None.
/// Guarantees:
///     `complete()` is idempotent and only records local state.
/// Invariants:
///     No real runtime callbacks occur.
class FakeConnectionHandle implements dp.ConnectionHandle {
  bool _completed = false;
  dp.ConnectionReadyMessageType readyMessageType =
      dp.ConnectionReadyMessageType.ready;

  /// Purpose:
  ///     Report whether the fake handle has been completed.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     `true` after `complete()` runs.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Exposes the current local completion state.
  /// Invariants:
  ///     Getter causes no side effects.
  @override
  bool get isCompleted => _completed;

  /// Purpose:
  ///     Record the ready-message type requested by the controller.
  /// Parameters:
  ///     messageType: Ready or error completion flavor.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Stores the latest requested message type.
  /// Invariants:
  ///     Does not complete the handle by itself.
  @override
  void setReadyMessage(dp.ConnectionReadyMessageType messageType) {
    readyMessageType = messageType;
  }

  /// Purpose:
  ///     Mark the fake handle complete.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     Future that completes immediately.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Sets `isCompleted` to `true`.
  /// Invariants:
  ///     Safe to call more than once.
  @override
  Future<void> complete() async {
    _completed = true;
  }
}

/// Purpose:
///     Test local endpoint that captures writes and exposes queued poll batches.
/// Parameters:
///     None.
/// Return value:
///     `LocalEndpoint` replacement safe for pure Dart tests.
/// Requirements:
///     Construct via `fromEndpointInfo()` so metadata matches controller setup.
/// Guarantees:
///     `write()` records payloads and `poll()` drains queued batches in order.
/// Invariants:
///     No native runtime delegate is required.
class FakeLocalEndpoint extends dp.LocalEndpoint {
  FakeLocalEndpoint._({
    required super.name,
    required super.spec,
    super.namespaceSelector,
  });

  final List<dynamic> writtenValues = <dynamic>[];
  final List<List<dynamic>> _queuedBatches = <List<dynamic>>[];

  /// Purpose:
  ///     Create one fake endpoint from controller-supplied endpoint metadata.
  /// Parameters:
  ///     info: Endpoint metadata created by the hello controller.
  /// Return value:
  ///     `FakeLocalEndpoint` preserving the provided metadata.
  /// Requirements:
  ///     `info` must include `spec` or `resolved`.
  /// Guarantees:
  ///     The returned endpoint is ready for in-test `write()` and `poll()` calls.
  /// Invariants:
  ///     No native delegate is attached.
  factory FakeLocalEndpoint.fromEndpointInfo(dp.EndpointInfo info) {
    final dp.EndpointSpec? initialSpec = info.spec ?? info.resolved;
    if (initialSpec == null) {
      throw StateError('FakeLocalEndpoint requires endpoint metadata.');
    }

    final FakeLocalEndpoint endpoint = FakeLocalEndpoint._(
      name: info.name,
      spec: initialSpec,
      namespaceSelector: info.namespaceSelector,
    );
    endpoint.copyMetadataFrom(info);
    return endpoint;
  }

  /// Purpose:
  ///     Queue one future poll batch for the hello controller.
  /// Parameters:
  ///     values: Decoded payloads that the next `poll()` should return.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     The next `poll()` returns `values` before any later queued batches.
  /// Invariants:
  ///     Queuing values causes no writes or runtime side effects.
  void queuePollBatch(List<dynamic> values) {
    _queuedBatches.add(List<dynamic>.from(values));
  }

  /// Purpose:
  ///     Record an output payload written by the controller.
  /// Parameters:
  ///     data: Payload value passed to `LocalEndpoint.write()`.
  /// Return value:
  ///     Always `true`.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Appends `data` to `writtenValues`.
  /// Invariants:
  ///     Never touches native transport state.
  @override
  bool write(dynamic data) {
    writtenValues.add(data);
    return true;
  }

  /// Purpose:
  ///     Return the next queued poll batch for the controller.
  /// Parameters:
  ///     connectionName: Ignored by the fake endpoint.
  /// Return value:
  ///     Next queued batch, or an empty list when none remain.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Each queued batch is returned at most once.
  /// Invariants:
  ///     Never throws when the queue is empty.
  @override
  List<dynamic> poll({String? connectionName}) {
    if (_queuedBatches.isEmpty) {
      return <dynamic>[];
    }
    return _queuedBatches.removeAt(0);
  }
}

void main() {
  test('start connects, creates endpoints, and completes the ready handle', () async {
    final FakeHelloDogPawClient client = FakeHelloDogPawClient();
    final HelloController controller = HelloController(
      client: client,
      pollInterval: const Duration(days: 1),
    );

    await controller.start();

    expect(client.connectCalled, isTrue);
    expect(client.createdEndpointNames, <String>['key_input', 'led_output']);
    expect(client.handle.isCompleted, isTrue);
    expect(controller.isReady, isTrue);
    expect(
      controller.statusMessage,
      'Connected and listening for key events.',
    );

    controller.dispose();
    expect(client.disconnectCalled, isTrue);
  });

  test(
    'key transitions create, update, and cancel one retained highlight per key',
    () async {
      final FakeHelloDogPawClient client = FakeHelloDogPawClient();
      final HelloController controller = HelloController(
        client: client,
        pollInterval: const Duration(days: 1),
      );

      await controller.start();
      final FakeLocalEndpoint keyInput =
          client.endpointsByName['key_input']!;
      final FakeLocalEndpoint ledOutput =
          client.endpointsByName['led_output']!;

      keyInput.queuePollBatch(<dynamic>[
        const dp.KeyEvent(
          type: dp.KeyEventType.activated,
          column: 2,
          row: 5,
          velocity: 0.25,
          oldState: dp.KeyState.rest,
          newState: dp.KeyState.activated,
          timestamp: 1,
        ),
      ]);
      controller.processPendingKeyEvents();

      expect(ledOutput.writtenValues, hasLength(1));
      final dp.KeyHighlightLEDMessage highlight =
          ledOutput.writtenValues.single as dp.KeyHighlightLEDMessage;
      expect(highlight.column, 2);
      expect(highlight.row, 5);
      expect(
        highlight.colorArgb,
        controller.colorForState(HelloHighlightState.active),
      );

      keyInput.queuePollBatch(<dynamic>[
        const dp.KeyEvent(
          type: dp.KeyEventType.pressed,
          column: 2,
          row: 5,
          velocity: 0.75,
          oldState: dp.KeyState.activated,
          newState: dp.KeyState.pressed,
          timestamp: 2,
        ),
      ]);
      controller.processPendingKeyEvents();

      expect(ledOutput.writtenValues, hasLength(2));
      final dp.AnimationColorUpdateLEDMessage pressedUpdate =
          ledOutput.writtenValues[1] as dp.AnimationColorUpdateLEDMessage;
      expect(pressedUpdate.clientInstanceId, highlight.clientInstanceId);
      expect(
        pressedUpdate.colorArgb,
        controller.colorForState(HelloHighlightState.pressed),
      );

      keyInput.queuePollBatch(<dynamic>[
        const dp.KeyEvent(
          type: dp.KeyEventType.released,
          column: 2,
          row: 5,
          velocity: 0,
          oldState: dp.KeyState.pressed,
          newState: dp.KeyState.rest,
          timestamp: 3,
        ),
      ]);
      controller.processPendingKeyEvents();

      expect(ledOutput.writtenValues, hasLength(3));
      final dp.AnimationCancelLEDMessage cancel =
          ledOutput.writtenValues[2] as dp.AnimationCancelLEDMessage;
      expect(cancel.clientInstanceId, highlight.clientInstanceId);
    },
  );

  test('changing a swatch updates currently tracked keys for that state', () async {
    final FakeHelloDogPawClient client = FakeHelloDogPawClient();
    final HelloController controller = HelloController(
      client: client,
      pollInterval: const Duration(days: 1),
    );

    await controller.start();
    final FakeLocalEndpoint keyInput =
        client.endpointsByName['key_input']!;
    final FakeLocalEndpoint ledOutput =
        client.endpointsByName['led_output']!;

    keyInput.queuePollBatch(<dynamic>[
      const dp.KeyEvent(
        type: dp.KeyEventType.activated,
        column: 1,
        row: 1,
        velocity: 0.2,
        oldState: dp.KeyState.rest,
        newState: dp.KeyState.activated,
        timestamp: 10,
      ),
    ]);
    controller.processPendingKeyEvents();

    controller.selectColor(HelloHighlightState.active, 0xFFFFC107);

    expect(ledOutput.writtenValues, hasLength(2));
    final dp.AnimationColorUpdateLEDMessage update =
        ledOutput.writtenValues[1] as dp.AnimationColorUpdateLEDMessage;
    expect(update.colorArgb, 0xFFFFC107);
  });
}
