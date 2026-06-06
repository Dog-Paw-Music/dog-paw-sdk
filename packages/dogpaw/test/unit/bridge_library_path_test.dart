import 'dart:io';

import 'package:dogpaw/src/ffi/native_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('bridge library path resolution', () {
    test('resolveBridgeLibraryPath prefers explicit DOGPAW_BRIDGE_LIB', () {
      final String resolved = resolveBridgeLibraryPath(
        environment: const <String, String>{
          'DOGPAW_BRIDGE_LIB': '/tmp/custom/libdogpaw_bridge.so',
        },
        resolvedExecutablePath: '/tmp/runtime/demo_layout',
      );

      expect(resolved, '/tmp/custom/libdogpaw_bridge.so');
    });

    test('resolveBridgeLibraryPath uses bundle-local bridge library', () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_bridge_path_',
      );

      try {
        final String bundleDirectory = path.join(tempRoot.path, 'demo_layout');
        final String executablePath = path.join(bundleDirectory, 'demo_layout');
        final String bridgePath =
            path.join(bundleDirectory, 'lib', 'libdogpaw_bridge.so');
        await Directory(path.dirname(bridgePath)).create(recursive: true);
        await File(executablePath).create(recursive: true);
        await File(bridgePath).writeAsString('bridge');

        final String resolved = resolveBridgeLibraryPath(
          environment: const <String, String>{},
          resolvedExecutablePath: executablePath,
        );

        expect(resolved, bridgePath);
      } finally {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    });
  });
}
