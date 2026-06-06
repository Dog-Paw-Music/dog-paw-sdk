import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const String _internalBuildDirMarker = 'build' '-native';
const String _internalHeadlessAppsMarker = 'headless' 'Apps/';
const String _internalTestingMarker = 'testing' '/';

void main() {
  group('dogpaw_test portable public contract', () {
    late String packageRoot;

    setUp(() {
      packageRoot = Directory.current.path;
    });

    test('README teaches portable staged-install setup', () {
      final String readme = File(path.join(packageRoot, 'README.md'))
          .readAsStringSync();

      expect(readme, isNot(contains(_internalBuildDirMarker)));
      expect(readme, isNot(contains(_internalHeadlessAppsMarker)));
      expect(readme, isNot(contains(_internalTestingMarker)));
      expect(readme, contains('buildLaunchTestStubInstallSource'));
      expect(readme, contains('EPIPHANY_PATH'));
    });

    test('integration fixture source stays portable for exported SDKs', () {
      final String source = File(
        path.join(packageRoot, 'lib', 'src', 'integration_test_fixture.dart'),
      ).readAsStringSync();

      expect(source, isNot(contains(_internalBuildDirMarker)));
      expect(source, isNot(contains(_internalHeadlessAppsMarker)));
    });

    test('staged install integration test uses package-owned portable fixture',
        () {
      final String source = File(
        path.join(
          packageRoot,
          'test',
          'integration',
          'staged_install_launch_test.dart',
        ),
      ).readAsStringSync();

      expect(source, isNot(contains(_internalBuildDirMarker)));
      expect(source, isNot(contains(_internalHeadlessAppsMarker)));
      expect(source, isNot(contains('../../..')));
      expect(source, contains('buildLaunchTestStubInstallSource'));
    });
  });
}
