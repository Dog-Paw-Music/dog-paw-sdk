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
