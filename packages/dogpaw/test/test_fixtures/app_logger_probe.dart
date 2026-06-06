import 'package:dogpaw/src/app_logger.dart';

/// Runs one deterministic `AppLogger` scenario for subprocess-based tests.
///
/// Purpose:
/// Gives package unit tests a stable way to observe `AppLogger` output from a
/// fresh Dart process, including behavior that depends on compile-time product
/// mode defines.
///
/// Parameters:
/// - [args]: Single scenario selector. Supported values are `immediate`,
///   `buffer_flush`, `buffer_discard`, `error`, and `mode_sensitive_info_fast`.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - [args] contains exactly one supported scenario string.
///
/// Guarantees/Postconditions:
/// - Emits deterministic output for the selected scenario and exits with code 0.
///
/// Invariants:
/// - Uses the production `AppLogger` implementation without test-only hooks.
void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Expected exactly one scenario argument.');
  }

  AppLogger.initialize('Probe');

  switch (args.first) {
    case 'immediate':
      AppLogger.info('immediate-message', 'Probe');
      return;
    case 'buffer_flush':
      AppLogger.startOutputBuffer('ProbeSection');
      AppLogger.info('buffered-message', 'Probe');
      AppLogger.endOutputBuffer(true);
      return;
    case 'buffer_discard':
      AppLogger.startOutputBuffer('ProbeSection');
      AppLogger.info('discarded-message', 'Probe');
      AppLogger.endOutputBuffer(false);
      return;
    case 'error':
      AppLogger.error('error-message', 'detail-message');
      return;
    case 'mode_sensitive_info_fast':
      AppLogger.infoFast('mode-sensitive-message', 'Probe');
      return;
  }

  throw ArgumentError('Unknown scenario: ${args.first}');
}
