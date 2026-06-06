// Integration tests for Layout operations.
//
// This file contains:
// - LayoutTestTraits implementation for CRUD operations
// - Standard CRUD tests (via the reusable framework)
//
// RUN WITH: flutter test test/integration/layout_test.dart --concurrency=1

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

import 'crud/crud_test_framework.dart';

// =============================================================================
// Layout Traits Implementation
// =============================================================================

class LayoutTestTraits implements CRUDTestTraits<Layout> {
  @override
  String get typeName => 'Layout';

  @override
  Layout createTestItem(String name) {
    return Layout(
      name: name,
      spec: LayoutData(displayName: 'Test Layout $name'),
    );
  }

  @override
  Layout modifyItem(Layout original) {
    return Layout(
      name: original.name,
      spec: LayoutData(displayName: 'Modified ${original.name}'),
    );
  }

  @override
  bool itemsEqual(Layout a, Layout b) {
    // Compare by name and displayName (use data getter which prefers resolved over spec)
    if (a.name != b.name) return false;
    if (!a.hasSpecData && !a.hasResolvedData) {
      return !b.hasSpecData && !b.hasResolvedData;
    }
    if (!b.hasSpecData && !b.hasResolvedData) return false;
    return a.data.displayName == b.data.displayName;
  }

  @override
  String getName(Layout item) => item.name;

  @override
  Future<Result<bool>> create(DogPawEntity entity, Layout item) {
    return entity.createLayout(item, addToLayoutStack: false);
  }

  @override
  Future<Result<Layout?>> read(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.readLayout(name,
        namespaceSelector: ns, includeResolved: true, includeSpec: true);
  }

  @override
  Future<Result<bool>> update(DogPawEntity entity, Layout item) {
    return entity.updateLayout(item);
  }

  @override
  Future<Result<bool>> set(DogPawEntity entity, Layout item) {
    return entity.setLayout(item);
  }

  @override
  Future<Result<bool>> delete(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.deleteLayout(name, namespaceSelector: ns);
  }

  @override
  Future<Result<List<Layout>>> list(DogPawEntity entity, NamespaceSelector ns) {
    return entity.listLayouts(
        namespaceSelector: ns, includeResolved: true, includeSpec: true);
  }

  @override
  Future<Result<bool>> subscribe(DogPawEntity entity,
      ItemChangeCallback callback, String name, NamespaceSelector ns) {
    return entity.subscribeToLayouts(callback,
        layoutName: name,
        namespaceSelector: ns,
        includeResolved: true,
        includeSpec: true);
  }

  @override
  Future<Result<bool>> unsubscribe(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.unsubscribeFromLayouts(
        layoutName: name, namespaceSelector: ns);
  }

  @override
  Layout setGlobalNamespace(Layout item) {
    return Layout(
        name: item.name,
        spec: item.spec!,
        namespaceSelector: const NamespaceSelector.global());
  }

  @override
  Layout setSpecificEntityNamespace(Layout item, String entityName) {
    return Layout(
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

  group('Layout CRUD', () {
    late TestEntities entities;

    setUp(() async {
      entities = await TestEntities.create();
    });

    tearDown(() async {
      await entities.dispose();
    });

    registerCRUDTests(LayoutTestTraits(), () => entities);
  });
}
