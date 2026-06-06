import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dogpaw/dogpaw.dart';

const String _launchMetadataFlag = '--dogpaw-launch-metadata';

/// Resolves the runtime entity name that this launched process should claim.
///
/// Purpose:
/// Mirrors the real Dog Paw launch contract where Epiphany exports the assigned
/// runtime entity name through `DOGPAW_ENTITY_NAME`, allowing a launched stub to
/// connect under the exact name Epiphany expects for lifecycle and routing.
///
/// Parameters: none.
///
/// Return value:
/// - Runtime entity name from `DOGPAW_ENTITY_NAME` when present.
/// - `launch_test_stub` as a fallback for direct/manual runs.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Returns a non-empty entity name.
///
/// Invariants:
/// - Does not modify process environment state.
String resolveRuntimeEntityName() {
  final String? configuredEntityName = Platform.environment['DOGPAW_ENTITY_NAME'];
  if (configuredEntityName != null && configuredEntityName.isNotEmpty) {
    return configuredEntityName;
  }
  return 'launch_test_stub';
}

/// Reads optional launch metadata passed through Epiphany command-line args.
///
/// Purpose:
/// Mirrors the current native launch-test stub behavior so lifecycle tests can
/// verify that launch metadata survives the full Epiphany app-start path.
///
/// Parameters:
/// - [args]: Process argument list passed to `main()`.
///
/// Return value:
/// - Parsed metadata object when the launch flag is present and readable.
/// - Empty map when the flag is absent or unreadable.
///
/// Requirements/Preconditions:
/// - [args] must be the live argument list for this process.
///
/// Guarantees/Postconditions:
/// - Does not throw for missing metadata or parse failures.
///
/// Invariants:
/// - Missing metadata is treated as an empty object instead of a fatal error.
Future<Map<String, dynamic>> readLaunchMetadataFromArgs(List<String> args) async {
  for (int i = 0; i + 1 < args.length; i += 1) {
    if (args[i] != _launchMetadataFlag) {
      continue;
    }

    final File metadataFile = File(args[i + 1]);
    if (!metadataFile.existsSync()) {
      stderr.writeln(
        'launch_test_stub: metadata file not found: ${metadataFile.path}',
      );
      return <String, dynamic>{};
    }

    try {
      final Object? decoded =
          jsonDecode(await metadataFile.readAsString()) as Object?;
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        );
      }
    } catch (error) {
      stderr.writeln('launch_test_stub: failed to parse metadata: $error');
      return <String, dynamic>{};
    }
  }

  return <String, dynamic>{};
}

/// Registers the command handler used by launch and routing integration tests.
///
/// Purpose:
/// Exposes launch metadata inspection and acknowledges routed commands so the
/// stub behaves like a real launched process from Epiphany's point of view.
///
/// Parameters:
/// - [entity]: Connected Dog Paw entity owned by this process.
/// - [launchMetadata]: Metadata captured from startup arguments.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - [entity] must already be connected and able to send command responses.
///
/// Guarantees/Postconditions:
/// - `get_launch_metadata` returns the captured metadata.
/// - All other commands receive a success response for routing/lifecycle tests.
///
/// Invariants:
/// - Does not mutate the stored metadata object after registration.
void registerCommandHandler(
  DogPawEntity entity,
  Map<String, dynamic> launchMetadata,
) {
  entity.setCommandCallback((
    String senderEntity,
    String command,
    Map<String, dynamic> params,
    String requestId,
  ) {
    if (command == 'get_launch_metadata') {
      entity.sendCommandResponse(
        senderEntity,
        requestId,
        success: true,
        result: <String, Object?>{'launchMetadata': launchMetadata},
      );
      return;
    }

    entity.sendCommandResponse(
      senderEntity,
      requestId,
      success: true,
      result: <String, Object?>{
        'handledCommand': command,
        'params': params,
      },
    );
  });
}

/// Wires process signals and connection polling into one shutdown future.
///
/// Purpose:
/// Keeps the stub alive long enough for Epiphany lifecycle tests while still
/// exiting promptly when the app is stopped or disconnected.
///
/// Parameters:
/// - [entity]: Connected Dog Paw entity owned by this process.
///
/// Return value:
/// - Future that completes when the stub should shut down.
///
/// Requirements/Preconditions:
/// - [entity] must already be connected.
///
/// Guarantees/Postconditions:
/// - Completes when SIGTERM/SIGINT arrives or when the Dog Paw connection ends.
///
/// Invariants:
/// - The returned future completes at most once.
Future<void> waitForShutdown(DogPawEntity entity) async {
  final Completer<void> shutdownCompleter = Completer<void>();
  late final StreamSubscription<ProcessSignal> sigtermSubscription;
  late final StreamSubscription<ProcessSignal> sigintSubscription;
  late final Timer connectionWatchdog;

  void completeShutdown() {
    if (!shutdownCompleter.isCompleted) {
      shutdownCompleter.complete();
    }
  }

  sigtermSubscription = ProcessSignal.sigterm.watch().listen((_) {
    completeShutdown();
  });
  sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
    completeShutdown();
  });
  connectionWatchdog = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (!entity.isConnected()) {
      completeShutdown();
    }
  });

  await shutdownCompleter.future;
  connectionWatchdog.cancel();
  await sigtermSubscription.cancel();
  await sigintSubscription.cancel();
}

/// Launch-test stub entrypoint used by `dogpaw_test` staged-install scenarios.
///
/// Purpose:
/// Acts as a tiny real executable that Epiphany can launch for lifecycle,
/// metadata, and routing tests without depending on internal native fixtures.
///
/// Parameters:
/// - [args]: Process arguments from Epiphany.
///
/// Return value:
/// - Process exit code `0` on clean shutdown.
/// - Process exit code `1` when the Dog Paw connection fails.
///
/// Requirements/Preconditions:
/// - Epiphany must provide the runtime environment needed by `DogPawEntity`.
///
/// Guarantees/Postconditions:
/// - Connects to Epiphany, sends ready, serves command responses, and disconnects
///   before exiting.
///
/// Invariants:
/// - Uses the public `package:dogpaw` API surface rather than internal test-only
///   native fixtures.
Future<void> main(List<String> args) async {
  final Map<String, dynamic> launchMetadata =
      await readLaunchMetadataFromArgs(args);
  final String runtimeEntityName = resolveRuntimeEntityName();
  final DogPawEntity entity = DogPawEntity(runtimeEntityName);
  entity.setErrorCallback((String error) {
    stderr.writeln('$runtimeEntityName: $error');
  });

  final ConnectionResult connectResult = await entity.connect();
  if (!connectResult.success) {
    stderr.writeln('$runtimeEntityName: connect failed: ${connectResult.error}');
    exitCode = 1;
    return;
  }

  registerCommandHandler(entity, launchMetadata);
  await connectResult.handle!.complete();
  await waitForShutdown(entity);
  entity.disconnect();
}
