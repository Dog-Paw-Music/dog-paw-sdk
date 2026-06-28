import 'dart:io';

import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/ffi/native_bridge.dart';
import 'package:test/test.dart';

import 'package_runtime_paths.dart';
import 'test_app_install.dart';

/// Configuration for Dog Paw integration tests that start Epiphany.
class DogpawIntegrationTestConfiguration {
  /// Creates one immutable integration-test configuration.
  ///
  /// Purpose:
  /// Collects all explicit paths and staged-app inputs needed to make the same
  /// integration test contract work in the repo and in an exported SDK.
  ///
  /// Parameters:
  /// - [epiphanyPath]: Optional explicit Epiphany binary path.
  /// - [instanceName]: Optional explicit Epiphany instance name.
  /// - [runtimeDir]: Optional explicit runtime root for port files and logs.
  /// - [dataDir]: Optional explicit persistent data root.
  /// - [appRootPath]: Optional explicit installed app registry root.
  /// - [installedApps]: Apps to stage into [appRootPath] before server start.
  /// - [serverStartTimeoutMs]: Optional server readiness timeout in
  ///   milliseconds.
  ///
  /// Return value:
  /// - New immutable configuration object.
  ///
  /// Requirements/Preconditions:
  /// - Any provided paths are appropriate for the current machine and test run.
  ///
  /// Guarantees/Postconditions:
  /// - [installedApps] is stored as an unmodifiable list.
  ///
  /// Invariants:
  /// - The object does not read or write the filesystem by itself.
  DogpawIntegrationTestConfiguration({
    this.epiphanyPath,
    this.instanceName,
    this.runtimeDir,
    this.dataDir,
    this.appRootPath,
    List<DogpawAppInstallSource> installedApps = const <DogpawAppInstallSource>[],
    this.serverStartTimeoutMs = 15000,
  }) : installedApps = List<DogpawAppInstallSource>.unmodifiable(
          installedApps,
        );

  /// Explicit Epiphany binary path, or null to use environment/fallback search.
  final String? epiphanyPath;

  /// Explicit instance name, or null to derive one from environment/defaults.
  final String? instanceName;

  /// Explicit runtime root, or null to use environment/defaults.
  final String? runtimeDir;

  /// Explicit persistent data root, or null to use environment/defaults.
  final String? dataDir;

  /// Explicit installed app registry root, or null to use `<dataDir>/apps`.
  final String? appRootPath;

  /// Apps to stage into the installed app registry before server start.
  final List<DogpawAppInstallSource> installedApps;

  /// Milliseconds to wait for Epiphany startup before failing the test.
  final int serverStartTimeoutMs;
}

/// Manages Epiphany server lifecycle for Dog Paw integration tests.
///
/// Purpose:
/// Provides a public app-author-facing fixture that stages test apps into an
/// installed layout, starts Epiphany against that layout, and cleans up the
/// server after tests complete.
class IntegrationTestFixture {
  static DogpawIntegrationTestConfiguration _configuration =
      DogpawIntegrationTestConfiguration();

  static int? _serverPid;
  static bool _serverStartedByUs = false;
  static bool _environmentSetUp = false;
  static bool _appsStaged = false;

  static String _instanceName = 'default';
  static String _runtimeDir = '';
  static String _dataDir = '';
  static String _appRootPath = '';
  static String? _logPath;

  static final Map<String, String?> _previousEnvironmentOverrides =
      <String, String?>{};

  static DogPawEntity? _logControlEntity;
  static bool _logSectionsEnabled = false;

  /// Returns the runtime root used by this fixture.
  ///
  /// Purpose:
  /// Exposes the active runtime directory to tests that need to inspect files
  /// such as logs or port files.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - Runtime root path used for this test suite.
  ///
  /// Requirements/Preconditions:
  /// - None. Lazily initializes the environment if needed.
  ///
  /// Guarantees/Postconditions:
  /// - The returned directory exists.
  ///
  /// Invariants:
  /// - Returns the same value for the lifetime of one registered fixture.
  static String get runtimeDir {
    _setupTestEnvironment();
    return _runtimeDir;
  }

  /// Returns the persistent data root used by this fixture.
  ///
  /// Purpose:
  /// Exposes the active data directory to tests that need to inspect staged app
  /// or app-data files.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - Persistent data root path used for this test suite.
  ///
  /// Requirements/Preconditions:
  /// - None. Lazily initializes the environment if needed.
  ///
  /// Guarantees/Postconditions:
  /// - The returned directory exists.
  ///
  /// Invariants:
  /// - Returns the same value for the lifetime of one registered fixture.
  static String get dataDir {
    _setupTestEnvironment();
    return _dataDir;
  }

  /// Returns the installed app registry root used by this fixture.
  ///
  /// Purpose:
  /// Lets tests verify staged installed apps or prepare extra fixtures under the
  /// same registry Epiphany sees.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - Installed app registry root path.
  ///
  /// Requirements/Preconditions:
  /// - None. Lazily initializes the environment if needed.
  ///
  /// Guarantees/Postconditions:
  /// - The returned directory exists.
  ///
  /// Invariants:
  /// - Returns the same value for the lifetime of one registered fixture.
  static String get appRootPath {
    _setupTestEnvironment();
    return _appRootPath;
  }

  /// Returns the active Epiphany instance name.
  ///
  /// Purpose:
  /// Exposes the isolated instance name so tests can derive instance-scoped
  /// runtime paths or diagnostics.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - Epiphany instance name used for this test suite.
  ///
  /// Requirements/Preconditions:
  /// - None. Lazily initializes the environment if needed.
  ///
  /// Guarantees/Postconditions:
  /// - The returned name is non-empty.
  ///
  /// Invariants:
  /// - Returns the same value for the lifetime of one registered fixture.
  static String get instanceName {
    _setupTestEnvironment();
    return _instanceName;
  }

  /// Returns the full instance port file path.
  ///
  /// Purpose:
  /// Centralizes the runtime convention for locating the Epiphany server port
  /// file used by readiness checks.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - `<runtimeDir>/<instanceName>/server_port`.
  ///
  /// Requirements/Preconditions:
  /// - None. Lazily initializes the environment if needed.
  ///
  /// Guarantees/Postconditions:
  /// - The parent runtime instance directory exists after environment setup.
  ///
  /// Invariants:
  /// - The path always matches the active runtime/data overrides.
  static String get _portFilePath {
    _setupTestEnvironment();
    return '$_runtimeDir/$_instanceName/server_port';
  }

  /// Registers test hooks that manage the Epiphany server lifecycle.
  ///
  /// Purpose:
  /// Sets up a repeatable integration-test environment, stages any configured
  /// apps into an installed registry, starts Epiphany before tests, and shuts it
  /// down afterward.
  ///
  /// Parameters:
  /// - [configuration]: Optional explicit path and staging configuration.
  /// - [enableLogSections]: Whether per-test log-section control should be
  ///   enabled.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Call once near the top of a test file's `main()`.
  ///
  /// Guarantees/Postconditions:
  /// - `setUpAll` and `tearDownAll` hooks are registered with the `test`
  ///   package.
  ///
  /// Invariants:
  /// - Registered hooks operate against the same resolved configuration.
  static void register({
    DogpawIntegrationTestConfiguration? configuration,
    bool enableLogSections = true,
  }) {
    _configuration = configuration ?? DogpawIntegrationTestConfiguration();
    _logSectionsEnabled = enableLogSections;

    _setupTestEnvironment();

    setUpAll(() async {
      if (isServerRunning()) {
        AppLogger.info(
          '[IntegrationTestFixture] Server already running, using existing',
        );
        _serverStartedByUs = false;
      } else {
        final bool started = await startServer();
        if (!started) {
          throw TestFailure(
            'IntegrationTestFixture: Failed to start Epiphany server.',
          );
        }
        _serverStartedByUs = true;
      }

      if (_logSectionsEnabled) {
        await _createLogControlEntity();
      }
    });

    tearDownAll(() async {
      if (_logControlEntity != null) {
        _logControlEntity!.disconnect();
        _logControlEntity = null;
      }

      if (_serverStartedByUs) {
        await stopServer();
      }

      _restoreEnvironmentOverrides();
      _environmentSetUp = false;
      _appsStaged = false;
    });
  }

  /// Configures environment overrides and stages installed apps for tests.
  ///
  /// Purpose:
  /// Resolves explicit config or environment defaults into the concrete runtime,
  /// data, instance, and app-root values used by the fixture.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - The configured paths are writable.
  ///
  /// Guarantees/Postconditions:
  /// - Runtime/data/app directories exist.
  /// - `DogPawEntity.environmentOverrides` and child-process env vars match the
  ///   resolved values.
  /// - Configured installed apps are staged into `DOGPAW_APP_DIR`.
  ///
  /// Invariants:
  /// - Running twice without teardown does nothing after the first success.
  static void _setupTestEnvironment() {
    if (_environmentSetUp) {
      return;
    }

    final String resolvedInstance =
        _configuration.instanceName ??
            Platform.environment['EPIPHANY_INSTANCE'] ??
            'test-$pid';
    final String resolvedRuntimeDir =
        _configuration.runtimeDir ??
            Platform.environment['DOGPAW_RUNTIME_DIR'] ??
            '/tmp/dogpaw_test';
    final String resolvedDataDir =
        _configuration.dataDir ??
            Platform.environment['DOGPAW_DATA_DIR'] ??
            '/tmp/dogpaw_test_data_$pid';
    final String resolvedAppRoot =
        _configuration.appRootPath ??
            Platform.environment['DOGPAW_APP_DIR'] ??
            '$resolvedDataDir/apps';

    Directory(resolvedRuntimeDir).createSync(recursive: true);
    Directory(resolvedDataDir).createSync(recursive: true);
    Directory(resolvedAppRoot).createSync(recursive: true);

    if (_configuration.installedApps.isNotEmpty && !_appsStaged) {
      stageInstalledDogpawApps(
        appRootPath: resolvedAppRoot,
        apps: _configuration.installedApps,
      );
      _appsStaged = true;
    }

    _applyEnvironmentOverride('EPIPHANY_INSTANCE', resolvedInstance);
    _applyEnvironmentOverride('DOGPAW_RUNTIME_DIR', resolvedRuntimeDir);
    _applyEnvironmentOverride('DOGPAW_DATA_DIR', resolvedDataDir);
    _applyEnvironmentOverride('DOGPAW_APP_DIR', resolvedAppRoot);
    final String? resolvedBridgeLibraryPath = resolveBridgeLibraryPathForFixture(
      environment: Platform.environment,
    );
    if (resolvedBridgeLibraryPath != null &&
        resolvedBridgeLibraryPath.isNotEmpty) {
      _applyEnvironmentOverride('DOGPAW_BRIDGE_LIB', resolvedBridgeLibraryPath);
    }

    _instanceName = resolvedInstance;
    _runtimeDir = resolvedRuntimeDir;
    _dataDir = resolvedDataDir;
    _appRootPath = resolvedAppRoot;
    _environmentSetUp = true;

    AppLogger.info('[IntegrationTestFixture] Test environment:');
    AppLogger.info('  Instance: $_instanceName');
    AppLogger.info('  Runtime dir: $_runtimeDir');
    AppLogger.info('  Data dir: $_dataDir');
    AppLogger.info('  App root: $_appRootPath');
  }

  /// Applies one environment override to both Dart and spawned child processes.
  ///
  /// Purpose:
  /// Keeps `DogPawEntity` path resolution and spawned Epiphany child processes in
  /// sync despite Dart's immutable `Platform.environment` snapshot.
  ///
  /// Parameters:
  /// - [name]: Environment variable name.
  /// - [value]: Resolved value to apply.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [name] is non-empty.
  ///
  /// Guarantees/Postconditions:
  /// - `DogPawEntity.environmentOverrides[name]` equals [value].
  /// - The current process environment is updated for child-process inheritance.
  ///
  /// Invariants:
  /// - Existing override values are captured once for later restoration.
  static void _applyEnvironmentOverride(String name, String value) {
    _previousEnvironmentOverrides.putIfAbsent(
      name,
      () => DogPawEntity.environmentOverrides[name],
    );
    DogPawEntity.environmentOverrides[name] = value;
    DogPawBridge.setEnv(name, value);
  }

  /// Restores environment overrides changed by the fixture.
  ///
  /// Purpose:
  /// Prevents one integration test file from leaking runtime/data/app roots into
  /// later tests running in the same Dart process.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - All keys modified by [_applyEnvironmentOverride] are restored to their
  ///   previous override state.
  ///
  /// Invariants:
  /// - Does not attempt to rewrite `Platform.environment`.
  static void _restoreEnvironmentOverrides() {
    for (final MapEntry<String, String?> entry
        in _previousEnvironmentOverrides.entries) {
      if (entry.value == null) {
        DogPawEntity.environmentOverrides.remove(entry.key);
      } else {
        DogPawEntity.environmentOverrides[entry.key] = entry.value!;
      }
    }
    _previousEnvironmentOverrides.clear();
  }

  /// Creates the log control entity used for per-test log sections.
  ///
  /// Purpose:
  /// Mirrors the existing internal integration fixture behavior where passing
  /// tests suppress logs and failing tests flush them.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Epiphany is running and accepting connections.
  ///
  /// Guarantees/Postconditions:
  /// - `_logControlEntity` is connected on success, otherwise remains null.
  ///
  /// Invariants:
  /// - Log-section failures do not fail the enclosing test file setup.
  static Future<void> _createLogControlEntity() async {
    try {
      _logControlEntity = DogPawEntity('LogControlEntity');
      final ConnectionResult result = await _logControlEntity!.connect();
      if (!result.success) {
        AppLogger.warning(
          'Failed to connect log control entity: ${result.error}',
          'IntegrationTestFixture',
        );
        _logControlEntity = null;
        return;
      }
      await result.handle!.complete();
    } catch (error) {
      AppLogger.warning(
        'Exception creating log control entity: $error',
        'IntegrationTestFixture',
      );
      _logControlEntity = null;
    }
  }

  /// Starts a per-test log section when log control is available.
  ///
  /// Purpose:
  /// Marks the beginning of buffered logs for one test.
  ///
  /// Parameters:
  /// - [testName]: Human-readable test description.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Epiphany is running.
  ///
  /// Guarantees/Postconditions:
  /// - When log control is connected, the section start request is sent.
  ///
  /// Invariants:
  /// - Missing log control entity is tolerated.
  static Future<void> _startLogSectionForTest(String testName) async {
    if (_logControlEntity == null || !_logControlEntity!.isConnected()) {
      return;
    }
    final Result<bool> result = await _logControlEntity!.startLogSection(
      testName,
    );
    if (!result.success) {
      AppLogger.warning(
        'Failed to start log section: ${result.error}',
        'IntegrationTestFixture',
      );
    }
  }

  /// Ends a per-test log section.
  ///
  /// Purpose:
  /// Flushes logs for failing tests or discards them for passing tests.
  ///
  /// Parameters:
  /// - [flush]: Whether buffered logs should be flushed.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Epiphany is running.
  ///
  /// Guarantees/Postconditions:
  /// - When log control is connected, the section end request is sent.
  ///
  /// Invariants:
  /// - Missing log control entity is tolerated.
  static Future<void> _endLogSectionForTest(bool flush) async {
    if (_logControlEntity == null || !_logControlEntity!.isConnected()) {
      return;
    }
    final Result<bool> result = await _logControlEntity!.endLogSection(flush);
    if (!result.success && !result.error.contains('not in')) {
      AppLogger.warning(
        'Failed to end log section: ${result.error}',
        'IntegrationTestFixture',
      );
    }
  }

  /// Flushes the current test's buffered logs immediately.
  ///
  /// Purpose:
  /// Gives tests an escape hatch for printing buffered logs before an assertion
  /// failure would naturally flush them.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Epiphany is running and log control is connected.
  ///
  /// Guarantees/Postconditions:
  /// - No-op when log control is unavailable.
  ///
  /// Invariants:
  /// - Does not fail the test if log flushing itself fails.
  static Future<void> flushLogsOnFailure() async {
    if (_logControlEntity == null || !_logControlEntity!.isConnected()) {
      return;
    }
    await _logControlEntity!.flushLogSection();
  }

  /// Returns whether Epiphany is running for this fixture's instance.
  ///
  /// Purpose:
  /// Uses the shared native helper for flock-based server detection so tests and
  /// internal infrastructure agree on readiness semantics.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - `true` when the server is running, otherwise `false`.
  ///
  /// Requirements/Preconditions:
  /// - None. Lazily initializes the environment if needed.
  ///
  /// Guarantees/Postconditions:
  /// - Does not start or stop the server.
  ///
  /// Invariants:
  /// - Reads state only through the port-file contract.
  static bool isServerRunning() {
    _setupTestEnvironment();
    final DogPawBridge bridge = DogPawBridge();
    final int result = bridge.checkServerRunningManaged(_portFilePath);
    return result > 0;
  }

  /// Waits for the Epiphany server to become ready.
  ///
  /// Purpose:
  /// Reuses the native flock-based readiness helper so launch timing stays
  /// aligned with the existing C++ and internal Dart fixtures.
  ///
  /// Parameters:
  /// - [timeoutMs]: Optional readiness timeout override.
  ///
  /// Return value:
  /// - Server port when ready, otherwise `null`.
  ///
  /// Requirements/Preconditions:
  /// - None. Lazily initializes the environment if needed.
  ///
  /// Guarantees/Postconditions:
  /// - Does not mutate server state.
  ///
  /// Invariants:
  /// - Uses the active fixture instance port-file path.
  static int? waitForServerReady({int? timeoutMs}) {
    _setupTestEnvironment();
    final DogPawBridge bridge = DogPawBridge();
    final int result = bridge.waitForServerManaged(
      _portFilePath,
      timeoutMs ?? _configuration.serverStartTimeoutMs,
    );
    return result > 0 ? result : null;
  }

  /// Resolves the Epiphany binary path for this test run.
  ///
  /// Purpose:
  /// Prefers explicit configuration and environment variables, then falls back
  /// to generic deployed or current-working-directory build locations without
  /// assuming a repository root.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - Executable path string, or `null` when nothing usable is found.
  ///
  /// Requirements/Preconditions:
  /// - Candidate paths, when provided, point at executable files.
  ///
  /// Guarantees/Postconditions:
  /// - Search order is deterministic and portable for the shipped SDK layout.
  ///
  /// Invariants:
  /// - Does not inspect internal monorepo build-output directories.
  static String? _findEpiphanyBinary() {
    return resolveEpiphanyBinaryPath(
      explicitPath: _configuration.epiphanyPath,
      environment: Platform.environment,
    );
  }

  /// Starts Epiphany and waits for readiness.
  ///
  /// Purpose:
  /// Launches Epiphany with the resolved runtime/data/app environment and waits
  /// until the server is ready to accept requests.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - `true` when Epiphany starts successfully, otherwise `false`.
  ///
  /// Requirements/Preconditions:
  /// - The resolved Epiphany binary exists.
  ///
  /// Guarantees/Postconditions:
  /// - On success, `_serverPid` and `_logPath` are populated.
  /// - On failure, any launched server process is stopped before returning
  ///   `false`.
  ///
  /// Invariants:
  /// - Uses `PR_SET_PDEATHSIG` via the native bridge for cleanup on parent exit.
  static Future<bool> startServer() async {
    _setupTestEnvironment();
    AppLogger.info('Starting Epiphany server...', 'IntegrationTestFixture');

    final String? epiphanyPath = _findEpiphanyBinary();
    if (epiphanyPath == null) {
      AppLogger.error('CRITICAL: Could not find Epiphany binary');
      final List<String> searchPaths = buildEpiphanyBinarySearchPaths(
        explicitPath: _configuration.epiphanyPath,
        environment: Platform.environment,
      );
      if (searchPaths.isEmpty) {
        AppLogger.error(
          'Epiphany search paths: none. Configure epiphanyPath, set EPIPHANY_PATH, '
          'or run from an SDK tree that ships runtime/bin/<platform>/Epiphany.',
        );
      } else {
        AppLogger.error(
          'Epiphany search paths:\n${searchPaths.map((String path) => '  - $path').join('\n')}',
        );
      }
      return false;
    }

    final DogPawBridge bridge = DogPawBridge();
    _serverPid = bridge.spawnWithDeathSignalManaged(
      epiphanyPath,
      <String>[epiphanyPath, '--no-term', '--instance', _instanceName],
      DPPBSignal.sigterm,
      logPath: 'auto',
    );
    if (_serverPid == null || _serverPid! < 0) {
      AppLogger.error(
        'FFI spawn failed with code $_serverPid',
        'IntegrationTestFixture',
      );
      _serverPid = null;
      _logPath = null;
      return false;
    }

    _logPath = '/tmp/epiphany_test_$_serverPid.log';
    final int? port = waitForServerReady();
    if (port == null) {
      await stopServer();
      return false;
    }

    AppLogger.info(
      '[IntegrationTestFixture] Server ready on port $port',
      'IntegrationTestFixture',
    );
    return true;
  }

  /// Stops the Epiphany server started by this fixture.
  ///
  /// Purpose:
  /// Ends the managed Epiphany process cleanly after an integration test file
  /// completes.
  ///
  /// Parameters: none.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None. Safe to call even when no server is running.
  ///
  /// Guarantees/Postconditions:
  /// - The managed process is terminated or force-killed on timeout.
  /// - `_serverPid` is cleared.
  ///
  /// Invariants:
  /// - Does not affect unrelated Epiphany processes.
  static Future<void> stopServer() async {
    _setupTestEnvironment();
    if (_serverPid == null) {
      return;
    }

    final DogPawBridge bridge = DogPawBridge();
    bridge.killProcessManaged(_serverPid!, DPPBSignal.sigterm);
    final int exitResult = bridge.waitProcessManaged(_serverPid!, 5000);
    if (exitResult == -2) {
      bridge.killProcessManaged(_serverPid!, DPPBSignal.sigkill);
      bridge.waitProcessManaged(_serverPid!, 1000);
    }

    _serverPid = null;
  }
}

/// Wraps a test body with automatic log-section management.
///
/// Purpose:
/// Keeps integration test output readable by buffering server logs for passing
/// tests and flushing them when a test fails.
///
/// Parameters:
/// - [description]: Test name and log section label.
/// - [body]: Test body callback.
/// - [skip]: Optional skip reason passed through to `test()`.
/// - [timeout]: Optional timeout passed through to `test()`.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - [IntegrationTestFixture.register] has already been called for the file when
///   log sections are desired.
///
/// Guarantees/Postconditions:
/// - Passing tests discard buffered logs.
/// - Failing tests flush buffered logs before rethrowing.
///
/// Invariants:
/// - Behavior falls back to a normal `test()` when log control is unavailable.
void integrationTest(
  String description,
  dynamic Function() body, {
  String? skip,
  Timeout? timeout,
}) {
  test(
    description,
    () async {
      await IntegrationTestFixture._startLogSectionForTest(description);

      bool testFailed = false;
      try {
        await body();
      } catch (_) {
        testFailed = true;
        await IntegrationTestFixture._endLogSectionForTest(true);
        rethrow;
      }

      if (!testFailed) {
        await IntegrationTestFixture._endLogSectionForTest(false);
      }
    },
    skip: skip,
    timeout: timeout,
  );
}
