import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Build one explicitly sized editor dialog shell.
///
/// Purpose:
/// Provides a shared dialog layout that avoids intrinsic-size measurement, so
/// editor content containing `LayoutBuilder` or scrolling regions can be hosted
/// safely and consistently across all reusable widget launchers.
///
/// Parameters:
/// - [context]: Build context used to read the current screen size.
/// - [child]: Main editor content placed in the expandable body region.
/// - [actions]: Optional trailing action row widgets shown below the content.
///   When null or empty, the bottom action row is omitted (e.g. connection
///   picker, which owns dismiss in its top band).
///
/// Return value:
/// - A `Dialog` widget with consistent padding and bounded size.
///
/// Requirements/Preconditions:
/// - [context] must have an active `MediaQuery`.
/// - When provided, [actions] should contain dialog-safe controls such as buttons.
///
/// Guarantees/Postconditions:
/// - The returned shell constrains the dialog to a practical size for both
///   embedded editors and smaller screens.
/// - [child] receives expandable vertical space inside the dialog body.
///
/// Invariants:
/// - The helper does not own editor state or perform navigation.
Widget buildEditorDialogShell({
  required BuildContext context,
  required Widget child,
  List<Widget>? actions,
}) {
  final Size screenSize = MediaQuery.sizeOf(context);
  final double dialogWidth = math.max(
    320,
    math.min(screenSize.width - 48, 960),
  );
  final double dialogHeight = math.max(
    360,
    math.min(screenSize.height - 48, 760),
  );
  final List<Widget> actionWidgets = actions ?? const <Widget>[];
  final bool showActions = actionWidgets.isNotEmpty;

  return Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: dialogWidth,
      height: dialogHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, showActions ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: child),
            if (showActions) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actionWidgets,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
