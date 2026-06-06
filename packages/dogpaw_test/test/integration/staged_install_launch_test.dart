import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw_test/dogpaw_test.dart';
import 'package:test/test.dart';

Future<void> main() async {
  final DogpawAppInstallSource launchTestStub =
      await buildLaunchTestStubInstallSource();

  IntegrationTestFixture.register(
    configuration: DogpawIntegrationTestConfiguration(
      installedApps: <DogpawAppInstallSource>[
        launchTestStub,
      ],
    ),
  );

  group('staged installed app launch', () {
    test('launches the staged stub app through Epiphany', () async {
      final controller =
          DogPawEntity(uniqueName('DogpawTestInstalledLaunchController'));
      final connectResult = await controller.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);

      final launchResult = await controller.launchApp('launch_test_stub');
      expect(launchResult.success, isTrue, reason: launchResult.error);
      expect(launchResult.value, isNotNull);

      final stopResult = await controller.stopApp(launchResult.value!);
      expect(stopResult.success, isTrue, reason: stopResult.error);

      controller.disconnect();
    });
  });
}
