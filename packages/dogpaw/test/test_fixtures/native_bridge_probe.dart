import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/ffi/native_bridge.dart';
import 'package:dogpaw/src/ffi/native_dogpaw_entity.dart';
import 'package:dogpaw/src/json_constants.dart';

const Duration _connectionCountProbeChurnDuration = Duration(seconds: 6);
const Duration _connectionCountWorkerDuration = Duration(seconds: 10);
const Duration _connectionCountProbeDeleteDelay = Duration(milliseconds: 2);

/// Purpose: Establish a native-backed entity connection and consume the ready
/// handle immediately for probe scenarios.
///
/// Parameters:
/// - [client]: connected `NativeDogPawEntityClient` wrapper to initialize.
/// - [entityName]: logical entity name used only for error reporting.
///
/// Return value:
/// - `Future<void>` that completes once the native entity reports ready.
///
/// Requirements/Preconditions:
/// - [client] must not be disposed.
/// - The Epiphany test server must already be reachable.
///
/// Guarantees/Postconditions:
/// - On success, [client] is connected and its connection-start handle has been
///   completed.
///
/// Invariants:
/// - Does not mutate any global probe configuration.
Future<void> _connectAndComplete(
  NativeDogPawEntityClient client,
  String entityName,
) async {
  final Result<bool> connectResult = await client.connect();
  if (!connectResult.success) {
    throw StateError(
      'Failed to connect probe entity $entityName: ${connectResult.error}',
    );
  }
  await client.completeConnectionStart();
}

/// Purpose: Create one endpoint through the native-backed probe client and
/// assert that creation succeeded.
///
/// Parameters:
/// - [client]: connected `NativeDogPawEntityClient` issuing the request.
/// - [entityName]: logical entity name used only for error reporting.
/// - [endpoint]: endpoint metadata to create.
///
/// Return value:
/// - `Future<void>` that completes once Epiphany has accepted the endpoint.
///
/// Requirements/Preconditions:
/// - [client] must already be connected.
/// - [endpoint] must satisfy normal Dog Paw endpoint invariants.
///
/// Guarantees/Postconditions:
/// - On success, the endpoint exists for [client.entityName].
///
/// Invariants:
/// - Throws instead of silently ignoring endpoint creation failures.
Future<void> _createEndpointOrThrow(
  NativeDogPawEntityClient client,
  String entityName,
  EndpointInfo endpoint,
) async {
  final Result<EndpointInfo> result = await client.createEndpoint(endpoint);
  if (!result.success) {
    throw StateError(
      'Failed to create endpoint ${endpoint.name} for $entityName: '
      '${result.error}',
    );
  }
}

/// Purpose: Wait until one local endpoint reports at least one realized
/// connection name, or fail if routing never appears.
///
/// Parameters:
/// - [client]: connected native-backed entity that owns the local endpoint.
/// - [endpointName]: owned endpoint name to inspect.
/// - [timeout]: maximum time to wait for the first realized connection.
///
/// Return value:
/// - `Future<String>` containing the first realized connection name.
///
/// Requirements/Preconditions:
/// - [client] must already be connected.
/// - [endpointName] must already exist on [client].
///
/// Guarantees/Postconditions:
/// - Returns as soon as one realized connection appears.
/// - Throws `StateError` if no connection appears before [timeout].
///
/// Invariants:
/// - Does not modify endpoint state or payload contents.
Future<String> _waitForFirstConnectionName(
  NativeDogPawEntityClient client,
  String endpointName, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final List<String> connectionNames =
        client.listLocalEndpointConnectionNames(endpointName);
    if (connectionNames.isNotEmpty) {
      return connectionNames.first;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError(
    'Timed out waiting for realized connection on $endpointName.',
  );
}

/// Purpose: Create one connection rule and delete it shortly afterward to
/// force a realized connection add/remove notification cycle.
///
/// Parameters:
/// - [producer]: connected producer entity that owns the source endpoint.
/// - [producerEntityName]: logical producer entity name for source references.
/// - [requestName]: unique connection-rule name for this cycle.
/// - [sourceEndpointName]: producer-owned output endpoint name.
/// - [consumerEntityName]: target entity owning the destination endpoint.
/// - [destinationEndpointName]: consumer-owned input endpoint name.
///
/// Return value:
/// - `Future<void>` that completes after both create and delete succeed.
///
/// Requirements/Preconditions:
/// - [producer] must already be connected.
/// - Source and destination endpoints must already exist.
///
/// Guarantees/Postconditions:
/// - The rule is removed before the function returns.
///
/// Invariants:
/// - Leaves no durable connection-rule record behind.
Future<void> _createAndDeleteConnectionRule(
  NativeDogPawEntityClient producer, {
  required String producerEntityName,
  required String requestName,
  required String sourceEndpointName,
  required String consumerEntityName,
  required String destinationEndpointName,
}) async {
  final Result<bool> createResult = await producer.createConnectionRule(
    ConnectionRule(
      name: requestName,
      spec: ConnectionRuleData(
        sourceRef: DataItemRef.byName(
          name: sourceEndpointName,
          namespaceSelector:
              NamespaceSelector.specificEntity(producerEntityName),
        ),
        destinationRef: DataItemRef.byName(
          name: destinationEndpointName,
          namespaceSelector:
              NamespaceSelector.specificEntity(consumerEntityName),
        ),
      ),
    ),
  );
  if (!createResult.success) {
    throw StateError(
      'Failed to create probe connection rule $requestName: '
      '${createResult.error}',
    );
  }

  await Future<void>.delayed(_connectionCountProbeDeleteDelay);

  final Result<bool> deleteResult =
      await producer.deleteConnectionRule(requestName);
  if (!deleteResult.success) {
    throw StateError(
      'Failed to delete probe connection rule $requestName: '
      '${deleteResult.error}',
    );
  }
}

/// Purpose: Drive repeated synchronous local-endpoint connection-count queries
/// from a worker isolate so the probe can detect whether the bridge deadlocks.
///
/// Parameters:
/// - [rawMessage]: sendable `Map<String, Object?>` containing `sendPort`,
///   `consumerEntityName`, and `endpointNames`.
///
/// Return value:
/// - `Future<void>` that reports either `ready`, `done`, or `error` back to the
///   parent isolate through the provided [SendPort].
///
/// Requirements/Preconditions:
/// - [rawMessage] must contain the documented keys with sendable values.
/// - The Epiphany server must already be running.
///
/// Guarantees/Postconditions:
/// - On success, the worker creates the input endpoints, hammers connection
///   queries for a fixed duration, then disconnects and reports completion.
///
/// Invariants:
/// - All probe status is communicated through the provided [SendPort].
Future<void> _runConnectionCountWorkerIsolate(
  Map<String, Object?> rawMessage,
) async {
  final SendPort sendPort = rawMessage['sendPort']! as SendPort;
  final String consumerEntityName = rawMessage['consumerEntityName']! as String;
  final List<String> endpointNames =
      List<String>.from(rawMessage['endpointNames']! as List<dynamic>);
  final NativeDogPawEntityClient consumer =
      NativeDogPawEntityClient(consumerEntityName);

  try {
    await _connectAndComplete(consumer, consumerEntityName);
    for (final String endpointName in endpointNames) {
      await _createEndpointOrThrow(
        consumer,
        consumerEntityName,
        EndpointInfo(
          name: endpointName,
          spec: const EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec(DataType.int_),
            category: EndpointCategory.messageQueue,
          ),
        ),
      );
    }

    sendPort.send(<String, Object?>{'state': 'ready'});

    final DateTime deadline =
        DateTime.now().add(_connectionCountWorkerDuration);
    int iterationCount = 0;
    while (DateTime.now().isBefore(deadline)) {
      for (final String endpointName in endpointNames) {
        consumer.listLocalEndpointConnectionNames(endpointName);
        iterationCount += 1;
      }
    }

    sendPort.send(<String, Object?>{
      'state': 'done',
      'iterations': iterationCount,
    });
  } catch (error, stackTrace) {
    sendPort.send(<String, Object?>{
      'state': 'error',
      'error': '$error',
      'stackTrace': '$stackTrace',
    });
  } finally {
    if (consumer.isConnected) {
      consumer.disconnect();
    }
    await consumer.dispose();
  }
}

/// Purpose: Reproduce the bridge lock-order inversion by racing connection-count
/// FFI reads against endpoint connection churn on the same native bridge.
///
/// Parameters: None.
///
/// Return value:
/// - `Future<void>` that completes when the worker isolate survives the full
///   probe window without wedging.
///
/// Requirements/Preconditions:
/// - The Epiphany integration-test server must already be running.
///
/// Guarantees/Postconditions:
/// - On success, the probe tears down its producer entity before returning.
///
/// Invariants:
/// - Uses unique entity, endpoint, and request names per invocation.
Future<void> _runConnectionCountDeadlockProbe() async {
  final String suffix =
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
  final String producerEntityName = 'NativeBridgeDeadlockProducer_$suffix';
  final String consumerEntityName = 'NativeBridgeDeadlockConsumer_$suffix';
  final List<String> endpointNames = List<String>.generate(
    4,
    (int index) => 'native_bridge_deadlock_endpoint_${index}_$suffix',
  );
  final NativeDogPawEntityClient producer =
      NativeDogPawEntityClient(producerEntityName);
  final ReceivePort workerPort = ReceivePort();
  Isolate? workerIsolate;
  StreamSubscription<dynamic>? workerSubscription;
  final Completer<void> readyCompleter = Completer<void>();
  final Completer<Map<String, Object?>> completionCompleter =
      Completer<Map<String, Object?>>();

  try {
    await _connectAndComplete(producer, producerEntityName);
    for (final String endpointName in endpointNames) {
      await _createEndpointOrThrow(
        producer,
        producerEntityName,
        EndpointInfo(
          name: endpointName,
          spec: const EndpointSpec(
            direction: EndpointDirection.output,
            dataType: DataTypeSpec(DataType.int_),
            category: EndpointCategory.messageQueue,
          ),
        ),
      );
    }

    workerIsolate = await Isolate.spawn(
      _runConnectionCountWorkerIsolate,
      <String, Object?>{
        'sendPort': workerPort.sendPort,
        'consumerEntityName': consumerEntityName,
        'endpointNames': endpointNames,
      },
    );
    workerSubscription = workerPort.listen((dynamic rawEvent) {
      if (rawEvent is! Map) {
        return;
      }

      final Map<String, Object?> event =
          Map<String, Object?>.from(rawEvent as Map<dynamic, dynamic>);
      final String state = event['state'] as String? ?? '';
      if (state == 'ready') {
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
        return;
      }

      if (!completionCompleter.isCompleted) {
        completionCompleter.complete(event);
      }
    });

    await readyCompleter.future.timeout(const Duration(seconds: 10));

    final DateTime deadline =
        DateTime.now().add(_connectionCountProbeChurnDuration);
    int requestCounter = 0;
    while (DateTime.now().isBefore(deadline)) {
      for (final String endpointName in endpointNames) {
        final String requestName =
            'native_bridge_deadlock_request_${requestCounter}_$suffix';
        await _createAndDeleteConnectionRule(
          producer,
          producerEntityName: producerEntityName,
          requestName: requestName,
          sourceEndpointName: endpointName,
          consumerEntityName: consumerEntityName,
          destinationEndpointName: endpointName,
        );
        requestCounter += 1;
      }
    }

    final Map<String, Object?> completionMessage =
        await completionCompleter.future.timeout(const Duration(seconds: 10));
    if (completionMessage['state'] != 'done') {
      throw StateError(
        'Probe worker reported ${completionMessage['state']}: '
        '${completionMessage['error'] ?? 'unknown error'}',
      );
    }
  } finally {
    await workerSubscription?.cancel();
    workerPort.close();
    workerIsolate?.kill(priority: Isolate.immediate);
    if (producer.isConnected) {
      producer.disconnect();
    }
    await producer.dispose();
  }
}

/// Purpose: Verify that bridge-local debug events preserve handoff order even
/// when the producing native worker threads continue running afterward.
///
/// Parameters: None.
///
/// Return value:
/// - `Future<void>` that completes after the probe observes two ordered debug
///   events.
///
/// Requirements/Preconditions:
/// - The Epiphany integration-test server must already be running.
///
/// Guarantees/Postconditions:
/// - On success, the probe disconnects and disposes its native client before
///   returning.
///
/// Invariants:
/// - The expected order is `first`, then `second`.
Future<void> _runDispatcherOrderProbe() async {
  final NativeDogPawEntityClient client =
      NativeDogPawEntityClient('NativeBridgeDispatcherOrderProbe');
  final Completer<List<String>> labelsCompleter = Completer<List<String>>();
  final List<String> labels = <String>[];

  try {
    await _connectAndComplete(client, 'NativeBridgeDispatcherOrderProbe');
    client.setDebugProbeEventCallback((Map<String, dynamic> event) {
      final Map<String, dynamic> result = Map<String, dynamic>.from(
        event[JsonFields.RESULT] as Map? ?? <String, dynamic>{},
      );
      final String? label = result[JsonFields.LABEL] as String?;
      if (label == null) {
        return;
      }
      labels.add(label);
      if (labels.length == 2 && !labelsCompleter.isCompleted) {
        labelsCompleter.complete(List<String>.from(labels));
      }
    });

    if (!client.runDebugDispatcherOrderProbe()) {
      throw StateError('Failed to launch dispatcher order probe.');
    }

    final List<String> observedLabels = await labelsCompleter.future.timeout(
      const Duration(seconds: 2),
    );
    if (observedLabels.length != 2 ||
        observedLabels[0] != 'first' ||
        observedLabels[1] != 'second') {
      throw StateError(
        'Expected debug probe labels [first, second], got $observedLabels',
      );
    }
  } finally {
    if (client.isConnected) {
      client.disconnect();
    }
    await client.dispose();
  }
}

/// Purpose: Verify that bridge shutdown drains a debug event that was already
/// handed to the bridge before teardown began.
///
/// Parameters: None.
///
/// Return value:
/// - `Future<void>` that completes after one shutdown-drain debug event is
///   observed.
///
/// Requirements/Preconditions:
/// - The Epiphany integration-test server must already be running.
///
/// Guarantees/Postconditions:
/// - On success, the probe frees the native bridge after confirming delivery.
///
/// Invariants:
/// - The observed debug label must be `drain-before-shutdown`.
Future<void> _runShutdownDrainProbe() async {
  final NativeDogPawEntityClient client =
      NativeDogPawEntityClient('NativeBridgeShutdownDrainProbe');
  final Completer<String> labelCompleter = Completer<String>();

  try {
    await _connectAndComplete(client, 'NativeBridgeShutdownDrainProbe');
    client.setDebugProbeEventCallback((Map<String, dynamic> event) {
      final Map<String, dynamic> result = Map<String, dynamic>.from(
        event[JsonFields.RESULT] as Map? ?? <String, dynamic>{},
      );
      final String? label = result[JsonFields.LABEL] as String?;
      if (label != null && !labelCompleter.isCompleted) {
        labelCompleter.complete(label);
      }
    });

    if (!client.runDebugShutdownDrainProbe()) {
      throw StateError('Failed to launch shutdown drain probe.');
    }

    final String observedLabel = await labelCompleter.future.timeout(
      const Duration(seconds: 2),
    );
    if (observedLabel != 'drain-before-shutdown') {
      throw StateError(
        'Expected shutdown drain label drain-before-shutdown, got '
        '$observedLabel',
      );
    }
  } finally {
    await client.dispose();
  }
}

/// Purpose: Exercise one native-backed continuous local endpoint before and
/// after the first producer write so tests can inspect startup logging policy.
///
/// Parameters: None.
///
/// Return value:
/// - `Future<void>` that completes after one initial empty poll and one
///   successful poll after the first write.
///
/// Requirements/Preconditions:
/// - The Epiphany integration-test server must already be running.
///
/// Guarantees/Postconditions:
/// - The probe performs one startup poll before any writer publish completes.
/// - The probe then writes one scalar payload and confirms a later poll sees
///   data through the native local-endpoint bridge.
///
/// Invariants:
/// - Uses unique entity and endpoint names per invocation.
Future<void> _runContinuousStartupPollProbe() async {
  final String suffix =
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
  final String endpointName = 'native_bridge_continuous_probe_$suffix';
  final String consumerEntityName = 'ContinuousProbeConsumer_$suffix';
  final DogPawEntity producer = DogPawEntity('ContinuousProbeProducer_$suffix');
  final NativeDogPawEntityClient consumer =
      NativeDogPawEntityClient(consumerEntityName);

  try {
    final ConnectionResult producerConnect = await producer.connect();
    if (!producerConnect.success) {
      throw StateError(
        'Failed to connect probe producer: ${producerConnect.error}',
      );
    }
    await producerConnect.handle!.complete();
    await _connectAndComplete(consumer, consumerEntityName);

    final Result<LocalEndpoint> outResult =
        await producer.createEndpoint(EndpointInfo(
      name: endpointName,
      spec: EndpointSpec(
        direction: EndpointDirection.output,
        dataType: const DataTypeSpec(DataType.int_),
        category: EndpointCategory.continuous,
        connectionPolicy: ConnectionPolicy(
          endpointConnectionRule: SearchCriteria.andCombination(<SearchCriteria>[
            SearchCriteria.directionEquals(EndpointDirection.input),
            SearchCriteria.nameEquals(endpointName),
          ]),
        ),
      ),
    ));
    if (!outResult.success || outResult.value == null) {
      throw StateError(
        'Failed to create probe continuous output: ${outResult.error}',
      );
    }

    await _createEndpointOrThrow(
      consumer,
      consumerEntityName,
      EndpointInfo(
        name: endpointName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.continuous,
          connectionPolicy: ConnectionPolicy(
            endpointConnectionRule: SearchCriteria.andCombination(<SearchCriteria>[
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(endpointName),
            ]),
          ),
        ),
      ),
    );

    await _waitForFirstConnectionName(consumer, endpointName);
    final List<LocalEndpointPollPacket> initialPackets =
        consumer.pollLocalEndpointBytes(endpointName);
    if (initialPackets.isNotEmpty) {
      throw StateError(
        'Expected initial continuous poll to be empty before first write.',
      );
    }

    final bool writeResult = outResult.value!.write(42);
    if (!writeResult) {
      throw StateError('Failed to write first continuous probe payload.');
    }

    final DateTime deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final List<LocalEndpointPollPacket> packets =
          consumer.pollLocalEndpointBytes(endpointName);
      if (packets.isNotEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    throw StateError(
      'Timed out waiting for first readable continuous payload.',
    );
  } finally {
    producer.disconnect();
    if (consumer.isConnected) {
      consumer.disconnect();
    }
    await consumer.dispose();
  }
}

/// Runs one deterministic native-bridge logging scenario in a fresh process.
///
/// Purpose:
/// Lets unit tests observe the real stdout/stderr emitted by the FFI bridge for
/// expected startup-poll and shutdown-timeout cases without sharing state with
/// the parent test process.
///
/// Parameters:
/// - [args]: Exactly one scenario name. Supported values are
///   `missing_port_file_check`, `wait_process_timeout`,
///   `connection_count_deadlock_probe`, `dispatcher_order_probe`, and
///   `shutdown_drain_probe`, and `continuous_startup_poll_probe`.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - [args] contains exactly one supported scenario string.
/// - The package `.dart_tool/package_config.json` resolves `package:dogpaw`.
///
/// Guarantees/Postconditions:
/// - Exits with code `0` after exercising the selected native bridge path.
///
/// Invariants:
/// - Uses the production `DogPawBridge` implementation without test-only hooks.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Expected exactly one scenario argument.');
  }

  final DogPawBridge bridge = DogPawBridge();
  switch (args.first) {
    case 'missing_port_file_check':
      final String missingPath = [
        Directory.systemTemp.path,
        'dogpaw_bridge_probe_missing',
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
        'server_port',
      ].join(Platform.pathSeparator);
      final int result = bridge.checkServerRunningManaged(missingPath);
      if (result != -1) {
        throw StateError('Expected -1 for missing port file, got $result');
      }
      return;
    case 'wait_process_timeout':
      final int pid = bridge.spawnWithDeathSignalManaged(
        '/bin/sh',
        <String>['sh', '-c', 'sleep 2'],
        DPPBSignal.sigterm,
      );
      if (pid <= 0) {
        throw StateError('Failed to spawn probe child process: $pid');
      }
      final int waitResult = bridge.waitProcessManaged(pid, 10);
      if (waitResult != -2) {
        throw StateError('Expected timeout result -2, got $waitResult');
      }
      bridge.killProcessManaged(pid, DPPBSignal.sigkill);
      bridge.waitProcessManaged(pid, 1000);
      return;
    case 'connection_count_deadlock_probe':
      await _runConnectionCountDeadlockProbe();
      return;
    case 'dispatcher_order_probe':
      await _runDispatcherOrderProbe();
      return;
    case 'shutdown_drain_probe':
      await _runShutdownDrainProbe();
      return;
    case 'continuous_startup_poll_probe':
      await _runContinuousStartupPollProbe();
      return;
  }

  throw ArgumentError('Unknown scenario: ${args.first}');
}
