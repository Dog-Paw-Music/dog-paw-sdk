import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const String _internalDartTestInfrastructureDependency =
    'dart_test_infrastructure:';
const String _publicDogpawTestDependency = 'dogpaw_test:';
const String _internalDartTestInfrastructureImport =
    'package:dart_test_' 'infrastructure/dart_test_infrastructure.dart';
const String _internalBuildDirMarker = 'build' '-native';

void main() {
  group('dogpaw test portability contract', () {
    late String packageRoot;

    setUp(() {
      packageRoot = Directory.current.path;
    });

    test('pubspec uses dogpaw_test and not internal dart test infrastructure', () {
      final String pubspec = File(path.join(packageRoot, 'pubspec.yaml'))
          .readAsStringSync();

      expect(pubspec, contains(_publicDogpawTestDependency));
      expect(pubspec, isNot(contains(_internalDartTestInfrastructureDependency)));
    });

    test('package owns local TestEntities helper under test support', () {
      final File helperFile = File(
        path.join(packageRoot, 'test', 'support', 'test_entities.dart'),
      );

      expect(helperFile.existsSync(), isTrue);
    });

    test('local test support is a thin barrel over public fixtures', () {
      final String supportSource = File(
        path.join(packageRoot, 'test', 'test_support.dart'),
      ).readAsStringSync();

      expect(supportSource, contains("export 'package:dogpaw_test/dogpaw_test.dart';"));
      expect(supportSource, contains("export 'support/test_entities.dart';"));
      expect(supportSource, isNot(contains('DOGPAW_BRIDGE_LIB')));
      expect(supportSource, isNot(contains(_internalBuildDirMarker)));
      expect(supportSource, isNot(contains('native_bridge.dart')));
      expect(supportSource, isNot(contains('class IntegrationTestFixture')));
    });

    test('launch-oriented tests use package-owned staged install source', () {
      final List<String> stagedLaunchTests = <String>[
        path.join(packageRoot, 'test', 'integration', 'launch_test.dart'),
        path.join(packageRoot, 'test', 'integration', 'command_test.dart'),
        path.join(packageRoot, 'test', 'lifecycle', 'lifecycle_test.dart'),
      ];

      for (final String testPath in stagedLaunchTests) {
        final String source = File(testPath).readAsStringSync();
        expect(source, contains('buildLaunchTestStubInstallSource'));
      }
    });

    test('test tree does not import the internal dart test package', () {
      final Directory testRoot = Directory(path.join(packageRoot, 'test'));
      final List<File> dartFiles = testRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => path.extension(file.path) == '.dart')
          .toList();

      for (final File dartFile in dartFiles) {
        final String source = dartFile.readAsStringSync();
        expect(
          source,
          isNot(contains(_internalDartTestInfrastructureImport)),
          reason: 'internal import found in ${path.relative(dartFile.path, from: packageRoot)}',
        );
      }
    });
  });
}
