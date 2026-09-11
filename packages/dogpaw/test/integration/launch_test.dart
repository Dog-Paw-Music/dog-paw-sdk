import 'dart:async';

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:test/test.dart';

const String _entityConnectedNotification = 'entity_connected';

Future<void> main() async {
  final DogpawAppInstallSource launchTestStub =
      await buildLaunchTestStubInstallSource();

  IntegrationTestFixture.register(
    configuration: DogpawIntegrationTestConfiguration(
      installedApps: <DogpawAppInstallSource>[launchTestStub],
    ),
  );

  group('App Launch Integration', () {
    test('LaunchAppPassesMetadataToHeadlessStub', () async {
      final controller = DogPawEntity(uniqueName('LaunchMetadataController'));
      final connectResult = await controller.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);

      final launchResult = await controller.launchApp(
        'launch_test_stub',
        launchMetadata: <String, dynamic>{
          'preset': 'alpha',
          'zoneId': 'zone_left',
        },
      );
      expect(launchResult.success, isTrue, reason: launchResult.error);
      expect(launchResult.value, isNotNull);

      final launchedEntityName = launchResult.value!;
      expect(launchedEntityName, startsWith('launch_test_stub_'));

      final Completer<void> entityConnectedCompleter = Completer<void>();
      final subscribeResult = await controller.subscribeToEntityLifecycle(
        (notificationType, entityName) {
          if (!entityConnectedCompleter.isCompleted &&
              notificationType == _entityConnectedNotification &&
              entityName == launchedEntityName) {
            entityConnectedCompleter.complete();
          }
        },
        watchEntityName: launchedEntityName,
        sendImmediately: true,
      );
      expect(subscribeResult.success, isTrue, reason: subscribeResult.error);

      await entityConnectedCompleter.future.timeout(const Duration(seconds: 5));

      final metadataResult = await controller.sendCommand(
        launchedEntityName,
        'get_launch_metadata',
      );
      expect(metadataResult.success, isTrue, reason: metadataResult.error);
      expect(
          metadataResult.result['launchMetadata'], isA<Map<String, dynamic>>());

      final launchMetadata =
          metadataResult.result['launchMetadata'] as Map<String, dynamic>;
      expect(launchMetadata['preset'], equals('alpha'));
      expect(launchMetadata['zoneId'], equals('zone_left'));

      final stopResult = await controller.stopApp(launchedEntityName);
      expect(stopResult.success, isTrue, reason: stopResult.error);
      final unsubscribeResult = await controller.unsubscribeFromEntityLifecycle(
        watchEntityName: launchedEntityName,
      );
      expect(unsubscribeResult.success, isTrue,
          reason: unsubscribeResult.error);

      controller.disconnect();
    });

    test('LaunchAppPassesDisplayNameToRunningEntityList', () async {
      final controller = DogPawEntity(uniqueName('LaunchDisplayNameController'));
      final connectResult = await controller.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);

      final launchResult = await controller.launchApp(
        'launch_test_stub',
        displayName: 'Phase2 Dart Display',
      );
      expect(launchResult.success, isTrue, reason: launchResult.error);
      expect(launchResult.value, isNotNull);

      final launchedEntityName = launchResult.value!;
      final listResult = await controller.listRunningEntities();
      expect(listResult.success, isTrue, reason: listResult.error);

      final List<dynamic> entities =
          listResult.value![JsonFields.ENTITIES] as List<dynamic>;
      final Map<String, dynamic> match = entities
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (Map<String, dynamic> entity) =>
                entity[JsonFields.ENTITY_NAME] == launchedEntityName,
          );
      expect(match[JsonFields.DISPLAY_NAME], equals('Phase2 Dart Display'));

      final stopResult = await controller.stopApp(launchedEntityName);
      expect(stopResult.success, isTrue, reason: stopResult.error);
      controller.disconnect();
    });
  });
}
