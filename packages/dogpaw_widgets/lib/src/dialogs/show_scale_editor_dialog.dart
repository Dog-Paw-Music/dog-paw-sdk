import 'dart:math' as math;

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../editors/scale_editor.dart';
import '../models/editor_preview.dart';

/// Show the reusable scale editor in a modal dialog.
///
/// Parameters:
/// - `context`: Build context used to present the dialog.
/// - `initialValue`: Starting scale value shown to the user.
/// - `previewController`: Optional host-owned live preview integration.
///
/// Return value:
/// - A future resolving to the final scale value when confirmed, or `null` when
///   dismissed.
///
/// Requirements/Preconditions:
/// - `context` must be able to present a dialog.
///
/// Guarantees/Postconditions:
/// - The dialog delegates editing to `ScaleEditor`.
///
/// Invariants:
/// - The helper does not persist changes on its own.
Future<dp.ScaleData?> showScaleEditorDialog({
  required BuildContext context,
  required dp.ScaleData initialValue,
  EditorPreviewController<dp.ScaleData>? previewController,
}) async {
  dp.ScaleData currentValue = initialValue;

  return showDialog<dp.ScaleData>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (
          BuildContext statefulContext,
          void Function(void Function()) setDialogState,
        ) {
          final Size screenSize = MediaQuery.sizeOf(statefulContext);
          final double dialogWidth = math.max(
            320,
            math.min(screenSize.width - 32, 1600),
          );
          final double dialogHeight = math.max(
            360,
            math.min(screenSize.height - 40, 780),
          );

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            child: SizedBox(
              key: const Key('scale-editor-dialog-shell'),
              width: dialogWidth,
              height: dialogHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: ScaleEditor(
                        value: currentValue,
                        onChanged: (dp.ScaleData nextValue) {
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
