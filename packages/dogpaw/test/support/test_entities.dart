import 'package:dogpaw/dogpaw.dart';

/// Package-local multi-entity helper for `package:dogpaw` tests.
///
/// Purpose:
/// Provides the `dogpaw` package's own test suite with a small reusable bundle
/// of connected entities so integration tests can exercise same-app and
/// cross-entity behavior without depending on the repo-only
/// `dart_test_infrastructure` package.
///
/// Parameters:
/// - None for the type itself. Use [create] to construct an instance.
///
/// Return value:
/// - Instances expose three connected [DogPawEntity] objects via [entity1],
///   [entity2], and [entity3].
///
/// Requirements/Preconditions:
/// - Epiphany must already be running before [create] is called.
///
/// Guarantees/Postconditions:
/// - [create] returns only after all three entities report connected handles.
/// - [dispose] disconnects any of the managed entities that are still connected.
///
/// Invariants:
/// - This helper stays local to the `dogpaw` package test tree and is not part
///   of the public SDK test surface.
class TestEntities {
  /// First managed test entity.
  final DogPawEntity entity1;

  /// Second managed test entity.
  final DogPawEntity entity2;

  /// Third managed test entity.
  final DogPawEntity entity3;

  /// Creates one immutable bundle of already-constructed entities.
  ///
  /// Purpose:
  /// Stores the three managed entities after [create] has connected them.
  ///
  /// Parameters:
  /// - [entity1]: First connected test entity.
  /// - [entity2]: Second connected test entity.
  /// - [entity3]: Third connected test entity.
  ///
  /// Return value:
  /// - New [TestEntities] wrapper.
  ///
  /// Requirements/Preconditions:
  /// - Each entity argument should already be constructed for the current test.
  ///
  /// Guarantees/Postconditions:
  /// - The same entity instances are exposed through the public fields.
  ///
  /// Invariants:
  /// - This constructor performs no network or filesystem work.
  TestEntities._(this.entity1, this.entity2, this.entity3);

  /// Creates and connects the package-local test entities.
  ///
  /// Purpose:
  /// Gives integration tests one standard way to obtain multiple connected
  /// entities with deterministic names for CRUD, subscription, and
  /// cross-entity behavior checks.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - Future resolving to a [TestEntities] bundle once all entities connect.
  ///
  /// Requirements/Preconditions:
  /// - Epiphany is running and reachable through the current test environment.
  ///
  /// Guarantees/Postconditions:
  /// - Returns only after each connection handle completes successfully.
  /// - Disconnects any earlier entities before throwing if a later connection
  ///   attempt fails.
  ///
  /// Invariants:
  /// - Uses the long-standing `TestEntity1`, `TestEntity2`, and `TestEntity3`
  ///   names expected by the existing `dogpaw` integration suite.
  static Future<TestEntities> create() async {
    final DogPawEntity entity1 = DogPawEntity('TestEntity1');
    final DogPawEntity entity2 = DogPawEntity('TestEntity2');
    final DogPawEntity entity3 = DogPawEntity('TestEntity3');

    final ConnectionResult result1 = await entity1.connect();
    if (!result1.success) {
      throw Exception('Failed to connect entity1: ${result1.error}');
    }
    await result1.handle!.complete();

    final ConnectionResult result2 = await entity2.connect();
    if (!result2.success) {
      entity1.disconnect();
      throw Exception('Failed to connect entity2: ${result2.error}');
    }
    await result2.handle!.complete();

    final ConnectionResult result3 = await entity3.connect();
    if (!result3.success) {
      entity1.disconnect();
      entity2.disconnect();
      throw Exception('Failed to connect entity3: ${result3.error}');
    }
    await result3.handle!.complete();

    return TestEntities._(entity1, entity2, entity3);
  }

  /// Disconnects all managed entities that remain connected.
  ///
  /// Purpose:
  /// Gives tests one cleanup call that returns the runtime connection state to a
  /// known baseline after each integration scenario.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - Future that completes after all disconnect requests have been issued.
  ///
  /// Requirements/Preconditions:
  /// - Safe to call even if some or all entities are already disconnected.
  ///
  /// Guarantees/Postconditions:
  /// - Each managed entity is disconnected by the time the returned future
  ///   completes.
  ///
  /// Invariants:
  /// - Does not create new entities or reconnect existing ones.
  Future<void> dispose() async {
    if (entity1.isConnected()) {
      entity1.disconnect();
    }
    if (entity2.isConnected()) {
      entity2.disconnect();
    }
    if (entity3.isConnected()) {
      entity3.disconnect();
    }
  }
}
