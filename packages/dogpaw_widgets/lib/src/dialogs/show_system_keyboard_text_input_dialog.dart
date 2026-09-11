import 'package:flutter/material.dart';

import '../inputs/system_keyboard_text_field.dart';

/// Default bottom inset for system-keyboard text dialogs on the Pi display.
const double kSystemKeyboardTextDialogBottomInset = 280;

/// Show a compositor-keyboard text-input dialog and return the confirmed string.
///
/// Purpose:
/// Prompt for a single line of text using [SystemKeyboardTextField], for flows
/// such as save-as naming on Pi targets with wvkbd running in the Sway session.
///
/// Parameters:
/// - `context`: Build context used to present the dialog.
/// - `title`: Dialog title text.
/// - `initialValue`: Optional starting text shown in the field.
/// - `hintText`: Optional placeholder when the field is empty.
/// - `autofocus`: Whether the field requests focus when the dialog opens.
///
/// Return value:
/// - Trimmed non-empty text when the user confirms with OK or Return.
/// - `null` when the user cancels or dismisses the dialog.
///
/// Requirements/Preconditions:
/// - `context` must be able to present a dialog.
/// - A compatible Wayland on-screen keyboard should be running on device.
///
/// Guarantees/Postconditions:
/// - Empty or whitespace-only OK/Return attempts leave the dialog open.
/// - The dialog does not persist data on its own.
///
/// Invariants:
/// - Does not render an embedded virtual keyboard.
Future<String?> showSystemKeyboardTextInputDialog({
  required BuildContext context,
  required String title,
  String? initialValue,
  String? hintText,
  bool autofocus = true,
}) async {
  final TextEditingController textController = TextEditingController(
    text: initialValue,
  );

  try {
    return await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 27)),
          content: SizedBox(
            width: 750,
            child: SingleChildScrollView(
              child: SystemKeyboardTextField(
                textController: textController,
                hintText: hintText,
                autofocus: autofocus,
                keyboardBottomInset: kSystemKeyboardTextDialogBottomInset,
                onSubmitted: () {
                  final String trimmed = textController.text.trim();
                  if (trimmed.isEmpty) {
                    return;
                  }
                  Navigator.of(dialogContext).pop(trimmed);
                },
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 21)),
            ),
            ElevatedButton(
              onPressed: () {
                final String trimmed = textController.text.trim();
                if (trimmed.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(trimmed);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
              ),
              child: const Text('OK', style: TextStyle(fontSize: 21)),
            ),
          ],
        );
      },
    );
  } finally {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      textController.dispose();
    });
  }
}
