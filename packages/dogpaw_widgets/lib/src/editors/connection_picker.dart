import 'dart:math' as math;

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../inputs/system_keyboard_text_field.dart';
import '../models/connection_picker_navigation.dart';
import '../models/connection_picker_types.dart';

/// Touch-friendly font sizes for the connection picker (~18% below prior).
const double _kPickerFontSm = 23;
const double _kPickerFontMd = 26;
const double _kPickerFontLg = 30;
const double _kPickerFontXl = 36;
const double _kPickerIconSm = 30;
const double _kPickerIconLg = 40;
const double _kPickerTap = 56;

/// How many cards fit across the picker rail (fractional peek of the next card).
const double kConnectionPickerVisibleCardSpan = 2.5;

/**
 * Purpose: Resolve the Material icon that marks endpoint transport type on a
 * leaf card (audio / MIDI / generic data).
 *
 * Parameters:
 * - [category]: Endpoint category from the leaf's primary member.
 *
 * Return value:
 * - Audio waveform for audio streams, piano for JACK MIDI, data-object for
 *   message queue / continuous / file-backed.
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Always returns a concrete [IconData].
 *
 * Invariants:
 * - Queue, continuous, and file-backed share one "data" glyph.
 */
IconData connectionPickerTypeIcon(
  dp.EndpointCategory category, {
  dp.DataType? baseType,
}) {
  if (baseType == dp.DataType.ledMessage) {
    return Icons.lightbulb;
  }
  switch (category) {
    case dp.EndpointCategory.audioStream:
      return Icons.speaker;
    case dp.EndpointCategory.jackMidiStream:
      return Icons.piano;
    case dp.EndpointCategory.messageQueue:
    case dp.EndpointCategory.continuous:
    case dp.EndpointCategory.fileBacked:
      return Icons.category;
  }
}

/**
 * Purpose: Musician-facing direction label for a leaf card header.
 *
 * Parameters:
 * - [direction]: Endpoint data-flow direction from the leaf's primary member.
 *
 * Return value:
 * - `"input"` or `"output"`. Bidirectional is treated as stale (C++ no longer
 *   authors it); the label falls back to `"output"` for exhaustiveness.
 *
 * Requirements/Preconditions:
 * - None.
 *
 * Guarantees/Postconditions:
 * - Always returns a non-empty lowercase label.
 *
 * Invariants:
 * - Does not invent bidirectional UI; see stale note above.
 */
String connectionPickerDirectionLabel(dp.EndpointDirection direction) {
  switch (direction) {
    case dp.EndpointDirection.input:
      return 'input';
    case dp.EndpointDirection.output:
      return 'output';
    // STALE: EndpointDirection.bidirectional is retained for Dart enum /
    // JSON exhaustiveness only; C++ EndpointManager no longer accepts it.
    case dp.EndpointDirection.bidirectional:
      return 'output';
  }
}

/// Search-result leaf fonts (~30% smaller than browse cards).
const double _kPickerSearchFontSm = 16;
const double _kPickerSearchFontMd = 18;
const double _kPickerSearchFontXl = 25;

/// Return the best available endpoint specification for one metadata snapshot.
///
/// Parameters:
/// - [endpoint]: Endpoint metadata snapshot whose spec should be inspected.
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

/// Reusable connection editor / endpoint picker with two modes.
///
/// Purpose:
/// Presents compatible peers (or, in endpoint mode, direction-filtered
/// endpoints) as a folder-navigable horizontal card rail with a top band
/// (Back, breadcrumb, focus context, search, optional dismiss). Uses
/// [ConnectionNavigationModel] for path/search logic. In
/// [ConnectionPickerMode.connection] (the default), the widget itself
/// mutates this entity's [dp.ConnectionRule]s via the supplied entity client.
/// In [ConnectionPickerMode.endpoint], the widget never mutates routing
/// state; it only reports the chosen leaf(s) back to the host.
class ConnectionPicker extends StatefulWidget {
  /// Entity client used to query and (in connection mode) mutate routing
  /// state.
  final dp.DogPawEntity entity;

  /// Picker mode; defaults to [ConnectionPickerMode.connection] so existing
  /// hosts keep today's behavior unchanged.
  final ConnectionPickerMode mode;

  /// Endpoint whose compatible peers should be presented to the user.
  ///
  /// Required in [ConnectionPickerMode.connection]; ignored in
  /// [ConnectionPickerMode.endpoint].
  final dp.EndpointInfo? focusedEndpoint;

  /// Direction filter for [ConnectionPickerMode.endpoint]; ignored in
  /// connection mode.
  final EndpointDirectionFilter directionFilter;

  /// Whether endpoint mode allows selecting more than one leaf via an
  /// explicit Confirm/Cancel bar. Ignored in connection mode.
  final bool multiSelect;

  /// Optional callback that requests an external refresh after connection work.
  final Future<void> Function()? onRefresh;

  /// Optional callback invoked after each connection-mode leaf action that
  /// produced at least one [ConnectionRuleMutation]. Ignored in endpoint mode.
  final void Function(List<ConnectionRuleMutation> mutations)? onMutated;

  /// Optional callback invoked when endpoint mode completes a selection:
  /// immediately after a single-select leaf tap, or after Confirm in
  /// multi-select mode. Ignored in connection mode.
  final void Function(List<EndpointLeafSelection> leaves)? onEndpointsSelected;

  /// Optional host-driven leaf chrome resolver. `null` uses the picker's
  /// default: this-entity connection-rule match ⇒ `lit`, else `unlit`.
  final ConnectionPickerLeafChromeResolver? leafChrome;

  /// Optional dismiss handler for dialog chrome (close control).
  ///
  /// When non-null, the top band shows an explicit dismiss control that
  /// invokes this callback; the endpoint-mode multi-select Cancel button also
  /// invokes this callback. Back at the root remains a no-op.
  final VoidCallback? onDismiss;

  /// Optional shared search text controller (dialog hosts own this).
  final TextEditingController? searchController;

  /// Optional shared search-field focus node (dialog hosts may own this).
  final FocusNode? searchFocusNode;

  /// Create one reusable connection / endpoint picker.
  ///
  /// Parameters:
  /// - [entity]: Dog Paw entity client used for routing operations.
  /// - [mode]: Connection mutation mode vs endpoint selection mode.
  /// - [focusedEndpoint]: Endpoint whose connections are being edited;
  ///   required in connection mode.
  /// - [directionFilter]: Endpoint-mode direction filter.
  /// - [multiSelect]: Endpoint-mode multi-select flag.
  /// - [onRefresh]: Optional host callback requested after connection changes.
  /// - [onMutated]: Optional connection-mode mutation-batch callback.
  /// - [onEndpointsSelected]: Optional endpoint-mode selection callback.
  /// - [leafChrome]: Optional host-driven per-leaf chrome resolver.
  /// - [onDismiss]: Optional close handler; when set, shows dismiss in the
  ///   top band (dialog hosts wire this to `Navigator.pop`).
  /// - [searchController]: Optional shared search text controller.
  /// - [searchFocusNode]: Optional shared search-field focus node.
  ///
  /// Return value:
  /// - A new [ConnectionPicker].
  ///
  /// Requirements/Preconditions:
  /// - [focusedEndpoint] must be non-null when [mode] is
  ///   [ConnectionPickerMode.connection] (enforced by an assertion).
  /// - When [searchController] / [searchFocusNode] are provided, the caller
  ///   owns their lifetimes.
  ///
  /// Guarantees/Postconditions:
  /// - The widget owns presentation and navigation stack state; path resolution
  ///   is delegated to [ConnectionNavigationModel].
  ///
  /// Invariants:
  /// - Raw JACK port names are not part of the public widget contract.
  const ConnectionPicker({
    super.key,
    required this.entity,
    this.mode = ConnectionPickerMode.connection,
    this.focusedEndpoint,
    this.directionFilter = EndpointDirectionFilter.both,
    this.multiSelect = false,
    this.onRefresh,
    this.onMutated,
    this.onEndpointsSelected,
    this.leafChrome,
    this.onDismiss,
    this.searchController,
    this.searchFocusNode,
  }) : assert(
          mode != ConnectionPickerMode.connection || focusedEndpoint != null,
          'ConnectionPicker requires a focusedEndpoint in connection mode.',
        );

  @override
  State<ConnectionPicker> createState() => _ConnectionPickerState();
}

/// Local UI state for the connection / endpoint picker.
class _ConnectionPickerState extends State<ConnectionPicker> {
  bool _isLoading = true;
  bool _isMutating = false;
  String? _errorMessage;
  ConnectionNavigationModel? _navigationModel;
  List<String> _path = <String>[];
  bool _isSearchMode = false;
  String _searchQuery = '';
  TextEditingController? _ownedSearchController;
  FocusNode? _ownedSearchFocusNode;
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;

  /// Endpoint-mode multi-select working set (identity-based; leaves are
  /// stable object references between taps since no reload happens while
  /// selecting).
  final Set<ConnectionNavLeafCard> _selectedLeaves = <ConnectionNavLeafCard>{};

  /// Attach shared or owned search controllers and focus node.
  ///
  /// Parameters: none.
  /// Return value: none.
  /// Requirements/Preconditions: Called from [initState] / [didUpdateWidget].
  /// Guarantees/Postconditions: [_searchController] and [_searchFocusNode]
  /// point at active objects.
  /// Invariants: At most one owned controller or focus node of each type exists.
  void _attachControllers() {
    if (widget.searchController != null) {
      _ownedSearchController?.dispose();
      _ownedSearchController = null;
      _searchController = widget.searchController!;
    } else {
      _ownedSearchController ??= TextEditingController();
      _searchController = _ownedSearchController!;
    }

    if (widget.searchFocusNode != null) {
      _ownedSearchFocusNode?.dispose();
      _ownedSearchFocusNode = null;
      _searchFocusNode = widget.searchFocusNode!;
    } else {
      _ownedSearchFocusNode ??= FocusNode();
      _searchFocusNode = _ownedSearchFocusNode!;
    }
  }

  @override
  void initState() {
    super.initState();
    _attachControllers();
    _searchController.addListener(_onSearchTextChanged);
    _loadCandidates();
  }

  @override
  void didUpdateWidget(covariant ConnectionPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchController != widget.searchController ||
        oldWidget.searchFocusNode != widget.searchFocusNode) {
      _searchController.removeListener(_onSearchTextChanged);
      _attachControllers();
      _searchController.addListener(_onSearchTextChanged);
    }

    if (oldWidget.mode != widget.mode) {
      _selectedLeaves.clear();
    }

    bool shouldReload =
        oldWidget.entity != widget.entity || oldWidget.mode != widget.mode;

    if (widget.mode == ConnectionPickerMode.connection) {
      final dp.EndpointInfo? oldFocused = oldWidget.focusedEndpoint;
      final dp.EndpointInfo? newFocused = widget.focusedEndpoint;
      final dp.EndpointSpec? oldFocusedSpec =
          oldFocused == null ? null : _effectiveSpec(oldFocused);
      final dp.EndpointSpec? newFocusedSpec =
          newFocused == null ? null : _effectiveSpec(newFocused);
      final bool focusedEndpointChanged =
          oldFocused?.name != newFocused?.name ||
              oldFocused?.namespaceSelector != newFocused?.namespaceSelector ||
              oldFocusedSpec?.direction != newFocusedSpec?.direction ||
              oldFocusedSpec?.dataType.baseType !=
                  newFocusedSpec?.dataType.baseType;
      shouldReload = shouldReload || focusedEndpointChanged;
    } else {
      shouldReload =
          shouldReload || oldWidget.directionFilter != widget.directionFilter;
    }

    if (shouldReload) {
      _loadCandidates();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _ownedSearchController?.dispose();
    _ownedSearchFocusNode?.dispose();
    super.dispose();
  }

  /// Sync [_searchQuery] from the active text controller.
  ///
  /// Parameters: none.
  /// Return value: none.
  /// Requirements/Preconditions: Controllers are attached.
  /// Guarantees/Postconditions: Rebuilds when query text changes in search mode.
  /// Invariants: Does not mutate the text controller value.
  void _onSearchTextChanged() {
    if (!_isSearchMode || !mounted) {
      return;
    }
    final String next = _searchController.text;
    if (next == _searchQuery) {
      return;
    }
    setState(() {
      _searchQuery = next;
    });
  }

  /// Load compatible endpoints (or peers) and build the navigation model.
  ///
  /// Parameters:
  /// - [resetNavigation]: Whether to reset path/search state (default).
  ///   `false` preserves the current folder path across a post-mutation
  ///   reload.
  ///
  /// Return value:
  /// - A future that completes when the picker state has refreshed.
  ///
  /// Requirements/Preconditions:
  /// - None beyond the widget's own mode-specific contract (asserted in the
  ///   constructor for connection mode).
  ///
  /// Guarantees/Postconditions:
  /// - Delegates to [_loadConnectionCandidates] or [_loadEndpointCandidates]
  ///   based on [widget.mode].
  ///
  /// Invariants:
  /// - Raw JACK port names are not stored for rendering.
  Future<void> _loadCandidates({bool resetNavigation = true}) {
    if (widget.mode == ConnectionPickerMode.endpoint) {
      return _loadEndpointCandidates(resetNavigation: resetNavigation);
    }
    return _loadConnectionCandidates(resetNavigation: resetNavigation);
  }

  /// Load compatible peers for connection mode and build the navigation model.
  ///
  /// Parameters:
  /// - [resetNavigation]: Whether to reset path/search state.
  ///
  /// Return value:
  /// - A future that completes when the picker state has refreshed.
  ///
  /// Requirements/Preconditions:
  /// - [widget.focusedEndpoint] must be non-null (guaranteed by the
  ///   constructor assertion in connection mode).
  ///
  /// Guarantees/Postconditions:
  /// - On success, [_navigationModel] is set from compatible peers + rules.
  /// - On failure, [_errorMessage] contains a user-facing explanation.
  /// - Navigation path and search mode reset on each successful/failed load
  ///   start except when preserving path after a mutation reload (path kept
  ///   when model rebuilds with same focus).
  ///
  /// Invariants:
  /// - Raw JACK port names are not stored for rendering.
  Future<void> _loadConnectionCandidates({bool resetNavigation = true}) async {
    final dp.EndpointInfo focused = widget.focusedEndpoint!;
    final dp.EndpointSpec? focusedSpec = _effectiveSpec(focused);
    if (focusedSpec == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'This endpoint is missing routing metadata.';
        _navigationModel = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (resetNavigation) {
        _path = <String>[];
        _isSearchMode = false;
        _searchQuery = '';
        _searchController.clear();
      }
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
        widget.entity.listConnectionRules(includeSpec: true),
      ],
    );

    final dp.Result<List<dp.EndpointInfo>> endpointResult =
        results[0] as dp.Result<List<dp.EndpointInfo>>;
    final dp.Result<List<dp.ConnectionRule>> requestResult =
        results[1] as dp.Result<List<dp.ConnectionRule>>;

    if (!endpointResult.success) {
      setState(() {
        _isLoading = false;
        _errorMessage = endpointResult.error;
        _navigationModel = null;
      });
      return;
    }

    if (!requestResult.success) {
      setState(() {
        _isLoading = false;
        _errorMessage = requestResult.error;
        _navigationModel = null;
      });
      return;
    }

    final List<dp.EndpointInfo> compatibleEndpoints =
        endpointResult.value!.where(_isCompatibleCandidate).toList();
    final List<dp.ConnectionRule> connectionRules =
        requestResult.value ?? <dp.ConnectionRule>[];

    final ConnectionNavigationModel model = ConnectionNavigationModel.build(
      focusedEndpoint: focused,
      candidates: compatibleEndpoints,
      connectionRules: connectionRules,
    );

    _applyLoadedModel(model, resetNavigation: resetNavigation);
  }

  /// Load direction-filtered endpoints for endpoint mode and build the model.
  ///
  /// Parameters:
  /// - [resetNavigation]: Whether to reset path/search state.
  ///
  /// Return value:
  /// - A future that completes when the picker state has refreshed.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - On success, [_navigationModel] is built with no focused endpoint, so
  ///   every leaf reports `isFullyConnected == false` by default.
  /// - On failure, [_errorMessage] contains a user-facing explanation.
  ///
  /// Invariants:
  /// - Never mutates routing state.
  Future<void> _loadEndpointCandidates({bool resetNavigation = true}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (resetNavigation) {
        _path = <String>[];
        _isSearchMode = false;
        _searchQuery = '';
        _searchController.clear();
      }
    });

    final dp.SearchCriteria criteria =
        _endpointModeCriteria(widget.directionFilter);
    final dp.Result<List<dp.EndpointInfo>> endpointResult =
        await widget.entity.searchEndpoints(criteria);

    if (!endpointResult.success) {
      setState(() {
        _isLoading = false;
        _errorMessage = endpointResult.error;
        _navigationModel = null;
      });
      return;
    }

    final ConnectionNavigationModel model = ConnectionNavigationModel.build(
      focusedEndpoint: null,
      candidates: endpointResult.value ?? const <dp.EndpointInfo>[],
    );

    _applyLoadedModel(model, resetNavigation: resetNavigation);
  }

  /// Commit a freshly built navigation model to state, preserving a valid
  /// folder path when reloading after a mutation.
  ///
  /// Parameters:
  /// - [model]: Newly built navigation model.
  /// - [resetNavigation]: Whether to reset the folder path to root.
  ///
  /// Return value: none.
  ///
  /// Requirements/Preconditions: none.
  ///
  /// Guarantees/Postconditions:
  /// - [_navigationModel] and [_isLoading] are updated together.
  /// - When not resetting, an invalidated path walks back to a valid ancestor.
  ///
  /// Invariants:
  /// - Does not touch search state.
  void _applyLoadedModel(
    ConnectionNavigationModel model, {
    required bool resetNavigation,
  }) {
    setState(() {
      _navigationModel = model;
      _isLoading = false;
      if (resetNavigation) {
        _path = <String>[];
      } else if (_path.isNotEmpty && model.cardsAt(_path).isEmpty) {
        // Path became invalid after mutation; walk back to a valid ancestor.
        while (_path.isNotEmpty && model.cardsAt(_path).isEmpty) {
          _path = List<String>.from(_path)..removeLast();
        }
      }
    });
  }

  /// Build the endpoint-mode search criteria for one direction filter.
  ///
  /// Parameters:
  /// - [filter]: Requested direction filter.
  ///
  /// Return value:
  /// - Criteria matching [dp.EndpointDirection.output] for `sources`,
  ///   [dp.EndpointDirection.input] for `destinations`, or every direction
  ///   for `both`.
  ///
  /// Requirements/Preconditions: none.
  ///
  /// Guarantees/Postconditions: Pure function of [filter].
  ///
  /// Invariants: Does not depend on any focused endpoint.
  dp.SearchCriteria _endpointModeCriteria(EndpointDirectionFilter filter) {
    switch (filter) {
      case EndpointDirectionFilter.sources:
        return dp.SearchCriteria.directionEquals(dp.EndpointDirection.output);
      case EndpointDirectionFilter.destinations:
        return dp.SearchCriteria.directionEquals(dp.EndpointDirection.input);
      case EndpointDirectionFilter.both:
        // STALE: bidirectional is included only for Dart/JSON exhaustiveness;
        // C++ no longer authors bidirectional endpoints.
        return dp.SearchCriteria.orCombination(<dp.SearchCriteria>[
          dp.SearchCriteria.directionEquals(dp.EndpointDirection.input),
          dp.SearchCriteria.directionEquals(dp.EndpointDirection.output),
          dp.SearchCriteria.directionEquals(dp.EndpointDirection.bidirectional),
        ]);
    }
  }

  /// Decide whether one discovered endpoint is compatible with the focused endpoint.
  ///
  /// Parameters:
  /// - [candidate]: Endpoint metadata to inspect.
  ///
  /// Return value:
  /// - `true` when the endpoint is eligible for display in this picker.
  ///
  /// Requirements/Preconditions:
  /// - [widget.focusedEndpoint] should contain endpoint metadata with a spec.
  ///
  /// Guarantees/Postconditions:
  /// - Self-connections are excluded.
  /// - Direction and base type must match the focused-endpoint routing rules.
  ///
  /// Invariants:
  /// - Candidate metadata is not mutated.
  bool _isCompatibleCandidate(dp.EndpointInfo candidate) {
    final dp.EndpointInfo focused = widget.focusedEndpoint!;
    return isCompatibleConnectionPair(focused, candidate);
  }

  /// Create the rule payload for one focused/candidate endpoint pair.
  ///
  /// Parameters:
  /// - [candidate]: Candidate endpoint to connect with the focused endpoint.
  ///
  /// Return value:
  /// - New [dp.ConnectionRule] describing the desired routing pair.
  ///
  /// Requirements/Preconditions:
  /// - [candidate] is compatible with [widget.focusedEndpoint].
  ///
  /// Guarantees/Postconditions:
  /// - Focused-input flows use the candidate as source.
  /// - Focused-output flows use the candidate as destination.
  ///
  /// Invariants:
  /// - Rule identity is opaque and independent of endpoint selectors.
  dp.ConnectionRule _buildConnectionRuleForCandidate(
      dp.EndpointInfo candidate) {
    final dp.EndpointInfo focused = widget.focusedEndpoint!;
    final dp.EndpointSpec focusedSpec = _effectiveSpec(focused)!;
    final bool focusedIsInput =
        focusedSpec.direction == dp.EndpointDirection.input;
    final dp.DataItemRef sourceRef =
        focusedIsInput ? endpointRef(candidate) : endpointRef(focused);
    final dp.DataItemRef destinationRef =
        focusedIsInput ? endpointRef(focused) : endpointRef(candidate);
    final dp.EndpointInfo sourceEndpoint = focusedIsInput ? candidate : focused;
    final dp.EndpointInfo destinationEndpoint =
        focusedIsInput ? focused : candidate;
    final dp.IndexConversionConfig? indexConversion =
        defaultIndexConversionForConnectionPair(
      sourceEndpoint,
      destinationEndpoint,
    );

    return dp.ConnectionRule(
      name: _newOpaqueRuleName(),
      spec: dp.ConnectionRuleData(
        sourceRef: sourceRef,
        destinationRef: destinationRef,
        indexConversion: indexConversion,
      ),
    );
  }

  /// Dispatch one leaf-card tap by mode.
  ///
  /// Parameters:
  /// - [leaf]: Leaf card whose whole-card tap was received.
  ///
  /// Return value:
  /// - A future that completes after the tap has been fully handled.
  ///
  /// Requirements/Preconditions:
  /// - None (no-op while a connection-mode mutation is in flight).
  ///
  /// Guarantees/Postconditions:
  /// - Connection mode mutates routing state; endpoint mode never does.
  ///
  /// Invariants:
  /// - Delegates entirely to mode-specific handlers.
  Future<void> _handleLeafAction(ConnectionNavLeafCard leaf) async {
    if (widget.mode == ConnectionPickerMode.endpoint) {
      _handleEndpointLeafTap(leaf);
      return;
    }
    await _handleConnectionLeafTap(leaf);
  }

  /// Handle one leaf tap in endpoint-selection mode.
  ///
  /// Parameters:
  /// - [leaf]: Leaf card whose whole-card tap was received.
  ///
  /// Return value: none.
  ///
  /// Requirements/Preconditions:
  /// - [widget.mode] is [ConnectionPickerMode.endpoint].
  ///
  /// Guarantees/Postconditions:
  /// - Single-select mode reports the leaf immediately via
  ///   [ConnectionPicker.onEndpointsSelected] and does not track selection
  ///   state.
  /// - Multi-select mode toggles [leaf] in [_selectedLeaves] without
  ///   reporting a result (Confirm/Cancel report the result).
  ///
  /// Invariants:
  /// - Never mutates routing state.
  void _handleEndpointLeafTap(ConnectionNavLeafCard leaf) {
    if (widget.multiSelect) {
      setState(() {
        if (!_selectedLeaves.remove(leaf)) {
          _selectedLeaves.add(leaf);
        }
      });
      return;
    }
    widget.onEndpointsSelected?.call(
      <EndpointLeafSelection>[endpointLeafSelectionFromCard(leaf)],
    );
  }

  /// Report the confirmed multi-select endpoint selection to the host.
  ///
  /// Parameters: none.
  /// Return value: none.
  /// Requirements/Preconditions: [widget.mode] is endpoint mode with
  /// `multiSelect: true`.
  /// Guarantees/Postconditions: Invokes [ConnectionPicker.onEndpointsSelected]
  /// with every currently selected leaf; does not clear the selection itself
  /// (the host typically closes the dialog on this callback).
  /// Invariants: Never mutates routing state.
  void _handleConfirmMultiSelect() {
    widget.onEndpointsSelected?.call(
      _selectedLeaves.map(endpointLeafSelectionFromCard).toList(),
    );
  }

  /// Cancel endpoint-mode multi-select without reporting a selection.
  ///
  /// Parameters: none.
  /// Return value: none.
  /// Requirements/Preconditions: none.
  /// Guarantees/Postconditions: Invokes [ConnectionPicker.onDismiss] when
  /// supplied; the selection working set is left untouched (the widget is
  /// typically disposed immediately after by the dialog host).
  /// Invariants: Never reports an endpoint selection.
  void _handleCancelMultiSelect() {
    widget.onDismiss?.call();
  }

  /// Resolve the chrome token for one leaf via the host resolver or default.
  ///
  /// Parameters:
  /// - [leaf]: Leaf card to resolve chrome for.
  ///
  /// Return value:
  /// - Host-supplied chrome when [ConnectionPicker.leafChrome] is non-null;
  ///   otherwise `lit` when [leaf.isFullyConnected], else `unlit`.
  ///
  /// Requirements/Preconditions: none.
  ///
  /// Guarantees/Postconditions: Pure function of [leaf] and widget config.
  ///
  /// Invariants:
  /// - Never queries realized-connection state itself; a host resolver is
  ///   responsible for any domain-specific lookup.
  ConnectionPickerLeafChrome _chromeForLeaf(ConnectionNavLeafCard leaf) {
    final ConnectionPickerLeafChromeResolver? resolver = widget.leafChrome;
    if (resolver != null) {
      return resolver(endpointLeafSelectionFromCard(leaf));
    }
    return leaf.isFullyConnected
        ? ConnectionPickerLeafChrome.lit
        : ConnectionPickerLeafChrome.unlit;
  }

  /// Toggle connect/disconnect for all members of one leaf card.
  ///
  /// Parameters:
  /// - [leaf]: Leaf card whose whole-card tap was received.
  ///
  /// Return value:
  /// - A future that completes after the routing change has been applied.
  ///
  /// Requirements/Preconditions:
  /// - [widget.mode] is [ConnectionPickerMode.connection] (no-op while
  ///   mutating).
  ///
  /// Guarantees/Postconditions:
  /// - Fully connected leaves disconnect all matching members, unless the
  ///   resolved chrome is `muted`, in which case the tap is a no-op (no
  ///   delete via the picker).
  /// - Other leaves connect every missing member in the leaf; members that
  ///   already have a matching rule are skipped (selector match) and
  ///   recorded as `skippedExisting` rather than creating a duplicate rule.
  /// - [ConnectionPicker.onMutated] is invoked with every mutation recorded
  ///   during this action, when non-empty.
  /// - Navigation path is preserved across the reload.
  ///
  /// Invariants:
  /// - Pair semantics match the former grouped action loop.
  /// - Opaque rule names mean "already connected" is determined solely by
  ///   selector match, never by name equality.
  Future<void> _handleConnectionLeafTap(ConnectionNavLeafCard leaf) async {
    if (_isMutating) {
      return;
    }

    final dp.EndpointInfo focused = widget.focusedEndpoint!;

    if (leaf.isFullyConnected &&
        _chromeForLeaf(leaf) == ConnectionPickerLeafChrome.muted) {
      // Muted: host indicates this pair should not be deleted via the picker.
      return;
    }

    setState(() {
      _isMutating = true;
    });

    bool sawFailure = false;
    final List<ConnectionRuleMutation> mutations = <ConnectionRuleMutation>[];
    final List<dp.ConnectionRule> rules = await _currentRulesSnapshot();
    if (leaf.isFullyConnected) {
      for (final dp.EndpointInfo member in leaf.members) {
        final dp.ConnectionRule? rule = matchingConnectionRule(
          focused: focused,
          candidate: member,
          connectionRules: rules,
        );
        if (rule == null) {
          continue;
        }
        final dp.Result<bool> result =
            await widget.entity.deleteConnectionRule(rule.name);
        if (!result.success) {
          sawFailure = true;
          _errorMessage = result.error;
          break;
        }
        final dp.ConnectionRuleData? ruleData = rule.spec ?? rule.resolved;
        if (ruleData != null) {
          mutations.add(
            ConnectionRuleMutation(
              kind: ConnectionRuleMutationKind.deleted,
              ruleName: rule.name,
              sourceRef: ruleData.sourceRef,
              destinationRef: ruleData.destinationRef,
            ),
          );
        }
      }
    } else {
      for (final dp.EndpointInfo member in leaf.members) {
        final dp.ConnectionRule? existing = matchingConnectionRule(
          focused: focused,
          candidate: member,
          connectionRules: rules,
        );
        if (existing != null) {
          final dp.ConnectionRuleData? existingData =
              existing.spec ?? existing.resolved;
          if (existingData != null) {
            mutations.add(
              ConnectionRuleMutation(
                kind: ConnectionRuleMutationKind.skippedExisting,
                ruleName: existing.name,
                sourceRef: existingData.sourceRef,
                destinationRef: existingData.destinationRef,
              ),
            );
          }
          continue;
        }
        final dp.ConnectionRule newRule =
            _buildConnectionRuleForCandidate(member);
        final dp.Result<bool> result =
            await widget.entity.createConnectionRule(newRule);
        if (!result.success) {
          sawFailure = true;
          _errorMessage = result.error;
          break;
        }
        mutations.add(
          ConnectionRuleMutation(
            kind: ConnectionRuleMutationKind.created,
            ruleName: newRule.name,
            sourceRef: newRule.spec!.sourceRef,
            destinationRef: newRule.spec!.destinationRef,
          ),
        );
      }
    }

    if (!sawFailure) {
      if (widget.onRefresh != null) {
        await widget.onRefresh!.call();
      }
      if (mutations.isNotEmpty) {
        widget.onMutated?.call(mutations);
      }
    }

    setState(() {
      _isMutating = false;
    });
    await _loadCandidates(resetNavigation: false);
  }

  /// Snapshot current connection rules from the entity client.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Rule list on success, or empty list on failure (caller may still mutate).
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Does not update widget loading UI.
  ///
  /// Invariants:
  /// - Pure fetch; no local model mutation.
  Future<List<dp.ConnectionRule>> _currentRulesSnapshot() async {
    final dp.Result<List<dp.ConnectionRule>> result =
        await widget.entity.listConnectionRules(includeSpec: true);
    if (!result.success) {
      return const <dp.ConnectionRule>[];
    }
    return result.value ?? const <dp.ConnectionRule>[];
  }

  /// Return the opposite direction required for a focused endpoint.
  ///
  /// Parameters:
  /// - [focusedDirection]: Direction on the focused endpoint.
  ///
  /// Return value:
  /// - Opposite endpoint direction to search for.
  ///
  /// Requirements/Preconditions:
  /// - Bidirectional endpoints are treated as output-focused for this version.
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
      // STALE: bidirectional treated like output for peer matching only.
      case dp.EndpointDirection.bidirectional:
        return dp.EndpointDirection.input;
    }
  }

  /// Build a fresh opaque persistent connection-rule identity.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - UUID-shaped random request identifier.
  ///
  /// Requirements/Preconditions:
  /// - The platform cryptographic random source is available.
  ///
  /// Guarantees/Postconditions:
  /// - The returned identifier does not encode endpoint identities.
  ///
  /// Invariants:
  /// - Existing rule names remain stable during later selector updates.
  String _newOpaqueRuleName() => newOpaqueConnectionRuleName();

  /// Pop one folder from the navigation stack, or no-op at root.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Not in search mode (search clear exits search instead).
  ///
  /// Guarantees/Postconditions:
  /// - At root, path is unchanged.
  /// - When nested, removes the last path segment.
  ///
  /// Invariants:
  /// - Does not dismiss the dialog.
  void _handleBack() {
    if (_isSearchMode) {
      _exitSearchMode();
      return;
    }
    if (_path.isEmpty) {
      return;
    }
    setState(() {
      _path = List<String>.from(_path)..removeLast();
    });
  }

  /// Enter search mode and focus the query field.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Navigation model may be null (empty/error states).
  ///
  /// Guarantees/Postconditions:
  /// - [_isSearchMode] becomes true.
  ///
  /// Invariants:
  /// - Folder path is preserved while searching.
  void _enterSearchMode() {
    setState(() {
      _isSearchMode = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _searchFocusNode.requestFocus();
    });
  }

  /// Clear the search query and return to folder navigation.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Search mode is off and query is empty; keyboard is hidden.
  ///
  /// Invariants:
  /// - Folder path is unchanged.
  void _exitSearchMode() {
    _searchFocusNode.unfocus();
    setState(() {
      _isSearchMode = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  /// Musician-facing focus context line for the top band.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - In connection mode: guide string with `(source)` / `(destination)`
  ///   blank and focused label.
  /// - In endpoint mode: a short prompt describing [widget.directionFilter].
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Uses display name when available; never raw JACK names.
  /// - Focused inputs: `(source) -> Label - Owner`.
  /// - Focused outputs/bidirectional: `Label - Owner -> (destination)`.
  ///
  /// Invariants:
  /// - Pure function of [widget.focusedEndpoint] / [widget.directionFilter].
  String _focusContextLabel() {
    if (widget.mode == ConnectionPickerMode.endpoint) {
      switch (widget.directionFilter) {
        case EndpointDirectionFilter.sources:
          return 'Choose a source';
        case EndpointDirectionFilter.destinations:
          return 'Choose a destination';
        case EndpointDirectionFilter.both:
          return 'Choose an endpoint';
      }
    }

    final dp.EndpointInfo focused = widget.focusedEndpoint!;
    final dp.EndpointSpec? spec = _effectiveSpec(focused);
    final String label = (spec != null && spec.displayName.trim().isNotEmpty)
        ? spec.displayName.trim()
        : focused.name;
    final String owner = focused.ownerDisplayName?.trim().isNotEmpty == true
        ? focused.ownerDisplayName!.trim()
        : (focused.namespaceSelector.sourceEntity ?? '');
    final String named = owner.isEmpty ? label : '$label - $owner';
    final bool focusedIsInput =
        spec != null && spec.direction == dp.EndpointDirection.input;
    if (focusedIsInput) {
      return '(source) -> $named';
    }
    return '$named -> (destination)';
  }

  /// Breadcrumb segments for the current folder stack (`Home` + path).
  ///
  /// Parameters: none.
  /// Return value: Ordered segment labels starting with `Home`.
  /// Requirements/Preconditions: none.
  /// Guarantees/Postconditions: Length is `1 + _path.length`.
  /// Invariants: Does not include leaf titles.
  List<String> _breadcrumbSegments() {
    return <String>['Home', ..._path];
  }

  /// Jump to a breadcrumb segment index (`0` = Home / root).
  ///
  /// Parameters:
  /// - [segmentIndex]: Zero-based index into [_breadcrumbSegments].
  ///
  /// Return value: none.
  /// Requirements/Preconditions: Index is within segment bounds.
  /// Guarantees/Postconditions: [_path] becomes the prefix up to that segment.
  /// Invariants: Does not enter or exit search mode.
  void _jumpToBreadcrumbSegment(int segmentIndex) {
    if (segmentIndex < 0) {
      return;
    }
    setState(() {
      if (segmentIndex == 0) {
        _path = <String>[];
      } else {
        _path = _path.sublist(0, math.min(segmentIndex, _path.length));
      }
    });
  }

  /// Cards currently shown on the rail (folder level or search flatten).
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Ordered navigation cards, or empty when model unavailable.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Search mode returns only leaf cards from [ConnectionNavigationModel.search].
  ///
  /// Invariants:
  /// - Does not mutate the model.
  List<ConnectionNavCard> _visibleCards() {
    final ConnectionNavigationModel? model = _navigationModel;
    if (model == null) {
      return const <ConnectionNavCard>[];
    }
    if (_isSearchMode) {
      return model.search(_searchQuery);
    }
    return model.cardsAt(_path);
  }

  /// Build the picker chrome for the current async and navigation state.
  ///
  /// Parameters:
  /// - [context]: Build context used for theming and MediaQuery.
  ///
  /// Return value:
  /// - Column with top band and rail / status content.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Never exposes raw JACK names.
  /// - Bounded-height hosts (dialogs) expand the rail to fill remaining space.
  /// - Unbounded-height hosts (scroll views) use a fixed rail height so
  ///   siblings below the picker keep normal document flow.
  ///
  /// Invariants:
  /// - Rendering is derived only from current state fields.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget body = _buildBody(context);
        final bool hasBoundedHeight = constraints.hasBoundedHeight;
        final Widget bodySlot;
        if (hasBoundedHeight) {
          bodySlot = Expanded(child: body);
        } else {
          // Embedded hosts (e.g. workbench SingleChildScrollView) give
          // unbounded height; expand would break sibling layout below.
          final double screenHeight = MediaQuery.sizeOf(context).height;
          final double embeddedHeight =
              (screenHeight * 0.42).clamp(220.0, 360.0);
          bodySlot = SizedBox(
            key: const Key('connection-picker-embedded-body'),
            height: embeddedHeight,
            child: body,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
          children: <Widget>[
            _ConnectionPickerTopBand(
              breadcrumbSegments: _breadcrumbSegments(),
              focusContext: _focusContextLabel(),
              isSearchMode: _isSearchMode,
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              canGoBack: _path.isNotEmpty || _isSearchMode,
              showDismiss: widget.onDismiss != null,
              onBack: _handleBack,
              onSearch: _enterSearchMode,
              onBreadcrumbSegmentTap: _jumpToBreadcrumbSegment,
              onSearchClear: _exitSearchMode,
              onDismiss: widget.onDismiss,
            ),
            bodySlot,
            if (widget.mode == ConnectionPickerMode.endpoint &&
                widget.multiSelect)
              _EndpointMultiSelectBar(
                selectedCount: _selectedLeaves.length,
                onCancel: _handleCancelMultiSelect,
                onConfirm:
                    _selectedLeaves.isEmpty ? null : _handleConfirmMultiSelect,
              ),
          ],
        );
      },
    );
  }

  /// Build loading, error, empty, or horizontal rail content.
  ///
  /// Parameters:
  /// - [context]: Build context used for theming.
  ///
  /// Return value:
  /// - Status widget or horizontal card rail.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Empty compatible set and empty search results show safe copy.
  ///
  /// Invariants:
  /// - Does not expose JACK names.
  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(
            key: Key('connection-picker-loading'),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _errorMessage!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: _kPickerFontLg,
          ),
        ),
      );
    }

    final List<ConnectionNavCard> cards = _visibleCards();
    if (cards.isEmpty) {
      final String emptyMessage = _isSearchMode
          ? 'No matching endpoints.'
          : 'No compatible endpoints are currently available.';
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          emptyMessage,
          style: const TextStyle(fontSize: _kPickerFontLg),
        ),
      );
    }

    return _ConnectionPickerRail(
      cards: cards,
      isMutating: _isMutating,
      showSearchBreadcrumb: _isSearchMode,
      chromeFor: _chromeForLeaf,
      isSelected: _selectedLeaves.contains,
      onFolderTap: (ConnectionNavFolderCard folder) {
        setState(() {
          _path = List<String>.from(folder.path);
        });
      },
      onLeafTap: _handleLeafAction,
    );
  }
}

/// Bottom Confirm/Cancel bar for endpoint-mode multi-select.
class _EndpointMultiSelectBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  /// Create the multi-select Confirm/Cancel bar.
  ///
  /// Parameters:
  /// - [selectedCount]: Number of leaves currently selected.
  /// - [onCancel]: Cancel tap handler.
  /// - [onConfirm]: Confirm tap handler, or `null` while disabled (no
  ///   selection yet).
  ///
  /// Return value:
  /// - A new [_EndpointMultiSelectBar].
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Confirm is disabled (greyed) when [onConfirm] is `null`.
  ///
  /// Invariants:
  /// - Does not own selection state.
  const _EndpointMultiSelectBar({
    required this.selectedCount,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Text(
              '$selectedCount selected',
              style: TextStyle(
                fontSize: _kPickerFontMd,
                color: colors.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            TextButton(
              key: const Key('connection-picker-multiselect-cancel'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('connection-picker-multiselect-confirm'),
              onPressed: onConfirm,
              child: Text('Confirm ($selectedCount)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim top band for navigation, focus context, search, and dismiss.
class _ConnectionPickerTopBand extends StatelessWidget {
  final List<String> breadcrumbSegments;
  final String focusContext;
  final bool isSearchMode;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool canGoBack;
  final bool showDismiss;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final ValueChanged<int> onBreadcrumbSegmentTap;
  final VoidCallback onSearchClear;
  final VoidCallback? onDismiss;

  /// Create the connection-picker top band.
  ///
  /// Parameters:
  /// - [breadcrumbSegments]: Clickable path segments starting with `Home`.
  /// - [focusContext]: Focused endpoint guide line.
  /// - [isSearchMode]: Whether the search field is active.
  /// - [searchController]: Controller for the search text field.
  /// - [searchFocusNode]: Focus node for the search text field.
  /// - [canGoBack]: Whether Back should appear enabled.
  /// - [showDismiss]: Whether to show the dismiss control.
  /// - [onBack]: Back tap handler.
  /// - [onSearch]: Enter-search handler.
  /// - [onBreadcrumbSegmentTap]: Segment index jump handler.
  /// - [onSearchClear]: Clear/exit search handler.
  /// - [onDismiss]: Optional dialog dismiss handler.
  ///
  /// Return value:
  /// - A new [_ConnectionPickerTopBand].
  ///
  /// Requirements/Preconditions:
  /// - Touch targets should remain >= 48 logical pixels.
  ///
  /// Guarantees/Postconditions:
  /// - Search and dismiss keys are stable for widget tests.
  ///
  /// Invariants:
  /// - Does not own navigation model state.
  const _ConnectionPickerTopBand({
    required this.breadcrumbSegments,
    required this.focusContext,
    required this.isSearchMode,
    required this.searchController,
    required this.searchFocusNode,
    required this.canGoBack,
    required this.showDismiss,
    required this.onBack,
    required this.onSearch,
    required this.onBreadcrumbSegmentTap,
    required this.onSearchClear,
    this.onDismiss,
  });

  /// Build one clickable breadcrumb row.
  ///
  /// Parameters:
  /// - [colors]: Active color scheme.
  ///
  /// Return value:
  /// - Horizontally scrollable segment buttons separated by `>`.
  ///
  /// Requirements/Preconditions:
  /// - [breadcrumbSegments] is non-empty.
  ///
  /// Guarantees/Postconditions:
  /// - Each segment has key `connection-picker-breadcrumb-<label>`.
  ///
  /// Invariants:
  /// - Does not mutate [breadcrumbSegments].
  Widget _buildBreadcrumb(ColorScheme colors) {
    final List<Widget> children = <Widget>[];
    for (int index = 0; index < breadcrumbSegments.length; index++) {
      final String label = breadcrumbSegments[index];
      if (index > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '>',
              style: TextStyle(
                fontSize: _kPickerFontLg,
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      children.add(
        TextButton(
          key: Key('connection-picker-breadcrumb-$label'),
          onPressed: () {
            onBreadcrumbSegmentTap(index);
          },
          style: TextButton.styleFrom(
            minimumSize: const Size(_kPickerTap, _kPickerTap),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            textStyle: const TextStyle(
              fontSize: _kPickerFontLg,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(label),
        ),
      );
    }
    return SingleChildScrollView(
      key: const Key('connection-picker-breadcrumb'),
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: isSearchMode
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: _kPickerTap,
                        height: _kPickerTap,
                        child: IconButton(
                          key: const Key('connection-picker-back'),
                          onPressed: onBack,
                          icon: Icon(
                            Icons.arrow_back,
                            size: _kPickerIconSm,
                            color: canGoBack
                                ? colors.onSurface
                                : colors.onSurface.withOpacity(0.35),
                          ),
                          tooltip: 'Back',
                        ),
                      ),
                      Expanded(
                        child: SystemKeyboardTextField(
                          key: const Key('connection-picker-search-field'),
                          textController: searchController,
                          focusNode: searchFocusNode,
                          hintText: 'Search endpoints',
                          style: const TextStyle(fontSize: _kPickerFontLg),
                          decoration: const InputDecoration(
                            hintText: 'Search endpoints',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          onSubmitted: onSearchClear,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: _kPickerTap,
                        child: TextButton(
                          key: const Key('connection-picker-search-clear'),
                          onPressed: onSearchClear,
                          child: const Text(
                            'Clear',
                            style: TextStyle(fontSize: _kPickerFontMd),
                          ),
                        ),
                      ),
                      if (showDismiss)
                        SizedBox(
                          width: _kPickerTap,
                          height: _kPickerTap,
                          child: IconButton(
                            key: const Key('connection-picker-dismiss'),
                            onPressed: onDismiss,
                            icon: const Icon(Icons.close, size: _kPickerIconSm),
                            tooltip: 'Close',
                          ),
                        ),
                    ],
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  SizedBox(
                    width: _kPickerTap,
                    height: _kPickerTap,
                    child: IconButton(
                      key: const Key('connection-picker-back'),
                      onPressed: onBack,
                      icon: Icon(
                        Icons.arrow_back,
                        size: _kPickerIconSm,
                        color: canGoBack
                            ? colors.onSurface
                            : colors.onSurface.withOpacity(0.35),
                      ),
                      tooltip: 'Back',
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _buildBreadcrumb(colors),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      focusContext,
                      key: const Key('connection-picker-focus-context'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _kPickerFontMd,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kPickerTap,
                    height: _kPickerTap,
                    child: IconButton(
                      key: const Key('connection-picker-search'),
                      onPressed: onSearch,
                      icon: const Icon(Icons.search, size: _kPickerIconSm),
                      tooltip: 'Search',
                    ),
                  ),
                  if (showDismiss)
                    SizedBox(
                      width: _kPickerTap,
                      height: _kPickerTap,
                      child: IconButton(
                        key: const Key('connection-picker-dismiss'),
                        onPressed: onDismiss,
                        icon: const Icon(Icons.close, size: _kPickerIconSm),
                        tooltip: 'Close',
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Horizontal free-scrolling card rail with peek-sized cards.
class _ConnectionPickerRail extends StatelessWidget {
  final List<ConnectionNavCard> cards;
  final bool isMutating;
  final bool showSearchBreadcrumb;
  final ConnectionPickerLeafChrome Function(ConnectionNavLeafCard leaf)
      chromeFor;
  final bool Function(ConnectionNavLeafCard leaf) isSelected;
  final ValueChanged<ConnectionNavFolderCard> onFolderTap;
  final ValueChanged<ConnectionNavLeafCard> onLeafTap;

  /// Create the horizontal connection card rail.
  ///
  /// Parameters:
  /// - [cards]: Folder and/or leaf cards to display.
  /// - [isMutating]: Disables taps while connect/disconnect is in flight.
  /// - [showSearchBreadcrumb]: When true, leaf cards show path breadcrumbs.
  /// - [chromeFor]: Resolves the chrome token for one leaf card.
  /// - [isSelected]: Whether one leaf is in the endpoint-mode multi-select set.
  /// - [onFolderTap]: Invoked when a folder card is tapped.
  /// - [onLeafTap]: Invoked when a leaf card is tapped.
  ///
  /// Return value:
  /// - A new [_ConnectionPickerRail].
  ///
  /// Requirements/Preconditions:
  /// - [cards] should be non-empty for a non-empty rail.
  ///
  /// Guarantees/Postconditions:
  /// - Card width is derived from constraints so overflow peeks a partial card.
  ///
  /// Invariants:
  /// - Does not own connection mutation logic.
  const _ConnectionPickerRail({
    required this.cards,
    required this.isMutating,
    required this.showSearchBreadcrumb,
    required this.chromeFor,
    required this.isSelected,
    required this.onFolderTap,
    required this.onLeafTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // ~2.5 cards visible → fractional last card peeks when overflowing.
        const double gap = 12;
        const double horizontalPadding = 16;
        final double available = constraints.maxWidth - (horizontalPadding * 2);
        final double cardWidth =
            (available - (gap * 2)) / kConnectionPickerVisibleCardSpan;
        final double availableHeight = constraints.maxHeight.isFinite
            ? math.max(0.0, constraints.maxHeight - 24)
            : 220.0;
        final double cardHeight = availableHeight.clamp(1.0, 320.0);

        return ListView.separated(
          key: const Key('connection-picker-rail'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 12,
          ),
          itemCount: cards.length,
          separatorBuilder: (BuildContext context, int index) {
            return const SizedBox(width: gap);
          },
          itemBuilder: (BuildContext context, int index) {
            final ConnectionNavCard card = cards[index];
            if (card is ConnectionNavFolderCard) {
              return SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _ConnectionFolderCard(
                  key: Key('connection-folder-${card.title}'),
                  card: card,
                  onTap: isMutating
                      ? null
                      : () {
                          onFolderTap(card);
                        },
                ),
              );
            }
            final ConnectionNavLeafCard leaf = card as ConnectionNavLeafCard;
            return SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _ConnectionLeafCard(
                key: Key('connection-leaf-${leaf.title}'),
                card: leaf,
                showBreadcrumb: showSearchBreadcrumb,
                chrome: chromeFor(leaf),
                selected: isSelected(leaf),
                onTap: isMutating
                    ? null
                    : () {
                        onLeafTap(leaf);
                      },
              ),
            );
          },
        );
      },
    );
  }
}

/// Folder card for one navigation level.
class _ConnectionFolderCard extends StatelessWidget {
  final ConnectionNavFolderCard card;
  final VoidCallback? onTap;

  /// Create one folder navigation card.
  ///
  /// Parameters:
  /// - [card]: Folder metadata from the navigation model.
  /// - [onTap]: Whole-card tap handler, or `null` while disabled.
  ///
  /// Return value:
  /// - A new [_ConnectionFolderCard].
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Entire card is the tap target.
  ///
  /// Invariants:
  /// - Does not mutate [card].
  const _ConnectionFolderCard({
    super.key,
    required this.card,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant, width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: constraints.maxWidth,
                  maxWidth: constraints.maxWidth,
                  maxHeight: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.folder_outlined,
                        size: _kPickerIconLg,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        card.title,
                        style: const TextStyle(
                          fontSize: _kPickerFontXl,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${card.compatibleLeafCount} '
                        '${card.compatibleLeafCount == 1 ? 'source' : 'sources'}',
                        style: TextStyle(
                          fontSize: _kPickerFontMd,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (card.connectedLeafCount > 0) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          '${card.connectedLeafCount} connected',
                          style: TextStyle(
                            fontSize: _kPickerFontMd,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Leaf card for a single endpoint or same-path pair/group.
class _ConnectionLeafCard extends StatelessWidget {
  final ConnectionNavLeafCard card;
  final bool showBreadcrumb;
  final ConnectionPickerLeafChrome chrome;
  final bool selected;
  final VoidCallback? onTap;

  /// Create one leaf connection/endpoint card.
  ///
  /// Parameters:
  /// - [card]: Leaf metadata from the navigation model.
  /// - [showBreadcrumb]: Whether to show the folder breadcrumb (search mode).
  /// - [chrome]: Resolved chrome token (`unlit` / `lit` / `muted`) driving
  ///   the card's visual emphasis.
  /// - [selected]: Whether this leaf is checked in endpoint-mode multi-select.
  /// - [onTap]: Whole-card tap handler, or `null` while disabled.
  ///
  /// Return value:
  /// - A new [_ConnectionLeafCard].
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - `lit` (or `selected`) leaves use an emphasized filled style; `muted`
  ///   leaves use a distinct de-emphasized style; `unlit` uses the neutral
  ///   default style.
  /// - Title row shows direction icon + leaf name; bottom shows type icon.
  /// - Entire card is the tap target (pair toggles all members).
  ///
  /// Invariants:
  /// - Does not mutate [card].
  const _ConnectionLeafCard({
    super.key,
    required this.card,
    required this.showBreadcrumb,
    required this.chrome,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool emphasized =
        chrome == ConnectionPickerLeafChrome.lit || selected;
    final bool deEmphasized =
        !emphasized && chrome == ConnectionPickerLeafChrome.muted;
    final bool isPair = card.members.length > 1;
    final dp.EndpointSpec? primarySpec = _effectiveSpec(card.members.first);
    final dp.EndpointDirection direction =
        primarySpec?.direction ?? dp.EndpointDirection.output;
    final dp.EndpointCategory category =
        primarySpec?.category ?? dp.EndpointCategory.messageQueue;
    final String directionLabel = connectionPickerDirectionLabel(direction);
    final IconData typeIcon = connectionPickerTypeIcon(
      category,
      baseType: primarySpec?.dataType.baseType,
    );

    final Color fillColor = emphasized
        ? colors.primaryContainer
        : deEmphasized
            ? colors.surfaceContainerHighest
            : colors.surface;
    final Color contentColor = emphasized
        ? colors.onPrimaryContainer
        : deEmphasized
            ? colors.onSurfaceVariant.withOpacity(0.7)
            : colors.onSurface;
    final Color borderColor = emphasized
        ? colors.primary
        : deEmphasized
            ? colors.outline.withOpacity(0.4)
            : colors.outlineVariant;

    return Material(
      color: fillColor,
      elevation: emphasized ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor,
          width: emphasized ? 3 : 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double titleSize =
                  showBreadcrumb ? _kPickerSearchFontXl : _kPickerFontXl;
              final double bodySize =
                  showBreadcrumb ? _kPickerSearchFontMd : _kPickerFontMd;
              final double crumbSize =
                  showBreadcrumb ? _kPickerSearchFontSm : _kPickerFontSm;
              final int titleMaxLines = showBreadcrumb ? 4 : 8;
              return ClipRect(
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            directionLabel,
                            style: TextStyle(
                              fontSize: bodySize,
                              fontWeight: FontWeight.w400,
                              color: contentColor.withOpacity(0.75),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            typeIcon,
                            size: _kPickerIconSm,
                            color: contentColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: constraints.maxWidth,
                            maxWidth: constraints.maxWidth,
                            minHeight: 0,
                            maxHeight: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  card.title,
                                  style: TextStyle(
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w700,
                                    color: contentColor,
                                  ),
                                  maxLines: titleMaxLines,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (isPair)
                                  Text(
                                    'Pair · ${card.members.length} endpoints',
                                    style: TextStyle(
                                      fontSize: bodySize,
                                      color: contentColor,
                                    ),
                                  ),
                                if (showBreadcrumb) ...<Widget>[
                                  const SizedBox(height: 6),
                                  Text(
                                    card.breadcrumb,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: crumbSize,
                                      color: contentColor,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
