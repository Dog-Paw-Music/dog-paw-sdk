import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../editors/theme_editor.dart';
import '../models/editor_preview.dart';
import '../models/shared_override_editor_value.dart';

/// Show the reusable theme editor in a modal dialog.
///
/// Parameters:
/// - `context`: Build context used to present the dialog.
/// - `initialValue`: Starting theme value shown to the user.
/// - `previewController`: Optional host-owned live preview integration.
/// - `showSourceSelector`: Whether to show the shared/override selector.
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
Future<SharedOverrideEditorValue<dp.ThemeData>?> showThemeEditorDialog({
  required BuildContext context,
  required SharedOverrideEditorValue<dp.ThemeData> initialValue,
  EditorPreviewController<SharedOverrideEditorValue<dp.ThemeData>>?
      previewController,
  bool showSourceSelector = false,
}) async {
  final SharedOverrideEditorValue<dp.ThemeData> originalValue = initialValue;
  SharedOverrideEditorValue<dp.ThemeData> currentValue = initialValue;

  return showDialog<SharedOverrideEditorValue<dp.ThemeData>>(
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
                        onChanged:
                            (SharedOverrideEditorValue<dp.ThemeData> nextValue) {
                          setDialogState(() {
                            currentValue = nextValue;
                          });
                        },
                        previewController: previewController,
                        showSourceSelector: showSourceSelector,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TextButton(
                          onPressed: () async {
                            if (previewController != null) {
                              await previewController.preview(originalValue);
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
                              await previewController.preview(currentValue);
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
