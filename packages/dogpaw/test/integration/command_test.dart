// Integration tests for entity-to-entity command handling.
//
// These tests require Epiphany server to be running.
// The IntegrationTestFixture automatically starts/stops the server.
//
// RUN WITH: flutter test test/integration/command_test.dart
// (not dart test - this package depends on Flutter)
//
// NOTE: These tests mirror the C++ equivalent tests in
// dogPawEntity/tests/gtest/integration/CommandTests.cpp
import 'dart:async';

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

Future<void> main() async {
  final DogpawAppInstallSource launchTestStub =
      await buildLaunchTestStubInstallSource();

  // Auto-start Epiphany before tests, stop after all tests complete
  IntegrationTestFixture.register(
    configuration: DogpawIntegrationTestConfiguration(
      installedApps: <DogpawAppInstallSource>[launchTestStub],
    ),
  );

  group('Commands', () {
    late DogPawEntity entity1;
    late DogPawEntity entity2;
    late DogPawEntity entity3;

    int commandCount = 0;
    String lastCommand = '';
    Map<String, dynamic> lastParams = {};
    // ignore: unused_local_variable - captured in callbacks for debugging
    String lastCommandId = '';
    String lastSenderEntity = '';

    /// Setup command handler that auto-responds with success
    void setupAutoAckHandler(DogPawEntity entity) {
      entity.setCommandCallback((senderEntity, command, params, requestId) {
        commandCount++;
        lastCommand = command;
        lastParams = params;
        lastCommandId = requestId;
        lastSenderEntity = senderEntity;

        entity.sendCommandResponse(
          senderEntity,
          requestId,
          success: true,
          result: {'result': 'success'},
        );
      });
    }

    /// Setup command handler that responds with failure
    void setupFailHandler(DogPawEntity entity) {
      entity.setCommandCallback((senderEntity, command, params, requestId) {
        commandCount++;
        lastCommand = command;
        lastParams = params;
        lastCommandId = requestId;

        entity.sendCommandResponse(
          senderEntity,
          requestId,
          success: false,
          errorMessage: 'Test failure',
        );
      });
    }

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();

      entity1 = DogPawEntity('CmdTest1_$suffix');
      entity1.setErrorCallback(
          (error) => AppLogger.error('Entity1 error: $error'));
      final conn1 = await entity1.connect();
      expect(conn1.success, isTrue,
          reason: 'Failed to connect entity1: ${conn1.error}');
      await conn1.handle!.complete();

      entity2 = DogPawEntity('CmdTest2_$suffix');
      entity2.setErrorCallback(
          (error) => AppLogger.error('Entity2 error: $error'));
      final conn2 = await entity2.connect();
      expect(conn2.success, isTrue,
          reason: 'Failed to connect entity2: ${conn2.error}');
      await conn2.handle!.complete();

      entity3 = DogPawEntity('CmdTest3_$suffix');
      entity3.setErrorCallback(
          (error) => AppLogger.error('Entity3 error: $error'));
      final conn3 = await entity3.connect();
      expect(conn3.success, isTrue,
          reason: 'Failed to connect entity3: ${conn3.error}');
      await conn3.handle!.complete();

      await Future.delayed(const Duration(milliseconds: 200));

      // Reset test state
      commandCount = 0;
      lastCommand = '';
      lastParams = {};
      lastCommandId = '';
      lastSenderEntity = '';
    });

    tearDown(() async {
      entity3.disconnect();
      entity2.disconnect();
      entity1.disconnect();
    });

    test('CommandDelivered', () async {
      setupAutoAckHandler(entity2);

      final result = await entity1.sendCommand(
        entity2.getEntityName(),
        'test_command',
        params: {'key': 'value'},
      );

      expect(result.success, isTrue, reason: 'Command failed: ${result.error}');
      expect(lastCommand, equals('test_command'));
      expect(lastParams['key'], equals('value'));
    });

    test('CommandResponseReceived', () async {
      setupAutoAckHandler(entity2);

      final result = await entity1.sendCommand(
        entity2.getEntityName(),
        'test_command',
        params: {'key': 'value'},
      );

      expect(result.success, isTrue);
      expect(result.result['result'], equals('success'));
    });

    test('SenderInfoCorrect', () async {
      setupAutoAckHandler(entity2);

      final result = await entity1.sendCommand(
        entity2.getEntityName(),
        'test_command',
      );

      expect(result.success, isTrue);
      expect(lastSenderEntity, equals(entity1.getEntityName()));
    });

    test('CommandToSelfDelivered', () async {
      setupAutoAckHandler(entity1);

      final result = await entity1.sendCommand(
        entity1.getEntityName(),
        'self_command',
        params: {'self': true},
      );

      expect(result.success, isTrue,
          reason: 'Command to self failed: ${result.error}');
      expect(lastCommand, equals('self_command'));
      expect(lastParams['self'], equals(true));
    });

    test('CommandToNonExistentEntityFails', () async {
      final result = await entity1.sendCommand(
        'NonExistentEntity',
        'test_command',
      );

      expect(result.success, isFalse,
          reason: 'Command to non-existent entity should fail');
    });

    test('CommandFailureResponseHandled', () async {
      setupFailHandler(entity2);

      final result = await entity1.sendCommand(
        entity2.getEntityName(),
        'fail_command',
      );

      expect(result.success, isFalse);
      expect(result.error, equals('Test failure'));
    });

    test('AsyncCommandWithAcceptedAcknowledgment', () async {
      String? savedRequestId;
      String savedSenderEntity = '';

      // Setup handler that sends accepted, then later sends completed
      entity2.setCommandCallback((senderEntity, command, params, requestId) {
        commandCount++;
        lastCommand = command;
        savedRequestId = requestId;
        savedSenderEntity = senderEntity;

        // Send accepted immediately
        entity2.sendCommandAccepted(
          savedSenderEntity,
          requestId,
        );
      });

      bool acceptedCallbackCalled = false;

      final future = entity1.sendCommand(
        entity2.getEntityName(),
        'async_command',
        timeout: const Duration(seconds: 5),
        waitForCompletion: true,
        onAccepted: (result) {
          acceptedCallbackCalled = true;
        },
      );

      // Wait for accepted callback
      await Future.delayed(const Duration(milliseconds: 500));
      expect(acceptedCallbackCalled, isTrue,
          reason: 'Accepted callback not called');

      // Now send completed response
      entity2.sendCommandResponse(
        savedSenderEntity,
        savedRequestId!,
        success: true,
        result: {'async_result': true},
      );

      final result = await future;
      expect(result.success, isTrue);
      expect(result.result['async_result'], equals(true));
    });

    test('MultipleCommandsAllDelivered', () async {
      setupAutoAckHandler(entity2);

      const numCommands = 5;
      final futures = <Future<CommandResponseResult>>[];

      for (int i = 0; i < numCommands; i++) {
        futures.add(entity1.sendCommand(
          entity2.getEntityName(),
          'batch_command',
          params: {'index': i},
        ));
      }

      for (final future in futures) {
        final result = await future;
        expect(result.success, isTrue);
      }

      expect(commandCount, equals(numCommands));
    });

    test('EmptyParamsHandled', () async {
      setupAutoAckHandler(entity2);

      final result = await entity1.sendCommand(
        entity2.getEntityName(),
        'no_params_command',
        // No params argument
      );

      expect(result.success, isTrue);
      expect(lastParams.isEmpty, isTrue);
    });

    test('CommandCanLaunchRegisteredTargetBeforeRouting', () async {
      const deliveryPolicy = CommandDeliveryPolicy(
        ifTargetMissing: CommandTargetMissingPolicy.launchIfRegistered,
        waitForReady: true,
      );

      final result = await entity1.sendCommand(
        'launch_test_stub',
        'launch_routed_command',
        waitForCompletion: false,
        timeout: const Duration(seconds: 5),
        deliveryPolicy: deliveryPolicy,
      );

      expect(
        result.success,
        isTrue,
        reason:
            'Command should route after launching registered target: ${result.error}',
      );
    });

    test('CommandLaunchPolicyStillFailsForUnknownEntity', () async {
      const deliveryPolicy = CommandDeliveryPolicy(
        ifTargetMissing: CommandTargetMissingPolicy.launchIfRegistered,
        waitForReady: true,
      );

      final result = await entity1.sendCommand(
        'totally_missing_entity_for_command_test',
        'launch_routed_command',
        waitForCompletion: false,
        timeout: const Duration(seconds: 5),
        deliveryPolicy: deliveryPolicy,
      );

      expect(
        result.success,
        isFalse,
        reason: 'Unknown entity should still fail even with launchIfRegistered',
      );
    });
  });
}
