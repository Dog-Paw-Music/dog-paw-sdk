import 'dart:io';

import 'package:dogpaw/dogpaw.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('public path utils contract', () {
    test('package path helpers do not ship repo-root fallbacks', () {
      final String packageRoot = Directory.current.path;
      final String pathUtilsSource = File(
        path.join(packageRoot, 'lib', 'src', 'path_utils.dart'),
      ).readAsStringSync();

      expect(pathUtilsSource, isNot(contains('String getRepoRoot(')));
      expect(pathUtilsSource, isNot(contains("'/workspace'")));
      expect(pathUtilsSource, isNot(contains('DOGPAW_REPO_ROOT')));
    });
  });

  group('getFlutterPackageRoot', () {
    test('returns source package root for built app nested under source tree',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_common_path_utils_',
      );

      try {
        final String packageRoot = path.join(
          tempRoot.path,
          'rpi',
          'uiApps',
          'dppController',
          'dpp_controller',
        );
        final String bundleDirectory = path.join(
          packageRoot,
          'build',
          'linux',
          'x64',
          'debug',
          'bundle',
        );
        final String flutterAssetsDirectory = path.join(
          bundleDirectory,
          'data',
          'flutter_assets',
        );

        await Directory(flutterAssetsDirectory).create(recursive: true);
        await File(path.join(packageRoot, 'pubspec.yaml'))
            .writeAsString('name: dpp_controller');
        await File(path.join(bundleDirectory, 'dpp_controller'))
            .writeAsString('');
        await File(path.join(flutterAssetsDirectory, 'kernel_blob.bin'))
            .writeAsString('');

        final String resolvedRoot = getFlutterPackageRoot(
          scriptUri:
              Uri.file(path.join(flutterAssetsDirectory, 'kernel_blob.bin')),
          resolvedExecutablePath: path.join(bundleDirectory, 'dpp_controller'),
          currentWorkingDirectory: tempRoot.path,
        );

        expect(resolvedRoot, equals(packageRoot));
      } finally {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    });

    test('returns source package root for source-run script path', () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_common_path_utils_',
      );

      try {
        final String packageRoot = path.join(tempRoot.path, 'demo_app');
        final String libDirectory = path.join(packageRoot, 'lib');
        await Directory(libDirectory).create(recursive: true);
        await File(path.join(packageRoot, 'pubspec.yaml'))
            .writeAsString('name: demo_app');
        await File(path.join(libDirectory, 'main.dart'))
            .writeAsString('void main() {}');

        final String resolvedRoot = getFlutterPackageRoot(
          scriptUri: Uri.file(path.join(libDirectory, 'main.dart')),
          resolvedExecutablePath: '/usr/bin/dart',
          currentWorkingDirectory: tempRoot.path,
        );

        expect(resolvedRoot, equals(packageRoot));
      } finally {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    });

    test(
        'returns source package root when only executable path is nested under source tree',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_common_path_utils_',
      );

      try {
        final String packageRoot = path.join(
          tempRoot.path,
          'rpi',
          'uiApps',
          'dppController',
          'dpp_controller',
        );
        final String bundleDirectory = path.join(
          packageRoot,
          'build',
          'linux',
          'x64',
          'release',
          'bundle',
        );

        await Directory(path.join(bundleDirectory, 'data'))
            .create(recursive: true);
        await Directory(path.join(bundleDirectory, 'lib'))
            .create(recursive: true);
        await File(path.join(packageRoot, 'pubspec.yaml'))
            .writeAsString('name: dpp_controller');
        await File(path.join(bundleDirectory, 'dpp_controller'))
            .writeAsString('');

        final String resolvedRoot = getFlutterPackageRoot(
          scriptUri: Uri.parse('data:,release'),
          resolvedExecutablePath: path.join(bundleDirectory, 'dpp_controller'),
          currentWorkingDirectory: tempRoot.path,
        );

        expect(resolvedRoot, equals(packageRoot));
      } finally {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    });

    test('returns bundle directory for out-of-tree built app bundle', () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_common_path_utils_',
      );

      try {
        final String bundleDirectory = path.join(
          tempRoot.path,
          'runtimeApps',
          'demo_mode',
        );

        await Directory(path.join(bundleDirectory, 'data'))
            .create(recursive: true);
        await Directory(path.join(bundleDirectory, 'lib'))
            .create(recursive: true);
        await File(path.join(bundleDirectory, 'demo_mode')).writeAsString('');

        final String resolvedRoot = getFlutterPackageRoot(
          scriptUri: Uri.parse('data:,release'),
          resolvedExecutablePath: path.join(bundleDirectory, 'demo_mode'),
          currentWorkingDirectory: tempRoot.path,
        );

        expect(resolvedRoot, equals(bundleDirectory));
      } finally {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    });

    test('resolves runtime symlink executable back to source package root',
        () async {
      final Directory tempRoot = await Directory.systemTemp.createTemp(
        'dogpaw_common_path_utils_',
      );

      try {
        final String packageRoot = path.join(
          tempRoot.path,
          'rpi',
          'uiApps',
          'demoMode',
          'demo_mode',
        );
        final String bundleDirectory = path.join(
          packageRoot,
          'build',
          'linux',
          'x64',
          'release',
          'bundle',
        );
        final String runtimeDirectory = path.join(
          tempRoot.path,
          'runtime',
          'dogpaw',
          'default',
        );
        final String executablePath = path.join(bundleDirectory, 'demo_mode');
        final String symlinkPath =
            path.join(runtimeDirectory, 'dogpaw-app-demo_mode');

        await Directory(path.join(bundleDirectory, 'data'))
            .create(recursive: true);
        await Directory(path.join(bundleDirectory, 'lib'))
            .create(recursive: true);
        await Directory(runtimeDirectory).create(recursive: true);
        await File(path.join(packageRoot, 'pubspec.yaml'))
            .writeAsString('name: demo_mode');
        await File(executablePath).writeAsString('');
        await Link(symlinkPath).create(executablePath);

        final String resolvedRoot = getFlutterPackageRoot(
          scriptUri: Uri.parse('data:,release'),
          resolvedExecutablePath: symlinkPath,
          currentWorkingDirectory: path.dirname(packageRoot),
        );

        expect(resolvedRoot, equals(packageRoot));
      } finally {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    });
  });
}
