import 'package:flutter/material.dart';

import 'app.dart';
import 'services/emulator_bridge_client.dart';

/// Start the Dog Paw emulator control GUI.
///
/// Purpose: creates the desktop developer tool that talks to the local emulator
/// bridge service.
/// Parameters: [args] may include `--bridge-url=<url>`; valid values are HTTP
/// origins such as `http://127.0.0.1:8765`.
/// Return value: none.
/// Requirements: the Python bridge should be started separately for live data.
/// Guarantees: defaults to `http://127.0.0.1:8765` when no URL is supplied.
/// Invariants: this GUI is not registered as a Dog Paw app.
void main(List<String> args) {
  final bridgeUrl = _bridgeUrlFromArgs(args);
  runApp(
    EmulatorControlRoot(
      client: EmulatorBridgeClient(baseUri: Uri.parse(bridgeUrl)),
    ),
  );
}

/// Resolve the bridge URL from command-line arguments.
///
/// Purpose: lets developers point the GUI at a non-default bridge port without
/// recompiling.
/// Parameters: [args] is the process argument list from [main].
/// Return value: bridge URL string.
/// Requirements: URL arguments must use the `--bridge-url=value` form.
/// Guarantees: returns the localhost default when the argument is absent.
/// Invariants: does not validate network reachability.
String _bridgeUrlFromArgs(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--bridge-url=')) {
      return arg.substring('--bridge-url='.length);
    }
  }
  return 'http://127.0.0.1:8765';
}
