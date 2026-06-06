// Integration tests for Scale operations.
//
// This file contains:
// - ScaleTestTraits implementation for CRUD operations
// - Standard CRUD tests (via the reusable framework)
//
// RUN WITH: flutter test test/integration/scale_test.dart --concurrency=1

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

import 'crud/crud_test_framework.dart';

// =============================================================================
// Scale Traits Implementation
// =============================================================================

class ScaleTestTraits implements CRUDTestTraits<Scale> {
  @override
  String get typeName => 'Scale';

  @override
  Scale createTestItem(String name) {
    // Create a C Major scale (same as C++ Scale::FromKey(name, "C", MAJOR))
    return Scale(
      name: name,
      spec: const ScaleData(
        displayName: 'C Major',
        rootNote: 0, // C
        noteCategories: [
          0,
          -1,
          0,
          -1,
          0,
          0,
          -1,
          0,
          -1,
          0,
          -1,
          0
        ], // Major scale pattern
      ),
    );
  }

  @override
  Scale modifyItem(Scale original) {
    // Create a D Major scale (same as C++ Scale::FromKey(name, "D", MAJOR))
    return Scale(
      name: original.name,
      spec: ScaleData(
        displayName: 'Modified ${original.name}',
        rootNote: 2, // D
        noteCategories: [
          0,
          -1,
          0,
          -1,
          0,
          0,
          -1,
          0,
          -1,
          0,
          -1,
          0
        ], // Major scale pattern
      ),
    );
  }

  @override
  bool itemsEqual(Scale a, Scale b) {
    // Compare by name and rootNote (use data getter which prefers resolved over spec)
    if (a.name != b.name) return false;
    if (!a.hasSpecData && !a.hasResolvedData) {
      return !b.hasSpecData && !b.hasResolvedData;
    }
    if (!b.hasSpecData && !b.hasResolvedData) return false;
    return a.data.rootNote == b.data.rootNote;
  }

  @override
  String getName(Scale item) => item.name;

  @override
  Future<Result<bool>> create(DogPawEntity entity, Scale item) {
    return entity.createScale(item);
  }

  @override
  Future<Result<Scale?>> read(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.readScale(name,
        namespaceSelector: ns, includeResolved: true, includeSpec: true);
  }

  @override
  Future<Result<bool>> update(DogPawEntity entity, Scale item) {
    return entity.updateScale(item);
  }

  @override
  Future<Result<bool>> set(DogPawEntity entity, Scale item) {
    return entity.setScale(item);
  }

  @override
  Future<Result<bool>> delete(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.deleteScale(name, namespaceSelector: ns);
  }

  @override
  Future<Result<List<Scale>>> list(DogPawEntity entity, NamespaceSelector ns) {
    return entity.listScales(
        namespaceSelector: ns, includeResolved: true, includeSpec: true);
  }

  @override
  Future<Result<bool>> subscribe(DogPawEntity entity,
      ItemChangeCallback callback, String name, NamespaceSelector ns) {
    return entity.subscribeToScales(callback,
        scaleName: name,
        namespaceSelector: ns,
        includeResolved: true,
        includeSpec: true);
  }

  @override
  Future<Result<bool>> unsubscribe(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.unsubscribeFromScales(scaleName: name, namespaceSelector: ns);
  }

  @override
  Scale setGlobalNamespace(Scale item) {
    return Scale(
        name: item.name,
        spec: item.spec!,
        namespaceSelector: const NamespaceSelector.global());
  }

  @override
  Scale setSpecificEntityNamespace(Scale item, String entityName) {
    return Scale(
        name: item.name,
        spec: item.spec!,
        namespaceSelector: NamespaceSelector.specificEntity(entityName));
  }
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // Auto-start Epiphany before tests, stop after all tests complete
  IntegrationTestFixture.register();

  group('Scale CRUD', () {
    late TestEntities entities;

    setUp(() async {
      entities = await TestEntities.create();
    });

    tearDown(() async {
      await entities.dispose();
    });

    registerCRUDTests(ScaleTestTraits(), () => entities);
  });
}
