import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:test/test.dart';

import '../test_support.dart';

Future<void> main() async {
  final DogpawAppInstallSource launchTestStub =
      await buildLaunchTestStubInstallSource();

  IntegrationTestFixture.register(
    configuration: DogpawIntegrationTestConfiguration(
      installedApps: <DogpawAppInstallSource>[launchTestStub],
    ),
  );

  group('Running Entity List Integration', () {
    test('listRunningEntities returns launched runtime entities with app names',
        () async {
      final DogPawEntity controller =
          DogPawEntity(uniqueName('RunningEntityListController'));
      final ConnectionResult connectResult = await controller.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);
      await connectResult.handle!.complete();

      final Result<String> launchResult =
          await controller.launchApp('launch_test_stub');
      expect(launchResult.success, isTrue, reason: launchResult.error);
      final String launchedEntityName = launchResult.value!;

      final Result<Map<String, dynamic>> runningEntitiesResult =
          await controller.listRunningEntities();
      expect(runningEntitiesResult.success, isTrue,
          reason: runningEntitiesResult.error);

      final List<dynamic> entities = List<dynamic>.from(
        runningEntitiesResult.value![JsonFields.ENTITIES] as List<dynamic>,
      );
      final Map<String, dynamic> launchedEntity = Map<String, dynamic>.from(
        entities.firstWhere(
          (dynamic candidate) =>
              candidate is Map<String, dynamic> &&
              candidate[JsonFields.ENTITY_NAME] == launchedEntityName,
        ) as Map,
      );

      expect(
        launchedEntity[JsonFields.RUNTIME_APP_NAME],
        equals('launch_test_stub'),
      );
      expect(launchedEntity[JsonFields.DISPLAY_NAME], isNotEmpty);

      final Result<bool> stopResult = await controller.stopApp(launchedEntityName);
      expect(stopResult.success, isTrue, reason: stopResult.error);

      controller.disconnect();
    });
  });
}
