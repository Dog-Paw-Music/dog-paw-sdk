import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/ffi/native_bridge.dart';
import 'package:dogpaw/src/ffi/native_dogpaw_entity.dart';

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

/// Purpose: Create one connection request and delete it shortly afterward to
/// force a realized connection add/remove notification cycle.
///
/// Parameters:
/// - [producer]: connected producer entity that owns the source endpoint.
/// - [producerEntityName]: logical producer entity name for source references.
/// - [requestName]: unique connection-request name for this cycle.
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
/// - The request is removed before the function returns.
///
/// Invariants:
/// - Leaves no durable connection-request record behind.
Future<void> _createAndDeleteConnectionRequest(
  NativeDogPawEntityClient producer, {
  required String producerEntityName,
  required String requestName,
  required String sourceEndpointName,
  required String consumerEntityName,
  required String destinationEndpointName,
}) async {
  final Result<bool> createResult = await producer.createConnectionRequest(
    ConnectionRequest(
      name: requestName,
      spec: ConnectionRequestData(
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
      'Failed to create probe connection request $requestName: '
      '${createResult.error}',
    );
  }

  await Future<void>.delayed(_connectionCountProbeDeleteDelay);

  final Result<bool> deleteResult =
      await producer.deleteConnectionRequest(requestName);
  if (!deleteResult.success) {
    throw StateError(
      'Failed to delete probe connection request $requestName: '
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
  final String consumerEntityName =
      rawMessage['consumerEntityName']! as String;
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
        await _createAndDeleteConnectionRequest(
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

/// Runs one deterministic native-bridge logging scenario in a fresh process.
///
/// Purpose:
/// Lets unit tests observe the real stdout/stderr emitted by the FFI bridge for
/// expected startup-poll and shutdown-timeout cases without sharing state with
/// the parent test process.
///
/// Parameters:
/// - [args]: Exactly one scenario name. Supported values are
///   `missing_port_file_check`, `wait_process_timeout`, and
///   `connection_count_deadlock_probe`.
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
  }

  throw ArgumentError('Unknown scenario: ${args.first}');
}
