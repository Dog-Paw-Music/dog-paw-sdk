import 'package:flutter/material.dart';

/// Wraps a widget with `MaterialApp` and `Scaffold` for widget testing.
///
/// Purpose:
/// Provides the minimum common Flutter ancestors many Dog Paw widgets expect,
/// such as `Navigator`, `Theme`, and `MediaQuery`.
///
/// Parameters:
/// - [child]: Widget under test.
/// - [theme]: Optional theme override. When omitted, [defaultTestTheme] is
///   used.
///
/// Return value:
/// - A fully wrapped widget tree suitable for `tester.pumpWidget()`.
///
/// Requirements/Preconditions:
/// - [child] is a valid widget subtree.
///
/// Guarantees/Postconditions:
/// - The returned tree includes a `MaterialApp` root and a `Scaffold` body.
///
/// Invariants:
/// - Does not trigger dialogs or additional navigation by itself.
Widget wrapForTest(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? defaultTestTheme(),
    home: Scaffold(
      body: child,
    ),
  );
}

/// Wraps a widget so it appears as a dialog during widget tests.
///
/// Purpose:
/// Lets tests exercise dialog widgets through `showDialog()` rather than
/// embedding them directly in a page body.
///
/// Parameters:
/// - [dialog]: Dialog widget to present.
/// - [theme]: Optional theme override. When omitted, [defaultTestTheme] is
///   used.
///
/// Return value:
/// - A widget tree that schedules [dialog] to appear after the first frame.
///
/// Requirements/Preconditions:
/// - [dialog] is a valid dialog widget for `showDialog()`.
///
/// Guarantees/Postconditions:
/// - The returned tree shows [dialog] once the widget is pumped and settled.
///
/// Invariants:
/// - The dialog is non-dismissible so tests have deterministic control.
Widget wrapDialogForTest(Widget dialog, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? defaultTestTheme(),
    home: Builder(
      builder: (BuildContext context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => dialog,
          );
        });
        return const Scaffold(body: SizedBox.shrink());
      },
    ),
  );
}

/// Returns the default dark theme used by Dog Paw widget tests.
///
/// Purpose:
/// Gives widget tests a shared baseline theme close to the main Dog Paw visual
/// styling so colors and contrast-dependent widgets behave predictably.
///
/// Parameters: none.
///
/// Return value:
/// - A `ThemeData` configured for dark mode with Dog Paw accent colors.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - The returned theme is safe to reuse across tests.
///
/// Invariants:
/// - Always returns a dark theme.
ThemeData defaultTestTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF00E5FF),
      secondary: Color(0xFFFF00E5),
    ),
  );
}
