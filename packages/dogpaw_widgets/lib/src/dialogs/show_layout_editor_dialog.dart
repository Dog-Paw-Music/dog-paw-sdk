import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../editors/layout_editor.dart';
import '../models/editor_preview.dart';

/// Show the reusable layout editor in a modal dialog.
///
/// Parameters:
/// - `context`: Build context used to present the dialog.
/// - `initialValue`: Starting layout draft shown to the user.
/// - `previewController`: Optional host-owned live preview integration.
/// - `availableTargets`: Host-provided target-picker choices.
/// - `targetVisibility`: Whether the target section is editable, read-only, or hidden.
/// - `themeVisibility`: Whether the theme section is editable, read-only, or hidden.
/// - `scaleVisibility`: Whether the scale section is editable, read-only, or hidden.
///
/// Return value:
/// - A future resolving to the final layout draft when confirmed, or `null` when
///   dismissed.
///
/// Requirements/Preconditions:
/// - `context` must be able to present a dialog.
///
/// Guarantees/Postconditions:
/// - The dialog delegates editing to `LayoutEditor`.
///
/// Invariants:
/// - The helper does not persist changes on its own.
Future<dp.LayoutDraft?> showLayoutEditorDialog({
  required BuildContext context,
  required dp.LayoutDraft initialValue,
  EditorPreviewController<dp.LayoutDraft>? previewController,
  List<LayoutEditorTargetOption> availableTargets =
      const <LayoutEditorTargetOption>[],
  LayoutEditorFieldVisibility targetVisibility =
      LayoutEditorFieldVisibility.editable,
  LayoutEditorFieldVisibility themeVisibility =
      LayoutEditorFieldVisibility.editable,
  LayoutEditorFieldVisibility scaleVisibility =
      LayoutEditorFieldVisibility.editable,
}) async {
  dp.LayoutDraft currentValue = initialValue;

  return showDialog<dp.LayoutDraft>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (
          BuildContext statefulContext,
          void Function(void Function()) setDialogState,
        ) {
          final Size screenSize = MediaQuery.sizeOf(statefulContext);
          final double dialogWidth = (screenSize.width - 48).clamp(360.0, 980.0);

          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              key: const Key('layout-editor-dialog-shell'),
              constraints: BoxConstraints(
                maxWidth: dialogWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LayoutEditor(
                      value: currentValue,
                      onChanged: (dp.LayoutDraft nextValue) {
                        setDialogState(() {
                          currentValue = nextValue;
                        });
                      },
                      previewController: previewController,
                      availableTargets: availableTargets,
                      targetVisibility: targetVisibility,
                      themeVisibility: themeVisibility,
                      scaleVisibility: scaleVisibility,
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
