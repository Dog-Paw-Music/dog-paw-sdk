import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

/// Return the best available endpoint specification for one metadata snapshot.
///
/// Parameters:
/// - `endpoint`: Endpoint metadata snapshot whose spec should be inspected.
///
/// Return value:
/// - Resolved spec when present, otherwise the authored spec, or `null`.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Prefers runtime-resolved metadata over authored metadata.
///
/// Invariants:
/// - The endpoint metadata is not mutated.
dp.EndpointSpec? _effectiveSpec(dp.EndpointInfo endpoint) {
  return endpoint.resolved ?? endpoint.spec;
}

/// Reusable connection editor focused on one endpoint.
///
/// Purpose:
/// Establishes the shared package contract for "set connections for this
/// endpoint" flows while leaving endpoint discovery and mutation on the
/// supplied Dog Paw entity client.
class ConnectionPicker extends StatefulWidget {
  /// Entity client used to query and mutate routing state.
  final dp.DogPawEntity entity;

  /// Endpoint whose compatible peers should be presented to the user.
  final dp.EndpointInfo focusedEndpoint;

  /// Optional callback that requests an external refresh after connection work.
  final Future<void> Function()? onRefresh;

  /// Create one reusable focused-endpoint connection picker shell.
  ///
  /// Parameters:
  /// - `entity`: Dog Paw entity client used for routing operations.
  /// - `focusedEndpoint`: Endpoint whose connections are being edited.
  /// - `onRefresh`: Optional host callback requested after connection changes.
  ///
  /// Return value:
  /// - A new `ConnectionPicker`.
  ///
  /// Requirements/Preconditions:
  /// - `focusedEndpoint` should describe a real endpoint identity.
  ///
  /// Guarantees/Postconditions:
  /// - The widget owns only presentation state; endpoint interpretation remains
  ///   consistent inside the package.
  ///
  /// Invariants:
  /// - Raw JACK port names are not part of the public widget contract.
  const ConnectionPicker({
    super.key,
    required this.entity,
    required this.focusedEndpoint,
    this.onRefresh,
  });

  @override
  State<ConnectionPicker> createState() => _ConnectionPickerState();
}

/// Local UI state for the focused-endpoint connection picker.
class _ConnectionPickerState extends State<ConnectionPicker> {
  bool _isLoading = true;
  bool _isMutating = false;
  String? _errorMessage;
  List<_ConnectionCandidateGroup> _candidateGroups = <_ConnectionCandidateGroup>[];

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  /// Refresh candidate data when the focused endpoint or entity changes.
  ///
  /// Parameters:
  /// - `oldWidget`: Previous widget configuration.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Candidate rows are reloaded when the picker is repointed at a different
  ///   endpoint or entity.
  ///
  /// Invariants:
  /// - Existing user-facing loading and error handling still flow through
  ///   `_loadCandidates()`.
  @override
  void didUpdateWidget(covariant ConnectionPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dp.EndpointSpec? oldFocusedSpec = _effectiveSpec(oldWidget.focusedEndpoint);
    final dp.EndpointSpec? newFocusedSpec = _effectiveSpec(widget.focusedEndpoint);
    final bool focusedEndpointChanged =
        oldWidget.focusedEndpoint.name != widget.focusedEndpoint.name ||
            oldWidget.focusedEndpoint.namespaceSelector !=
                widget.focusedEndpoint.namespaceSelector ||
            oldFocusedSpec?.direction != newFocusedSpec?.direction ||
            oldFocusedSpec?.dataType.baseType != newFocusedSpec?.dataType.baseType;
    if (oldWidget.entity != widget.entity || focusedEndpointChanged) {
      _loadCandidates();
    }
  }

  /// Load compatible endpoints and current connection-request state.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - A future that completes when the picker state has refreshed.
  ///
  /// Requirements/Preconditions:
  /// - `widget.focusedEndpoint` should contain endpoint metadata with a spec.
  ///
  /// Guarantees/Postconditions:
  /// - On success, `_candidateGroups` contains grouped compatible peers.
  /// - On failure, `_errorMessage` contains a user-facing explanation.
  ///
  /// Invariants:
  /// - Raw JACK port names are not stored for rendering.
  Future<void> _loadCandidates() async {
    final dp.EndpointSpec? focusedSpec = _effectiveSpec(widget.focusedEndpoint);
    if (focusedSpec == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'This endpoint is missing routing metadata.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final dp.SearchCriteria criteria = dp.SearchCriteria.andCombination(
      <dp.SearchCriteria>[
        dp.SearchCriteria.directionEquals(
          _candidateDirectionForFocused(focusedSpec.direction),
        ),
        dp.SearchCriteria.baseTypeEquals(focusedSpec.dataType.baseType),
      ],
    );

    final List<dynamic> results = await Future.wait<dynamic>(
      <Future<dynamic>>[
        widget.entity.searchEndpoints(criteria),
        widget.entity.listConnectionRequests(includeSpec: true),
      ],
    );

    final dp.Result<List<dp.EndpointInfo>> endpointResult =
        results[0] as dp.Result<List<dp.EndpointInfo>>;
    final dp.Result<List<dp.ConnectionRequest>> requestResult =
        results[1] as dp.Result<List<dp.ConnectionRequest>>;

    if (!endpointResult.success) {
      setState(() {
        _isLoading = false;
        _errorMessage = endpointResult.error;
      });
      return;
    }

    if (!requestResult.success) {
      setState(() {
        _isLoading = false;
        _errorMessage = requestResult.error;
      });
      return;
    }

    final List<dp.EndpointInfo> compatibleEndpoints = endpointResult.value!
        .where(_isCompatibleCandidate)
        .toList();
    final List<dp.ConnectionRequest> connectionRequests =
        requestResult.value ?? <dp.ConnectionRequest>[];

    setState(() {
      _candidateGroups = _groupCandidates(compatibleEndpoints, connectionRequests);
      _isLoading = false;
    });
  }

  /// Decide whether one discovered endpoint is compatible with the focused endpoint.
  ///
  /// Parameters:
  /// - `candidate`: Endpoint metadata to inspect.
  ///
  /// Return value:
  /// - `true` when the endpoint is eligible for display in this picker.
  ///
  /// Requirements/Preconditions:
  /// - `widget.focusedEndpoint` should contain endpoint metadata with a spec.
  ///
  /// Guarantees/Postconditions:
  /// - Self-connections are excluded.
  /// - Direction and base type must match the focused-endpoint routing rules.
  ///
  /// Invariants:
  /// - Candidate metadata is not mutated.
  bool _isCompatibleCandidate(dp.EndpointInfo candidate) {
    if (candidate.name == widget.focusedEndpoint.name &&
        candidate.namespaceSelector == widget.focusedEndpoint.namespaceSelector) {
      return false;
    }

    final dp.EndpointSpec? focusedSpec = _effectiveSpec(widget.focusedEndpoint);
    final dp.EndpointSpec? candidateSpec = _effectiveSpec(candidate);
    if (focusedSpec == null || candidateSpec == null) {
      return false;
    }

    return candidateSpec.direction ==
            _candidateDirectionForFocused(focusedSpec.direction) &&
        candidateSpec.dataType.baseType == focusedSpec.dataType.baseType;
  }

  /// Group compatible endpoints into musician-facing action rows.
  ///
  /// Parameters:
  /// - `candidates`: Compatible endpoints discovered from the entity.
  /// - `connectionRequests`: Current request state used to infer connected rows.
  ///
  /// Return value:
  /// - Sorted grouped candidate rows.
  ///
  /// Requirements/Preconditions:
  /// - Candidate endpoints have already been filtered for compatibility.
  ///
  /// Guarantees/Postconditions:
  /// - Endpoints sharing a `groupKey` become one grouped action row.
  /// - Each row captures the matching current connection requests for its members.
  ///
  /// Invariants:
  /// - Grouping uses endpoint metadata already present in the system.
  List<_ConnectionCandidateGroup> _groupCandidates(
    List<dp.EndpointInfo> candidates,
    List<dp.ConnectionRequest> connectionRequests,
  ) {
    final Map<String, List<dp.EndpointInfo>> groupedEndpoints =
        <String, List<dp.EndpointInfo>>{};
    for (final dp.EndpointInfo candidate in candidates) {
      final dp.EndpointSpec? candidateSpec = _effectiveSpec(candidate);
      final String label = (candidateSpec?.groupKey?.trim().isNotEmpty ?? false)
          ? candidateSpec!.groupKey!.trim()
          : _candidateLabel(candidate);
      groupedEndpoints.putIfAbsent(label, () => <dp.EndpointInfo>[]).add(candidate);
    }

    final List<_ConnectionCandidateGroup> groups =
        groupedEndpoints.entries.map((MapEntry<String, List<dp.EndpointInfo>> entry) {
      final List<_ConnectionCandidateMember> members =
          entry.value.map(_ConnectionCandidateMember.fromEndpoint).toList();
      for (final _ConnectionCandidateMember member in members) {
        member.matchingRequest =
            _matchingConnectionRequest(member.endpoint, connectionRequests);
      }
      return _ConnectionCandidateGroup(label: entry.key, members: members);
    }).toList();

    groups.sort(
      (_ConnectionCandidateGroup left, _ConnectionCandidateGroup right) {
        if (left.isSystem != right.isSystem) {
          return left.isSystem ? -1 : 1;
        }
        return left.label.compareTo(right.label);
      },
    );
    return groups;
  }

  /// Find the existing connection request that matches one candidate/focused pair.
  ///
  /// Parameters:
  /// - `candidate`: Candidate endpoint shown in the picker.
  /// - `connectionRequests`: Current connection requests to inspect.
  ///
  /// Return value:
  /// - Matching connection request, or `null` when none exists.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Matching is symmetric with `_buildConnectionRequestForCandidate`.
  ///
  /// Invariants:
  /// - Existing request objects are not mutated.
  dp.ConnectionRequest? _matchingConnectionRequest(
    dp.EndpointInfo candidate,
    List<dp.ConnectionRequest> connectionRequests,
  ) {
    final dp.ConnectionRequest prototype =
        _buildConnectionRequestForCandidate(candidate);
    final dp.DataItemRef expectedSource = prototype.spec!.sourceRef;
    final dp.DataItemRef expectedDestination = prototype.spec!.destinationRef;

    for (final dp.ConnectionRequest request in connectionRequests) {
      final dp.ConnectionRequestData? requestData = request.spec ?? request.resolved;
      if (requestData == null) {
        continue;
      }
      if (requestData.sourceRef == expectedSource &&
          requestData.destinationRef == expectedDestination) {
        return request;
      }
    }
    return null;
  }

  /// Create the request payload for one focused/candidate endpoint pair.
  ///
  /// Parameters:
  /// - `candidate`: Candidate endpoint to connect with the focused endpoint.
  ///
  /// Return value:
  /// - New `ConnectionRequest` describing the desired routing pair.
  ///
  /// Requirements/Preconditions:
  /// - `candidate` is compatible with `widget.focusedEndpoint`.
  ///
  /// Guarantees/Postconditions:
  /// - Focused-input flows use the candidate as source.
  /// - Focused-output flows use the candidate as destination.
  ///
  /// Invariants:
  /// - Request naming is deterministic for the same endpoint pair.
  dp.ConnectionRequest _buildConnectionRequestForCandidate(dp.EndpointInfo candidate) {
    final dp.EndpointSpec focusedSpec = _effectiveSpec(widget.focusedEndpoint)!;
    final bool focusedIsInput = focusedSpec.direction == dp.EndpointDirection.input;
    final dp.DataItemRef sourceRef = focusedIsInput
        ? _endpointRef(candidate)
        : _endpointRef(widget.focusedEndpoint);
    final dp.DataItemRef destinationRef = focusedIsInput
        ? _endpointRef(widget.focusedEndpoint)
        : _endpointRef(candidate);

    return dp.ConnectionRequest(
      name: _requestNameForPair(sourceRef, destinationRef),
      spec: dp.ConnectionRequestData(
        sourceRef: sourceRef,
        destinationRef: destinationRef,
      ),
    );
  }

  /// Apply the grouped connect or disconnect action for one candidate row.
  ///
  /// Parameters:
  /// - `group`: Candidate row whose action button was pressed.
  ///
  /// Return value:
  /// - A future that completes after the routing change has been applied.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Fully connected groups disconnect all matching members.
  /// - Other groups connect every missing member in the group.
  ///
  /// Invariants:
  /// - Group action is derived from endpoint metadata already loaded into the picker.
  Future<void> _handleGroupAction(_ConnectionCandidateGroup group) async {
    setState(() {
      _isMutating = true;
    });

    bool sawFailure = false;
    if (group.isFullyConnected) {
      for (final _ConnectionCandidateMember member in group.members) {
        final dp.ConnectionRequest? matchingRequest = member.matchingRequest;
        if (matchingRequest == null) {
          continue;
        }
        final dp.Result<bool> result = await widget.entity.deleteConnectionRequest(
          matchingRequest.name,
        );
        if (!result.success) {
          sawFailure = true;
          _errorMessage = result.error;
          break;
        }
      }
    } else {
      for (final _ConnectionCandidateMember member in group.members) {
        if (member.matchingRequest != null) {
          continue;
        }
        final dp.Result<bool> result = await widget.entity.createConnectionRequest(
          _buildConnectionRequestForCandidate(member.endpoint),
        );
        if (!result.success) {
          sawFailure = true;
          _errorMessage = result.error;
          break;
        }
      }
    }

    if (!sawFailure && widget.onRefresh != null) {
      await widget.onRefresh!.call();
    }

    setState(() {
      _isMutating = false;
    });
    await _loadCandidates();
  }

  /// Build one endpoint reference suitable for connection requests.
  ///
  /// Parameters:
  /// - `endpoint`: Endpoint metadata snapshot to reference.
  ///
  /// Return value:
  /// - `DataItemRef` pointing at the endpoint name and namespace.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Reference identity matches the endpoint metadata exactly.
  ///
  /// Invariants:
  /// - No remote state is touched.
  dp.DataItemRef _endpointRef(dp.EndpointInfo endpoint) {
    return dp.DataItemRef.byName(
      name: endpoint.name,
      namespaceSelector: endpoint.namespaceSelector,
    );
  }

  /// Return the opposite direction required for a focused endpoint.
  ///
  /// Parameters:
  /// - `focusedDirection`: Direction on the focused endpoint.
  ///
  /// Return value:
  /// - Opposite endpoint direction to search for.
  ///
  /// Requirements/Preconditions:
  /// - Bidirectional endpoints are treated as output-focused for this first version.
  ///
  /// Guarantees/Postconditions:
  /// - Inputs search outputs, outputs search inputs.
  ///
  /// Invariants:
  /// - Direction mapping is deterministic.
  dp.EndpointDirection _candidateDirectionForFocused(
    dp.EndpointDirection focusedDirection,
  ) {
    switch (focusedDirection) {
      case dp.EndpointDirection.input:
        return dp.EndpointDirection.output;
      case dp.EndpointDirection.output:
      case dp.EndpointDirection.bidirectional:
        return dp.EndpointDirection.input;
    }
  }

  /// Build one musician-facing label for an individual candidate endpoint.
  ///
  /// Parameters:
  /// - `candidate`: Endpoint metadata snapshot to label.
  ///
  /// Return value:
  /// - Endpoint display name when present, otherwise the endpoint identifier.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Raw JACK metadata is never used in the label.
  ///
  /// Invariants:
  /// - Candidate metadata is not mutated.
  String _candidateLabel(dp.EndpointInfo candidate) {
    final dp.EndpointSpec? candidateSpec = _effectiveSpec(candidate);
    if (candidateSpec != null && candidateSpec.displayName.trim().isNotEmpty) {
      return candidateSpec.displayName.trim();
    }
    return candidate.name;
  }

  /// Build a stable deterministic request name for one endpoint pair.
  ///
  /// Parameters:
  /// - `sourceRef`: Source endpoint reference.
  /// - `destinationRef`: Destination endpoint reference.
  ///
  /// Return value:
  /// - Deterministic request identifier safe for repeated connect actions.
  ///
  /// Requirements/Preconditions:
  /// - Both refs identify real endpoints.
  ///
  /// Guarantees/Postconditions:
  /// - Same pair always produces the same request name.
  ///
  /// Invariants:
  /// - Request naming uses only endpoint identities.
  String _requestNameForPair(
    dp.DataItemRef sourceRef,
    dp.DataItemRef destinationRef,
  ) {
    final String sourceNamespace =
        sourceRef.namespaceSelector.sourceEntity ?? 'current';
    final String destinationNamespace =
        destinationRef.namespaceSelector.sourceEntity ?? 'current';
    return '${sourceNamespace}_${sourceRef.name}_to_'
        '${destinationNamespace}_${destinationRef.name}';
  }

  /// Build the picker body for the current async state.
  ///
  /// Parameters:
  /// - `context`: Build context used for theming.
  ///
  /// Return value:
  /// - Loading, error, empty, or grouped candidate content.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Never exposes raw JACK names.
  ///
  /// Invariants:
  /// - Rendering is derived only from current state fields.
  ///
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(key: Key('connection-picker-loading')),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _errorMessage!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    if (_candidateGroups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No compatible endpoints are currently available.'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _candidateGroups.map((_ConnectionCandidateGroup group) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ConnectionGroupCard(
              key: Key('connection-group-${group.label}'),
              group: group,
              isMutating: _isMutating,
              onPressed: () {
                _handleGroupAction(group);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// One grouped action row of candidate endpoints.
class _ConnectionCandidateGroup {
  /// Musician-facing row label.
  final String label;

  /// Endpoints included in the grouped action.
  final List<_ConnectionCandidateMember> members;

  /// Create one grouped candidate row.
  const _ConnectionCandidateGroup({
    required this.label,
    required this.members,
  });

  /// Whether any member uses system-routing metadata.
  bool get isSystem {
    return members.any(
      (_ConnectionCandidateMember member) => member.flags.any(
        (String flag) => flag.startsWith('system_'),
      ),
    );
  }

  /// Whether all members in the row are already connected.
  bool get isFullyConnected {
    return members.isNotEmpty &&
        members.every(
          (_ConnectionCandidateMember member) => member.matchingRequest != null,
        );
  }

  /// Summary of the owning entity or entities represented in the row.
  String get ownerSummary {
    final Set<String> ownerNames = members
        .map((_ConnectionCandidateMember member) => member.ownerEntityName)
        .toSet();
    if (ownerNames.length == 1) {
      return ownerNames.first;
    }
    return 'Multiple apps';
  }
}

/// One endpoint member inside a grouped candidate row.
class _ConnectionCandidateMember {
  /// Raw endpoint metadata for this candidate.
  final dp.EndpointInfo endpoint;

  /// Musician-facing item label.
  final String label;

  /// Owning entity name used for secondary labeling.
  final String ownerEntityName;

  /// Semantic routing flags from endpoint metadata.
  final List<String> flags;

  /// Existing connection request if this member is already connected.
  dp.ConnectionRequest? matchingRequest;

  /// Create one grouped candidate member from raw endpoint metadata.
  _ConnectionCandidateMember({
    required this.endpoint,
    required this.label,
    required this.ownerEntityName,
    required this.flags,
    this.matchingRequest,
  });

  /// Construct one candidate member directly from an endpoint snapshot.
  factory _ConnectionCandidateMember.fromEndpoint(dp.EndpointInfo endpoint) {
    final dp.EndpointSpec? spec = _effectiveSpec(endpoint);
    final String displayLabel =
        spec != null && spec.displayName.trim().isNotEmpty
            ? spec.displayName.trim()
            : endpoint.name;
    return _ConnectionCandidateMember(
      endpoint: endpoint,
      label: displayLabel,
      ownerEntityName:
          endpoint.namespaceSelector.sourceEntity ?? 'Current App',
      flags: spec?.flags ?? const <String>[],
    );
  }
}

/// Presentational card for one grouped connection action row.
class _ConnectionGroupCard extends StatelessWidget {
  /// Candidate row metadata to render.
  final _ConnectionCandidateGroup group;

  /// Whether the picker is currently mutating connection state.
  final bool isMutating;

  /// Invoked when the grouped action button is pressed.
  final VoidCallback onPressed;

  /// Create one grouped connection card.
  const _ConnectionGroupCard({
    super.key,
    required this.group,
    required this.isMutating,
    required this.onPressed,
  });

  /// Build the grouped connection card.
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String actionLabel = group.isFullyConnected ? 'Disconnect' : 'Connect';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    group.label,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (group.isSystem)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'System I/O',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              group.ownerSummary,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (group.members.length > 1) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '${group.members.length} endpoints',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: Key('connection-group-action-${group.label}'),
              onPressed: isMutating ? null : onPressed,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
