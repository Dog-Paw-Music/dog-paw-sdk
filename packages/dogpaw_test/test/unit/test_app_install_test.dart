import 'dart:convert';
import 'dart:io';

import 'package:dogpaw_test/dogpaw_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stageInstalledDogpawApps', () {
    late Directory tempRoot;
    late Directory sourceAppDir;
    late Directory bundleDir;
    late Directory appRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('dogpaw_test_stage_');
      sourceAppDir = Directory('${tempRoot.path}/source_app')..createSync();
      bundleDir = Directory('${tempRoot.path}/bundle')..createSync();
      appRoot = Directory('${tempRoot.path}/installed_apps')..createSync();

      File('${sourceAppDir.path}/dogpawapp.json').writeAsStringSync(
        jsonEncode(<String, Object?>{
          'name': 'sample_app',
          'displayName': 'Sample App',
          'type': 'headless',
          'visible': 'never',
          'instancePolicy': 'multi_instance',
          'executable': 'SampleBinary',
          'install': <String, Object?>{
            'assets': <String>['config/defaults.json'],
          },
        }),
      );

      Directory('${sourceAppDir.path}/config').createSync();
      File('${sourceAppDir.path}/config/defaults.json').writeAsStringSync(
        '{"mode":"test"}',
      );

      File('${bundleDir.path}/SampleBinary').writeAsStringSync('binary');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    test('copies manifest bundle and declared assets into installed layout',
        () {
      final staged = stageInstalledDogpawApps(
        appRootPath: appRoot.path,
        apps: <DogpawAppInstallSource>[
          DogpawAppInstallSource.bundle(
            manifestPath: '${sourceAppDir.path}/dogpawapp.json',
            bundlePath: bundleDir.path,
          ),
        ],
      );

      expect(staged, hasLength(1));
      final installedApp = Directory('${appRoot.path}/sample_app');
      expect(installedApp.existsSync(), isTrue);
      expect(File('${installedApp.path}/dogpawapp.json').existsSync(), isTrue);
      expect(File('${installedApp.path}/bundle/SampleBinary').existsSync(),
          isTrue);
      expect(
        File('${installedApp.path}/assets/config/defaults.json').existsSync(),
        isTrue,
      );
    });

    test('builds a package-owned launch test stub install source', () async {
      final DogpawAppInstallSource installSource =
          await buildLaunchTestStubInstallSource();

      expect(File(installSource.manifestPath).existsSync(), isTrue);
      expect(installSource.binaryPath, isNotNull);
      expect(File(installSource.binaryPath!).existsSync(), isTrue);
      expect(installSource.bundlePath, isNull);

      final manifest = jsonDecode(
        File(installSource.manifestPath).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifest['name'], 'launch_test_stub');
    });
  });
}
