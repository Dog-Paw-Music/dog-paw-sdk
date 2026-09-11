import 'dart:math' as math;

import 'package:dogpaw/dogpaw.dart' as dp;

import 'connection_picker_types.dart';

/// Built-in leaf titles for well-known `groupKey` values (Decision 8).
///
/// Maps at least the System stereo audio pairs onto musician-facing labels.
const Map<String, String> kKnownGroupKeyLeafTitles = <String, String>{
  'system_audio_out': 'Main Speakers',
  'system_audio_in': 'Main Audio Input',
};

/**
 * Purpose: True when an endpoint should be omitted from connection pickers.
 *
 * Parameters:
 * - [endpoint]: Endpoint metadata whose effective spec is inspected.
 *
 * Return value:
 * - `true` when `hideFromPicker` is set on the effective spec.
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Missing specs are treated as visible (`false`).
 *
 * Invariants:
 * - Does not mutate [endpoint].
 */
bool endpointHiddenFromPicker(dp.EndpointInfo endpoint) {
  final dp.EndpointSpec? spec = _effectiveSpec(endpoint);
  return spec?.hideFromPicker ?? false;
}

/**
 * Purpose: Prefer resolved endpoint metadata, else authored spec.
 *
 * Parameters:
 * - [endpoint]: Endpoint snapshot to inspect.
 *
 * Return value:
 * - Effective [dp.EndpointSpec], or `null` when neither is present.
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Prefers runtime-resolved metadata over authored metadata.
 *
 * Invariants:
 * - Does not mutate [endpoint].
 */
dp.EndpointSpec? _effectiveSpec(dp.EndpointInfo endpoint) {
  return endpoint.resolved ?? endpoint.spec;
}

/**
 * Purpose: Resolve the folder path segments for one endpoint in the picker tree.
 *
 * Parameters:
 * - [endpoint]: Candidate (or focused) endpoint metadata including optional
 *   `display` hierarchy and `ownerDisplayName`.
 *
 * Return value:
 * - Ordered path segments: top-level title, then nested `categoryPath` segments.
 *   Whitespace-only segments are skipped.
 *
 * Requirements/Preconditions:
 * - None; missing display / owner fields fall back per Contracts.
 *
 * Guarantees/Postconditions:
 * - Does not mutate [endpoint].
 *
 * Invariants:
 * - Transport `category` is unused.
 * - Top-level uses trimmed `display.topLevelCategory` when non-empty, else
 *   trimmed non-empty `ownerDisplayName`, else entity id (`sourceEntity`),
 *   else the endpoint name.
 */
List<String> resolveEndpointNavigationPath(dp.EndpointInfo endpoint) {
  final dp.EndpointSpec? spec = _effectiveSpec(endpoint);
  final dp.EndpointDisplaySpec? display = spec?.display;

  String topLevel;
  final String? overrideTop = display?.topLevelCategory?.trim();
  if (overrideTop != null && overrideTop.isNotEmpty) {
    topLevel = overrideTop;
  } else {
    final String? owner = endpoint.ownerDisplayName?.trim();
    if (owner != null && owner.isNotEmpty) {
      topLevel = owner;
    } else {
      final String? entityId = endpoint.namespaceSelector.sourceEntity?.trim();
      if (entityId != null && entityId.isNotEmpty) {
        topLevel = entityId;
      } else {
        topLevel = endpoint.name;
      }
    }
  }

  final List<String> path = <String>[topLevel];
  final List<String> nested = display?.categoryPath ?? const <String>[];
  for (final String segment in nested) {
    final String trimmed = segment.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    path.add(trimmed);
  }
  return path;
}

/**
 * Purpose: Build the musician-facing label for one endpoint member.
 *
 * Parameters:
 * - [endpoint]: Endpoint whose leaf/member label is needed.
 *
 * Return value:
 * - Trimmed `displayName` when non-empty, otherwise endpoint `name`.
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Never uses raw JACK port names.
 *
 * Invariants:
 * - Does not mutate [endpoint].
 */
String endpointMemberDisplayLabel(dp.EndpointInfo endpoint) {
  final dp.EndpointSpec? spec = _effectiveSpec(endpoint);
  if (spec != null && spec.displayName.trim().isNotEmpty) {
    return spec.displayName.trim();
  }
  return endpoint.name;
}

/**
 * Purpose: Choose the leaf card title for a same-path group or single endpoint.
 *
 * Parameters:
 * - [groupKey]: Shared `groupKey` when pairing; `null`/empty for singles.
 * - [members]: Non-empty member list (order preserved for fallbacks).
 *
 * Return value:
 * - Known-map title when [groupKey] is recognized; else the trimmed
 *   [groupKey] when there are multiple members; else first member
 *   display label; else trimmed [groupKey]; else first member name.
 *
 * Requirements/Preconditions:
 * - [members] must be non-empty.
 *
 * Guarantees/Postconditions:
 * - Pure function of inputs.
 *
 * Invariants:
 * - Decision 8 map entries take precedence for known keys.
 */
String pairedLeafTitle(String? groupKey, List<dp.EndpointInfo> members) {
  assert(members.isNotEmpty);
  final String? trimmedKey = groupKey?.trim();
  if (trimmedKey != null && trimmedKey.isNotEmpty) {
    final String? mapped = kKnownGroupKeyLeafTitles[trimmedKey];
    if (mapped != null) {
      return mapped;
    }
    // Multi-member groups use the shared groupKey as the leaf title when no
    // known-map entry exists (e.g. workbench "Main Knobs").
    if (members.length > 1) {
      return trimmedKey;
    }
  }
  final String firstLabel = endpointMemberDisplayLabel(members.first);
  if (firstLabel.isNotEmpty) {
    return firstLabel;
  }
  if (trimmedKey != null && trimmedKey.isNotEmpty) {
    return trimmedKey;
  }
  return members.first.name;
}

/**
 * Purpose: True when [candidate] is the same endpoint identity as [focused].
 *
 * Parameters:
 * - [focused]: Focused endpoint being edited.
 * - [candidate]: Candidate under consideration.
 *
 * Return value:
 * - `true` when name and namespace selector match.
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Pure identity comparison.
 *
 * Invariants:
 * - Does not inspect connection rules or display metadata.
 */
bool isSameEndpointIdentity(
    dp.EndpointInfo focused, dp.EndpointInfo candidate) {
  return candidate.name == focused.name &&
      candidate.namespaceSelector == focused.namespaceSelector;
}

/**
 * Purpose: Build a [dp.DataItemRef] for one endpoint snapshot.
 *
 * Parameters:
 * - [endpoint]: Endpoint to reference.
 *
 * Return value:
 * - Ref with matching name and namespace selector.
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Pure; no remote I/O.
 *
 * Invariants:
 * - Identity matches [endpoint] metadata exactly.
 */
dp.DataItemRef endpointRef(dp.EndpointInfo endpoint) {
  return dp.DataItemRef.byName(
    name: endpoint.name,
    namespaceSelector: endpoint.namespaceSelector,
  );
}

/**
 * Purpose: Find a connection rule linking [focused] with [candidate].
 *
 * Parameters:
 * - [focused]: Focused endpoint in the picker.
 * - [candidate]: Peer endpoint on a leaf card.
 * - [connectionRules]: Current connection rules to scan.
 *
 * Return value:
 * - Matching rule, or `null` when none exists / focused lacks a direction.
 *
 * Requirements/Preconditions:
 * - Focused should have an effective spec with a direction when used live.
 *
 * Guarantees/Postconditions:
 * - Matching is symmetric with create/delete rule source/destination orientation.
 *
 * Invariants:
 * - Does not mutate [connectionRules].
 */
dp.ConnectionRule? matchingConnectionRule({
  required dp.EndpointInfo focused,
  required dp.EndpointInfo candidate,
  required List<dp.ConnectionRule> connectionRules,
}) {
  final dp.EndpointSpec? focusedSpec = _effectiveSpec(focused);
  if (focusedSpec == null) {
    return null;
  }

  final bool focusedIsInput =
      focusedSpec.direction == dp.EndpointDirection.input;
  final dp.DataItemRef expectedSource =
      focusedIsInput ? endpointRef(candidate) : endpointRef(focused);
  final dp.DataItemRef expectedDestination =
      focusedIsInput ? endpointRef(focused) : endpointRef(candidate);

  for (final dp.ConnectionRule rule in connectionRules) {
    final dp.ConnectionRuleData? ruleData = rule.spec ?? rule.resolved;
    if (ruleData == null) {
      continue;
    }
    try {
      if (ruleData.sourceRef == expectedSource &&
          ruleData.destinationRef == expectedDestination) {
        return rule;
      }
    } on StateError {
      // Criteria-based selectors are not picker-connect pairs; skip.
      continue;
    }
  }
  return null;
}

/**
 * Purpose: Return the endpoint direction required of a peer for [direction]
 * to be able to connect to it.
 *
 * Parameters:
 * - [direction]: Direction of one side of a candidate pair.
 *
 * Return value:
 * - The opposite direction a compatible peer must have.
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Deterministic function of [direction].
 *
 * Invariants:
 * - `input` requires `output`; `output` requires `input`.
 * - STALE: `bidirectional` is handled like `output` for exhaustiveness only;
 *   C++ no longer authors bidirectional endpoints.
 */
dp.EndpointDirection _oppositeConnectionDirection(
  dp.EndpointDirection direction,
) {
  switch (direction) {
    case dp.EndpointDirection.input:
      return dp.EndpointDirection.output;
    case dp.EndpointDirection.output:
    // STALE: see comment above.
    case dp.EndpointDirection.bidirectional:
      return dp.EndpointDirection.input;
  }
}

/**
 * Purpose: Decide whether two endpoint index shapes can connect without
 * reader-side projection.
 *
 * Parameters:
 * - [a]: Focused endpoint data type.
 * - [b]: Candidate endpoint data type.
 *
 * Return value:
 * - `true` when both endpoints use the same index type.
 *
 * Requirements/Preconditions:
 * - Callers have already verified base type/category compatibility.
 *
 * Guarantees/Postconditions:
 * - Pure; does not mutate either data type.
 *
 * Invariants:
 * - Dimensions are not inspected; this mirrors the current picker-level
 *   compatibility surface, which reasons about index kind only.
 */
bool _hasSameIndexType(dp.DataTypeSpec a, dp.DataTypeSpec b) {
  return a.indexSpec.type == b.indexSpec.type;
}

/**
 * Purpose: Decide whether a mismatched-index pair is a Phase 3b projectable
 * FLOAT message-queue candidate.
 *
 * Parameters:
 * - [a]: Focused endpoint spec.
 * - [b]: Candidate endpoint spec.
 *
 * Return value:
 * - `true` for NONE<->KEY or NONE<->VOICE FLOAT MESSAGE_QUEUE pairs.
 *
 * Requirements/Preconditions:
 * - Direction, distinct identity, category equality, and base-type equality
 *   are checked by the caller.
 *
 * Guarantees/Postconditions:
 * - Fails closed for KEY<->VOICE, non-FLOAT, and non-MESSAGE_QUEUE pairs.
 *
 * Invariants:
 * - This is discovery metadata only; no projection is applied.
 */
bool _isProjectableFloatMessageQueuePair(
  dp.EndpointSpec a,
  dp.EndpointSpec b,
) {
  if (a.category != dp.EndpointCategory.messageQueue ||
      b.category != dp.EndpointCategory.messageQueue) {
    return false;
  }
  if (a.dataType.baseType != dp.DataType.float ||
      b.dataType.baseType != dp.DataType.float) {
    return false;
  }

  final dp.IndexType aIndex = a.dataType.indexSpec.type;
  final dp.IndexType bIndex = b.dataType.indexSpec.type;
  return (aIndex == dp.IndexType.none && bIndex != dp.IndexType.none) ||
      (aIndex != dp.IndexType.none && bIndex == dp.IndexType.none);
}

const Set<String> _manyToOneProjectionStrategies = <String>{
  dp.JsonFields.CONVERSION_MAX_VALUE,
  dp.JsonFields.CONVERSION_MIN_VALUE,
  dp.JsonFields.CONVERSION_MAX_ABS,
  dp.JsonFields.CONVERSION_AVERAGE_VALUE,
  dp.JsonFields.CONVERSION_LAST_ACTIVE,
  dp.JsonFields.CONVERSION_FIRST_ACTIVE,
};

/**
 * Purpose: Choose the fallback many-to-one strategy for a source polarity.
 *
 * Parameters:
 * - [polarity]: Projection polarity resolved from source endpoint hints.
 *
 * Return value:
 * - `max_abs` for bipolar sources, otherwise `max_value`.
 *
 * Requirements/Preconditions:
 * - [polarity] must be a supported Dog Paw projection polarity.
 *
 * Guarantees/Postconditions:
 * - Pure conversion; no endpoint metadata is mutated.
 *
 * Invariants:
 * - Only reader-side index projection defaults are considered here.
 */
String _fallbackManyToOneStrategyForPolarity(dp.ProjectionPolarity polarity) {
  if (polarity == dp.ProjectionPolarity.bipolar) {
    return dp.JsonFields.CONVERSION_MAX_ABS;
  }
  return dp.JsonFields.CONVERSION_MAX_VALUE;
}

/**
 * Purpose: Resolve the source-advertised many-to-one strategy allow-list.
 *
 * Parameters:
 * - [sourceSpec]: Effective source endpoint spec for a projected connection.
 *
 * Return value:
 * - Ordered strategy wire names the UI may offer for indexed-to-NONE
 *   projection edits.
 *
 * Requirements/Preconditions:
 * - [sourceSpec] should describe a MESSAGE_QUEUE FLOAT output.
 *
 * Guarantees/Postconditions:
 * - Explicit source strategy order is preserved and filtered to v1-supported
 *   many-to-one strategies.
 * - Omitted hints resolve to pressure-like defaults.
 * - Hints with omitted strategy arrays use the polarity fallback.
 *
 * Invariants:
 * - Does not mutate [sourceSpec] or its hint list.
 */
List<String> _advertisedManyToOneStrategies(dp.EndpointSpec sourceSpec) {
  final dp.ProjectionHints? sourceHints = sourceSpec.projectionHints;
  if (sourceHints != null && !sourceHints.strategiesProvided) {
    return <String>[
      _fallbackManyToOneStrategyForPolarity(sourceHints.polarity),
    ];
  }

  final dp.ProjectionHints hints = dp.resolveProjectionHints(sourceHints);
  final List<String> strategies = <String>[];
  for (final dp.ProjectionStrategyHint hint in hints.strategies) {
    if (_manyToOneProjectionStrategies.contains(hint.name) &&
        !strategies.contains(hint.name)) {
      strategies.add(hint.name);
    }
  }
  return strategies;
}

/**
 * Purpose: List editable index-conversion strategies for one source/dest pair.
 *
 * Parameters:
 * - [sourceEndpoint]: Endpoint metadata for the OUTPUT side of the pair.
 * - [destinationEndpoint]: Endpoint metadata for the INPUT side of the pair.
 *
 * Return value:
 * - Ordered strategy wire names appropriate for the pair; empty when the pair
 *   is not compatible for index-conversion editing.
 *
 * Requirements/Preconditions:
 * - Callers must pass source then destination orientation, not focused/candidate
 *   orientation.
 *
 * Guarantees/Postconditions:
 * - Same-index pairs expose only `none`.
 * - NONE-to-indexed FLOAT MQ pairs expose only `uniform`.
 * - Indexed-to-NONE FLOAT MQ pairs expose source-advertised many-to-one
 *   strategies filtered to the supported v1 set.
 *
 * Invariants:
 * - Continuous/category mismatches, KEY-to-VOICE, and FLOAT2 pairs return an
 *   empty list.
 */
List<String> allowedIndexConversionStrategiesForConnectionPair(
  dp.EndpointInfo sourceEndpoint,
  dp.EndpointInfo destinationEndpoint,
) {
  final dp.EndpointSpec? sourceSpec = _effectiveSpec(sourceEndpoint);
  final dp.EndpointSpec? destinationSpec = _effectiveSpec(destinationEndpoint);
  if (sourceSpec == null || destinationSpec == null) {
    return const <String>[];
  }
  if (sourceSpec.direction != dp.EndpointDirection.output ||
      destinationSpec.direction != dp.EndpointDirection.input) {
    return const <String>[];
  }
  if (sourceSpec.category != destinationSpec.category ||
      sourceSpec.dataType.baseType != destinationSpec.dataType.baseType) {
    return const <String>[];
  }
  if (_hasSameIndexType(sourceSpec.dataType, destinationSpec.dataType)) {
    return const <String>[dp.JsonFields.CONVERSION_NONE];
  }
  if (!_isProjectableFloatMessageQueuePair(sourceSpec, destinationSpec)) {
    return const <String>[];
  }

  final dp.IndexType sourceIndex = sourceSpec.dataType.indexSpec.type;
  final dp.IndexType destinationIndex = destinationSpec.dataType.indexSpec.type;
  if (sourceIndex == dp.IndexType.none &&
      destinationIndex != dp.IndexType.none) {
    return const <String>[dp.JsonFields.CONVERSION_UNIFORM];
  }
  if (sourceIndex != dp.IndexType.none &&
      destinationIndex == dp.IndexType.none) {
    return List<String>.unmodifiable(
      _advertisedManyToOneStrategies(sourceSpec),
    );
  }
  return const <String>[];
}

/**
 * Purpose: Compute the default index-conversion assertion for a new pair.
 *
 * Parameters:
 * - [sourceEndpoint]: Endpoint metadata for the OUTPUT side of the pair.
 * - [destinationEndpoint]: Endpoint metadata for the INPUT side of the pair.
 *
 * Return value:
 * - Default conversion config for a projected NONE<->KEY/VOICE FLOAT MQ pair,
 *   or `null` when no explicit projection default is needed.
 *
 * Requirements/Preconditions:
 * - Callers must pass source then destination orientation.
 *
 * Guarantees/Postconditions:
 * - Indexed-to-NONE defaults to the first allowed advertised strategy.
 * - NONE-to-indexed defaults to `uniform`.
 * - Same-index and incompatible pairs return `null`.
 *
 * Invariants:
 * - Does not create or validate a connection rule; Epiphany remains the source
 *   of truth for final reconciliation.
 */
dp.IndexConversionConfig? defaultIndexConversionForConnectionPair(
  dp.EndpointInfo sourceEndpoint,
  dp.EndpointInfo destinationEndpoint,
) {
  final List<String> allowed =
      allowedIndexConversionStrategiesForConnectionPair(
    sourceEndpoint,
    destinationEndpoint,
  );
  if (allowed.isEmpty ||
      (allowed.length == 1 &&
          allowed.single == dp.JsonFields.CONVERSION_NONE)) {
    return null;
  }
  return dp.IndexConversionConfig(strategy: allowed.first);
}

/**
 * Purpose: Decide whether two endpoints could be connected to each other.
 *
 * Parameters:
 * - [a]: One endpoint (treated as the "focused" side).
 * - [b]: The other endpoint (treated as the candidate peer).
 *
 * Return value:
 * - `true` when [a] and [b] are distinct endpoints, [b]'s effective
 *   direction is the opposite direction required by [a], categories and base
 *   types match, and their indexes either match exactly or form a Phase 3b
 *   projectable FLOAT MESSAGE_QUEUE pair; `false` otherwise.
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Pure; performs no I/O and does not mutate [a] or [b].
 *
 * Invariants:
 * - Mirrors the compatibility rule `ConnectionPicker` itself uses for
 *   connection-mode candidates (focused vs. candidate), so hosts validating
 *   a pair outside the picker (e.g. a Detail screen's Change FROM/TO) see
 *   the same answer the picker would have shown.
 */
bool isCompatibleConnectionPair(dp.EndpointInfo a, dp.EndpointInfo b) {
  if (a.name == b.name && a.namespaceSelector == b.namespaceSelector) {
    return false;
  }
  final dp.EndpointSpec? specA = _effectiveSpec(a);
  final dp.EndpointSpec? specB = _effectiveSpec(b);
  if (specA == null || specB == null) {
    return false;
  }
  if (specB.direction != _oppositeConnectionDirection(specA.direction)) {
    return false;
  }
  if (specA.category != specB.category ||
      specA.dataType.baseType != specB.dataType.baseType) {
    return false;
  }
  if (_hasSameIndexType(specA.dataType, specB.dataType)) {
    return true;
  }
  return _isProjectableFloatMessageQueuePair(specA, specB);
}

/**
 * Purpose: Build a fresh opaque persistent connection-rule identity.
 *
 * Parameters:
 * - None.
 *
 * Return value:
 * - UUID-shaped random request identifier.
 *
 * Requirements/Preconditions:
 * - The platform cryptographic random source is available.
 *
 * Guarantees/Postconditions:
 * - The returned identifier does not encode endpoint identities.
 *
 * Invariants:
 * - Existing rule names remain stable during later selector updates (Goals
 *   decision #18: stable opaque `ConnectionRule` names).
 */
String newOpaqueConnectionRuleName() {
  final math.Random random = math.Random.secure();
  final List<int> bytes =
      List<int>.generate(16, (int _) => random.nextInt(256));
  final String hex =
      bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

/// Shared card fields for folder and leaf navigation cards.
abstract class ConnectionNavCard {
  /// Musician-facing card title.
  String get title;
}

/// Folder card: tapping pushes one path segment.
class ConnectionNavFolderCard implements ConnectionNavCard {
  @override
  final String title;

  /// Full path including [title] used to enter this folder.
  final List<String> path;

  /// Number of reachable compatible leaves under this folder (pairs = 1).
  final int compatibleLeafCount;

  /// Number of fully-connected leaves under this folder (pairs = 1).
  final int connectedLeafCount;

  /**
   * Purpose: Construct one folder navigation card.
   *
   * Parameters:
   * - [title]: Folder label shown on the card.
   * - [path]: Absolute path stack to this folder (includes [title]).
   * - [compatibleLeafCount]: Reachable compatible leaf count beneath.
   * - [connectedLeafCount]: Fully-connected leaf count beneath.
   *
   * Return value:
   * - A new [ConnectionNavFolderCard].
   *
   * Requirements/Preconditions:
   * - [path] is non-empty and last segment equals [title].
   * - Counts are non-negative.
   *
   * Guarantees/Postconditions:
   * - Card fields are immutable after construction.
   *
   * Invariants:
   * - Counts treat paired endpoints as a single leaf.
   */
  const ConnectionNavFolderCard({
    required this.title,
    required this.path,
    required this.compatibleLeafCount,
    required this.connectedLeafCount,
  });
}

/// Leaf card: single endpoint or same-path `groupKey` pair/group.
class ConnectionNavLeafCard implements ConnectionNavCard {
  @override
  final String title;

  /// Parent folder path (excludes [title]).
  final List<String> folderPath;

  /// Member endpoints toggled together on connect/disconnect.
  final List<dp.EndpointInfo> members;

  /// Whether every member has a matching connection rule to the focus.
  ///
  /// Always `false` when the model was built without a focused endpoint
  /// (endpoint-selection mode), since no pair is defined to match against.
  final bool isFullyConnected;

  /// Shared `groupKey` for this leaf's members, or `null` for a single
  /// non-grouped endpoint. Preserved for host callbacks that need the raw
  /// grouping identity (e.g. [EndpointLeafSelection.groupKey]).
  final String? groupKey;

  /**
   * Purpose: Construct one leaf navigation card.
   *
   * Parameters:
   * - [title]: Leaf label (known groupKey map, displayName, or groupKey).
   * - [folderPath]: Parent folder segments.
   * - [members]: Endpoints in this leaf (one or more).
   * - [isFullyConnected]: True when all members are connected to focus.
   * - [groupKey]: Shared grouping key for members, or `null` when ungrouped.
   *
   * Return value:
   * - A new [ConnectionNavLeafCard].
   *
   * Requirements/Preconditions:
   * - [members] is non-empty.
   *
   * Guarantees/Postconditions:
   * - Card fields are immutable after construction.
   *
   * Invariants:
   * - Members share the same resolved folder path.
   */
  const ConnectionNavLeafCard({
    required this.title,
    required this.folderPath,
    required this.members,
    required this.isFullyConnected,
    this.groupKey,
  });

  /**
   * Purpose: Build the musician-facing breadcrumb for search results.
   *
   * Parameters:
   * - None.
   *
   * Return value:
   * - `folderPath` segments plus [title], joined with ` > `.
   *
   * Requirements/Preconditions:
   * - None.
   *
   * Guarantees/Postconditions:
   * - Pure function of [folderPath] and [title].
   *
   * Invariants:
   * - Does not include raw JACK port names.
   */
  String get breadcrumb {
    if (folderPath.isEmpty) {
      return title;
    }
    return '${folderPath.join(' > ')} > $title';
  }
}

/// Internal leaf before tree insertion.
class _PendingLeaf {
  final List<String> folderPath;
  final String title;
  final List<dp.EndpointInfo> members;
  final bool isFullyConnected;
  final String? groupKey;

  _PendingLeaf({
    required this.folderPath,
    required this.title,
    required this.members,
    required this.isFullyConnected,
    this.groupKey,
  });
}

/**
 * Purpose: Build the host-facing [EndpointLeafSelection] for one leaf card.
 *
 * Parameters:
 * - [leaf]: Navigation leaf card to convert.
 *
 * Return value:
 * - An [EndpointLeafSelection] carrying the same title, members, and
 *   `groupKey` as [leaf].
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Pure function of [leaf]; does not mutate it.
 *
 * Invariants:
 * - Member order matches [leaf.members] order.
 */
EndpointLeafSelection endpointLeafSelectionFromCard(
    ConnectionNavLeafCard leaf) {
  return EndpointLeafSelection(
    title: leaf.title,
    members: leaf.members,
    groupKey: leaf.groupKey,
  );
}

/// Tree node holding child folders and direct leaves.
class _NavNode {
  final Map<String, _NavNode> folders = <String, _NavNode>{};
  final List<ConnectionNavLeafCard> leaves = <ConnectionNavLeafCard>[];

  int compatibleLeafCount = 0;
  int connectedLeafCount = 0;
}

/// Pure folder-navigation model for the connection picker (Phase 3).
///
/// Builds folder levels, same-path `groupKey` leaves, search flatten results,
/// and connected counts from endpoint metadata + connection rules — no Flutter.
class ConnectionNavigationModel {
  final _NavNode _root;
  final List<ConnectionNavLeafCard> _allLeaves;

  ConnectionNavigationModel._(this._root, this._allLeaves);

  /**
   * Purpose: Build a navigation model from focused endpoint + candidates.
   *
   * Parameters:
   * - [focusedEndpoint]: Endpoint whose peers are being browsed (excluded).
   *   `null` in endpoint-selection mode, where there is no focus/pair concept.
   * - [candidates]: Compatible peer endpoints (may still include focused).
   * - [connectionRules]: Current rules used for connected-state / counts.
   *   Ignored (all leaves report `isFullyConnected == false`) when
   *   [focusedEndpoint] is `null`.
   *
   * Return value:
   * - Immutable model exposing [cardsAt] and [search].
   *
   * Requirements/Preconditions:
   * - Candidates should already be direction/base-type compatible when wired
   *   from the live picker; this model does not re-check compatibility.
   *
   * Guarantees/Postconditions:
   * - Focused endpoint (when non-null) is never shown as a leaf.
   * - Empty folders are omitted transitively.
   * - Top-level orders canonical `System` first, then alphabetical.
   *
   * Invariants:
   * - `groupKey` pairing is scoped to identical resolved paths.
   */
  factory ConnectionNavigationModel.build({
    required dp.EndpointInfo? focusedEndpoint,
    required List<dp.EndpointInfo> candidates,
    List<dp.ConnectionRule> connectionRules = const <dp.ConnectionRule>[],
  }) {
    final List<dp.EndpointInfo> filtered = focusedEndpoint == null
        ? List<dp.EndpointInfo>.from(candidates)
        : candidates
            .where(
              (dp.EndpointInfo candidate) =>
                  !isSameEndpointIdentity(focusedEndpoint, candidate),
            )
            .toList();

    filtered.removeWhere(endpointHiddenFromPicker);

    // Group by (pathKey, groupKey-or-unique-id).
    final Map<String, List<dp.EndpointInfo>> groups =
        <String, List<dp.EndpointInfo>>{};
    final Map<String, List<String>> groupPaths = <String, List<String>>{};
    final Map<String, String?> groupKeys = <String, String?>{};

    for (final dp.EndpointInfo candidate in filtered) {
      final List<String> path = resolveEndpointNavigationPath(candidate);
      final dp.EndpointSpec? spec = _effectiveSpec(candidate);
      final String? rawGroupKey = spec?.groupKey?.trim();
      final String? groupKey =
          (rawGroupKey != null && rawGroupKey.isNotEmpty) ? rawGroupKey : null;

      final String pathKey = path.join('\u0001');
      final String groupingKey;
      if (groupKey != null) {
        groupingKey = '$pathKey\u0002$groupKey';
      } else {
        final String entity = candidate.namespaceSelector.sourceEntity ?? '';
        groupingKey = '$pathKey\u0002\u0003$entity\u0003${candidate.name}';
      }

      groups.putIfAbsent(groupingKey, () => <dp.EndpointInfo>[]).add(candidate);
      groupPaths.putIfAbsent(groupingKey, () => path);
      groupKeys.putIfAbsent(groupingKey, () => groupKey);
    }

    final List<_PendingLeaf> pending = <_PendingLeaf>[];
    for (final MapEntry<String, List<dp.EndpointInfo>> entry
        in groups.entries) {
      final List<dp.EndpointInfo> members = entry.value;
      final List<String> fullPath = groupPaths[entry.key]!;
      final String? groupKey = groupKeys[entry.key];
      final String title = pairedLeafTitle(groupKey, members);

      bool fullyConnected = false;
      if (focusedEndpoint != null) {
        fullyConnected = members.isNotEmpty;
        for (final dp.EndpointInfo member in members) {
          final dp.ConnectionRule? rule = matchingConnectionRule(
            focused: focusedEndpoint,
            candidate: member,
            connectionRules: connectionRules,
          );
          if (rule == null) {
            fullyConnected = false;
            break;
          }
        }
      }

      pending.add(
        _PendingLeaf(
          folderPath: List<String>.from(fullPath),
          title: title,
          members: List<dp.EndpointInfo>.unmodifiable(members),
          isFullyConnected: fullyConnected,
          groupKey: groupKey,
        ),
      );
    }

    final _NavNode root = _NavNode();
    final List<ConnectionNavLeafCard> allLeaves = <ConnectionNavLeafCard>[];

    for (final _PendingLeaf leaf in pending) {
      _NavNode node = root;
      for (final String segment in leaf.folderPath) {
        node = node.folders.putIfAbsent(segment, () => _NavNode());
      }
      final ConnectionNavLeafCard card = ConnectionNavLeafCard(
        title: leaf.title,
        folderPath: List<String>.unmodifiable(leaf.folderPath),
        members: leaf.members,
        isFullyConnected: leaf.isFullyConnected,
        groupKey: leaf.groupKey,
      );
      node.leaves.add(card);
      allLeaves.add(card);
    }

    _pruneAndCount(root);

    allLeaves.sort((ConnectionNavLeafCard a, ConnectionNavLeafCard b) {
      final int pathCmp = a.breadcrumb.compareTo(b.breadcrumb);
      if (pathCmp != 0) {
        return pathCmp;
      }
      return a.title.compareTo(b.title);
    });

    return ConnectionNavigationModel._(
      root,
      List<ConnectionNavLeafCard>.unmodifiable(allLeaves),
    );
  }

  /**
   * Purpose: Prune empty folders transitively and compute leaf counts.
   *
   * Parameters:
   * - [node]: Subtree root to prune in place.
   *
   * Return value:
   * - `true` when [node] has at least one reachable leaf (keep parent link).
   *
   * Requirements/Preconditions:
   * - Called after all leaves are inserted.
   *
   * Guarantees/Postconditions:
   * - Child folders with zero reachable leaves are removed.
   * - [node.compatibleLeafCount] / [node.connectedLeafCount] are set.
   *
   * Invariants:
   * - Leaves already on [node] are never removed.
   */
  static bool _pruneAndCount(_NavNode node) {
    final List<String> folderNames = node.folders.keys.toList();
    for (final String name in folderNames) {
      final _NavNode child = node.folders[name]!;
      if (!_pruneAndCount(child)) {
        node.folders.remove(name);
      }
    }

    int compatible = node.leaves.length;
    int connected = node.leaves
        .where((ConnectionNavLeafCard l) => l.isFullyConnected)
        .length;
    for (final _NavNode child in node.folders.values) {
      compatible += child.compatibleLeafCount;
      connected += child.connectedLeafCount;
    }
    node.compatibleLeafCount = compatible;
    node.connectedLeafCount = connected;
    return compatible > 0;
  }

  /**
   * Purpose: Return ordered cards at one navigation stack depth.
   *
   * Parameters:
   * - [path]: Current folder stack (`[]` = top-level).
   *
   * Return value:
   * - Folder and/or leaf cards at that level; empty when path is unknown.
   *
   * Requirements/Preconditions:
   * - [path] segments match titles previously returned by this model.
   *
   * Guarantees/Postconditions:
   * - Nested levels are alphabetical by title; top-level is System-first.
   *
   * Invariants:
   * - Does not mutate model state.
   */
  List<ConnectionNavCard> cardsAt(List<String> path) {
    _NavNode? node = _root;
    for (final String segment in path) {
      node = node!.folders[segment];
      if (node == null) {
        return const <ConnectionNavCard>[];
      }
    }

    final bool atTopLevel = path.isEmpty;
    final List<ConnectionNavFolderCard> folderCards =
        <ConnectionNavFolderCard>[];
    final List<String> sortedFolderNames = node!.folders.keys.toList()..sort();

    if (atTopLevel) {
      sortedFolderNames.sort((String a, String b) {
        final bool aSystem = a == dp.kDisplayCategorySystem;
        final bool bSystem = b == dp.kDisplayCategorySystem;
        if (aSystem != bSystem) {
          return aSystem ? -1 : 1;
        }
        return a.compareTo(b);
      });
    }

    for (final String name in sortedFolderNames) {
      final _NavNode child = node.folders[name]!;
      folderCards.add(
        ConnectionNavFolderCard(
          title: name,
          path: List<String>.unmodifiable(<String>[...path, name]),
          compatibleLeafCount: child.compatibleLeafCount,
          connectedLeafCount: child.connectedLeafCount,
        ),
      );
    }

    final List<ConnectionNavLeafCard> leafCards =
        List<ConnectionNavLeafCard>.from(node.leaves)
          ..sort(
            (ConnectionNavLeafCard a, ConnectionNavLeafCard b) =>
                a.title.compareTo(b.title),
          );

    if (atTopLevel) {
      // Top-level: System folder first (already first among folders), then
      // remaining folders + leaves alphabetical by title.
      final List<ConnectionNavCard> systemFirst = <ConnectionNavCard>[];
      final List<ConnectionNavCard> rest = <ConnectionNavCard>[];
      for (final ConnectionNavFolderCard folder in folderCards) {
        if (folder.title == dp.kDisplayCategorySystem) {
          systemFirst.add(folder);
        } else {
          rest.add(folder);
        }
      }
      rest.addAll(leafCards);
      rest.sort(
        (ConnectionNavCard a, ConnectionNavCard b) =>
            a.title.compareTo(b.title),
      );
      return <ConnectionNavCard>[...systemFirst, ...rest];
    }

    final List<ConnectionNavCard> combined = <ConnectionNavCard>[
      ...folderCards,
      ...leafCards,
    ];
    combined.sort(
      (ConnectionNavCard a, ConnectionNavCard b) => a.title.compareTo(b.title),
    );
    return combined;
  }

  /**
   * Purpose: Flatten leaves whose label or path matches [query].
   *
   * Parameters:
   * - [query]: Case-insensitive substring; empty/whitespace returns all leaves.
   *
   * Return value:
   * - Matching leaves (pairs count as one), each with [ConnectionNavLeafCard.breadcrumb].
   *
   * Requirements/Preconditions:
   * - None.
   *
   * Guarantees/Postconditions:
   * - Match considers leaf title and every folder path segment.
   *
   * Invariants:
   * - Does not mutate model state.
   */
  List<ConnectionNavLeafCard> search(String query) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return List<ConnectionNavLeafCard>.from(_allLeaves);
    }

    return _allLeaves.where((ConnectionNavLeafCard leaf) {
      if (leaf.title.toLowerCase().contains(needle)) {
        return true;
      }
      for (final String segment in leaf.folderPath) {
        if (segment.toLowerCase().contains(needle)) {
          return true;
        }
      }
      return false;
    }).toList();
  }
}
