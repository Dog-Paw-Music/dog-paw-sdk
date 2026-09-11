import 'dart:io';

import 'package:flutter/foundation.dart';

/// Controls visibility of a session-level compositor on-screen keyboard.
///
/// Purpose:
/// Bridge Dog Paw text fields to wvkbd (or compatible OSKs) that expose
/// show/hide via Unix signals when `--auto` is unavailable.
///
/// Architecture:
/// Shared helper for [SystemKeyboardTextField]. Production Pi sessions run
/// `wvkbd-mobintl --hidden` and rely on focus handlers here to show it.
abstract class CompositorKeyboardControl {
  /// Purpose:
  /// Show the compositor on-screen keyboard if it is running.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Future that completes after the show signal is sent.
  ///
  /// Requirements/Preconditions:
  /// - A compatible keyboard daemon should be running in the Sway session.
  ///
  /// Guarantees/Postconditions:
  /// - Safe to call repeatedly while the keyboard is already visible.
  ///
  /// Invariants:
  /// - Does not start the keyboard process when none is running.
  Future<void> show();

  /// Purpose:
  /// Hide the compositor on-screen keyboard if it is running.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Future that completes after the hide signal is sent.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Safe to call when the keyboard is already hidden or not running.
  ///
  /// Invariants:
  /// - Does not stop the keyboard process.
  Future<void> hide();
}

/// Production [CompositorKeyboardControl] that signals wvkbd over `pkill`.
///
/// Purpose:
/// Send wvkbd visibility signals (`SIGUSR2` show, `SIGUSR1` hide) to common
/// binary names installed by the distro package.
///
/// Architecture:
/// Default backend for Pi Linux targets used by [SystemKeyboardTextField].
class WvkbdCompositorKeyboardControl implements CompositorKeyboardControl {
  /// Shared production control instance.
  static final WvkbdCompositorKeyboardControl instance =
      WvkbdCompositorKeyboardControl();

  /// Process names tried when sending a visibility signal.
  static const List<String> processNames = <String>[
    'wvkbd-mobintl',
    'wvkbd-deskintl',
  ];

  @override
  Future<void> show() {
    return _sendSignal('SIGUSR2');
  }

  @override
  Future<void> hide() {
    return _sendSignal('SIGUSR1');
  }

  /// Purpose:
  /// Send one visibility signal to every known wvkbd process name.
  ///
  /// Parameters:
  /// - `signalName`: Unix signal name accepted by `pkill`, e.g. `SIGUSR2`.
  ///
  /// Return value:
  /// - Future that completes after signals are sent.
  ///
  /// Requirements/Preconditions:
  /// - [signalName] must be a signal name supported by `pkill`.
  ///
  /// Guarantees/Postconditions:
  /// - Ignores missing-process exit codes from `pkill`.
  ///
  /// Invariants:
  /// - Does not throw when no keyboard process is running.
  Future<void> _sendSignal(String signalName) async {
    if (kIsWeb || !Platform.isLinux) {
      return;
    }
    for (final String processName in processNames) {
      try {
        await Process.run('pkill', <String>['-$signalName', processName]);
      } on ProcessException {
        // No keyboard process running for this name.
      }
    }
  }
}

/// No-op [CompositorKeyboardControl] for widget tests and non-Linux hosts.
class NoOpCompositorKeyboardControl implements CompositorKeyboardControl {
  /// Create one no-op compositor keyboard control.
  const NoOpCompositorKeyboardControl();

  @override
  Future<void> show() async {}

  @override
  Future<void> hide() async {}
}

/// Purpose:
/// Resolve the compositor keyboard backend for production vs widget tests.
///
/// Parameters:
/// - `override`: Optional caller-provided backend.
///
/// Return value:
/// - [override] when provided, otherwise a test-safe or production backend.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Never launches host processes during widget tests.
///
/// Invariants:
/// - Does not mutate global keyboard state.
CompositorKeyboardControl resolveCompositorKeyboardControl([
  CompositorKeyboardControl? override,
]) {
  if (override != null) {
    return override;
  }
  if (kIsWeb || !Platform.isLinux) {
    return const NoOpCompositorKeyboardControl();
  }
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return const NoOpCompositorKeyboardControl();
  }
  return WvkbdCompositorKeyboardControl.instance;
}
