import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../editors/theme_editor.dart';
import '../models/editor_preview.dart';

/// Show the reusable theme editor in a modal dialog.
///
/// Parameters:
/// - `context`: Build context used to present the dialog.
/// - `initialValue`: Starting theme value shown to the user.
/// - `previewController`: Optional host-owned live preview integration.
///
/// Return value:
/// - A future resolving to the final theme value when confirmed, or `null` when
///   dismissed.
///
/// Requirements/Preconditions:
/// - `context` must be able to present a dialog.
///
/// Guarantees/Postconditions:
/// - The dialog delegates editing to `ThemeEditor`.
///
/// Invariants:
/// - The helper does not persist changes on its own.
Future<dp.ThemeData?> showThemeEditorDialog({
  required BuildContext context,
  required dp.ThemeData initialValue,
  EditorPreviewController<dp.ThemeData>? previewController,
}) async {
  dp.ThemeData currentValue = initialValue;

  return showDialog<dp.ThemeData>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (
          BuildContext statefulContext,
          void Function(void Function()) setDialogState,
        ) {
          final Size screenSize = MediaQuery.sizeOf(statefulContext);
          final double dialogWidth = (screenSize.width - 48).clamp(320.0, 860.0);
          final double maxDialogHeight =
              (screenSize.height - 48).clamp(360.0, 760.0);

          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dialogWidth,
                maxHeight: maxDialogHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Flexible(
                      child: ThemeEditor(
                        value: currentValue,
                        onChanged: (dp.ThemeData nextValue) {
                          setDialogState(() {
                            currentValue = nextValue;
                          });
                        },
                        previewController: previewController,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TextButton(
                          onPressed: () async {
                            if (previewController != null) {
                              await previewController.clear();
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () async {
                            if (previewController != null) {
                              await previewController.clear();
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(currentValue);
                            }
                          },
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
