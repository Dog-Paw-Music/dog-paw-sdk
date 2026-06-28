import 'dart:async';
import 'dart:io';

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:dogpaw/src/ffi/native_dogpaw_entity.dart';
import 'package:dogpaw_test/src/package_runtime_paths.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Purpose: Resolve the native bridge library used by child-process bridge
/// probes in the direct package integration suite.
///
/// Parameters: None.
///
/// Return value:
/// - Absolute `String` path to the selected `libdogpaw_bridge.so` artifact.
///
/// Requirements/Preconditions:
/// - The package fixture or source checkout must expose a bridge artifact for
///   the current host ABI.
///
/// Guarantees/Postconditions:
/// - Throws [StateError] when the current host ABI is unsupported or the
///   bridge artifact is missing.
///
/// Invariants:
/// - Does not modify filesystem state.
String _resolveFixtureBridgePath() {
  final String packageRoot = Directory.current.path;
  final String? bridgePath = resolveBridgeLibraryPathForFixture(
    environment: Platform.environment,
    dogpawPackageRootPath: packageRoot,
  );
  if (bridgePath == null || bridgePath.isEmpty) {
    throw StateError(
      'Missing bridge artifact for integration probe in package: $packageRoot',
    );
  }
  return bridgePath;
}

/// Purpose: Execute one native-bridge probe scenario in a child Dart process and
/// fail cleanly if it wedges past a fixed timeout.
///
/// Parameters:
/// - [scenario]: scenario name understood by `native_bridge_probe.dart`.
/// - [timeout]: maximum wall-clock time to wait for probe completion.
///
/// Return value:
/// - `Future<ProcessResult>` containing the child exit code and captured output.
///
/// Requirements/Preconditions:
/// - [scenario] must be supported by `test_fixtures/native_bridge_probe.dart`.
/// - The package `.dart_tool/package_config.json` must already exist.
///
/// Guarantees/Postconditions:
/// - The child process is killed before returning when the timeout expires.
///
/// Invariants:
/// - Always launches the probe with the bridge library resolved by the shared
///   fixture policy.
Future<ProcessResult> _runNativeBridgeProbe(
  String scenario, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final String packageRoot = Directory.current.path;
  final String packageConfigPath =
      path.join(packageRoot, '.dart_tool', 'package_config.json');
  final String bridgeLibraryPath = _resolveFixtureBridgePath();
  final String probePath = path.join(
    packageRoot,
    'test',
    'test_fixtures',
    'native_bridge_probe.dart',
  );

  final Process process = await Process.start(
    'dart',
    <String>[
      '--packages=$packageConfigPath',
      probePath,
      scenario,
    ],
    workingDirectory: packageRoot,
    environment: <String, String>{
      ...Platform.environment,
      'DOGPAW_BRIDGE_LIB': bridgeLibraryPath,
      'DOGPAW_RUNTIME_DIR': IntegrationTestFixture.runtimeDir,
      'EPIPHANY_INSTANCE': IntegrationTestFixture.instanceName,
    },
  );

  final Future<String> stdoutFuture =
      process.stdout.transform(SystemEncoding().decoder).join();
  final Future<String> stderrFuture =
      process.stderr.transform(SystemEncoding().decoder).join();

  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    exitCode = await process.exitCode;
    final String stdoutText = await stdoutFuture;
    final String stderrText = await stderrFuture;
    return ProcessResult(
      process.pid,
      exitCode,
      stdoutText,
      'Probe timed out after ${timeout.inSeconds}s.\n$stderrText',
    );
  }

  final String stdoutText = await stdoutFuture;
  final String stderrText = await stderrFuture;
  return ProcessResult(process.pid, exitCode, stdoutText, stderrText);
}

void main() {
  IntegrationTestFixture.register();

  group('Native DPE bridge', () {
    test('connects, completes ready, and disconnects cleanly', () async {
      final NativeDogPawEntityClient entity =
          NativeDogPawEntityClient('NativeBridgeConnectEntity');

      final Result<bool> connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason:
              'Native-backed connect should succeed: ${connectResult.error}');
      expect(entity.isConnected, isTrue);

      await entity.completeConnectionStart();
      entity.disconnect();

      expect(entity.isConnected, isFalse);
      await entity.dispose();
    });

    test('lists scales through native-backed request resolution', () async {
      final DogPawEntity creator = DogPawEntity('NativeBridgeScaleCreator');
      final ConnectionResult creatorConnect = await creator.connect();
      expect(creatorConnect.success, isTrue,
          reason: 'Scale creator should connect: ${creatorConnect.error}');
      await creatorConnect.handle!.complete();

      final String scaleName = uniqueName('native_bridge_scale');
      final Scale createScale = Scale(
        name: scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ScaleData(
          displayName: 'Bridge Global Scale',
          rootNote: 5,
          noteCategories: [1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
        ),
      );

      final Result<bool> createResult = await creator.createScale(createScale);
      expect(createResult.success, isTrue,
          reason: 'Scale setup should succeed: ${createResult.error}');

      final NativeDogPawEntityClient entity =
          NativeDogPawEntityClient('NativeBridgeScaleReader');
      final Result<bool> connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason:
              'Native-backed connect should succeed: ${connectResult.error}');
      await entity.completeConnectionStart();

      final Result<List<Scale>> listResult = await entity.listScales(
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );

      expect(listResult.success, isTrue,
          reason:
              'Native-backed listScales should succeed: ${listResult.error}');
      expect(listResult.value, isNotNull);

      final Scale matchingScale = listResult.value!
          .firstWhere((Scale scale) => scale.name == scaleName);
      expect(matchingScale.displayName, equals('Bridge Global Scale'));
      expect(matchingScale.rootNote, equals(5));

      entity.disconnect();
      await entity.dispose();
      creator.disconnect();
    });

    test(
        'executes scale CRUD and current-scale lifecycle through native-backed requests',
        () async {
      final NativeDogPawEntityClient entity =
          NativeDogPawEntityClient('NativeBridgeScaleCrudEntity');

      final Result<bool> connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason:
              'Native-backed connect should succeed: ${connectResult.error}');
      await entity.completeConnectionStart();

      final String scaleName = uniqueName('native_bridge_scale_crud');
      final Scale initialScale = Scale(
        name: scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ScaleData(
          displayName: 'Native CRUD Scale',
          rootNote: 2,
          noteCategories: [1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
        ),
      );

      final Result<bool> createResult = await entity.createScale(initialScale);
      expect(createResult.success, isTrue,
          reason:
              'Native-backed createScale should succeed: ${createResult.error}');

      final Result<Scale?> readCreatedResult = await entity.readScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readCreatedResult.success, isTrue,
          reason:
              'Native-backed readScale should succeed: ${readCreatedResult.error}');
      expect(readCreatedResult.value, isNotNull);
      expect(readCreatedResult.value!.displayName, equals('Native CRUD Scale'));
      expect(readCreatedResult.value!.rootNote, equals(2));
      expect(
        readCreatedResult.value!.noteCategories,
        equals(const [1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1]),
      );

      final Scale updatedScale = Scale(
        name: scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ScaleData(
          displayName: 'Native Updated Scale',
          rootNote: 7,
          noteCategories: [1, 1, -1, 1, -1, 1, -1, 1, 1, -1, 1, -1],
        ),
      );

      final Result<bool> updateResult = await entity.updateScale(updatedScale);
      expect(updateResult.success, isTrue,
          reason:
              'Native-backed updateScale should succeed: ${updateResult.error}');

      final Result<Scale?> readUpdatedResult = await entity.readScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readUpdatedResult.success, isTrue,
          reason:
              'Native-backed readScale after update should succeed: ${readUpdatedResult.error}');
      expect(readUpdatedResult.value, isNotNull);
      expect(
          readUpdatedResult.value!.displayName, equals('Native Updated Scale'));
      expect(readUpdatedResult.value!.rootNote, equals(7));
      expect(
        readUpdatedResult.value!.noteCategories,
        equals(const [1, 1, -1, 1, -1, 1, -1, 1, 1, -1, 1, -1]),
      );

      final Scale upsertedScale = Scale(
        name: scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ScaleData(
          displayName: 'Native Upserted Scale',
          rootNote: 9,
          noteCategories: [-1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1, 1],
        ),
      );

      final Result<bool> setResult = await entity.setScale(upsertedScale);
      expect(setResult.success, isTrue,
          reason: 'Native-backed setScale should succeed: ${setResult.error}');

      final Result<Scale?> readUpsertedResult = await entity.readScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readUpsertedResult.success, isTrue,
          reason:
              'Native-backed readScale after set should succeed: ${readUpsertedResult.error}');
      expect(readUpsertedResult.value, isNotNull);
      expect(readUpsertedResult.value!.displayName,
          equals('Native Upserted Scale'));
      expect(readUpsertedResult.value!.rootNote, equals(9));

      final Result<bool> setCurrentResult = await entity.setCurrentScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(setCurrentResult.success, isTrue,
          reason:
              'Native-backed setCurrentScale should succeed: ${setCurrentResult.error}');

      final Result<Scale?> readCurrentResult = await entity.readCurrentScale(
        includeResolved: true,
        includeSpec: true,
      );
      expect(readCurrentResult.success, isTrue,
          reason:
              'Native-backed readCurrentScale should succeed: ${readCurrentResult.error}');
      expect(readCurrentResult.value, isNotNull);
      expect(readCurrentResult.value!.name, equals(scaleName));
      expect(readCurrentResult.value!.displayName,
          equals('Native Upserted Scale'));

      final Result<bool> removeCurrentResult =
          await entity.removeCurrentScale();
      expect(removeCurrentResult.success, isTrue,
          reason:
              'Native-backed removeCurrentScale should succeed: ${removeCurrentResult.error}');

      final Result<Scale?> readDefaultCurrentResult =
          await entity.readCurrentScale(
        includeResolved: true,
        includeSpec: true,
      );
      expect(readDefaultCurrentResult.success, isTrue,
          reason:
              'Native-backed readCurrentScale after remove should succeed: ${readDefaultCurrentResult.error}');
      expect(readDefaultCurrentResult.value, isNotNull);
      expect(
          readDefaultCurrentResult.value!.name, equals('__DEFAULT_CURRENT__'));
      expect(readDefaultCurrentResult.value!.displayName, equals('Major (C)'));

      final Result<bool> deleteResult = await entity.deleteScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(deleteResult.success, isTrue,
          reason:
              'Native-backed deleteScale should succeed: ${deleteResult.error}');

      final Result<Scale?> readDeletedResult = await entity.readScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readDeletedResult.success, isTrue,
          reason:
              'Native-backed readScale after delete should succeed: ${readDeletedResult.error}');
      expect(readDeletedResult.value, isNull);

      entity.disconnect();
      await entity.dispose();
    });

    test(
        'executes theme CRUD and current-theme lifecycle through native-backed requests',
        () async {
      final NativeDogPawEntityClient entity =
          NativeDogPawEntityClient('NativeBridgeThemeCrudEntity');

      final Result<bool> connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason:
              'Native-backed connect should succeed: ${connectResult.error}');
      await entity.completeConnectionStart();

      final String themeName = uniqueName('native_bridge_theme_crud');
      final Theme initialTheme = Theme(
        name: themeName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ThemeData(
          displayName: 'Native CRUD Theme',
          primaryColor: '#101010',
          secondaryColor: '#202020',
          accentColor: '#303030',
          backgroundColor: '#404040',
        ),
      );

      final Result<bool> createResult = await entity.createTheme(initialTheme);
      expect(createResult.success, isTrue,
          reason:
              'Native-backed createTheme should succeed: ${createResult.error}');

      final Result<Theme?> readCreatedResult = await entity.readTheme(
        themeName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readCreatedResult.success, isTrue,
          reason:
              'Native-backed readTheme should succeed: ${readCreatedResult.error}');
      expect(readCreatedResult.value, isNotNull);
      expect(readCreatedResult.value!.data.displayName,
          equals('Native CRUD Theme'));
      expect(readCreatedResult.value!.spec, isNotNull);
      expect(readCreatedResult.value!.spec!.primaryColor, equals('#101010'));

      final Theme updatedTheme = Theme(
        name: themeName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ThemeData(
          displayName: 'Native Updated Theme',
          primaryColor: '#505050',
          secondaryColor: '#606060',
          accentColor: '#707070',
          backgroundColor: '#808080',
        ),
      );

      final Result<bool> updateResult = await entity.updateTheme(updatedTheme);
      expect(updateResult.success, isTrue,
          reason:
              'Native-backed updateTheme should succeed: ${updateResult.error}');

      final Theme setThemeValue = Theme(
        name: themeName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ThemeData(
          displayName: 'Native Set Theme',
          primaryColor: '#909090',
          secondaryColor: '#A0A0A0',
          accentColor: '#B0B0B0',
          backgroundColor: '#C0C0C0',
        ),
      );

      final Result<bool> setResult = await entity.setTheme(setThemeValue);
      expect(setResult.success, isTrue,
          reason: 'Native-backed setTheme should succeed: ${setResult.error}');

      final Result<List<Theme>> listResult = await entity.listThemes(
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(listResult.success, isTrue,
          reason:
              'Native-backed listThemes should succeed: ${listResult.error}');
      expect(listResult.value, isNotNull);
      expect(
        listResult.value!.any((Theme item) => item.name == themeName),
        isTrue,
      );

      final Result<bool> setCurrentResult = await entity.setCurrentTheme(
        themeName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(setCurrentResult.success, isTrue,
          reason:
              'Native-backed setCurrentTheme should succeed: ${setCurrentResult.error}');

      final Result<Theme?> currentResult = await entity.readCurrentTheme(
        includeResolved: true,
        includeSpec: true,
      );
      expect(currentResult.success, isTrue,
          reason:
              'Native-backed readCurrentTheme should succeed: ${currentResult.error}');
      expect(currentResult.value, isNotNull);
      expect(currentResult.value!.name, equals(themeName));
      expect(currentResult.value!.data.displayName, equals('Native Set Theme'));

      final Result<bool> removeCurrentResult =
          await entity.removeCurrentTheme();
      expect(removeCurrentResult.success, isTrue,
          reason:
              'Native-backed removeCurrentTheme should succeed: ${removeCurrentResult.error}');

      final Result<Theme?> readDefaultCurrentResult =
          await entity.readCurrentTheme(
        includeResolved: true,
        includeSpec: true,
      );
      expect(readDefaultCurrentResult.success, isTrue,
          reason:
              'Native-backed readCurrentTheme after remove should succeed: ${readDefaultCurrentResult.error}');
      expect(readDefaultCurrentResult.value, isNotNull);
      expect(
          readDefaultCurrentResult.value!.name, equals('__DEFAULT_CURRENT__'));

      final Result<bool> deleteResult = await entity.deleteTheme(
        themeName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(deleteResult.success, isTrue,
          reason:
              'Native-backed deleteTheme should succeed: ${deleteResult.error}');

      entity.disconnect();
      await entity.dispose();
    });

    test(
        'executes theme subscriptions and current-theme subscriptions through native-backed events',
        () async {
      final NativeDogPawEntityClient subscriber =
          NativeDogPawEntityClient('NativeBridgeThemeSubscriptionSubscriber');
      final NativeDogPawEntityClient publisher =
          NativeDogPawEntityClient('NativeBridgeThemeSubscriptionPublisher');

      final Result<bool> subscriberConnect = await subscriber.connect();
      expect(subscriberConnect.success, isTrue,
          reason:
              'Native-backed subscriber connect should succeed: ${subscriberConnect.error}');
      await subscriber.completeConnectionStart();

      final Result<bool> publisherConnect = await publisher.connect();
      expect(publisherConnect.success, isTrue,
          reason:
              'Native-backed publisher connect should succeed: ${publisherConnect.error}');
      await publisher.completeConnectionStart();

      final String ordinaryThemeName =
          uniqueName('native_bridge_theme_subscription');
      final Completer<Theme> ordinaryNotification = Completer<Theme>();
      final Result<bool> ordinarySubscribeResult =
          await subscriber.subscribeToThemes(
        (String notificationType, DataItemRef ref, Theme theme) {
          if (theme.name == ordinaryThemeName &&
              !ordinaryNotification.isCompleted) {
            ordinaryNotification.complete(theme);
          }
        },
        themeName: ordinaryThemeName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
        sendImmediately: false,
      );
      expect(ordinarySubscribeResult.success, isTrue,
          reason:
              'Native-backed subscribeToThemes should succeed: ${ordinarySubscribeResult.error}');

      final Theme ordinaryTheme = Theme(
        name: ordinaryThemeName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ThemeData(
          displayName: 'Native Subscription Theme',
          primaryColor: '#111111',
          secondaryColor: '#222222',
          accentColor: '#333333',
          backgroundColor: '#444444',
        ),
      );
      final Result<bool> createOrdinaryThemeResult =
          await publisher.createTheme(ordinaryTheme);
      expect(createOrdinaryThemeResult.success, isTrue,
          reason:
              'Native-backed createTheme for subscription should succeed: ${createOrdinaryThemeResult.error}');

      final Theme ordinaryReceivedTheme =
          await ordinaryNotification.future.timeout(const Duration(seconds: 2));
      expect(ordinaryReceivedTheme.name, equals(ordinaryThemeName));
      expect(ordinaryReceivedTheme.data.displayName,
          equals('Native Subscription Theme'));

      final Result<bool> ordinaryUnsubscribeResult =
          await subscriber.unsubscribeFromThemes(
        themeName: ordinaryThemeName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(ordinaryUnsubscribeResult.success, isTrue,
          reason:
              'Native-backed unsubscribeFromThemes should succeed: ${ordinaryUnsubscribeResult.error}');

      final String currentThemeName = uniqueName('native_bridge_current_theme');
      final Theme currentTheme = Theme(
        name: currentThemeName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ThemeData(
          displayName: 'Native Current Theme',
          primaryColor: '#515151',
          secondaryColor: '#616161',
          accentColor: '#717171',
          backgroundColor: '#818181',
        ),
      );
      final Result<bool> createCurrentThemeResult =
          await publisher.createTheme(currentTheme);
      expect(createCurrentThemeResult.success, isTrue,
          reason:
              'Native-backed createTheme for current subscription should succeed: ${createCurrentThemeResult.error}');

      final Completer<Theme> currentNotification = Completer<Theme>();
      final Result<bool> currentSubscribeResult =
          await subscriber.subscribeToCurrentTheme(
        (String notificationType, DataItemRef ref, Theme theme) {
          if (theme.name == currentThemeName &&
              !currentNotification.isCompleted) {
            currentNotification.complete(theme);
          }
        },
        includeResolved: true,
        includeSpec: true,
        sendImmediately: false,
      );
      expect(currentSubscribeResult.success, isTrue,
          reason:
              'Native-backed subscribeToCurrentTheme should succeed: ${currentSubscribeResult.error}');

      final Result<bool> setCurrentThemeResult =
          await publisher.setCurrentTheme(
        currentThemeName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(setCurrentThemeResult.success, isTrue,
          reason:
              'Native-backed setCurrentTheme for subscription should succeed: ${setCurrentThemeResult.error}');

      final Theme currentReceivedTheme =
          await currentNotification.future.timeout(const Duration(seconds: 2));
      expect(currentReceivedTheme.name, equals(currentThemeName));
      expect(
        currentReceivedTheme.data.displayName,
        equals('Native Current Theme'),
      );

      final Result<bool> currentUnsubscribeResult =
          await subscriber.unsubscribeFromCurrentTheme();
      expect(currentUnsubscribeResult.success, isTrue,
          reason:
              'Native-backed unsubscribeFromCurrentTheme should succeed: ${currentUnsubscribeResult.error}');

      subscriber.disconnect();
      publisher.disconnect();
      await subscriber.dispose();
      await publisher.dispose();
    });

    test('executes entity lifecycle subscriptions through native-backed events',
        () async {
      final NativeDogPawEntityClient watcher =
          NativeDogPawEntityClient('NativeBridgeLifecycleWatcher');
      final NativeDogPawEntityClient subject =
          NativeDogPawEntityClient('NativeBridgeLifecycleSubject');

      final Result<bool> watcherConnect = await watcher.connect();
      expect(watcherConnect.success, isTrue,
          reason:
              'Native-backed lifecycle watcher connect should succeed: ${watcherConnect.error}');
      await watcher.completeConnectionStart();

      final Completer<String> connectedNotification = Completer<String>();
      final Completer<String> disconnectedNotification = Completer<String>();

      final Result<bool> subscribeResult =
          await watcher.subscribeToEntityLifecycle(
        (String notificationType, String entityName) {
          if (entityName == 'NativeBridgeLifecycleSubject' &&
              notificationType == 'entity_connected' &&
              !connectedNotification.isCompleted) {
            connectedNotification.complete(entityName);
          }
          if (entityName == 'NativeBridgeLifecycleSubject' &&
              notificationType == 'entity_disconnected' &&
              !disconnectedNotification.isCompleted) {
            disconnectedNotification.complete(entityName);
          }
        },
        watchEntityName: 'NativeBridgeLifecycleSubject',
        sendImmediately: false,
      );
      expect(subscribeResult.success, isTrue,
          reason:
              'Native-backed subscribeToEntityLifecycle should succeed: ${subscribeResult.error}');

      final Result<bool> subjectConnect = await subject.connect();
      expect(subjectConnect.success, isTrue,
          reason:
              'Native-backed lifecycle subject connect should succeed: ${subjectConnect.error}');
      await subject.completeConnectionStart();

      expect(
        await connectedNotification.future.timeout(const Duration(seconds: 2)),
        equals('NativeBridgeLifecycleSubject'),
      );

      subject.disconnect();

      expect(
        await disconnectedNotification.future.timeout(
          const Duration(seconds: 2),
        ),
        equals('NativeBridgeLifecycleSubject'),
      );

      final Result<bool> unsubscribeResult =
          await watcher.unsubscribeFromEntityLifecycle(
        watchEntityName: 'NativeBridgeLifecycleSubject',
      );
      expect(unsubscribeResult.success, isTrue,
          reason:
              'Native-backed unsubscribeFromEntityLifecycle should succeed: ${unsubscribeResult.error}');

      watcher.disconnect();
      await watcher.dispose();
      await subject.dispose();
    });

    test('executes direct messages through native-backed events', () async {
      final NativeDogPawEntityClient receiver =
          NativeDogPawEntityClient('NativeBridgeDirectMessageReceiver');
      final NativeDogPawEntityClient sender =
          NativeDogPawEntityClient('NativeBridgeDirectMessageSender');

      final Result<bool> receiverConnect = await receiver.connect();
      expect(receiverConnect.success, isTrue,
          reason:
              'Native-backed direct-message receiver connect should succeed: ${receiverConnect.error}');
      await receiver.completeConnectionStart();

      final Result<bool> senderConnect = await sender.connect();
      expect(senderConnect.success, isTrue,
          reason:
              'Native-backed direct-message sender connect should succeed: ${senderConnect.error}');
      await sender.completeConnectionStart();

      final Completer<Map<String, dynamic>> deliveredMessage =
          Completer<Map<String, dynamic>>();
      final Completer<String> deliveredSender = Completer<String>();
      receiver.setDirectMessageCallback(
        (String senderEntity, Map<String, dynamic> message) {
          if (!deliveredSender.isCompleted) {
            deliveredSender.complete(senderEntity);
          }
          if (!deliveredMessage.isCompleted) {
            deliveredMessage.complete(message);
          }
        },
      );

      final Result<bool> sendResult = await sender.sendDirectMessage(
        'NativeBridgeDirectMessageReceiver',
        <String, dynamic>{'kind': 'native', 'value': 7},
      );
      expect(sendResult.success, isTrue,
          reason:
              'Native-backed sendDirectMessage should succeed: ${sendResult.error}');

      expect(
        await deliveredSender.future.timeout(const Duration(seconds: 2)),
        equals('NativeBridgeDirectMessageSender'),
      );
      final Map<String, dynamic> receivedMessage =
          await deliveredMessage.future.timeout(const Duration(seconds: 2));
      expect(receivedMessage['kind'], equals('native'));
      expect(receivedMessage['value'], equals(7));

      receiver.disconnect();
      sender.disconnect();
      await receiver.dispose();
      await sender.dispose();
    });

    test('executes commands through native-backed events and responses',
        () async {
      final NativeDogPawEntityClient requester =
          NativeDogPawEntityClient('NativeBridgeCommandRequester');
      final NativeDogPawEntityClient handler =
          NativeDogPawEntityClient('NativeBridgeCommandHandler');

      final Result<bool> requesterConnect = await requester.connect();
      expect(requesterConnect.success, isTrue,
          reason:
              'Native-backed command requester connect should succeed: ${requesterConnect.error}');
      await requester.completeConnectionStart();

      final Result<bool> handlerConnect = await handler.connect();
      expect(handlerConnect.success, isTrue,
          reason:
              'Native-backed command handler connect should succeed: ${handlerConnect.error}');
      await handler.completeConnectionStart();

      final Completer<String> receivedSender = Completer<String>();
      final Completer<String> receivedCommand = Completer<String>();
      final Completer<Map<String, dynamic>> receivedParams =
          Completer<Map<String, dynamic>>();
      handler.setCommandCallback(
        (String senderEntity, String command, Map<String, dynamic> params,
            String commandId) {
          if (!receivedSender.isCompleted) {
            receivedSender.complete(senderEntity);
          }
          if (!receivedCommand.isCompleted) {
            receivedCommand.complete(command);
          }
          if (!receivedParams.isCompleted) {
            receivedParams.complete(params);
          }
          handler.sendCommandAccepted(senderEntity, commandId);
          Future<void>.delayed(const Duration(milliseconds: 50), () {
            handler.sendCommandResponse(
              senderEntity,
              commandId,
              success: true,
              result: <String, dynamic>{'handled': true},
            );
          });
        },
      );

      bool acceptedCalled = false;
      final CommandResponseResult result = await requester.sendCommand(
        'NativeBridgeCommandHandler',
        'native_bridge_command',
        params: <String, dynamic>{'index': 3},
        timeout: const Duration(seconds: 3),
        onAccepted: (Map<String, dynamic> _) {
          acceptedCalled = true;
        },
      );

      expect(
        await receivedSender.future.timeout(const Duration(seconds: 2)),
        equals('NativeBridgeCommandRequester'),
      );
      expect(
        await receivedCommand.future.timeout(const Duration(seconds: 2)),
        equals('native_bridge_command'),
      );
      final Map<String, dynamic> params =
          await receivedParams.future.timeout(const Duration(seconds: 2));
      expect(params['index'], equals(3));
      expect(acceptedCalled, isTrue);
      expect(result.success, isTrue,
          reason: 'Native-backed command should succeed: ${result.error}');
      expect(result.result['handled'], equals(true));

      requester.disconnect();
      handler.disconnect();
      await requester.dispose();
      await handler.dispose();
    });

    test('executes preset requests through native-backed preset callbacks',
        () async {
      final DogPawEntity controller =
          DogPawEntity('NativeBridgePresetController');
      final NativeDogPawEntityClient target =
          NativeDogPawEntityClient('NativeBridgePresetTarget');

      final ConnectionResult controllerConnect = await controller.connect();
      expect(controllerConnect.success, isTrue,
          reason:
              'Preset controller should connect: ${controllerConnect.error}');
      await controllerConnect.handle!.complete();

      final Result<bool> targetConnect = await target.connect();
      expect(targetConnect.success, isTrue,
          reason:
              'Native-backed preset target connect should succeed: ${targetConnect.error}');
      await target.completeConnectionStart();

      final String presetName = uniqueName('native_bridge_preset');
      final Completer<String> saveRequestType = Completer<String>();
      final Completer<String> loadRequestType = Completer<String>();
      final Completer<String> deferredLoadCompletion = Completer<String>();
      bool firstRequest = true;

      target.setPresetRequestCallback(
        (String serverRequestId, Map<String, dynamic> content) async {
          final String requestType = content['requestType'] as String? ?? '';
          if (firstRequest) {
            firstRequest = false;
            if (!saveRequestType.isCompleted) {
              saveRequestType.complete(requestType);
            }
            return true;
          }

          if (!loadRequestType.isCompleted) {
            loadRequestType.complete(requestType);
          }
          Future<void>.delayed(const Duration(milliseconds: 50), () async {
            await target.completePresetRequest(serverRequestId, success: true);
            if (!deferredLoadCompletion.isCompleted) {
              deferredLoadCompletion.complete(serverRequestId);
            }
          });
          return false;
        },
      );

      final Result<bool> saveResult =
          await controller.saveGlobalState(presetName);
      expect(saveResult.success, isTrue,
          reason: 'saveGlobalState should succeed: ${saveResult.error}');
      expect(
        await saveRequestType.future.timeout(const Duration(seconds: 2)),
        equals('save'),
      );

      final Result<bool> loadResult =
          await controller.loadGlobalState(presetName);
      expect(loadResult.success, isTrue,
          reason: 'loadGlobalState should succeed: ${loadResult.error}');
      expect(
        await loadRequestType.future.timeout(const Duration(seconds: 2)),
        equals('load'),
      );
      expect(
        await deferredLoadCompletion.future.timeout(const Duration(seconds: 2)),
        isNotEmpty,
      );

      controller.disconnect();
      target.disconnect();
      await target.dispose();
      await Future<void>.delayed(const Duration(seconds: 1));
    });

    test(
        'executes endpoint create, read, search, and delete through native-backed requests',
        () async {
      const String ownerEntityName = 'NativeBridgeEndpointOwner';
      const String observerEntityName = 'NativeBridgeEndpointObserver';
      final NativeDogPawEntityClient owner =
          NativeDogPawEntityClient(ownerEntityName);
      final NativeDogPawEntityClient observer =
          NativeDogPawEntityClient(observerEntityName);

      final Result<bool> ownerConnect = await owner.connect();
      expect(ownerConnect.success, isTrue,
          reason:
              'Endpoint owner connect should succeed: ${ownerConnect.error}');
      await owner.completeConnectionStart();

      final Result<bool> observerConnect = await observer.connect();
      expect(observerConnect.success, isTrue,
          reason:
              'Endpoint observer connect should succeed: ${observerConnect.error}');
      await observer.completeConnectionStart();

      final String endpointName = uniqueName('native_bridge_endpoint');
      final String endpointFlag = uniqueName('native_bridge_endpoint_flag');
      final EndpointInfo endpoint = EndpointInfo(
        name: endpointName,
        spec: EndpointSpec(
          displayName: 'Native Bridge Endpoint',
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
          flags: <String>[endpointFlag],
        ),
      );

      final Result<EndpointInfo> createResult =
          await owner.createEndpoint(endpoint);
      expect(createResult.success, isTrue,
          reason:
              'Native-backed createEndpoint should succeed: ${createResult.error}');
      expect(createResult.value, isNotNull);
      expect(createResult.value!.name, equals(endpointName));

      final Result<EndpointInfo?> readResult = await owner.readEndpoint(
        endpointName,
        namespaceSelector:
            const NamespaceSelector.specificEntity(ownerEntityName),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readResult.success, isTrue,
          reason:
              'Native-backed readEndpoint should succeed: ${readResult.error}');
      expect(readResult.value, isNotNull);
      expect(readResult.value!.spec!.displayName,
          equals('Native Bridge Endpoint'));
      expect(readResult.value!.spec!.flags, contains(endpointFlag));

      final Result<List<EndpointInfo>> searchResult =
          await observer.searchEndpoints(
        SearchCriteria.flagContains(endpointFlag),
      );
      expect(searchResult.success, isTrue,
          reason:
              'Native-backed searchEndpoints should succeed: ${searchResult.error}');
      expect(
        searchResult.value!
            .any((EndpointInfo item) => item.name == endpointName),
        isTrue,
      );

      final Result<bool> deleteResult =
          await owner.deleteEndpoint(endpointName);
      expect(deleteResult.success, isTrue,
          reason:
              'Native-backed deleteEndpoint should succeed: ${deleteResult.error}');

      owner.disconnect();
      observer.disconnect();
      await owner.dispose();
      await observer.dispose();
    });

    test(
        'executes routing requests and realized connections through native-backed requests',
        () async {
      const String sourceOwnerEntityName = 'NativeBridgeRoutingSource';
      const String destinationOwnerEntityName =
          'NativeBridgeRoutingDestination';
      const String observerEntityName = 'NativeBridgeRoutingObserver';
      final NativeDogPawEntityClient sourceOwner =
          NativeDogPawEntityClient(sourceOwnerEntityName);
      final NativeDogPawEntityClient destinationOwner =
          NativeDogPawEntityClient(destinationOwnerEntityName);
      final NativeDogPawEntityClient observer =
          NativeDogPawEntityClient(observerEntityName);

      final Result<bool> sourceConnect = await sourceOwner.connect();
      expect(sourceConnect.success, isTrue,
          reason:
              'Routing source connect should succeed: ${sourceConnect.error}');
      await sourceOwner.completeConnectionStart();

      final Result<bool> destinationConnect = await destinationOwner.connect();
      expect(destinationConnect.success, isTrue,
          reason:
              'Routing destination connect should succeed: ${destinationConnect.error}');
      await destinationOwner.completeConnectionStart();

      final Result<bool> observerConnect = await observer.connect();
      expect(observerConnect.success, isTrue,
          reason:
              'Routing observer connect should succeed: ${observerConnect.error}');
      await observer.completeConnectionStart();

      final String sourceEndpointName = uniqueName('native_bridge_route_out');
      final String destinationEndpointName =
          uniqueName('native_bridge_route_in');
      final String connectionRequestName =
          uniqueName('native_bridge_connection_rule');
      final String followRequestName =
          uniqueName('native_bridge_follow_rule');
      final String leaderFlag = uniqueName('native_bridge_leader_flag');

      expect(
        (await sourceOwner.createEndpoint(
          EndpointInfo(
            name: sourceEndpointName,
            spec: const EndpointSpec(
              direction: EndpointDirection.output,
              dataType: DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
            ),
          ),
        ))
            .success,
        isTrue,
      );
      expect(
        (await destinationOwner.createEndpoint(
          EndpointInfo(
            name: destinationEndpointName,
            spec: EndpointSpec(
              direction: EndpointDirection.input,
              dataType: const DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
              flags: <String>[leaderFlag],
            ),
          ),
        ))
            .success,
        isTrue,
      );

      final ConnectionRule connectionRequest = ConnectionRule(
        name: connectionRequestName,
        spec: ConnectionRuleData(
          sourceRef: DataItemRef.byName(
            name: sourceEndpointName,
            namespaceSelector:
                const NamespaceSelector.specificEntity(sourceOwnerEntityName),
          ),
          destinationRef: DataItemRef.byName(
            name: destinationEndpointName,
            namespaceSelector: const NamespaceSelector.specificEntity(
                destinationOwnerEntityName),
          ),
        ),
      );

      final Result<bool> createConnectionRuleResult =
          await observer.createConnectionRule(connectionRequest);
      expect(createConnectionRuleResult.success, isTrue,
          reason:
              'Native-backed createConnectionRule should succeed: ${createConnectionRuleResult.error}');

      final Result<List<ConnectionRule>> connectionRequestsResult =
          await observer.listConnectionRules(includeSpec: true);
      expect(connectionRequestsResult.success, isTrue,
          reason:
              'Native-backed listConnectionRules should succeed: ${connectionRequestsResult.error}');
      expect(
        connectionRequestsResult.value!.any(
            (ConnectionRule item) => item.name == connectionRequestName),
        isTrue,
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final Result<List<Connection>> realizedConnectionsResult =
          await observer.listConnections(
        includeResolved: true,
        includeSpec: true,
      );
      expect(realizedConnectionsResult.success, isTrue,
          reason:
              'Native-backed listConnections should succeed: ${realizedConnectionsResult.error}');
      expect(
        realizedConnectionsResult.value!.any(
          (Connection connection) =>
              connection.spec?.sourceRef.name == sourceEndpointName &&
              connection.spec?.destinationRef.name == destinationEndpointName,
        ),
        isTrue,
      );

      final FollowRule followRule = FollowRule(
        name: followRequestName,
        spec: FollowRuleData(
          followerRef: DataItemRef.byName(
            name: destinationEndpointName,
            namespaceSelector: const NamespaceSelector.specificEntity(
                destinationOwnerEntityName),
          ),
          leaderCriteria: SearchCriteria.flagContains(leaderFlag),
        ),
      );

      final Result<bool> createFollowRuleResult =
          await destinationOwner.createFollowRule(followRule);
      expect(createFollowRuleResult.success, isTrue,
          reason:
              'Native-backed createFollowRule should succeed: ${createFollowRuleResult.error}');

      final Result<List<FollowRule>> followRulesResult =
          await destinationOwner.listFollowRules(includeSpec: true);
      expect(followRulesResult.success, isTrue,
          reason:
              'Native-backed listFollowRules should succeed: ${followRulesResult.error}');
      expect(
        followRulesResult.value!
            .any((FollowRule item) => item.name == followRequestName),
        isTrue,
      );

      sourceOwner.disconnect();
      destinationOwner.disconnect();
      observer.disconnect();
      await sourceOwner.dispose();
      await destinationOwner.dispose();
      await observer.dispose();
    });

    test(
        'serializes debug probe events in bridge-local FIFO order during multi-threaded handoff',
        () async {
      final ProcessResult result = await _runNativeBridgeProbe(
        'dispatcher_order_probe',
      );

      expect(result.exitCode, 0,
          reason: 'Native bridge dispatcher-order probe should preserve FIFO '
              'handoff order.\nstdout:\n${result.stdout}\n\nstderr:\n'
              '${result.stderr}');
    });

    test('drains debug probe events that were accepted before shutdown',
        () async {
      final ProcessResult result = await _runNativeBridgeProbe(
        'shutdown_drain_probe',
      );

      expect(result.exitCode, 0,
          reason: 'Native bridge shutdown-drain probe should deliver accepted '
              'events before teardown returns.\nstdout:\n${result.stdout}'
              '\n\nstderr:\n${result.stderr}');
    });

    test(
        'startup continuous polls stay quiet until first payload then log readiness',
        () async {
      final ProcessResult result = await _runNativeBridgeProbe(
        'continuous_startup_poll_probe',
      );
      final String logs = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, 0,
          reason:
              'Continuous startup poll probe should exit cleanly.\nstdout:\n'
              '${result.stdout}\n\nstderr:\n${result.stderr}');
      expect(
        logs,
        isNot(contains('Failed to get read guard for connection')),
        reason: 'Initial no-frame continuous polls should not emit read-guard '
            'warnings before the first payload arrives.\nstdout:\n'
            '${result.stdout}\n\nstderr:\n${result.stderr}',
      );
      expect(
        logs,
        contains('First readable continuous payload observed'),
        reason:
            'The bridge should log when the first continuous payload becomes '
            'readable.\nstdout:\n${result.stdout}\n\nstderr:\n${result.stderr}',
      );
    });

    test(
        'survives concurrent local-endpoint connection queries during routing churn',
        () async {
      final ProcessResult result = await _runNativeBridgeProbe(
        'connection_count_deadlock_probe',
      );

      expect(result.exitCode, 0,
          reason: 'Native bridge deadlock probe should exit cleanly.\nstdout:\n'
              '${result.stdout}\n\nstderr:\n${result.stderr}');
    });

    test(
        'executes layout CRUD and layout-stack lifecycle through native-backed requests',
        () async {
      final NativeDogPawEntityClient entity =
          NativeDogPawEntityClient('NativeBridgeLayoutCrudEntity');

      final Result<bool> connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason:
              'Native-backed connect should succeed: ${connectResult.error}');
      await entity.completeConnectionStart();

      final String layoutName = uniqueName('native_bridge_layout_crud');
      final Layout initialLayout = Layout(
        name: layoutName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const LayoutData(displayName: 'Native CRUD Layout'),
      );

      final Result<bool> createResult =
          await entity.createLayout(initialLayout);
      expect(createResult.success, isTrue,
          reason:
              'Native-backed createLayout should succeed: ${createResult.error}');

      final Result<Layout?> readCreatedResult = await entity.readLayout(
        layoutName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readCreatedResult.success, isTrue,
          reason:
              'Native-backed readLayout should succeed: ${readCreatedResult.error}');
      expect(readCreatedResult.value, isNotNull);
      expect(readCreatedResult.value!.data.displayName,
          equals('Native CRUD Layout'));

      final Layout updatedLayout = Layout(
        name: layoutName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const LayoutData(displayName: 'Native Updated Layout'),
      );

      final Result<bool> updateResult =
          await entity.updateLayout(updatedLayout);
      expect(updateResult.success, isTrue,
          reason:
              'Native-backed updateLayout should succeed: ${updateResult.error}');

      final Layout setLayoutValue = Layout(
        name: layoutName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const LayoutData(displayName: 'Native Set Layout'),
      );

      final Result<bool> setResult = await entity.setLayout(setLayoutValue);
      expect(setResult.success, isTrue,
          reason: 'Native-backed setLayout should succeed: ${setResult.error}');

      final Result<List<Layout>> listResult = await entity.listLayouts(
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(listResult.success, isTrue,
          reason:
              'Native-backed listLayouts should succeed: ${listResult.error}');
      expect(listResult.value, isNotNull);
      expect(
        listResult.value!.any((Layout item) => item.name == layoutName),
        isTrue,
      );

      final Result<String> addStackEntryResult =
          await entity.addLayoutStackEntry(
        DataItemRef(
          name: layoutName,
          namespaceSelector: const NamespaceSelector.global(),
        ),
      );
      expect(addStackEntryResult.success, isTrue,
          reason:
              'Native-backed addLayoutStackEntry should succeed: ${addStackEntryResult.error}');

      final Result<LayoutStackSnapshot> readStackResult =
          await entity.readLayoutStack(
        includeResolved: true,
        includeSpec: true,
      );
      expect(readStackResult.success, isTrue,
          reason:
              'Native-backed readLayoutStack should succeed: ${readStackResult.error}');
      expect(readStackResult.value, isNotNull);
      expect(
        readStackResult.value!.entries.any(
          (LayoutStackEntry entry) => entry.layoutRef.name == layoutName,
        ),
        isTrue,
      );
      expect(readStackResult.value!.resolvedLayout, isNotNull);

      final Result<bool> removeStackEntryResult =
          await entity.removeLayoutStackEntry(addStackEntryResult.value!);
      expect(removeStackEntryResult.success, isTrue,
          reason:
              'Native-backed removeLayoutStackEntry should succeed: ${removeStackEntryResult.error}');

      final Result<LayoutStackSnapshot> readStackAfterRemoveResult =
          await entity.readLayoutStack(
              includeResolved: false, includeSpec: false);
      expect(readStackAfterRemoveResult.success, isTrue,
          reason:
              'Native-backed readLayoutStack after remove should succeed: ${readStackAfterRemoveResult.error}');
      expect(readStackAfterRemoveResult.value, isNotNull);
      expect(
        readStackAfterRemoveResult.value!.entries.any(
          (LayoutStackEntry entry) =>
              entry.entryId == addStackEntryResult.value,
        ),
        isFalse,
      );

      final Result<bool> deleteResult = await entity.deleteLayout(
        layoutName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(deleteResult.success, isTrue,
          reason:
              'Native-backed deleteLayout should succeed: ${deleteResult.error}');

      entity.disconnect();
      await entity.dispose();
    });

    test('executes KV CRUD and list through native-backed requests', () async {
      final NativeDogPawEntityClient entity =
          NativeDogPawEntityClient('NativeBridgeKVCrudEntity');

      final Result<bool> connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason:
              'Native-backed connect should succeed: ${connectResult.error}');
      await entity.completeConnectionStart();

      final String kvName = uniqueName('native_bridge_kv_crud');
      final KV initialKV = KV(
        name: kvName,
        namespaceSelector: const NamespaceSelector.global(),
        value: 'native kv initial',
      );

      final Result<bool> createResult = await entity.createKV(initialKV);
      expect(createResult.success, isTrue,
          reason:
              'Native-backed createKV should succeed: ${createResult.error}');

      final Result<KV?> readCreatedResult = await entity.readKV(
        kvName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readCreatedResult.success, isTrue,
          reason:
              'Native-backed readKV should succeed: ${readCreatedResult.error}');
      expect(readCreatedResult.value, isNotNull);
      expect(readCreatedResult.value!.value, equals('native kv initial'));

      final KV updatedKV = KV(
        name: kvName,
        namespaceSelector: const NamespaceSelector.global(),
        value: 'native kv updated',
      );

      final Result<bool> updateResult = await entity.updateKV(updatedKV);
      expect(updateResult.success, isTrue,
          reason:
              'Native-backed updateKV should succeed: ${updateResult.error}');

      final KV setKVValue = KV(
        name: kvName,
        namespaceSelector: const NamespaceSelector.global(),
        value: 'native kv set',
      );

      final Result<bool> setResult = await entity.setKV(setKVValue);
      expect(setResult.success, isTrue,
          reason: 'Native-backed setKV should succeed: ${setResult.error}');

      final Result<List<KV>> listResult = await entity.listKVs(
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(listResult.success, isTrue,
          reason: 'Native-backed listKVs should succeed: ${listResult.error}');
      expect(listResult.value, isNotNull);
      final KV matchingKV =
          listResult.value!.firstWhere((KV item) => item.name == kvName);
      expect(matchingKV.value, equals('native kv set'));

      final Result<bool> deleteResult = await entity.deleteKV(
        kvName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(deleteResult.success, isTrue,
          reason:
              'Native-backed deleteKV should succeed: ${deleteResult.error}');

      entity.disconnect();
      await entity.dispose();
    });

    test(
        'public facade routes lifecycle and scale family through native bridge',
        () async {
      final DogPawEntity entity = DogPawEntity('PublicNativeScaleEntity');

      final ConnectionResult connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason: 'Public connect should succeed: ${connectResult.error}');
      expect(entity.isConnected(), isTrue);
      await connectResult.handle!.complete();

      final String scaleName = uniqueName('public_native_scale');
      final Scale scale = Scale(
        name: scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ScaleData(
          displayName: 'Public Native Scale',
          rootNote: 4,
          noteCategories: [1, -1, 1, 1, -1, 1, -1, 1, -1, 1, 1, -1],
        ),
      );

      final Result<bool> createResult = await entity.createScale(scale);
      expect(createResult.success, isTrue,
          reason: 'Public createScale should succeed: ${createResult.error}');

      final Result<Scale?> readResult = await entity.readScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readResult.success, isTrue,
          reason: 'Public readScale should succeed: ${readResult.error}');
      expect(readResult.value, isNotNull);
      expect(readResult.value!.displayName, equals('Public Native Scale'));

      final Scale updatedScale = Scale(
        name: scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ScaleData(
          displayName: 'Public Native Scale Updated',
          rootNote: 7,
          noteCategories: [1, 1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1],
        ),
      );

      final Result<bool> updateResult = await entity.updateScale(updatedScale);
      expect(updateResult.success, isTrue,
          reason: 'Public updateScale should succeed: ${updateResult.error}');

      final Scale setScaleValue = Scale(
        name: scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ScaleData(
          displayName: 'Public Native Scale Set',
          rootNote: 9,
          noteCategories: [1, -1, 1, 1, -1, 1, -1, 1, 1, -1, 1, -1],
        ),
      );

      final Result<bool> setResult = await entity.setScale(setScaleValue);
      expect(setResult.success, isTrue,
          reason: 'Public setScale should succeed: ${setResult.error}');

      final Result<Scale?> readBackAfterSet = await entity.readScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readBackAfterSet.success, isTrue,
          reason:
              'Public readScale after set should succeed: ${readBackAfterSet.error}');
      expect(readBackAfterSet.value, isNotNull);
      expect(readBackAfterSet.value!.displayName,
          equals('Public Native Scale Set'));

      final Result<List<Scale>> listResult = await entity.listScales(
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(listResult.success, isTrue,
          reason: 'Public listScales should succeed: ${listResult.error}');
      expect(
        listResult.value!.any((Scale item) => item.name == scaleName),
        isTrue,
      );

      final Result<bool> setCurrentResult = await entity.setCurrentScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(setCurrentResult.success, isTrue,
          reason:
              'Public setCurrentScale should succeed: ${setCurrentResult.error}');

      final Result<Scale?> currentResult = await entity.readCurrentScale();
      expect(currentResult.success, isTrue,
          reason:
              'Public readCurrentScale should succeed: ${currentResult.error}');
      expect(currentResult.value, isNotNull);
      expect(currentResult.value!.name, equals(scaleName));

      final Result<Connection?> missingConnectionResult =
          await entity.readConnection('definitely_not_implemented_here');
      expect(missingConnectionResult.success, isTrue);
      expect(missingConnectionResult.value, isNull);

      final Result<bool> deleteResult = await entity.deleteScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(deleteResult.success, isTrue,
          reason: 'Public deleteScale should succeed: ${deleteResult.error}');

      entity.disconnect();
      expect(entity.isConnected(), isFalse);
    });

    test(
        'public facade routes theme, layout, and KV families through native bridge',
        () async {
      final DogPawEntity entity = DogPawEntity('PublicNativeOtherCrudEntity');

      final ConnectionResult connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason: 'Public connect should succeed: ${connectResult.error}');
      await connectResult.handle!.complete();

      final String themeName = uniqueName('public_native_theme');
      final Theme theme = Theme(
        name: themeName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const ThemeData(
          displayName: 'Public Native Theme',
          primaryColor: '#112233',
          secondaryColor: '#223344',
          accentColor: '#334455',
          backgroundColor: '#445566',
        ),
      );

      final Result<bool> createThemeResult = await entity.createTheme(theme);
      expect(createThemeResult.success, isTrue,
          reason:
              'Public createTheme should succeed: ${createThemeResult.error}');

      final Result<Theme?> readThemeResult = await entity.readTheme(
        themeName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readThemeResult.success, isTrue,
          reason: 'Public readTheme should succeed: ${readThemeResult.error}');
      expect(readThemeResult.value, isNotNull);
      expect(readThemeResult.value!.data.displayName,
          equals('Public Native Theme'));

      final Result<bool> setCurrentThemeResult = await entity.setCurrentTheme(
        themeName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(setCurrentThemeResult.success, isTrue,
          reason:
              'Public setCurrentTheme should succeed: ${setCurrentThemeResult.error}');

      final Result<Theme?> currentThemeResult = await entity.readCurrentTheme();
      expect(currentThemeResult.success, isTrue,
          reason:
              'Public readCurrentTheme should succeed: ${currentThemeResult.error}');
      expect(currentThemeResult.value, isNotNull);
      expect(currentThemeResult.value!.name, equals(themeName));

      final String layoutName = uniqueName('public_native_layout');
      final Layout layout = Layout(
        name: layoutName,
        namespaceSelector: const NamespaceSelector.global(),
        spec: const LayoutData(displayName: 'Public Native Layout'),
      );

      final Result<bool> createLayoutResult = await entity.createLayout(layout);
      expect(createLayoutResult.success, isTrue,
          reason:
              'Public createLayout should succeed: ${createLayoutResult.error}');

      final Result<Layout?> readLayoutResult = await entity.readLayout(
        layoutName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readLayoutResult.success, isTrue,
          reason:
              'Public readLayout should succeed: ${readLayoutResult.error}');
      expect(readLayoutResult.value, isNotNull);
      expect(readLayoutResult.value!.data.displayName,
          equals('Public Native Layout'));

      final Result<LayoutStackSnapshot> currentLayoutResult =
          await entity.readLayoutStack();
      expect(currentLayoutResult.success, isTrue,
          reason:
              'Public readLayoutStack should succeed: ${currentLayoutResult.error}');
      expect(currentLayoutResult.value, isNotNull);
      expect(
        currentLayoutResult.value!.entries.any(
          (LayoutStackEntry entry) => entry.layoutRef.name == layoutName,
        ),
        isTrue,
      );

      final String kvName = uniqueName('public_native_kv');
      final KV kv = KV(
        name: kvName,
        namespaceSelector: const NamespaceSelector.global(),
        value: 'public kv value',
      );

      final Result<bool> createKVResult = await entity.createKV(kv);
      expect(createKVResult.success, isTrue,
          reason: 'Public createKV should succeed: ${createKVResult.error}');

      final Result<KV?> readKVResult = await entity.readKV(
        kvName,
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readKVResult.success, isTrue,
          reason: 'Public readKV should succeed: ${readKVResult.error}');
      expect(readKVResult.value, isNotNull);
      expect(readKVResult.value!.value, equals('public kv value'));

      final Result<List<KV>> listKVResult = await entity.listKVs(
        namespaceSelector: const NamespaceSelector.global(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(listKVResult.success, isTrue,
          reason: 'Public listKVs should succeed: ${listKVResult.error}');
      expect(
        listKVResult.value!.any((KV item) => item.name == kvName),
        isTrue,
      );

      final Result<bool> deleteThemeResult = await entity.deleteTheme(
        themeName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(deleteThemeResult.success, isTrue,
          reason:
              'Public deleteTheme should succeed: ${deleteThemeResult.error}');

      final Result<bool> deleteLayoutResult = await entity.deleteLayout(
        layoutName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(deleteLayoutResult.success, isTrue,
          reason:
              'Public deleteLayout should succeed: ${deleteLayoutResult.error}');

      final Result<bool> deleteKVResult = await entity.deleteKV(
        kvName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(deleteKVResult.success, isTrue,
          reason: 'Public deleteKV should succeed: ${deleteKVResult.error}');

      entity.disconnect();
    });

    test(
        'public facade routes current theme/scale and layout-stack subscriptions through native bridge',
        () async {
      final DogPawEntity subscriber =
          DogPawEntity('PublicNativeCurrentSubscriber');
      final DogPawEntity publisher =
          DogPawEntity('PublicNativeCurrentPublisher');

      final ConnectionResult subscriberConnect = await subscriber.connect();
      expect(subscriberConnect.success, isTrue,
          reason:
              'Public current subscriber should connect: ${subscriberConnect.error}');
      await subscriberConnect.handle!.complete();

      final ConnectionResult publisherConnect = await publisher.connect();
      expect(publisherConnect.success, isTrue,
          reason:
              'Public current publisher should connect: ${publisherConnect.error}');
      await publisherConnect.handle!.complete();

      final String themeName = uniqueName('public_native_current_theme');
      final String scaleName = uniqueName('public_native_current_scale');
      final String layoutName = uniqueName('public_native_current_layout');

      final Result<bool> createThemeResult = await publisher.createTheme(
        Theme(
          name: themeName,
          namespaceSelector: const NamespaceSelector.global(),
          spec: const ThemeData(
            displayName: 'Public Current Theme',
            primaryColor: '#121212',
            secondaryColor: '#232323',
            accentColor: '#343434',
            backgroundColor: '#454545',
          ),
        ),
      );
      expect(createThemeResult.success, isTrue,
          reason:
              'Public createTheme for current subscription should succeed: ${createThemeResult.error}');

      final Result<bool> createScaleResult = await publisher.createScale(
        Scale(
          name: scaleName,
          namespaceSelector: const NamespaceSelector.global(),
          spec: const ScaleData(
            displayName: 'Public Current Scale',
            rootNote: 3,
            noteCategories: [1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
          ),
        ),
      );
      expect(createScaleResult.success, isTrue,
          reason:
              'Public createScale for current subscription should succeed: ${createScaleResult.error}');

      final Result<bool> createLayoutResult = await publisher.createLayout(
        Layout(
          name: layoutName,
          namespaceSelector: const NamespaceSelector.global(),
          spec: const LayoutData(displayName: 'Public Current Layout'),
        ),
        addToLayoutStack: false,
      );
      expect(createLayoutResult.success, isTrue,
          reason:
              'Public createLayout for current subscription should succeed: ${createLayoutResult.error}');

      final Completer<Theme> themeNotification = Completer<Theme>();
      final Completer<Scale> scaleNotification = Completer<Scale>();
      final Completer<LayoutStackSnapshot> layoutNotification =
          Completer<LayoutStackSnapshot>();

      final Result<bool> subscribeThemeResult =
          await subscriber.subscribeToCurrentTheme(
        (String notificationType, DataItemRef ref, dynamic theme) {
          if (theme.name == themeName && !themeNotification.isCompleted) {
            themeNotification.complete(theme as Theme);
          }
        },
        includeResolved: true,
        includeSpec: true,
        sendImmediately: false,
      );
      expect(subscribeThemeResult.success, isTrue,
          reason:
              'Public subscribeToCurrentTheme should succeed: ${subscribeThemeResult.error}');

      final Result<bool> subscribeScaleResult =
          await subscriber.subscribeToCurrentScale(
        (String notificationType, DataItemRef ref, dynamic scale) {
          if (scale.name == scaleName && !scaleNotification.isCompleted) {
            scaleNotification.complete(scale as Scale);
          }
        },
        includeResolved: true,
        includeSpec: true,
        sendImmediately: false,
      );
      expect(subscribeScaleResult.success, isTrue,
          reason:
              'Public subscribeToCurrentScale should succeed: ${subscribeScaleResult.error}');

      final Result<bool> subscribeLayoutResult =
          await subscriber.subscribeToLayoutStack(
        (String notificationType, DataItemRef ref,
            LayoutStackSnapshot snapshot) {
          final bool containsLayout = snapshot.entries.any(
            (LayoutStackEntry entry) => entry.layoutRef.name == layoutName,
          );
          if (containsLayout && !layoutNotification.isCompleted) {
            layoutNotification.complete(snapshot);
          }
        },
        includeResolved: true,
        includeSpec: true,
        sendImmediately: false,
      );
      expect(subscribeLayoutResult.success, isTrue,
          reason:
              'Public subscribeToLayoutStack should succeed: ${subscribeLayoutResult.error}');

      final Result<bool> setCurrentThemeResult =
          await publisher.setCurrentTheme(
        themeName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(setCurrentThemeResult.success, isTrue,
          reason:
              'Public setCurrentTheme for current subscription should succeed: ${setCurrentThemeResult.error}');

      final Result<bool> setCurrentScaleResult =
          await publisher.setCurrentScale(
        scaleName,
        namespaceSelector: const NamespaceSelector.global(),
      );
      expect(setCurrentScaleResult.success, isTrue,
          reason:
              'Public setCurrentScale for current subscription should succeed: ${setCurrentScaleResult.error}');

      final Result<String> addLayoutStackEntryResult =
          await publisher.addLayoutStackEntry(
        DataItemRef(
          name: layoutName,
          namespaceSelector: const NamespaceSelector.global(),
        ),
      );
      expect(addLayoutStackEntryResult.success, isTrue,
          reason:
              'Public addLayoutStackEntry for layout stack subscription should succeed: ${addLayoutStackEntryResult.error}');

      final Theme receivedTheme =
          await themeNotification.future.timeout(const Duration(seconds: 2));
      final Scale receivedScale =
          await scaleNotification.future.timeout(const Duration(seconds: 2));
      final LayoutStackSnapshot receivedLayout =
          await layoutNotification.future.timeout(const Duration(seconds: 2));

      expect(receivedTheme.name, equals(themeName));
      expect(receivedScale.name, equals(scaleName));
      expect(
        receivedLayout.entries.any(
          (LayoutStackEntry entry) => entry.layoutRef.name == layoutName,
        ),
        isTrue,
      );

      final Result<bool> unsubscribeThemeResult =
          await subscriber.unsubscribeFromCurrentTheme();
      expect(unsubscribeThemeResult.success, isTrue,
          reason:
              'Public unsubscribeFromCurrentTheme should succeed: ${unsubscribeThemeResult.error}');

      final Result<bool> unsubscribeScaleResult =
          await subscriber.unsubscribeFromCurrentScale();
      expect(unsubscribeScaleResult.success, isTrue,
          reason:
              'Public unsubscribeFromCurrentScale should succeed: ${unsubscribeScaleResult.error}');

      final Result<bool> unsubscribeLayoutResult =
          await subscriber.unsubscribeFromLayoutStack();
      expect(unsubscribeLayoutResult.success, isTrue,
          reason:
              'Public unsubscribeFromLayoutStack should succeed: ${unsubscribeLayoutResult.error}');

      subscriber.disconnect();
      publisher.disconnect();
    });

    test(
        'public facade routes entity lifecycle subscriptions through native bridge',
        () async {
      final DogPawEntity watcher = DogPawEntity('PublicNativeLifecycleWatcher');
      final DogPawEntity subject = DogPawEntity('PublicNativeLifecycleSubject');

      final ConnectionResult watcherConnect = await watcher.connect();
      expect(watcherConnect.success, isTrue,
          reason:
              'Public lifecycle watcher should connect: ${watcherConnect.error}');
      await watcherConnect.handle!.complete();

      final Completer<String> connectedNotification = Completer<String>();
      final Completer<String> disconnectedNotification = Completer<String>();

      final Result<bool> subscribeResult =
          await watcher.subscribeToEntityLifecycle(
        (String notificationType, String entityName) {
          if (entityName == 'PublicNativeLifecycleSubject' &&
              notificationType == 'entity_connected' &&
              !connectedNotification.isCompleted) {
            connectedNotification.complete(entityName);
          }
          if (entityName == 'PublicNativeLifecycleSubject' &&
              notificationType == 'entity_disconnected' &&
              !disconnectedNotification.isCompleted) {
            disconnectedNotification.complete(entityName);
          }
        },
        watchEntityName: 'PublicNativeLifecycleSubject',
        sendImmediately: false,
      );
      expect(subscribeResult.success, isTrue,
          reason:
              'Public subscribeToEntityLifecycle should succeed: ${subscribeResult.error}');

      final ConnectionResult subjectConnect = await subject.connect();
      expect(subjectConnect.success, isTrue,
          reason:
              'Public lifecycle subject should connect: ${subjectConnect.error}');
      await subjectConnect.handle!.complete();

      expect(
        await connectedNotification.future.timeout(const Duration(seconds: 2)),
        equals('PublicNativeLifecycleSubject'),
      );

      subject.disconnect();

      expect(
        await disconnectedNotification.future.timeout(
          const Duration(seconds: 2),
        ),
        equals('PublicNativeLifecycleSubject'),
      );

      final Result<bool> unsubscribeResult =
          await watcher.unsubscribeFromEntityLifecycle(
        watchEntityName: 'PublicNativeLifecycleSubject',
      );
      expect(unsubscribeResult.success, isTrue,
          reason:
              'Public unsubscribeFromEntityLifecycle should succeed: ${unsubscribeResult.error}');

      watcher.disconnect();
    });

    test(
        'public facade delivers native error callbacks from native connect errors',
        skip:
            'FFI_BRIDGE_PORT_PENDING: serverUrl override for error-induction no longer exposed on the constructor; needs a new mechanism for simulating native connect failures',
        () async {
      final DogPawEntity entity =
          DogPawEntity('PublicNativeErrorCallbackEntity');
      final Completer<String> errorNotification = Completer<String>();
      entity.setErrorCallback((String error) {
        if (!errorNotification.isCompleted) {
          errorNotification.complete(error);
        }
      });

      final ConnectionResult connectResult = await entity.connect();
      expect(connectResult.success, isFalse);

      final String errorMessage = await errorNotification.future.timeout(
        const Duration(seconds: 3),
      );
      expect(
          errorMessage, contains('Failed to create connection to server URL'));
    });

    test('public facade routes preset requests through native bridge',
        () async {
      final DogPawEntity controller =
          DogPawEntity('PublicNativePresetController');
      final DogPawEntity target = DogPawEntity('PublicNativePresetTarget');

      final ConnectionResult controllerConnect = await controller.connect();
      expect(controllerConnect.success, isTrue,
          reason:
              'Public preset controller should connect: ${controllerConnect.error}');
      await controllerConnect.handle!.complete();

      final ConnectionResult targetConnect = await target.connect();
      expect(targetConnect.success, isTrue,
          reason:
              'Public preset target should connect: ${targetConnect.error}');
      await targetConnect.handle!.complete();

      final String presetName = uniqueName('public_native_preset');
      final Completer<String> saveRequestType = Completer<String>();
      final Completer<String> loadRequestType = Completer<String>();
      final Completer<String> deferredLoadCompletion = Completer<String>();
      bool firstRequest = true;

      target.setPresetRequestCallback(
          (String serverRequestId, Map<String, dynamic> content) async {
        final String requestType = content['requestType'] as String? ?? '';
        if (firstRequest) {
          firstRequest = false;
          if (!saveRequestType.isCompleted) {
            saveRequestType.complete(requestType);
          }
          return true;
        }

        if (!loadRequestType.isCompleted) {
          loadRequestType.complete(requestType);
        }
        Future<void>.delayed(const Duration(milliseconds: 50), () async {
          await target.completePresetRequest(serverRequestId, success: true);
          if (!deferredLoadCompletion.isCompleted) {
            deferredLoadCompletion.complete(serverRequestId);
          }
        });
        return false;
      });

      final Result<bool> saveResult =
          await controller.saveGlobalState(presetName);
      expect(saveResult.success, isTrue,
          reason: 'Public saveGlobalState should succeed: ${saveResult.error}');
      expect(
        await saveRequestType.future.timeout(const Duration(seconds: 2)),
        equals('save'),
      );

      final Result<bool> loadResult =
          await controller.loadGlobalState(presetName);
      expect(loadResult.success, isTrue,
          reason: 'Public loadGlobalState should succeed: ${loadResult.error}');
      expect(
        await loadRequestType.future.timeout(const Duration(seconds: 2)),
        equals('load'),
      );
      expect(
        await deferredLoadCompletion.future.timeout(const Duration(seconds: 2)),
        isNotEmpty,
      );

      controller.disconnect();
      target.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    test('public facade routes supported utility methods through native bridge',
        () async {
      final DogPawEntity entity = DogPawEntity('PublicNativeUtilityEntity');

      final ConnectionResult connectResult = await entity.connect();
      expect(connectResult.success, isTrue,
          reason:
              'Public utility entity should connect: ${connectResult.error}');
      await connectResult.handle!.complete();

      final Result<bool> startLogSectionResult =
          await entity.startLogSection('PublicNativeUtilitySection');
      expect(startLogSectionResult.success, isTrue,
          reason:
              'Public startLogSection should succeed: ${startLogSectionResult.error}');

      final Result<bool> logResult =
          await entity.log('Public native utility log message');
      expect(logResult.success, isTrue,
          reason: 'Public log should succeed: ${logResult.error}');

      final Result<bool> flushLogSectionResult = await entity.flushLogSection();
      expect(flushLogSectionResult.success, isTrue,
          reason:
              'Public flushLogSection should succeed: ${flushLogSectionResult.error}');

      final Result<bool> endLogSectionResult = await entity.endLogSection();
      expect(endLogSectionResult.success, isTrue,
          reason:
              'Public endLogSection should succeed: ${endLogSectionResult.error}');

      final Result<Map<String, dynamic>> systemInfoResult =
          await entity.getSystemInfo();
      expect(systemInfoResult.success, isTrue,
          reason:
              'Public getSystemInfo should succeed: ${systemInfoResult.error}');
      expect(systemInfoResult.value, isNotNull);
      expect(
        systemInfoResult.value![JsonFields.MESSAGE],
        contains('Debug system info printed to log'),
      );

      entity.disconnect();
    });
  });
}
