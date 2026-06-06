// Integration tests for Theme operations.
//
// This file contains:
// - ThemeTestTraits implementation for CRUD operations
// - Standard CRUD tests (via the reusable framework)
//
// RUN WITH: flutter test test/integration/theme_test.dart --concurrency=1

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

import 'crud/crud_test_framework.dart';

// =============================================================================
// Theme Traits Implementation
// =============================================================================

class ThemeTestTraits implements CRUDTestTraits<Theme> {
  @override
  String get typeName => 'Theme';

  @override
  Theme createTestItem(String name) {
    return Theme(
      name: name,
      spec: ThemeData(
        displayName: 'Test Theme $name',
        primaryColor: '#FF0000',
        secondaryColor: '#00FF00',
        accentColor: '#0000FF',
        backgroundColor: '#FFFFFF',
      ),
    );
  }

  @override
  Theme modifyItem(Theme original) {
    return Theme(
      name: original.name,
      spec: ThemeData(
        displayName: 'Modified ${original.name}',
        primaryColor: '#AA0000',
        secondaryColor: '#00AA00',
        accentColor: '#0000AA',
        backgroundColor: '#AAAAAA',
      ),
    );
  }

  @override
  bool itemsEqual(Theme a, Theme b) {
    // Compare by name and primaryColor (use data getter which prefers resolved over spec)
    if (a.name != b.name) return false;
    if (!a.hasSpecData && !a.hasResolvedData) {
      return !b.hasSpecData && !b.hasResolvedData;
    }
    if (!b.hasSpecData && !b.hasResolvedData) return false;
    return a.data.primaryColor == b.data.primaryColor;
  }

  @override
  String getName(Theme item) => item.name;

  @override
  Future<Result<bool>> create(DogPawEntity entity, Theme item) {
    return entity.createTheme(item);
  }

  @override
  Future<Result<Theme?>> read(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.readTheme(name,
        namespaceSelector: ns, includeResolved: true, includeSpec: true);
  }

  @override
  Future<Result<bool>> update(DogPawEntity entity, Theme item) {
    return entity.updateTheme(item);
  }

  @override
  Future<Result<bool>> set(DogPawEntity entity, Theme item) {
    return entity.setTheme(item);
  }

  @override
  Future<Result<bool>> delete(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.deleteTheme(name, namespaceSelector: ns);
  }

  @override
  Future<Result<List<Theme>>> list(DogPawEntity entity, NamespaceSelector ns) {
    return entity.listThemes(
        namespaceSelector: ns, includeResolved: true, includeSpec: true);
  }

  @override
  Future<Result<bool>> subscribe(DogPawEntity entity,
      ItemChangeCallback callback, String name, NamespaceSelector ns) {
    return entity.subscribeToThemes(callback,
        themeName: name,
        namespaceSelector: ns,
        includeResolved: true,
        includeSpec: true);
  }

  @override
  Future<Result<bool>> unsubscribe(
      DogPawEntity entity, String name, NamespaceSelector ns) {
    return entity.unsubscribeFromThemes(themeName: name, namespaceSelector: ns);
  }

  @override
  Theme setGlobalNamespace(Theme item) {
    return Theme(
        name: item.name,
        spec: item.spec!,
        namespaceSelector: const NamespaceSelector.global());
  }

  @override
  Theme setSpecificEntityNamespace(Theme item, String entityName) {
    return Theme(
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

  group('Theme CRUD', () {
    late TestEntities entities;

    setUp(() async {
      entities = await TestEntities.create();
    });

    tearDown(() async {
      await entities.dispose();
    });

    registerCRUDTests(ThemeTestTraits(), () => entities);
  });
}
