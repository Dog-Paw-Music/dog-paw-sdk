// Integration tests for direct entity-to-entity messaging.
//
// These tests require Epiphany server to be running.
// The IntegrationTestFixture automatically starts/stops the server.
//
// RUN WITH: flutter test test/integration/direct_message_test.dart
// (not dart test - this package depends on Flutter)
//
// NOTE: These tests mirror the C++ equivalent tests in
// dogPawEntity/tests/gtest/integration/DirectMessageTests.cpp
import 'dart:async';

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

void main() {
  // Auto-start Epiphany before tests, stop after all tests complete
  IntegrationTestFixture.register();

  group('Direct Messages', () {
    late DogPawEntity entity1;
    late DogPawEntity entity2;
    late DogPawEntity entity3;

    int messageCount = 0;
    Map<String, dynamic> lastMessage = {};
    String lastSenderEntity = '';

    void setupMessageCallback(DogPawEntity entity) {
      entity.setDirectMessageCallback((senderEntity, message) {
        lastSenderEntity = senderEntity;
        lastMessage = message;
        messageCount++;
      });
    }

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();

      entity1 = DogPawEntity('DMTest1_$suffix');
      entity1.setErrorCallback(
          (error) => AppLogger.error('Entity1 error: $error'));
      final conn1 = await entity1.connect();
      expect(conn1.success, isTrue,
          reason: 'Failed to connect entity1: ${conn1.error}');

      entity2 = DogPawEntity('DMTest2_$suffix');
      entity2.setErrorCallback(
          (error) => AppLogger.error('Entity2 error: $error'));
      final conn2 = await entity2.connect();
      expect(conn2.success, isTrue,
          reason: 'Failed to connect entity2: ${conn2.error}');

      entity3 = DogPawEntity('DMTest3_$suffix');
      entity3.setErrorCallback(
          (error) => AppLogger.error('Entity3 error: $error'));
      final conn3 = await entity3.connect();
      expect(conn3.success, isTrue,
          reason: 'Failed to connect entity3: ${conn3.error}');

      await Future.delayed(const Duration(milliseconds: 200));

      // Reset test state
      messageCount = 0;
      lastMessage = {};
      lastSenderEntity = '';
    });

    tearDown(() async {
      entity3.disconnect();
      entity2.disconnect();
      entity1.disconnect();
    });

    test('MessageDelivered', () async {
      setupMessageCallback(entity1);

      final testMessage = {'type': 'test', 'data': 'hello'};
      final result = await entity2.sendDirectMessage(
        entity1.getEntityName(),
        testMessage,
      );

      expect(result.success, isTrue,
          reason: 'Send should succeed: ${result.error}');

      await Future.delayed(const Duration(milliseconds: 500));

      expect(messageCount, equals(1), reason: 'Message should be received');
      expect(lastMessage['type'], equals('test'));
      expect(lastMessage['data'], equals('hello'));
    });

    test('SenderInfoCorrect', () async {
      setupMessageCallback(entity1);

      final testMessage = {'content': 'sender test'};
      await entity2.sendDirectMessage(
        entity1.getEntityName(),
        testMessage,
      );

      await Future.delayed(const Duration(milliseconds: 500));

      expect(messageCount, equals(1));
      expect(lastSenderEntity, equals(entity2.getEntityName()));
    });

    test('MessageToSelfDelivered', () async {
      setupMessageCallback(entity1);

      final testMessage = {'type': 'self_message'};
      final result = await entity1.sendDirectMessage(
        entity1.getEntityName(),
        testMessage,
      );

      expect(result.success, isTrue,
          reason: 'Self-send should succeed: ${result.error}');

      await Future.delayed(const Duration(milliseconds: 500));

      expect(messageCount, equals(1),
          reason: 'Self-message should be received');
    });

    test('MessageToNonExistentEntityFails', () async {
      final testMessage = {'type': 'should_fail'};
      final result = await entity1.sendDirectMessage(
        'NonExistentEntity',
        testMessage,
      );

      expect(result.success, isFalse,
          reason: 'Message to non-existent entity should fail');
    });

    test('MultipleMessagesAllDelivered', () async {
      setupMessageCallback(entity1);

      const count = 5;
      for (int i = 0; i < count; i++) {
        final msg = {'index': i};
        await entity2.sendDirectMessage(
          entity1.getEntityName(),
          msg,
        );
      }

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(messageCount, equals(count),
          reason: 'All messages should be received');
    });
  });
}
