// Lifecycle tests for server lifecycle scenarios (crash, restart, reconnect).
//
// These tests have MANUAL control over Epiphany's lifecycle, unlike the main
// integration tests which use a global environment for automatic management.
//
// RUN WITH: flutter test test/lifecycle/lifecycle_test.dart
// (not dart test - this package depends on Flutter)
//
// NOTE: Do NOT use IntegrationTestFixture.register() in this file.
// We need manual control over server start/stop.
//
// NOTE: These tests mirror the C++ equivalent tests in
// dogPawEntity/tests/gtest/lifecycle/LifecycleTests.cpp
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

String _resolveLifecycleAppRootPath() {
  return DogPawEntity.environmentOverrides['DOGPAW_APP_DIR'] ??
      Platform.environment['DOGPAW_APP_DIR'] ??
      '/tmp/dogpaw_test_data/apps';
}

Future<DogpawAppInstallSource> _buildHomeScreenPlaceholderInstallSource({
  required DogpawAppInstallSource launchTestStub,
}) async {
  final Directory fixtureDirectory = Directory(
    path.join(
      Directory.systemTemp.path,
      'dogpaw_test_fixture_cache',
      'dog_paw_home_screen',
    ),
  )..createSync(recursive: true);
  final File manifestFile = File(
    path.join(fixtureDirectory.path, 'dogpawapp.json'),
  );
  const JsonEncoder encoder = JsonEncoder.withIndent('  ');
  manifestFile.writeAsStringSync(
    '${encoder.convert(<String, Object?>{
      'name': 'dog_paw_home_screen',
      'displayName': 'Dog Paw Home Screen Test Stub',
      'type': 'headless',
      'visible': 'never',
      'instancePolicy': 'singleton',
      'executable': 'launch_test_stub',
      'version': '0.1',
    })}\n',
  );
  return DogpawAppInstallSource.binary(
    manifestPath: manifestFile.path,
    binaryPath: launchTestStub.binaryPath!,
  );
}

Future<void> main() async {
  final DogpawAppInstallSource launchTestStub =
      await buildLaunchTestStubInstallSource();
  final DogpawAppInstallSource homeScreenPlaceholder =
      await _buildHomeScreenPlaceholderInstallSource(
    launchTestStub: launchTestStub,
  );

  // Note: No IntegrationTestFixture.register() - we control server manually

  /// Wait for async operations
  Future<void> waitForAsync([int ms = 100]) async {
    await Future.delayed(Duration(milliseconds: ms));
  }

  /// Waits until the Epiphany server is fully reported as stopped.
  ///
  /// Purpose:
  /// Makes lifecycle assertions resilient to the asynchronous cleanup window
  /// between requesting shutdown and the runtime port file actually disappearing.
  ///
  /// Parameters:
  /// - [timeout]: Maximum total time to wait for the server to stop.
  /// - [pollInterval]: Delay between repeated `isServerRunning()` checks.
  ///
  /// Return value:
  /// - Future that completes once the server stops or the timeout expires.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returns promptly once `IntegrationTestFixture.isServerRunning()` is false.
  ///
  /// Invariants:
  /// - Does not start or stop the server itself.
  Future<void> waitForServerToStop({
    Duration timeout = const Duration(seconds: 3),
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (IntegrationTestFixture.isServerRunning()) {
      if (DateTime.now().isAfter(deadline)) {
        return;
      }
      await Future.delayed(pollInterval);
    }
  }

  group('Server Lifecycle', () {
    setUp(() async {
      stageInstalledDogpawApps(
        appRootPath: _resolveLifecycleAppRootPath(),
        apps: <DogpawAppInstallSource>[
          launchTestStub,
          homeScreenPlaceholder,
        ],
      );

      // Ensure clean state - stop server if running from previous test
      if (IntegrationTestFixture.isServerRunning()) {
        await IntegrationTestFixture.stopServer();
        await waitForServerToStop();
      }
    });

    tearDown(() async {
      // Clean up server if test left it running
      if (IntegrationTestFixture.isServerRunning()) {
        await IntegrationTestFixture.stopServer();
        await waitForServerToStop();
      }
    });

    test('ServerStartsAndStops', () async {
      // Server should not be running initially
      expect(IntegrationTestFixture.isServerRunning(), isFalse);

      // Start server
      final started = await IntegrationTestFixture.startServer();
      expect(started, isTrue);
      expect(IntegrationTestFixture.isServerRunning(), isTrue);

      // Stop server
      await IntegrationTestFixture.stopServer();
      await waitForServerToStop();
      expect(IntegrationTestFixture.isServerRunning(), isFalse);
    });

    test('EntityConnectsAfterServerStart', () async {
      // Start server
      final started = await IntegrationTestFixture.startServer();
      expect(started, isTrue);

      // Create and connect entity
      final entity = DogPawEntity('TestEntity');
      final result = await entity.connect();

      expect(result.success, isTrue, reason: 'Should connect: ${result.error}');
      expect(entity.isConnected(), isTrue);

      entity.disconnect();
    });

    test('EntityDetectsServerShutdown', () async {
      // Start server and connect
      final started = await IntegrationTestFixture.startServer();
      expect(started, isTrue);

      final entity = DogPawEntity('TestEntity');
      final result = await entity.connect();
      expect(result.success, isTrue);
      expect(entity.isConnected(), isTrue);

      // Stop server while entity is connected
      await IntegrationTestFixture.stopServer();
      await waitForAsync(500); // Give entity time to detect disconnect

      // Entity should no longer be connected
      expect(entity.isConnected(), isFalse,
          reason: 'Entity should detect server shutdown');
    });

    test('LaunchAppCanStartAndStopHeadlessStub', () async {
      final started = await IntegrationTestFixture.startServer();
      expect(started, isTrue);

      final controller = DogPawEntity('LaunchController');
      final ConnectionResult connectResult = await controller.connect();
      expect(connectResult.success, isTrue,
          reason: 'Controller failed to connect: ${connectResult.error}');
      await connectResult.handle!.complete();

      final Result<String> launchResult =
          await controller.launchApp('launch_test_stub');
      expect(launchResult.success, isTrue,
          reason: 'launchApp failed: ${launchResult.error}');
      final String launchedEntityName = launchResult.value!;
      expect(launchedEntityName, startsWith('launch_test_stub'),
          reason: 'Expected runtime entity name to derive from template');

      await waitForAsync(300);

      final Result<bool> stopResult =
          await controller.stopApp(launchedEntityName);
      expect(stopResult.success, isTrue,
          reason: 'stopApp failed: ${stopResult.error}');

      controller.disconnect();
    });

    test('KillAllAppsReportsSuccess', () async {
      final started = await IntegrationTestFixture.startServer();
      expect(started, isTrue);

      final controller = DogPawEntity('KillAllAppsController');
      final ConnectionResult connectResult = await controller.connect();
      expect(connectResult.success, isTrue,
          reason: 'Controller failed to connect: ${connectResult.error}');
      await connectResult.handle!.complete();

      final Result<String> killAllResult = await controller.killAllApps();
      expect(killAllResult.success, isTrue,
          reason: 'killAllApps failed: ${killAllResult.error}');
      expect(killAllResult.value, isNotNull);
      expect(killAllResult.value!, isNotEmpty);

      controller.disconnect();
    });
    test('EntityRetriesConnectionWhenServerUnavailable', () async {
      // Implement when connection retry logic is ready
      //
      // Test outline:
      // 1. Try to connect entity when server is NOT running
      // 2. Verify it fails gracefully (with appropriate timeout)
      // 3. Start server
      // 4. Try to connect again
      // 5. Verify it succeeds
    }, skip: 'Connection retry testing not yet implemented');
  });
}
