import 'package:dogpaw/dogpaw.dart';

/// Waits until [listConnections] includes a realized pair matching [sourceName]
/// → [destinationName], optionally satisfying [matches].
///
/// Purpose: Coalesced Epiphany reconcile can leave `listConnections` empty or
/// carrying stale resolved metadata for a short window after ConnectionRule
/// CRUD. Integration tests should poll until the projection catches up.
///
/// Parameters:
/// - [entity]: Connected entity used to list connections.
/// - [sourceName]: Expected `sourceRef.name`.
/// - [destinationName]: Expected `destinationRef.name`.
/// - [matches]: Optional predicate on the candidate connection (e.g. resolved
///   field values after a clear/update). When null, the first name match wins.
/// - [timeout]: Maximum time to wait before throwing.
///
/// Return value: The matching [Connection] once found.
///
/// Requirements/Preconditions: [entity] must be connected; Epiphany must be
/// running with reconcile enabled.
///
/// Guarantees/Postconditions: Returned connection satisfies the name match and
/// [matches] (if provided).
///
/// Invariants: Does not mutate rules or endpoints; only reads via list.
Future<Connection> waitForProjectedConnection(
  DogPawEntity entity, {
  required String sourceName,
  required String destinationName,
  bool Function(Connection connection)? matches,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (true) {
    final Result<List<Connection>> projection = await entity.listConnections(
      includeResolved: true,
      includeSpec: true,
    );
    if (projection.success && projection.value != null) {
      for (final Connection connection in projection.value!) {
        if (connection.sourceRef?.name == sourceName &&
            connection.destinationRef?.name == destinationName) {
          if (matches == null || matches(connection)) {
            return connection;
          }
        }
      }
    } else {
      lastError = projection.error;
    }
    if (!DateTime.now().isBefore(deadline)) {
      throw StateError(
        'Timed out waiting for projected connection '
        '$sourceName -> $destinationName'
        '${lastError == null ? '' : ' (last list error: $lastError)'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
