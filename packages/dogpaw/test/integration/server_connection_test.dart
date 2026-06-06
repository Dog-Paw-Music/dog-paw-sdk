// Integration tests for DogPawEntity server connection.
//
// These tests require Epiphany server to be running.
// The IntegrationTestFixture automatically starts/stops the server.
//
// RUN WITH: flutter test test/integration/server_connection_test.dart
// (not dart test - this package depends on Flutter)
//
// NOTE: These tests mirror the C++ equivalent tests in
// dogPawEntity/tests/gtest/integration/ServerConnectionTests.cpp
import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

void main() {
  // Auto-start Epiphany before tests, stop after all tests complete
  IntegrationTestFixture.register();

  group('Basic Connection Tests', () {
    test('EntityStartsDisconnected', () {
      final entity = DogPawEntity('TestEntity');
      expect(entity.isConnected(), isFalse);
    });

    test('ConnectEstablishesConnection', () async {
      final entity = DogPawEntity('ConnectionTestEntity');
      final result = await entity.connect();

      expect(result.success, isTrue);
      expect(entity.isConnected(), isTrue);

      entity.disconnect();
    });

    test('EntityNameIsAssignedCorrectly', () async {
      final entity = DogPawEntity('MyTestEntity');
      final result = await entity.connect();
      expect(result.success, isTrue,
          reason:
              'Failed to connect entity to Epiphany server: ${result.error}');

      expect(entity.getEntityName(), equals('MyTestEntity'));

      entity.disconnect();
    });

    test('EntityNameDefaultsFromOverrideWhenConstructorOmitted', () async {
      addTearDown(() => DogPawEntity.entityNameOverride = null);
      DogPawEntity.entityNameOverride = 'OverrideEntity';

      final entity = DogPawEntity();
      final result = await entity.connect();
      expect(result.success, isTrue,
          reason:
              'Failed to connect entity to Epiphany server: ${result.error}');

      expect(entity.getEntityName(), equals('OverrideEntity'));

      entity.disconnect();
    });
  });

  group('Multi-Entity Connection Tests', () {
    test('TwoDifferentEntitiesCanConnect', () async {
      final entity1 = DogPawEntity('Entity1');
      final entity2 = DogPawEntity('Entity2');

      final result1 = await entity1.connect();
      final result2 = await entity2.connect();

      expect(result1.success, isTrue);
      expect(result2.success, isTrue);
      expect(entity1.getEntityName(), isNot(equals(entity2.getEntityName())));

      entity2.disconnect();
      entity1.disconnect();
    });
  });

  group('Error Handling Tests', () {
    test('DuplicateEntityNameIsRejected', () async {
      final entity1 = DogPawEntity('DuplicateName');
      final entity2 = DogPawEntity('DuplicateName');

      final result1 = await entity1.connect();
      expect(result1.success, isTrue,
          reason: 'First connection should succeed: ${result1.error}');

      final result2 = await entity2.connect();
      expect(result2.success, isFalse,
          reason: 'Duplicate entity name should be rejected');

      entity1.disconnect();
    });

    test('DisconnectAllowsReconnect', () async {
      final entity = DogPawEntity('ReconnectEntity');

      // First connection
      final result1 = await entity.connect();
      expect(result1.success, isTrue,
          reason: 'First connection should succeed: ${result1.error}');
      expect(entity.isConnected(), isTrue);

      // Disconnect
      entity.disconnect();
      expect(entity.isConnected(), isFalse);

      // Reconnect
      final result2 = await entity.connect();
      expect(result2.success, isTrue,
          reason: 'Second connection should succeed: ${result2.error}');
      expect(entity.isConnected(), isTrue);

      entity.disconnect();
    });

    test('ExplicitDefaultServerUrlStillConnects', () async {
      final DogPawEntity entity =
          DogPawEntity('ExplicitDefaultServerUrlEntity');

      final ConnectionResult connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason:
              'Default localhost URL should connect through native resolution: ${connectResult.error}');

      await connectResult.handle!.complete();
      expect(entity.isConnected(), isTrue);

      entity.disconnect();
    });
  });
}
