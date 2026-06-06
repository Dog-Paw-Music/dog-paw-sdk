import 'dart:io';
import 'dart:ffi';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Resolves the package-owned prebuilt native bridge artifact for this host.
///
/// Purpose:
/// Supplies subprocess tests with the exact bridge library path that Flutter app
/// bundles would consume, without changing the production runtime lookup
/// contract.
///
/// Parameters:
/// - None.
///
/// Return value:
/// - Absolute `String` path to the matching `libdogpaw_bridge.so` prebuilt.
///
/// Requirements/Preconditions:
/// - The repo-local `dogpaw_bridge` target has been built for the current host
///   architecture.
///
/// Guarantees/Postconditions:
/// - Throws [StateError] if the current host ABI is unsupported by the package
///   prebuilt layout or if the artifact is missing.
///
/// Invariants:
/// - Never mutates filesystem state.
String resolvePackagePrebuiltBridgePath() {
  final String packageRoot = Directory.current.path;
  final String subdir;
  switch (Abi.current()) {
    case Abi.linuxX64:
      subdir = 'linux-x64';
      break;
    case Abi.linuxArm64:
      subdir = 'linux-arm64';
      break;
    default:
      throw StateError('Unsupported ABI for test bridge probe: ${Abi.current()}');
  }

  final String bridgePath = path.join(
    packageRoot,
    'linux',
    'prebuilt',
    subdir,
    'libdogpaw_bridge.so',
  );
  if (!File(bridgePath).existsSync()) {
    throw StateError(
      'Missing prebuilt bridge artifact for probe test: $bridgePath',
    );
  }
  return bridgePath;
}

/// Runs the subprocess probe for one native-bridge logging scenario.
///
/// Purpose:
/// Executes `DogPawBridge` in a fresh Dart process so tests can observe the
/// bridge's real stdout/stderr behavior around expected startup polling and
/// shutdown timeout paths.
///
/// Parameters:
/// - [scenario]: Probe scenario name understood by `native_bridge_probe.dart`.
///
/// Return value:
/// - Future resolving to the completed child-process result.
///
/// Requirements/Preconditions:
/// - The package `.dart_tool/package_config.json` exists.
/// - [scenario] names a supported probe scenario.
///
/// Guarantees/Postconditions:
/// - Launches the probe with the current package's package-config file.
///
/// Invariants:
/// - Uses the current Dart executable reported by the running test process.
Future<ProcessResult> runNativeBridgeProbe(String scenario) {
  final String packageRoot = Directory.current.path;
  final String packageConfigPath =
      path.join(packageRoot, '.dart_tool', 'package_config.json');
  final String bridgeLibraryPath = resolvePackagePrebuiltBridgePath();
  final String probePath = path.join(
    packageRoot,
    'test',
    'test_fixtures',
    'native_bridge_probe.dart',
  );

  return Process.run(
    'dart',
    <String>[
      '--packages=$packageConfigPath',
      probePath,
      scenario,
    ],
    environment: <String, String>{
      ...Platform.environment,
      'DOGPAW_BRIDGE_LIB': bridgeLibraryPath,
    },
  );
}

void main() {
  group('DogPawBridge subprocess logging contract', () {
    test('missing port-file checks stay silent while returning not-running', () async {
      final ProcessResult result = await runNativeBridgeProbe(
        'missing_port_file_check',
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, isNot(contains('Failed to open port file')));
      expect(result.stderr, isEmpty);
    });

    test('wait-process timeout stays silent while returning timeout', () async {
      final ProcessResult result = await runNativeBridgeProbe(
        'wait_process_timeout',
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, isNot(contains('Timeout waiting for process')));
      expect(result.stderr, isEmpty);
    });
  });
}
