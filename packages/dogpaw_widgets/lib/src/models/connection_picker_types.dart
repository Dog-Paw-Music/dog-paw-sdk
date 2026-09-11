import 'package:dogpaw/dogpaw.dart' as dp;

/// Picker presentation mode: mutate connection rules, or select an endpoint.
///
/// [connection] preserves today's behavior: a focused endpoint's compatible
/// peers are shown and tapping a leaf creates/deletes this entity's
/// [dp.ConnectionRule]. [endpoint] is non-mutating: it browses compatible
/// endpoints for a direction and returns the chosen leaf(s) to the host.
enum ConnectionPickerMode { connection, endpoint }

/// Direction filter for [ConnectionPickerMode.endpoint].
///
/// `sources` roughly matches [dp.EndpointDirection.output] (things that
/// produce data); `destinations` roughly matches [dp.EndpointDirection.input]
/// (things that receive data); `both` returns endpoints of every direction.
enum EndpointDirectionFilter { sources, destinations, both }

/// Host-driven leaf chrome tokens.
///
/// The picker only knows `unlit` (idle), `lit` (emphasized/active), and
/// `muted` (present but de-emphasized) — ordinary UI emphasis language. It
/// does not know app-domain concepts like "ours" or "external"; hosts map
/// their own domain state onto these tokens via
/// [ConnectionPickerLeafChromeResolver].
enum ConnectionPickerLeafChrome { unlit, lit, muted }

/// One selected leaf from [ConnectionPickerMode.endpoint].
///
/// A leaf may carry more than one member when endpoints share a `groupKey`
/// (e.g. a stereo pair that toggles together).
class EndpointLeafSelection {
  /// Musician-facing leaf title as shown on the card.
  final String title;

  /// Member endpoints for this leaf; length 1 unless the leaf is `groupKey`
  /// paired.
  final List<dp.EndpointInfo> members;

  /// Shared `groupKey` for [members], or `null` for a single ungrouped
  /// endpoint.
  final String? groupKey;

  /**
   * Purpose: Construct one endpoint-mode leaf selection result.
   *
   * Parameters:
   * - [title]: Musician-facing leaf title.
   * - [members]: Non-empty member endpoint list.
   * - [groupKey]: Shared grouping key, or `null` when ungrouped.
   *
   * Return value:
   * - A new [EndpointLeafSelection].
   *
   * Requirements/Preconditions:
   * - [members] should be non-empty.
   *
   * Guarantees/Postconditions:
   * - Fields are immutable after construction.
   *
   * Invariants:
   * - Does not encode navigation path/folder information.
   */
  const EndpointLeafSelection({
    required this.title,
    required this.members,
    this.groupKey,
  });
}

/// Resolver hook: host supplies per-leaf chrome for the picker's leaf cards.
///
/// `null` (no resolver supplied) makes the picker fall back to its default:
/// this-entity connection-rule match ⇒ `lit`, else `unlit`. Hosts must not
/// need the picker to bake in realized-connection list queries; the picker
/// stays domain-agnostic and simply renders whatever token the resolver
/// returns.
typedef ConnectionPickerLeafChromeResolver = ConnectionPickerLeafChrome
    Function(EndpointLeafSelection leaf);

/// Kind of change recorded in one [ConnectionRuleMutation].
enum ConnectionRuleMutationKind { created, deleted, skippedExisting }

/// One mutation handle from a connection-mode picker session.
///
/// Exposed so hosts do not need to reverse-engineer what changed from a
/// bare success/failure signal.
class ConnectionRuleMutation {
  /// What happened to the rule.
  final ConnectionRuleMutationKind kind;

  /// Opaque stable rule name; usable for follow-up CRUD.
  final String ruleName;

  /// Pair identity: source endpoint ref for this rule.
  final dp.DataItemRef sourceRef;

  /// Pair identity: destination endpoint ref for this rule.
  final dp.DataItemRef destinationRef;

  /**
   * Purpose: Construct one connection-rule mutation record.
   *
   * Parameters:
   * - [kind]: What happened to the rule (created/deleted/skippedExisting).
   * - [ruleName]: Opaque stable rule name.
   * - [sourceRef]: Pair source ref.
   * - [destinationRef]: Pair destination ref.
   *
   * Return value:
   * - A new [ConnectionRuleMutation].
   *
   * Requirements/Preconditions:
   * - [ruleName] should be non-empty.
   *
   * Guarantees/Postconditions:
   * - Fields are immutable after construction.
   *
   * Invariants:
   * - Does not itself perform any CRUD; it is a report of what already
   *   happened.
   */
  const ConnectionRuleMutation({
    required this.kind,
    required this.ruleName,
    required this.sourceRef,
    required this.destinationRef,
  });
}

/// Sealed result returned by `showConnectionPickerDialog`.
sealed class ConnectionPickerResult {
  const ConnectionPickerResult();
}

/// The dialog closed without any mutation or endpoint selection.
class ConnectionPickerDismissed extends ConnectionPickerResult {
  /**
   * Purpose: Construct the no-op dismissal result.
   *
   * Parameters: none.
   * Return value: A new [ConnectionPickerDismissed].
   * Requirements/Preconditions: None.
   * Guarantees/Postconditions: Carries no mutation/selection payload.
   * Invariants: Stateless.
   */
  const ConnectionPickerDismissed();
}

/// The dialog closed after connection-mode mutations (possibly empty when
/// the host explicitly requests a mutation-shaped result).
class ConnectionPickerMutated extends ConnectionPickerResult {
  /// Every mutation recorded during this dialog session, in order.
  final List<ConnectionRuleMutation> mutations;

  /**
   * Purpose: Construct a connection-mode mutation result.
   *
   * Parameters:
   * - [mutations]: Ordered mutation handles for this dialog session.
   *
   * Return value:
   * - A new [ConnectionPickerMutated].
   *
   * Requirements/Preconditions:
   * - None.
   *
   * Guarantees/Postconditions:
   * - [mutations] reflects every create/delete/skip that occurred while the
   *   dialog was open, in chronological order.
   *
   * Invariants:
   * - Does not include mutations from other dialog sessions.
   */
  const ConnectionPickerMutated({required this.mutations});
}

/// The dialog closed after endpoint-selection mode returned leaf(s).
class ConnectionPickerEndpointsSelected extends ConnectionPickerResult {
  /// Selected leaves; length 1 unless `multiSelect` was requested.
  final List<EndpointLeafSelection> leaves;

  /**
   * Purpose: Construct an endpoint-selection result.
   *
   * Parameters:
   * - [leaves]: Selected leaf(s); length 1 unless multi-select.
   *
   * Return value:
   * - A new [ConnectionPickerEndpointsSelected].
   *
   * Requirements/Preconditions:
   * - [leaves] should be non-empty.
   *
   * Guarantees/Postconditions:
   * - Fields are immutable after construction.
   *
   * Invariants:
   * - Does not include mutation handles (endpoint mode never mutates rules).
   */
  const ConnectionPickerEndpointsSelected({required this.leaves});
}
