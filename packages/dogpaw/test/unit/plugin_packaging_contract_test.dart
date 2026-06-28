import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('dogpaw plugin packaging contract', () {
    test('pubspec declares dogpaw as a linux ffi plugin', () {
      final File pubspecFile = File(
        path.join(
          Directory.current.path,
          'pubspec.yaml',
        ),
      );
      final String pubspec = pubspecFile.readAsStringSync();

      expect(pubspec, contains('plugin:'));
      expect(pubspec, contains('linux:'));
      expect(pubspec, contains('ffiPlugin: true'));
    });

    test('linux cmake supports repo-local bridge provider override', () {
      final File cmakeFile = File(
        path.join(
          Directory.current.path,
          'linux',
          'CMakeLists.txt',
        ),
      );
      final String cmake = cmakeFile.readAsStringSync();

      expect(cmake, contains('set(dogpaw_bundled_libraries'));
      expect(cmake, contains('local_bridge_provider.cmake'));
      expect(cmake, isNot(contains('set(BINARY_NAME "dogpaw")')));
    });

    test('repo-local bridge provider stages a concrete bundle library file', () {
      final File localProviderFile = File(
        path.join(
          Directory.current.path,
          'linux',
          'local_bridge_provider.cmake',
        ),
      );
      if (!localProviderFile.existsSync()) {
        return;
      }

      final String localProvider = localProviderFile.readAsStringSync();

      expect(localProvider, contains('REALPATH'));
      expect(localProvider, contains('copy_if_different'));
      expect(localProvider, contains('dogpaw_local_bridge_bundle'));
      expect(localProvider, contains('libdogpaw_bridge.so'));
      expect(localProvider, contains('DOGPAW_HAS_REPO_LOCAL_RPI_PROJECT'));
      expect(localProvider, contains('CMakePresets.json'));
      expect(
        localProvider,
        contains('uiApps/tools/dogpaw_bridge/CMakeLists.txt'),
      );
      expect(localProvider, contains('linux/prebuilt'));
      expect(
        localProvider,
        contains(
          'add_custom_target(dogpaw_local_bridge_bundle ALL',
        ),
      );
      expect(
        localProvider,
        contains(
          r'COMMAND "${CMAKE_COMMAND}" -P "${DOGPAW_LOCAL_BRIDGE_STAGE_SCRIPT}"',
        ),
      );
    });

    test('rpi cmake presets declare explicit bridge prebuilt ABI', () {
      final String packageRoot = Directory.current.path;
      final File presetsFile = File(
        path.normalize(path.join(packageRoot, '..', '..', '..', 'CMakePresets.json')),
      );
      final Map<String, dynamic> presets = jsonDecode(
        presetsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
      final List<dynamic> configurePresets =
          presets['configurePresets'] as List<dynamic>;

      Map<String, dynamic> presetNamed(String name) {
        return configurePresets.cast<Map<String, dynamic>>().firstWhere(
              (Map<String, dynamic> preset) => preset['name'] == name,
            );
      }

      final Map<String, dynamic> nativeCache =
          presetNamed('rpi-native-base')['cacheVariables'] as Map<String, dynamic>;
      final Map<String, dynamic> armCache =
          presetNamed('rpi-arm-base')['cacheVariables'] as Map<String, dynamic>;

      expect(nativeCache['DOGPAW_BRIDGE_PREBUILT_ABI'], 'linux-x64');
      expect(armCache['DOGPAW_BRIDGE_PREBUILT_ABI'], 'linux-arm64');
    });

    test('dogpaw bridge publisher uses explicit prebuilt ABI variable', () {
      final String packageRoot = Directory.current.path;
      final File bridgeCMakeFile = File(
        path.normalize(path.join(
          packageRoot,
          '..',
          '..',
          'tools',
          'dogpaw_bridge',
          'CMakeLists.txt',
        )),
      );
      final String cmake = bridgeCMakeFile.readAsStringSync();

      expect(cmake, contains('DOGPAW_BRIDGE_PREBUILT_ABI'));
      expect(cmake, isNot(contains('CMAKE_SYSTEM_PROCESSOR')));
    });

    test('source package keeps repo-local bridge helper out of exported src build files', () {
      final String packageRoot = Directory.current.path;
      final bool hasLocalHelper = File(
        path.join(packageRoot, 'linux', 'local_bridge_provider.cmake'),
      ).existsSync();

      expect(
        File(path.join(packageRoot, 'src', 'CMakeLists.txt')).existsSync(),
        isFalse,
      );
      if (hasLocalHelper) {
        expect(hasLocalHelper, isTrue);
      } else {
        expect(
          File(
            path.join(
              packageRoot,
              'linux',
              'prebuilt',
              'linux-x64',
              'libdogpaw_bridge.so',
            ),
          ).existsSync(),
          isTrue,
        );
        expect(
          File(
            path.join(
              packageRoot,
              'linux',
              'prebuilt',
              'linux-arm64',
              'libdogpaw_bridge.so',
            ),
          ).existsSync(),
          isTrue,
        );
      }
    });
  });
}
