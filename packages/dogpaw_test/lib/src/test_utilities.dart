/// Utility functions for Dog Paw widget and integration tests.
library;

int _uniqueCounter = 0;

/// Generates a unique name for test resources.
///
/// Purpose:
/// Creates stable-enough unique identifiers for transient test objects such as
/// entities, KVs, themes, and layouts.
///
/// Parameters:
/// - [prefix]: Short human-readable label describing the resource type.
///
/// Return value:
/// - A unique string like `theme_1706745600000_42`.
///
/// Requirements/Preconditions:
/// - [prefix] should be a non-empty string suitable for use in Dog Paw names.
///
/// Guarantees/Postconditions:
/// - The returned string starts with [prefix].
/// - Repeated calls within one process produce different values unless
///   [resetUniqueCounter] is used.
///
/// Invariants:
/// - Does not touch the filesystem or network.
String uniqueName(String prefix) {
  final int timestamp = DateTime.now().millisecondsSinceEpoch;
  return '${prefix}_${timestamp}_${_uniqueCounter++}';
}

/// Resets the in-process unique-name counter.
///
/// Purpose:
/// Gives tests a way to make [`uniqueName`] sequences deterministic when a test
/// needs reproducible local naming.
///
/// Parameters: none.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - Call only when the test knows no other concurrent logic depends on the
///   current counter value.
///
/// Guarantees/Postconditions:
/// - The next [`uniqueName`] call uses counter value `0`.
///
/// Invariants:
/// - Does not change the timestamp component of future generated names.
void resetUniqueCounter() {
  _uniqueCounter = 0;
}

/// Waits for an asynchronous condition to become true.
///
/// Purpose:
/// Polls a lightweight async predicate until success or timeout, which is
/// useful for waiting on subscriptions and process state in tests.
///
/// Parameters:
/// - [condition]: Async callback that returns `true` when the wait should stop.
/// - [timeout]: Maximum total wait duration.
/// - [pollInterval]: Delay between predicate checks.
///
/// Return value:
/// - `true` when [condition] becomes true before timeout, otherwise `false`.
///
/// Requirements/Preconditions:
/// - [pollInterval] and [timeout] should both be positive durations.
///
/// Guarantees/Postconditions:
/// - Returns within approximately [timeout] plus one poll interval.
///
/// Invariants:
/// - Never swallows exceptions thrown by [condition].
Future<bool> waitFor(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return true;
    }
    await Future<void>.delayed(pollInterval);
  }

  return false;
}

/// Waits for an asynchronous getter to return a non-null value.
///
/// Purpose:
/// Reuses the same polling contract as [`waitFor`] for tests that need a value
/// rather than a boolean condition.
///
/// Parameters:
/// - [getter]: Async callback that returns a nullable value.
/// - [timeout]: Maximum total wait duration.
/// - [pollInterval]: Delay between getter calls.
///
/// Return value:
/// - The first non-null value returned by [getter], or `null` on timeout.
///
/// Requirements/Preconditions:
/// - [pollInterval] and [timeout] should both be positive durations.
///
/// Guarantees/Postconditions:
/// - Returns the first observed non-null value without additional polling.
///
/// Invariants:
/// - Never suppresses exceptions thrown by [getter].
Future<T?> waitForValue<T>(
  Future<T?> Function() getter, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    final T? value = await getter();
    if (value != null) {
      return value;
    }
    await Future<void>.delayed(pollInterval);
  }

  return null;
}
