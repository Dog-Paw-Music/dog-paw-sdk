// Integration tests for Key-Value store operations.
//
// This file contains:
// - KVTestTraits implementation for CRUD operations
// - Standard CRUD tests (via the reusable framework)
// - KV-specific tests that can't be generalized
//
// RUN WITH: flutter test test/integration/kv_test.dart --concurrency=1

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

import 'crud/crud_test_framework.dart';

// =============================================================================
// KV Traits Implementation
// =============================================================================

class KVTestTraits implements CRUDTestTraits<KV> {
  @override
  String get typeName => 'KV';

  @override
  KV createTestItem(String name) {
    return KV(name: name, value: 'test_value_$name');
  }

  @override
  KV modifyItem(KV original) {
    return KV(name: original.name, value: 'modified_${original.value ?? ""}');
  }

  @override
  bool itemsEqual(KV a, KV b) {
    return a.name == b.name && a.value == b.value;
  }

  @override
  String getName(KV item) => item.name;

  @override
  Future<Result<bool>> create(DogPawEntity entity, KV item) {
    return entity.createKV(item);
  }

  @override
  Future<Result<KV?>> read(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.readKV(name,
        namespaceSelector: ns, includeResolved: true, includeSpec: true);
  }

  @override
  Future<Result<bool>> update(DogPawEntity entity, KV item) {
    return entity.updateKV(item);
  }

  @override
  Future<Result<bool>> set(DogPawEntity entity, KV item) {
    return entity.setKV(item);
  }

  @override
  Future<Result<bool>> delete(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.deleteKV(name, namespaceSelector: ns);
  }

  @override
  Future<Result<List<KV>>> list(DogPawEntity entity, NamespaceSelector ns) {
    return entity.listKVs(
        namespaceSelector: ns, includeResolved: true, includeSpec: true);
  }

  @override
  Future<Result<bool>> subscribe(DogPawEntity entity,
      ItemChangeCallback callback, String name, NamespaceSelector ns) {
    return entity.subscribeToKV(callback,
        key: name,
        namespaceSelector: ns,
        includeResolved: true,
        includeSpec: true);
  }

  @override
  Future<Result<bool>> unsubscribe(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.unsubscribeFromKV(key: name, namespaceSelector: ns);
  }

  @override
  KV setGlobalNamespace(KV item) {
    return KV(
        name: item.name,
        value: item.value ?? '',
        namespaceSelector: const NamespaceSelector.global());
  }

  @override
  KV setSpecificEntityNamespace(KV item, String entityName) {
    return KV(
        name: item.name,
        value: item.value ?? '',
        namespaceSelector: NamespaceSelector.specificEntity(entityName));
  }
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // Auto-start Epiphany before tests, stop after all tests complete
  IntegrationTestFixture.register();

  // Standard CRUD Tests (includes namespace, subscription, error handling, persistence, stress)
  group('KV CRUD', () {
    late TestEntities entities;

    setUp(() async {
      entities = await TestEntities.create();
    });

    tearDown(() async {
      await entities.dispose();
    });

    registerCRUDTests(KVTestTraits(), () => entities);
  });

  // =============================================================================
  // KV-Specific Tests
  // =============================================================================

  group('KV Specific', () {
    integrationTest('ListWithResolvedFlagIncludesValues', () async {
      final entities = await TestEntities.create();
      try {
        final name = uniqueName('resolved_test');
        final testKV = KV(name: name, value: 'resolved_value');
        await entities.entity1.setKV(testKV);

        // List with resolved=true
        final listResult = await entities.entity1.listKVs(
          namespaceSelector: const NamespaceSelector.currentEntity(),
          includeResolved: true,
          includeSpec: false,
        );
        expect(listResult.success, isTrue);

        for (final kv in listResult.value!) {
          if (kv.name == name) {
            expect(kv.value, isNotNull,
                reason: 'Value should be included with resolved=true');
            expect(kv.value, equals('resolved_value'));
            break;
          }
        }

        await entities.entity1.deleteKV(name,
            namespaceSelector: const NamespaceSelector.currentEntity());
      } finally {
        await entities.dispose();
      }
    });
  });
}
