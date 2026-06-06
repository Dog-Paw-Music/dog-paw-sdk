import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import 'dialog_shell.dart';
import '../editors/connection_picker.dart';

/// Show the reusable focused-endpoint connection picker in a modal dialog.
///
/// Parameters:
/// - `context`: Build context used to present the dialog.
/// - `entity`: Dog Paw entity client used for routing operations.
/// - `focusedEndpoint`: Endpoint whose connections are being edited.
/// - `onRefresh`: Optional host callback requested after connection work.
///
/// Return value:
/// - A future that completes when the dialog is dismissed.
///
/// Requirements/Preconditions:
/// - `context` must be able to present a dialog.
///
/// Guarantees/Postconditions:
/// - The dialog delegates rendering to `ConnectionPicker`.
///
/// Invariants:
/// - The helper does not expose raw JACK port names in its public API.
Future<void> showConnectionPickerDialog({
  required BuildContext context,
  required dp.DogPawEntity entity,
  required dp.EndpointInfo focusedEndpoint,
  Future<void> Function()? onRefresh,
}) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return buildEditorDialogShell(
        context: dialogContext,
        child: ConnectionPicker(
          entity: entity,
          focusedEndpoint: focusedEndpoint,
          onRefresh: onRefresh,
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Done'),
          ),
        ],
      );
    },
  );
}
