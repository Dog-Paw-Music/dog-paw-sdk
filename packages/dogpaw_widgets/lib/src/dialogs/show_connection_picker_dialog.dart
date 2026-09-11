import 'dart:math' as math;

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../editors/connection_picker.dart';
import '../inputs/compositor_keyboard_control.dart';
import '../models/connection_picker_types.dart';

/// Fraction of screen height used by the connection picker dialog panel.
const double kConnectionPickerDialogHeightFactor = 2 / 3;

/// Show the reusable connection / endpoint picker in a modal dialog.
///
/// Parameters:
/// - [context]: Build context used to present the dialog.
/// - [entity]: Dog Paw entity client used for routing operations.
/// - [mode]: Connection mutation mode (default) vs endpoint selection mode.
/// - [focusedEndpoint]: Endpoint whose connections are being edited; required
///   in connection mode.
/// - [directionFilter]: Endpoint-mode direction filter.
/// - [multiSelect]: Endpoint-mode multi-select flag.
/// - [onRefresh]: Optional host callback requested after connection work.
/// - [leafChrome]: Optional host-driven per-leaf chrome resolver.
///
/// Return value:
/// - A future that resolves to the sealed [ConnectionPickerResult] once the
///   dialog closes: [ConnectionPickerMutated] when connection-mode mutations
///   occurred before close, [ConnectionPickerEndpointsSelected] when endpoint
///   mode reported a selection, or [ConnectionPickerDismissed] otherwise.
///
/// Requirements/Preconditions:
/// - [context] must be able to present a dialog.
/// - [focusedEndpoint] must be non-null when [mode] is
///   [ConnectionPickerMode.connection].
///
/// Guarantees/Postconditions:
/// - Dialog panel height is about [kConnectionPickerDialogHeightFactor] of the
///   screen; wvkbd overlays the bottom of the display when search is focused.
/// - The dialog is not barrier-dismissible: closing always goes through the
///   explicit dismiss control (or an endpoint-mode selection/cancel), so the
///   returned result always reflects what happened during the session.
///
/// Invariants:
/// - The helper does not expose raw JACK port names in its public API.
Future<ConnectionPickerResult> showConnectionPickerDialog({
  required BuildContext context,
  required dp.DogPawEntity entity,
  ConnectionPickerMode mode = ConnectionPickerMode.connection,
  dp.EndpointInfo? focusedEndpoint,
  EndpointDirectionFilter directionFilter = EndpointDirectionFilter.both,
  bool multiSelect = false,
  Future<void> Function()? onRefresh,
  ConnectionPickerLeafChromeResolver? leafChrome,
}) async {
  final ConnectionPickerResult? result =
      await showDialog<ConnectionPickerResult>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return _ConnectionPickerDialogHost(
        entity: entity,
        mode: mode,
        focusedEndpoint: focusedEndpoint,
        directionFilter: directionFilter,
        multiSelect: multiSelect,
        onRefresh: onRefresh,
        leafChrome: leafChrome,
      );
    },
  );
  return result ?? const ConnectionPickerDismissed();
}

/// Dialog host that top-aligns the picker panel above the compositor keyboard.
class _ConnectionPickerDialogHost extends StatefulWidget {
  final dp.DogPawEntity entity;
  final ConnectionPickerMode mode;
  final dp.EndpointInfo? focusedEndpoint;
  final EndpointDirectionFilter directionFilter;
  final bool multiSelect;
  final Future<void> Function()? onRefresh;
  final ConnectionPickerLeafChromeResolver? leafChrome;

  /// Create the connection-picker dialog host.
  const _ConnectionPickerDialogHost({
    required this.entity,
    required this.mode,
    this.focusedEndpoint,
    required this.directionFilter,
    required this.multiSelect,
    this.onRefresh,
    this.leafChrome,
  });

  @override
  State<_ConnectionPickerDialogHost> createState() =>
      _ConnectionPickerDialogHostState();
}

class _ConnectionPickerDialogHostState
    extends State<_ConnectionPickerDialogHost> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  /// Every mutation recorded during this dialog session, in order.
  final List<ConnectionRuleMutation> _sessionMutations =
      <ConnectionRuleMutation>[];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _searchFocusNode.unfocus();
    resolveCompositorKeyboardControl().hide();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Record one connection-mode mutation batch for this dialog session.
  void _recordMutations(List<ConnectionRuleMutation> mutations) {
    _sessionMutations.addAll(mutations);
  }

  /// Close the dialog, reporting accumulated mutations (or dismissal).
  void _handleDismiss() {
    _searchFocusNode.unfocus();
    resolveCompositorKeyboardControl().hide();
    final ConnectionPickerResult result = _sessionMutations.isEmpty
        ? const ConnectionPickerDismissed()
        : ConnectionPickerMutated(
            mutations: List<ConnectionRuleMutation>.from(_sessionMutations),
          );
    Navigator.of(context).pop(result);
  }

  /// Close the dialog reporting an endpoint-mode selection.
  void _handleEndpointsSelected(List<EndpointLeafSelection> leaves) {
    _searchFocusNode.unfocus();
    resolveCompositorKeyboardControl().hide();
    Navigator.of(context)
        .pop(ConnectionPickerEndpointsSelected(leaves: leaves));
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final double panelHeight = math.max(
      280.0,
      screenSize.height * kConnectionPickerDialogHeightFactor,
    );
    final double panelWidth = math.max(
      320,
      math.min(screenSize.width - 48, 960),
    );

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: const Key('connection-picker-dialog-panel'),
              width: panelWidth,
              height: panelHeight,
              child: Material(
                color: Theme.of(context).dialogBackgroundColor,
                elevation: 24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConnectionPicker(
                    entity: widget.entity,
                    mode: widget.mode,
                    focusedEndpoint: widget.focusedEndpoint,
                    directionFilter: widget.directionFilter,
                    multiSelect: widget.multiSelect,
                    onRefresh: widget.onRefresh,
                    leafChrome: widget.leafChrome,
                    onMutated: _recordMutations,
                    onEndpointsSelected: _handleEndpointsSelected,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    onDismiss: _handleDismiss,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
