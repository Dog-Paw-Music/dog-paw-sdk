import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Runs the subprocess probe for one logger scenario.
///
/// Purpose:
/// Executes `AppLogger` in a fresh Dart process so tests can observe real stdout
/// behavior and compile-time product-mode branching.
///
/// Parameters:
/// - [scenario]: Probe scenario name understood by `app_logger_probe.dart`.
/// - [dartDefines]: Optional compile-time `-D` definitions passed to Dart.
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
Future<ProcessResult> runAppLoggerProbe(
  String scenario, {
  List<String> dartDefines = const <String>[],
}) {
  final String packageRoot = Directory.current.path;
  final String packageConfigPath =
      path.join(packageRoot, '.dart_tool', 'package_config.json');
  final String probePath = path.join(
    packageRoot,
    'test',
    'test_fixtures',
    'app_logger_probe.dart',
  );

  return Process.run(
    'dart',
    <String>[
      ...dartDefines,
      '--packages=$packageConfigPath',
      probePath,
      scenario,
    ],
  );
}

void main() {
  group('AppLogger subprocess contract', () {
    test('prints immediate info output in debug mode', () async {
      final ProcessResult result = await runAppLoggerProbe('immediate');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        contains('INFO: [Probe] immediate-message'),
      );
    });

    test('flushes buffered messages when requested', () async {
      final ProcessResult result = await runAppLoggerProbe('buffer_flush');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        contains('INFO: === BUFFERED SECTION START: ProbeSection ==='),
      );
      expect(
        result.stdout,
        contains('INFO: [Probe] buffered-message'),
      );
    });

    test('discards buffered messages when flush is false', () async {
      final ProcessResult result = await runAppLoggerProbe('buffer_discard');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        contains('INFO: === BUFFERED SECTION START: ProbeSection ==='),
      );
      expect(result.stdout, isNot(contains('discarded-message')));
    });

    test('prints error details in debug mode', () async {
      final ProcessResult result = await runAppLoggerProbe('error');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('ERROR: error-message'));
      expect(result.stdout, contains('Error details: detail-message'));
    });

    test('detects debug builds by writing fast info to stdout', () async {
      final ProcessResult result =
          await runAppLoggerProbe('mode_sensitive_info_fast');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        contains('INFO: [Probe] mode-sensitive-message'),
      );
    });

    test('detects product builds by suppressing fast info stdout', () async {
      final ProcessResult result = await runAppLoggerProbe(
        'mode_sensitive_info_fast',
        dartDefines: const <String>['-Ddart.vm.product=true'],
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, isEmpty);
      expect(result.stderr, isEmpty);
    });
  });
}
