import 'dart:io';

import 'package:dogpaw_test/src/package_runtime_paths.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const String _internalBuildDirMarker = 'build' '-native';

void main() {
  group('dogpaw_test Epiphany path resolution', () {
    test('explicit path is preferred over environment and SDK runtime paths', () {
      final List<String> searchPaths = buildEpiphanyBinarySearchPaths(
        explicitPath: '/tmp/explicit/Epiphany',
        environment: const <String, String>{
          'EPIPHANY_PATH': '/tmp/env/Epiphany',
        },
        packageRootPath: '/tmp/sdk/packages/dogpaw_test',
      );

      expect(searchPaths.first, '/tmp/explicit/Epiphany');
      expect(searchPaths[1], '/tmp/env/Epiphany');
    });

    test('includes SDK runtime Epiphany beside exported packages', () {
      final List<String> searchPaths = buildEpiphanyBinarySearchPaths(
        explicitPath: null,
        environment: const <String, String>{},
        packageRootPath: '/tmp/sdk/packages/dogpaw_test',
      );

      expect(
        searchPaths,
        contains('/tmp/sdk/runtime/bin/linux-x64/Epiphany'),
      );
    });

    test('does not fall back to internal monorepo build directories', () {
      final List<String> searchPaths = buildEpiphanyBinarySearchPaths(
        explicitPath: null,
        environment: const <String, String>{},
        packageRootPath: '/tmp/sdk/packages/dogpaw_test',
      );

      expect(
        searchPaths.where(
          (String candidate) => candidate.contains(_internalBuildDirMarker),
        ),
        isEmpty,
      );
      expect(
        searchPaths.where((String candidate) => candidate.endsWith('/build/bin/Epiphany')),
        isEmpty,
      );
    });

    test('includes source checkout build-output candidates for manual repo runs',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_test_source_epiphany_paths_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final String packageRootPath = path.join(
        tempRoot.path,
        'tree',
        'apps',
        'packages',
        'dogpaw_test',
      );
      final String localBuildBinaryPath = path.join(
        tempRoot.path,
        'tree',
        'build_local',
        'bin',
        'Epiphany',
      );
      await Directory(packageRootPath).create(recursive: true);
      await Directory(path.dirname(localBuildBinaryPath)).create(recursive: true);

      final List<String> searchPaths = buildEpiphanyBinarySearchPaths(
        explicitPath: null,
        environment: const <String, String>{},
        packageRootPath: packageRootPath,
      );

      expect(searchPaths, contains(localBuildBinaryPath));
    });

    test('resolveEpiphanyBinaryPath returns first existing SDK runtime binary',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_test_epiphany_paths_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final String packageRootPath =
          path.join(tempRoot.path, 'sdk', 'packages', 'dogpaw_test');
      final String runtimeBinaryPath = path.join(
        tempRoot.path,
        'sdk',
        'runtime',
        'bin',
        'linux-x64',
        'Epiphany',
      );
      await Directory(packageRootPath).create(recursive: true);
      await Directory(path.dirname(runtimeBinaryPath)).create(recursive: true);
      await File(runtimeBinaryPath).writeAsString('epiphany');

      final String? resolved = resolveEpiphanyBinaryPath(
        explicitPath: null,
        environment: const <String, String>{},
        packageRootPath: packageRootPath,
      );

      expect(resolved, runtimeBinaryPath);
    });

    test(
        'resolveEpiphanyBinaryPath returns source checkout build binary when SDK runtime is absent',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_test_source_epiphany_resolve_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final String packageRootPath = path.join(
        tempRoot.path,
        'tree',
        'apps',
        'packages',
        'dogpaw_test',
      );
      final String localBuildBinaryPath = path.join(
        tempRoot.path,
        'tree',
        'build_local',
        'bin',
        'Epiphany',
      );
      await Directory(packageRootPath).create(recursive: true);
      await Directory(path.dirname(localBuildBinaryPath)).create(recursive: true);
      await File(localBuildBinaryPath).writeAsString('epiphany');

      final String? resolved = resolveEpiphanyBinaryPath(
        explicitPath: null,
        environment: const <String, String>{},
        packageRootPath: packageRootPath,
      );

      expect(resolved, localBuildBinaryPath);
    });

    test(
        'source checkout resolution prefers more specific build directories over plain build',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_test_source_epiphany_priority_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final String packageRootPath = path.join(
        tempRoot.path,
        'tree',
        'apps',
        'packages',
        'dogpaw_test',
      );
      final String genericBuildBinaryPath = path.join(
        tempRoot.path,
        'tree',
        'build',
        'bin',
        'Epiphany',
      );
      final String specificBuildBinaryPath = path.join(
        tempRoot.path,
        'tree',
        'build_local',
        'bin',
        'Epiphany',
      );
      await Directory(packageRootPath).create(recursive: true);
      await Directory(path.dirname(genericBuildBinaryPath)).create(
        recursive: true,
      );
      await Directory(path.dirname(specificBuildBinaryPath)).create(
        recursive: true,
      );
      await File(genericBuildBinaryPath).writeAsString('epiphany');
      await File(specificBuildBinaryPath).writeAsString('epiphany');

      final String? resolved = resolveEpiphanyBinaryPath(
        explicitPath: null,
        environment: const <String, String>{},
        packageRootPath: packageRootPath,
      );

      expect(resolved, specificBuildBinaryPath);
    });
  });

  group('dogpaw_test bridge path resolution', () {
    test('explicit bridge path is preferred over package-owned defaults', () {
      final List<String> searchPaths = buildBridgeLibrarySearchPaths(
        environment: const <String, String>{
          'DOGPAW_BRIDGE_LIB': '/tmp/custom/libdogpaw_bridge.so',
        },
        dogpawTestPackageRootPath: '/tmp/sdk/packages/dogpaw_test',
        dogpawPackageRootPath: '/tmp/sdk/packages/dogpaw',
      );

      expect(searchPaths.first, '/tmp/custom/libdogpaw_bridge.so');
    });

    test('includes dogpaw package prebuilt bridge library', () {
      final List<String> searchPaths = buildBridgeLibrarySearchPaths(
        environment: const <String, String>{},
        dogpawTestPackageRootPath: '/tmp/sdk/packages/dogpaw_test',
        dogpawPackageRootPath: '/tmp/sdk/packages/dogpaw',
      );

      expect(
        searchPaths,
        contains('/tmp/sdk/packages/dogpaw/linux/prebuilt/linux-x64/libdogpaw_bridge.so'),
      );
    });

    test('resolveBridgeLibraryPathForFixture returns package prebuilt bridge',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_test_bridge_paths_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final String dogpawTestPackageRootPath = path.join(
        tempRoot.path,
        'sdk',
        'packages',
        'dogpaw_test',
      );
      final String dogpawPackageRootPath = path.join(
        tempRoot.path,
        'sdk',
        'packages',
        'dogpaw',
      );
      final String bridgePath = path.join(
        dogpawPackageRootPath,
        'linux',
        'prebuilt',
        'linux-x64',
        'libdogpaw_bridge.so',
      );
      await Directory(dogpawTestPackageRootPath).create(recursive: true);
      await Directory(path.dirname(bridgePath)).create(recursive: true);
      await File(bridgePath).writeAsString('bridge');

      final String? resolved = resolveBridgeLibraryPathForFixture(
        environment: const <String, String>{},
        dogpawTestPackageRootPath: dogpawTestPackageRootPath,
        dogpawPackageRootPath: dogpawPackageRootPath,
      );

      expect(resolved, bridgePath);
    });

    test(
        'resolveBridgeLibraryPathForFixture falls back to source checkout build outputs when package prebuilt is absent',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_test_source_bridge_paths_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final String dogpawTestPackageRootPath = path.join(
        tempRoot.path,
        'tree',
        'apps',
        'packages',
        'dogpaw_test',
      );
      final String dogpawPackageRootPath = path.join(
        tempRoot.path,
        'tree',
        'apps',
        'packages',
        'dogpaw',
      );
      final String bridgePath = path.join(
        tempRoot.path,
        'tree',
        'build_local',
        'lib',
        'libdogpaw_bridge.so',
      );
      await Directory(dogpawTestPackageRootPath).create(recursive: true);
      await Directory(dogpawPackageRootPath).create(recursive: true);
      await Directory(path.dirname(bridgePath)).create(recursive: true);
      await File(bridgePath).writeAsString('bridge');

      final String? resolved = resolveBridgeLibraryPathForFixture(
        environment: const <String, String>{},
        dogpawTestPackageRootPath: dogpawTestPackageRootPath,
        dogpawPackageRootPath: dogpawPackageRootPath,
      );

      expect(resolved, bridgePath);
    });

    test(
        'resolveBridgeLibraryPathForFixture ignores non-host package prebuilt before source build fallback',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_test_source_bridge_arch_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final String dogpawTestPackageRootPath = path.join(
        tempRoot.path,
        'tree',
        'apps',
        'packages',
        'dogpaw_test',
      );
      final String dogpawPackageRootPath = path.join(
        tempRoot.path,
        'tree',
        'apps',
        'packages',
        'dogpaw',
      );
      final String nonHostPrebuiltPath = path.join(
        dogpawPackageRootPath,
        'linux',
        'prebuilt',
        'linux-arm64',
        'libdogpaw_bridge.so',
      );
      final String sourceBuildBridgePath = path.join(
        tempRoot.path,
        'tree',
        'build_local',
        'lib',
        'libdogpaw_bridge.so',
      );
      await Directory(dogpawTestPackageRootPath).create(recursive: true);
      await Directory(path.dirname(nonHostPrebuiltPath)).create(recursive: true);
      await Directory(path.dirname(sourceBuildBridgePath))
          .create(recursive: true);
      await File(nonHostPrebuiltPath).writeAsString('wrong architecture');
      await File(sourceBuildBridgePath).writeAsString('host bridge');

      final String? resolved = resolveBridgeLibraryPathForFixture(
        environment: const <String, String>{},
        dogpawTestPackageRootPath: dogpawTestPackageRootPath,
        dogpawPackageRootPath: dogpawPackageRootPath,
      );

      expect(resolved, sourceBuildBridgePath);
    });
  });
}
