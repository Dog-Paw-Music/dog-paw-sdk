// CRUD test framework for data types (KV, Theme, Scale, Layout).
//
// This framework enables writing CRUD tests once and running them
// against KV, Theme, Scale, and Layout data types.
//
// Mirrors the C++ CRUDTestFramework in dogPawEntity/tests/gtest/integration/

import 'dart:async';

import '../../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

/// Callback type for subscriptions (matches DogPawEntity pattern)
/// Note: Dart API uses dynamic for the item type in callbacks
typedef ItemChangeCallback = void Function(
    String notificationType, DataItemRef ref, dynamic item);

/// Traits class for CRUD operations on a specific data type.
///
/// Implement this for each data type (KV, Theme, Scale, Layout)
/// to enable the generic CRUD test suite.
abstract class CRUDTestTraits<T> {
  /// Type name for error messages
  String get typeName;

  /// Create a test item with the given name
  T createTestItem(String name);

  /// Create a modified version of the item (for update tests)
  T modifyItem(T original);

  /// Check if two items are equal (for content comparison tests)
  bool itemsEqual(T a, T b);

  /// CRUD operations
  Future<Result<bool>> create(DogPawEntity entity, T item);
  Future<Result<T?>> read(
      DogPawEntity entity, String name, NamespaceSelector ns);
  Future<Result<bool>> update(DogPawEntity entity, T item);
  Future<Result<bool>> set(DogPawEntity entity, T item);
  Future<Result<bool>> delete(
      DogPawEntity entity, String name, NamespaceSelector ns);
  Future<Result<List<T>>> list(DogPawEntity entity, NamespaceSelector ns);

  /// Subscription operations
  Future<Result<bool>> subscribe(DogPawEntity entity,
      ItemChangeCallback callback, String name, NamespaceSelector ns);
  Future<Result<bool>> unsubscribe(
      DogPawEntity entity, String name, NamespaceSelector ns);

  /// Namespace manipulation (for testing namespace isolation)
  T setGlobalNamespace(T item);
  T setSpecificEntityNamespace(T item, String entityName);

  /// Get the item's name
  String getName(T item);
}

/// Registers all standard CRUD tests for a given data type.
///
/// This includes:
/// - Basic CRUD operations (create, read, update, set, delete)
/// - Namespace access tests
/// - List tests
/// - Subscription tests
/// - Error handling tests
/// - Persistence tests
/// - Stress tests
///
/// Usage:
/// ```dart
/// void main() {
///   IntegrationTestFixture.register();
///
///   group('KV CRUD', () {
///     late TestEntities entities;
///     setUp(() async => entities = await TestEntities.create());
///     tearDown(() async => await entities.dispose());
///
///     registerCRUDTests(KVTestTraits(), () => entities);
///   });
/// }
/// ```
void registerCRUDTests<T>(
  CRUDTestTraits<T> traits,
  TestEntities Function() getEntities,
) {
  // ===========================================================================
  // Basic CRUD Tests
  // ===========================================================================

  test('CreateSucceeds', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('test_item'));
    final result = await traits.create(entities.entity1, item);
    expect(result.success, isTrue, reason: 'Create failed: ${result.error}');
    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  test('CreateDuplicateFails', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('test_item'));

    final result1 = await traits.create(entities.entity1, item);
    expect(result1.success, isTrue,
        reason: 'Initial create failed: ${result1.error}');

    final result2 = await traits.create(entities.entity1, item);
    expect(result2.success, isFalse, reason: 'Duplicate create should fail');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  test('ReadReturnsCreatedItem', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('test_item'));

    await traits.create(entities.entity1, item);
    final readResult = await traits.read(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());

    expect(readResult.success, isTrue,
        reason: 'Read failed: ${readResult.error}');
    expect(readResult.value, isNotNull, reason: 'Read should return value');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  test('ReadNonexistentReturnsNull', () async {
    final entities = getEntities();
    final readResult = await traits.read(
        entities.entity1,
        'definitely_does_not_exist_12345',
        const NamespaceSelector.currentEntity());

    expect(readResult.success, isTrue,
        reason: 'Read should succeed even for missing item');
    expect(readResult.value, isNull,
        reason: 'Non-existent item should return null');
  });

  test('UpdateExistingSucceeds', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('test_item'));

    await traits.create(entities.entity1, item);
    final modified = traits.modifyItem(item);
    final result = await traits.update(entities.entity1, modified);

    expect(result.success, isTrue, reason: 'Update failed: ${result.error}');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  test('UpdateNonexistentFails', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('test_item'));

    final result = await traits.update(entities.entity1, item);
    expect(result.success, isFalse, reason: 'Update non-existent should fail');
  });

  test('SetCreatesNewItem', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('test_item'));

    final result = await traits.set(entities.entity1, item);
    expect(result.success, isTrue, reason: 'Set new failed: ${result.error}');

    final readResult = await traits.read(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
    expect(readResult.value, isNotNull, reason: 'Item should exist after set');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  test('SetUpdatesExistingItem', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('test_item'));

    await traits.create(entities.entity1, item);
    final modified = traits.modifyItem(item);
    final result = await traits.set(entities.entity1, modified);

    expect(result.success, isTrue,
        reason: 'Set existing failed: ${result.error}');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  test('DeleteRemovesItem', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('test_item'));

    await traits.create(entities.entity1, item);
    final delResult = await traits.delete(entities.entity1,
        traits.getName(item), const NamespaceSelector.currentEntity());

    expect(delResult.success, isTrue,
        reason: 'Delete failed: ${delResult.error}');

    final readResult = await traits.read(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
    expect(readResult.value, isNull,
        reason: 'Item should not exist after delete');
  });

  test('DeleteNonexistentHandlesGracefully', () async {
    final entities = getEntities();
    final result = await traits.delete(
        entities.entity1,
        'definitely_does_not_exist_12345',
        const NamespaceSelector.currentEntity());
    expect(result.success, isTrue,
        reason: 'Delete non-existent should handle gracefully');
  });

  test('MultipleUpdatesSucceed', () async {
    final entities = getEntities();
    var item = traits.createTestItem(uniqueName('test_item'));

    await traits.create(entities.entity1, item);

    for (int i = 0; i < 5; i++) {
      final modified = traits.modifyItem(item);
      final result = await traits.update(entities.entity1, modified);
      expect(result.success, isTrue,
          reason: 'Update $i failed: ${result.error}');
      item = modified;
    }

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  // ===========================================================================
  // Namespace Tests
  // ===========================================================================

  test('GlobalNamespaceAccessibleFromAllEntities', () async {
    final entities = getEntities();
    var item = traits.createTestItem(uniqueName('global_item'));
    item = traits.setGlobalNamespace(item);

    final setResult = await traits.set(entities.entity1, item);
    expect(setResult.success, isTrue,
        reason: 'Set global item failed: ${setResult.error}');

    // entity2 can read it
    final read2 = await traits.read(entities.entity2, traits.getName(item),
        const NamespaceSelector.global());
    expect(read2.success, isTrue);
    expect(read2.value, isNotNull, reason: 'Entity2 should read global');

    // entity3 can read it
    final read3 = await traits.read(entities.entity3, traits.getName(item),
        const NamespaceSelector.global());
    expect(read3.success, isTrue);
    expect(read3.value, isNotNull, reason: 'Entity3 should read global');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.global());
  });

  test('EntityNamespaceVisibleViaSpecificEntity', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('entity_item'));

    final setResult = await traits.set(entities.entity1, item);
    expect(setResult.success, isTrue);

    // entity3 can read via specificEntity
    final read3 = await traits.read(entities.entity3, traits.getName(item),
        NamespaceSelector.specificEntity(entities.entity1.getEntityName()));
    expect(read3.success, isTrue,
        reason: 'Read from other entity namespace failed: ${read3.error}');
    expect(read3.value, isNotNull,
        reason: 'Item should be visible from other entity');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  test('EntityNamespaceNotEditableByOtherEntities', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('entity_item'));

    final setResult = await traits.set(entities.entity1, item);
    expect(setResult.success, isTrue);

    // entity3 should NOT be able to update it
    var modified = traits.modifyItem(item);
    modified = traits.setSpecificEntityNamespace(
        modified, entities.entity1.getEntityName());
    final updateResult = await traits.update(entities.entity3, modified);

    expect(updateResult.success, isFalse,
        reason: 'Other entity should not be able to edit item');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  test('SameNameDifferentNamespacesDontInterfere', () async {
    final entities = getEntities();
    final name = uniqueName('shared_name');

    // Create in global namespace
    var globalItem = traits.createTestItem(name);
    globalItem = traits.setGlobalNamespace(globalItem);
    await traits.set(entities.entity1, globalItem);

    // Create in entity namespace with same name (modified content)
    var entityItem = traits.createTestItem(name);
    entityItem = traits.modifyItem(entityItem);
    await traits.set(entities.entity1, entityItem);

    // Read both - should be different
    final readGlobal = await traits.read(
        entities.entity1, name, const NamespaceSelector.global());
    final readEntity = await traits.read(
        entities.entity1, name, const NamespaceSelector.currentEntity());

    expect(readGlobal.value, isNotNull);
    expect(readEntity.value, isNotNull);
    expect(traits.itemsEqual(readGlobal.value as T, readEntity.value as T),
        isFalse,
        reason: 'Items in different namespaces should be different');

    await traits.delete(
        entities.entity1, name, const NamespaceSelector.global());
    await traits.delete(
        entities.entity1, name, const NamespaceSelector.currentEntity());
  });

  // ===========================================================================
  // List Tests
  // ===========================================================================

  test('ListFromOtherEntity', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('list_test'));

    await traits.set(entities.entity1, item);

    // entity3 lists from entity1's namespace
    final listResult = await traits.list(entities.entity3,
        NamespaceSelector.specificEntity(entities.entity1.getEntityName()));
    expect(listResult.success, isTrue);

    bool found = false;
    for (final listed in listResult.value!) {
      if (traits.getName(listed) == traits.getName(item)) {
        found = true;
        break;
      }
    }
    expect(found, isTrue,
        reason: 'Item should appear in list from other entity');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  // ===========================================================================
  // Subscription Tests
  // ===========================================================================

  test('SubscribeReceivesChanges', () async {
    final entities = getEntities();
    final name = uniqueName('subscribe_test');
    int notificationCount = 0;

    final subResult = await traits.subscribe(
      entities.entity1,
      (notificationType, ref, item) {
        notificationCount++;
      },
      name,
      NamespaceSelector.specificEntity(entities.entity2.getEntityName()),
    );
    expect(subResult.success, isTrue,
        reason: 'Subscribe failed: ${subResult.error}');

    // entity2 sets the item in its namespace
    final item = traits.createTestItem(name);
    await traits.set(entities.entity2, item);

    await Future.delayed(const Duration(milliseconds: 500));

    expect(notificationCount, greaterThanOrEqualTo(1),
        reason: 'Should receive notification');

    await traits.unsubscribe(entities.entity1, name,
        NamespaceSelector.specificEntity(entities.entity2.getEntityName()));
    await traits.delete(
        entities.entity2, name, const NamespaceSelector.currentEntity());
  });

  test('UnsubscribeStopsNotifications', () async {
    final entities = getEntities();
    final name = uniqueName('unsub_test');
    int notificationCount = 0;

    await traits.subscribe(
      entities.entity1,
      (notificationType, ref, item) {
        notificationCount++;
      },
      name,
      NamespaceSelector.specificEntity(entities.entity2.getEntityName()),
    );

    // Trigger notification
    final item = traits.createTestItem(name);
    await traits.set(entities.entity2, item);
    await Future.delayed(const Duration(milliseconds: 200));

    final countAfterFirst = notificationCount;
    expect(countAfterFirst, greaterThanOrEqualTo(1));

    // Unsubscribe
    await traits.unsubscribe(entities.entity1, name,
        NamespaceSelector.specificEntity(entities.entity2.getEntityName()));

    // Trigger another change
    final modified = traits.modifyItem(item);
    await traits.set(entities.entity2, modified);
    await Future.delayed(const Duration(milliseconds: 200));

    expect(notificationCount, equals(countAfterFirst),
        reason: 'Should not receive more notifications after unsubscribe');

    await traits.delete(
        entities.entity2, name, const NamespaceSelector.currentEntity());
  });

  // ===========================================================================
  // Error Handling Tests
  // ===========================================================================

  test('LongNameAccepted', () async {
    final entities = getEntities();
    final longName = 'k' * 1000;
    final item = traits.createTestItem(longName);

    final result = await traits.set(entities.entity1, item);
    expect(result.success, isTrue,
        reason: 'Long name should be accepted: ${result.error}');

    final readResult = await traits.read(
        entities.entity1, longName, const NamespaceSelector.currentEntity());
    expect(readResult.value, isNotNull);

    await traits.delete(
        entities.entity1, longName, const NamespaceSelector.currentEntity());
  });

  test('SpecialCharactersAccepted', () async {
    final entities = getEntities();
    const specialName = 'item with spaces & punctuation! @#\$%^&*()';
    final item = traits.createTestItem(specialName);

    final result = await traits.set(entities.entity1, item);
    expect(result.success, isTrue,
        reason: 'Special characters should be accepted: ${result.error}');

    final readResult = await traits.read(
        entities.entity1, specialName, const NamespaceSelector.currentEntity());
    expect(readResult.value, isNotNull);

    await traits.delete(
        entities.entity1, specialName, const NamespaceSelector.currentEntity());
  });

  // ===========================================================================
  // Persistence Tests
  // ===========================================================================

  test('SurvivesReconnect', () async {
    final entities = getEntities();
    final item = traits.createTestItem(uniqueName('persist_item'));

    final setResult = await traits.set(entities.entity1, item);
    expect(setResult.success, isTrue);

    // Disconnect and reconnect entity1
    entities.entity1.disconnect();
    final reconnectResult = await entities.entity1.connect();
    expect(reconnectResult.success, isTrue, reason: 'Reconnect failed');
    await reconnectResult.handle?.complete();

    await Future.delayed(const Duration(milliseconds: 200));

    // Read the item - should persist
    final readResult = await traits.read(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
    expect(readResult.success, isTrue);
    expect(readResult.value, isNotNull,
        reason: 'Item should persist after reconnect');

    await traits.delete(entities.entity1, traits.getName(item),
        const NamespaceSelector.currentEntity());
  });

  // ===========================================================================
  // Stress Tests
  // ===========================================================================

  test('ManyCreatedConcurrently', () async {
    final entities = getEntities();
    const numItems = 50;
    final futures = <Future<Result<bool>>>[];
    final names = <String>[];

    for (int i = 0; i < numItems; i++) {
      final name = uniqueName('stress_item');
      names.add(name);
      final item = traits.createTestItem(name);
      futures.add(traits.set(entities.entity1, item));
    }

    int successCount = 0;
    for (final future in futures) {
      final result = await future;
      if (result.success) successCount++;
    }

    expect(successCount, equals(numItems),
        reason: 'All concurrent sets should succeed');

    // Verify all exist
    final listResult = await traits.list(
        entities.entity1, const NamespaceSelector.currentEntity());
    expect(listResult.value!.length, greaterThanOrEqualTo(numItems));

    // Cleanup
    for (final name in names) {
      await traits.delete(
          entities.entity1, name, const NamespaceSelector.currentEntity());
    }
  });
}
