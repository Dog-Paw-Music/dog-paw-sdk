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

    test('linux cmake consumes bundled dogpaw bridge library artifacts', () {
      final File cmakeFile = File(
        path.join(
          Directory.current.path,
          'linux',
          'CMakeLists.txt',
        ),
      );
      final String cmake = cmakeFile.readAsStringSync();

      expect(cmake, contains('set(dogpaw_bundled_libraries'));
      expect(cmake, contains('prebuilt")'));
      expect(cmake, contains('linux-x64/libdogpaw_bridge.so'));
      expect(cmake, contains('linux-arm64/libdogpaw_bridge.so'));
      expect(cmake, isNot(contains('local_bridge_provider.cmake')));
      expect(cmake, isNot(contains('set(BINARY_NAME "dogpaw")')));
    });

    test('package includes prebuilt bridge artifacts and omits repo-local build files', () {
      final String packageRoot = Directory.current.path;

      expect(
        File(path.join(packageRoot, 'linux', 'local_bridge_provider.cmake'))
            .existsSync(),
        isFalse,
      );
      expect(
        File(path.join(packageRoot, 'src', 'CMakeLists.txt')).existsSync(),
        isFalse,
      );
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
    });
  });
}
