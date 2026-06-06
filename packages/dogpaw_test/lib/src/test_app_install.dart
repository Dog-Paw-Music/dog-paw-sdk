import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package_runtime_paths.dart';

const String _manifestName = 'dogpawapp.json';
const String _metadataName = 'install_metadata.json';
Future<DogpawAppInstallSource>? _launchTestStubInstallSourceFuture;

/// Declarative description of one app payload to stage into an installed app
/// registry for tests.
class DogpawAppInstallSource {
  /// Creates a staging description for a headless/native app binary.
  ///
  /// Purpose:
  /// Describes the same input shape that headless install tooling uses: a
  /// manifest plus a single primary executable copied into `bundle/`.
  ///
  /// Parameters:
  /// - [manifestPath]: Source `dogpawapp.json` path.
  /// - [binaryPath]: Source executable file path.
  /// - [extraBinaryPaths]: Optional helper binaries copied into `bundle/`.
  ///
  /// Return value:
  /// - New immutable install-source description.
  ///
  /// Requirements/Preconditions:
  /// - [manifestPath] and [binaryPath] are non-empty file paths.
  ///
  /// Guarantees/Postconditions:
  /// - The resulting object represents a binary-based staging request.
  ///
  /// Invariants:
  /// - Exactly one primary payload mode is active.
  factory DogpawAppInstallSource.binary({
    required String manifestPath,
    required String binaryPath,
    List<String> extraBinaryPaths = const <String>[],
  }) {
    return DogpawAppInstallSource._(
      manifestPath: manifestPath,
      binaryPath: binaryPath,
      bundlePath: null,
      extraBinaryPaths: extraBinaryPaths,
    );
  }

  /// Creates a staging description for a prebuilt runtime bundle.
  ///
  /// Purpose:
  /// Describes Flutter or other multi-file runtime payloads that should be
  /// copied wholesale into the installed app `bundle/` directory.
  ///
  /// Parameters:
  /// - [manifestPath]: Source `dogpawapp.json` path.
  /// - [bundlePath]: Source bundle directory path.
  /// - [extraBinaryPaths]: Optional helper binaries copied into `bundle/`.
  ///
  /// Return value:
  /// - New immutable install-source description.
  ///
  /// Requirements/Preconditions:
  /// - [manifestPath] is a non-empty file path.
  /// - [bundlePath] is a non-empty directory path.
  ///
  /// Guarantees/Postconditions:
  /// - The resulting object represents a bundle-based staging request.
  ///
  /// Invariants:
  /// - Exactly one primary payload mode is active.
  factory DogpawAppInstallSource.bundle({
    required String manifestPath,
    required String bundlePath,
    List<String> extraBinaryPaths = const <String>[],
  }) {
    return DogpawAppInstallSource._(
      manifestPath: manifestPath,
      binaryPath: null,
      bundlePath: bundlePath,
      extraBinaryPaths: extraBinaryPaths,
    );
  }

  /// Internal constructor for normalized staging descriptions.
  ///
  /// Purpose:
  /// Centralizes invariant checks shared by the public factories.
  ///
  /// Parameters:
  /// - [manifestPath]: Source manifest path.
  /// - [binaryPath]: Optional primary executable path.
  /// - [bundlePath]: Optional runtime bundle directory path.
  /// - [extraBinaryPaths]: Optional helper executable paths.
  ///
  /// Return value:
  /// - Constructed immutable source description.
  ///
  /// Requirements/Preconditions:
  /// - Exactly one of [binaryPath] or [bundlePath] is non-null.
  ///
  /// Guarantees/Postconditions:
  /// - Stored helper path list is unmodifiable.
  ///
  /// Invariants:
  /// - Instances never represent both payload modes at once.
  DogpawAppInstallSource._({
    required this.manifestPath,
    required this.binaryPath,
    required this.bundlePath,
    required List<String> extraBinaryPaths,
  }) : extraBinaryPaths = List<String>.unmodifiable(extraBinaryPaths) {
    if (manifestPath.isEmpty) {
      throw ArgumentError.value(
        manifestPath,
        'manifestPath',
        'Manifest path must be non-empty.',
      );
    }
    if ((binaryPath == null) == (bundlePath == null)) {
      throw ArgumentError(
        'Provide exactly one of binaryPath or bundlePath.',
      );
    }
  }

  /// Source `dogpawapp.json` path.
  final String manifestPath;

  /// Source executable path for headless/native installs.
  final String? binaryPath;

  /// Source runtime bundle directory path for Flutter installs.
  final String? bundlePath;

  /// Additional helper executables copied into `bundle/`.
  final List<String> extraBinaryPaths;
}

/// Stages one or more apps into an installed app registry layout.
///
/// Purpose:
/// Gives tests an installed-layout staging step that matches Epiphany's runtime
/// contract without depending on repo-shape fallbacks or external scripts.
///
/// Parameters:
/// - [appRootPath]: Installed app registry root to populate.
/// - [apps]: App payload descriptions to copy into [appRootPath].
///
/// Return value:
/// - Installed app directories in the same order as [apps].
///
/// Requirements/Preconditions:
/// - [appRootPath] is writable.
/// - Every app description names readable source files/directories.
///
/// Guarantees/Postconditions:
/// - Each app is staged under `<appRootPath>/<manifest.name>/`.
/// - Existing app directories with the same name are replaced by this call.
///
/// Invariants:
/// - Source manifests and payloads are never modified.
List<Directory> stageInstalledDogpawApps({
  required String appRootPath,
  required List<DogpawAppInstallSource> apps,
}) {
  final Directory appRoot = Directory(appRootPath)..createSync(recursive: true);
  return apps
      .map((DogpawAppInstallSource source) =>
          _stageInstalledDogpawApp(appRoot: appRoot, source: source))
      .toList(growable: false);
}

/// Stages one app into an installed app registry root.
///
/// Purpose:
/// Applies the installed-app copy contract for one test app using explicit
/// paths rather than CLI wrappers.
///
/// Parameters:
/// - [appRoot]: Installed app registry root.
/// - [source]: App payload description.
///
/// Return value:
/// - Final installed app directory.
///
/// Requirements/Preconditions:
/// - [appRoot] is writable.
/// - [source] points at readable input files/directories.
///
/// Guarantees/Postconditions:
/// - The target app directory contains `dogpawapp.json`, `bundle/`, copied
///   assets, and generated install metadata.
///
/// Invariants:
/// - The final directory name always matches the manifest `name`.
Directory _stageInstalledDogpawApp({
  required Directory appRoot,
  required DogpawAppInstallSource source,
}) {
  final File manifestFile = File(source.manifestPath).absolute;
  final Directory manifestDirectory = manifestFile.parent;
  final Map<String, dynamic> manifest = _loadManifest(manifestFile);
  final String appName = manifest['name'] as String;
  final Directory finalDirectory = Directory(path.join(appRoot.path, appName));
  final Directory stagingDirectory = Directory(
    path.join(
      appRoot.path,
      '.installing_${appName}_${DateTime.now().millisecondsSinceEpoch}_$pid',
    ),
  );

  if (stagingDirectory.existsSync()) {
    stagingDirectory.deleteSync(recursive: true);
  }
  stagingDirectory.createSync(recursive: true);

  try {
    manifestFile.copySync(path.join(stagingDirectory.path, _manifestName));
    if (source.binaryPath != null) {
      _copyBinaryPayload(
        binaryPath: File(source.binaryPath!).absolute,
        installDirectory: stagingDirectory,
      );
    }
    if (source.bundlePath != null) {
      _copyBundlePayload(
        bundleDirectory: Directory(source.bundlePath!).absolute,
        installDirectory: stagingDirectory,
      );
    }

    final String? iconEntry = _declaredIcon(manifest);
    if (iconEntry != null) {
      _copyManifestIcon(
        iconEntry: iconEntry,
        manifestDirectory: manifestDirectory,
        installDirectory: stagingDirectory,
      );
    }

    _copyExtraBinaryPayloads(
      extraBinaryPaths: source.extraBinaryPaths,
      declaredNames: _declaredExtraBinaries(manifest),
      installDirectory: stagingDirectory,
    );

    for (final String assetEntry in _declaredAssets(manifest, 'assets')) {
      final FileSystemEntity assetSource = _resolveManifestRelativeAsset(
        assetEntry: assetEntry,
        manifestDirectory: manifestDirectory,
      );
      if (!assetSource.existsSync()) {
        throw ArgumentError('Required asset not found: $assetEntry');
      }
      _copyAsset(
        source: assetSource,
        manifestDirectory: manifestDirectory,
        installDirectory: stagingDirectory,
      );
    }

    for (final String assetEntry in _declaredAssets(
      manifest,
      'optionalAssets',
    )) {
      final FileSystemEntity assetSource = _resolveManifestRelativeAsset(
        assetEntry: assetEntry,
        manifestDirectory: manifestDirectory,
      );
      if (assetSource.existsSync()) {
        _copyAsset(
          source: assetSource,
          manifestDirectory: manifestDirectory,
          installDirectory: stagingDirectory,
        );
      }
    }

    _writeInstallMetadata(
      manifest: manifest,
      manifestFile: manifestFile,
      installDirectory: stagingDirectory,
    );

    if (finalDirectory.existsSync()) {
      finalDirectory.deleteSync(recursive: true);
    }
    stagingDirectory.renameSync(finalDirectory.path);
    return finalDirectory;
  } catch (_) {
    if (stagingDirectory.existsSync()) {
      stagingDirectory.deleteSync(recursive: true);
    }
    rethrow;
  }
}

/// Loads and minimally validates a Dog Paw app manifest.
///
/// Purpose:
/// Reads `dogpawapp.json` so staging can derive the installed directory name
/// and copy behavior from the same manifest contract Epiphany uses.
///
/// Parameters:
/// - [manifestFile]: Source manifest file.
///
/// Return value:
/// - Parsed manifest object.
///
/// Requirements/Preconditions:
/// - [manifestFile] exists and contains a JSON object.
///
/// Guarantees/Postconditions:
/// - Returned manifest contains a non-empty string `name`.
///
/// Invariants:
/// - The source file is only read, never modified.
Map<String, dynamic> _loadManifest(File manifestFile) {
  if (!manifestFile.existsSync()) {
    throw ArgumentError('Manifest not found: ${manifestFile.path}');
  }

  final Object? decoded = jsonDecode(manifestFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw ArgumentError('Manifest must be a JSON object.');
  }

  final Object? nameValue = decoded['name'];
  if (nameValue is! String || nameValue.isEmpty) {
    throw ArgumentError('Manifest requires a non-empty string name.');
  }

  return decoded;
}

/// Reads one manifest asset array.
///
/// Purpose:
/// Keeps asset parsing aligned with the install schema while staying small
/// enough for test staging.
///
/// Parameters:
/// - [manifest]: Parsed app manifest.
/// - [key]: Install field name to read.
///
/// Return value:
/// - String asset entries, or an empty list when absent.
///
/// Requirements/Preconditions:
/// - [manifest] is a parsed app manifest object.
///
/// Guarantees/Postconditions:
/// - Throws when the selected field exists but is not a string array.
///
/// Invariants:
/// - Does not mutate [manifest].
List<String> _declaredAssets(Map<String, dynamic> manifest, String key) {
  final Object? installValue = manifest['install'];
  if (installValue == null) {
    return const <String>[];
  }
  if (installValue is! Map<String, dynamic>) {
    throw ArgumentError('Manifest install field must be an object.');
  }
  final Object? value = installValue[key];
  if (value == null) {
    return const <String>[];
  }
  if (value is! List || value.any((Object? item) => item is! String)) {
    throw ArgumentError('install.$key must be an array of strings.');
  }
  return value.cast<String>();
}

/// Reads the optional manifest icon path.
///
/// Purpose:
/// Preserves the installed manifest-relative icon contract used by Epiphany and
/// launchers.
///
/// Parameters:
/// - [manifest]: Parsed app manifest.
///
/// Return value:
/// - Relative icon path, or `null` when absent.
///
/// Requirements/Preconditions:
/// - [manifest] is a parsed app manifest object.
///
/// Guarantees/Postconditions:
/// - Throws when `icon` exists but is not a non-empty string.
///
/// Invariants:
/// - Does not mutate [manifest].
String? _declaredIcon(Map<String, dynamic> manifest) {
  final Object? iconValue = manifest['icon'];
  if (iconValue == null) {
    return null;
  }
  if (iconValue is! String || iconValue.isEmpty) {
    throw ArgumentError('Manifest icon field must be a non-empty string.');
  }
  return iconValue;
}

/// Reads manifest-declared helper binary names.
///
/// Purpose:
/// Lets tests stage helper tools alongside the primary executable without
/// introducing a second bundling convention.
///
/// Parameters:
/// - [manifest]: Parsed app manifest.
///
/// Return value:
/// - Helper binary file names declared in `install.extraBinaries`.
///
/// Requirements/Preconditions:
/// - [manifest] is a parsed app manifest object.
///
/// Guarantees/Postconditions:
/// - Throws when the field exists but is not an array of plain file names.
///
/// Invariants:
/// - Does not mutate [manifest].
List<String> _declaredExtraBinaries(Map<String, dynamic> manifest) {
  final Object? installValue = manifest['install'];
  if (installValue == null) {
    return const <String>[];
  }
  if (installValue is! Map<String, dynamic>) {
    throw ArgumentError('Manifest install field must be an object.');
  }
  final Object? value = installValue['extraBinaries'];
  if (value == null) {
    return const <String>[];
  }
  if (value is! List || value.any((Object? item) => item is! String)) {
    throw ArgumentError('install.extraBinaries must be an array of strings.');
  }

  final List<String> names = value.cast<String>();
  for (final String name in names) {
    if (name.isEmpty || path.basename(name) != name) {
      throw ArgumentError(
        'install.extraBinaries entries must be plain file names: $name',
      );
    }
  }
  return names;
}

/// Resolves one manifest-relative asset without allowing directory escape.
///
/// Purpose:
/// Reuses the install tool's "assets are relative to the manifest directory"
/// rule so tests stage the same logical payload shape.
///
/// Parameters:
/// - [assetEntry]: Relative path string from the manifest.
/// - [manifestDirectory]: Directory containing the manifest file.
///
/// Return value:
/// - File or directory entity addressed by [assetEntry].
///
/// Requirements/Preconditions:
/// - [assetEntry] is a non-empty relative path.
///
/// Guarantees/Postconditions:
/// - Throws when the resolved path escapes [manifestDirectory].
///
/// Invariants:
/// - Does not copy or modify files.
FileSystemEntity _resolveManifestRelativeAsset({
  required String assetEntry,
  required Directory manifestDirectory,
}) {
  if (assetEntry.isEmpty) {
    throw ArgumentError('Asset entries must be non-empty strings.');
  }
  final String manifestRoot = manifestDirectory.absolute.path;
  final String resolvedPath = path.normalize(
    path.absolute(path.join(manifestRoot, assetEntry)),
  );
  final String relative = path.relative(resolvedPath, from: manifestRoot);
  if (relative == '..' || relative.startsWith('../')) {
    throw ArgumentError('Asset path escapes manifest directory: $assetEntry');
  }

  final File fileCandidate = File(resolvedPath);
  if (fileCandidate.existsSync()) {
    return fileCandidate;
  }
  return Directory(resolvedPath);
}

/// Copies one validated asset into the installed app `assets/` tree.
///
/// Purpose:
/// Preserves the source-relative asset layout below `<installed_app>/assets/`.
///
/// Parameters:
/// - [source]: Existing file or directory inside [manifestDirectory].
/// - [manifestDirectory]: Manifest root used to compute relative asset paths.
/// - [installDirectory]: Staging install directory for this app.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - [source] exists and is inside [manifestDirectory].
///
/// Guarantees/Postconditions:
/// - Files are copied byte-for-byte.
/// - Directories are copied recursively.
///
/// Invariants:
/// - Destination paths stay under `<installDirectory>/assets/`.
void _copyAsset({
  required FileSystemEntity source,
  required Directory manifestDirectory,
  required Directory installDirectory,
}) {
  final String sourcePath = source.absolute.path;
  final String relativeSource = path.relative(
    sourcePath,
    from: manifestDirectory.absolute.path,
  );
  final String destinationPath =
      path.join(installDirectory.path, 'assets', relativeSource);

  if (source is Directory) {
    Directory(destinationPath).createSync(recursive: true);
    for (final FileSystemEntity child
        in source.listSync(recursive: true, followLinks: false)) {
      final String childRelative = path.relative(
        child.path,
        from: source.absolute.path,
      );
      final String childDestination = path.join(destinationPath, childRelative);
      if (child is Directory) {
        Directory(childDestination).createSync(recursive: true);
      } else if (child is File) {
        Directory(path.dirname(childDestination)).createSync(recursive: true);
        child.copySync(childDestination);
      }
    }
    return;
  }

  Directory(path.dirname(destinationPath)).createSync(recursive: true);
  (source as File).copySync(destinationPath);
}

/// Copies a manifest-declared icon beside the installed manifest.
///
/// Purpose:
/// Maintains the manifest-relative icon path contract used by launchers.
///
/// Parameters:
/// - [iconEntry]: Relative icon path declared in the manifest.
/// - [manifestDirectory]: Directory containing the source manifest.
/// - [installDirectory]: Staging install directory for this app.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - [iconEntry] resolves to an existing file inside [manifestDirectory].
///
/// Guarantees/Postconditions:
/// - The copied icon exists at `<installDirectory>/<iconEntry>`.
///
/// Invariants:
/// - Icons are not copied under `assets/`.
void _copyManifestIcon({
  required String iconEntry,
  required Directory manifestDirectory,
  required Directory installDirectory,
}) {
  final FileSystemEntity source = _resolveManifestRelativeAsset(
    assetEntry: iconEntry,
    manifestDirectory: manifestDirectory,
  );
  if (source is! File || !source.existsSync()) {
    throw ArgumentError('Declared icon not found: $iconEntry');
  }
  final String relativePath = path.relative(
    source.absolute.path,
    from: manifestDirectory.absolute.path,
  );
  final String destinationPath = path.join(installDirectory.path, relativePath);
  Directory(path.dirname(destinationPath)).createSync(recursive: true);
  source.copySync(destinationPath);
}

/// Copies one primary executable into `bundle/`.
///
/// Purpose:
/// Stages headless/native apps in the same single-binary bundle location that
/// EpiphanyLauncher expects for installed apps.
///
/// Parameters:
/// - [binaryPath]: Source executable file.
/// - [installDirectory]: Staging install directory for this app.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - [binaryPath] exists and is a regular file.
///
/// Guarantees/Postconditions:
/// - The executable is copied to `<installDirectory>/bundle/<basename>`.
///
/// Invariants:
/// - Only the named primary binary is copied.
void _copyBinaryPayload({
  required File binaryPath,
  required Directory installDirectory,
}) {
  if (!binaryPath.existsSync()) {
    throw ArgumentError('Binary not found: ${binaryPath.path}');
  }
  final Directory bundleDirectory =
      Directory(path.join(installDirectory.path, 'bundle'))
        ..createSync(recursive: true);
  binaryPath.copySync(path.join(bundleDirectory.path, path.basename(binaryPath.path)));
}

/// Copies a complete runtime bundle into `bundle/`.
///
/// Purpose:
/// Supports Flutter-style multi-file runtime payloads whose executable is not
/// the only required runtime artifact.
///
/// Parameters:
/// - [bundleDirectory]: Source bundle directory.
/// - [installDirectory]: Staging install directory for this app.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - [bundleDirectory] exists and is a directory.
///
/// Guarantees/Postconditions:
/// - Bundle contents are copied into `<installDirectory>/bundle/`.
///
/// Invariants:
/// - The source bundle directory itself is not nested under `bundle/`.
void _copyBundlePayload({
  required Directory bundleDirectory,
  required Directory installDirectory,
}) {
  if (!bundleDirectory.existsSync()) {
    throw ArgumentError('Bundle directory not found: ${bundleDirectory.path}');
  }

  final Directory destination =
      Directory(path.join(installDirectory.path, 'bundle'))
        ..createSync(recursive: true);
  for (final FileSystemEntity entity
      in bundleDirectory.listSync(recursive: true, followLinks: false)) {
    final String relativePath = path.relative(
      entity.path,
      from: bundleDirectory.absolute.path,
    );
    final String destinationPath = path.join(destination.path, relativePath);
    if (entity is Directory) {
      Directory(destinationPath).createSync(recursive: true);
    } else if (entity is File) {
      Directory(path.dirname(destinationPath)).createSync(recursive: true);
      entity.copySync(destinationPath);
    }
  }
}

/// Copies manifest-declared helper binaries into `bundle/`.
///
/// Purpose:
/// Preserves the explicit `install.extraBinaries` contract so tests can stage
/// the same helper-binary layout as real installs.
///
/// Parameters:
/// - [extraBinaryPaths]: Provided helper binary file paths.
/// - [declaredNames]: Helper binary basenames declared by the manifest.
/// - [installDirectory]: Staging install directory for this app.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - Each declared helper binary has exactly one provided source file.
///
/// Guarantees/Postconditions:
/// - Every declared helper binary is copied into `<installDirectory>/bundle/`.
///
/// Invariants:
/// - Undeclared helper binaries are rejected.
void _copyExtraBinaryPayloads({
  required List<String> extraBinaryPaths,
  required List<String> declaredNames,
  required Directory installDirectory,
}) {
  final Map<String, File> providedByName = <String, File>{};
  for (final String extraBinaryPath in extraBinaryPaths) {
    final File resolved = File(extraBinaryPath).absolute;
    if (!resolved.existsSync()) {
      throw ArgumentError('Extra binary not found: $extraBinaryPath');
    }
    final String name = path.basename(resolved.path);
    if (providedByName.containsKey(name)) {
      throw ArgumentError('Duplicate extra binary provided: $name');
    }
    providedByName[name] = resolved;
  }

  final Set<String> declaredSet = declaredNames.toSet();
  final Set<String> providedSet = providedByName.keys.toSet();
  final List<String> missing = (declaredSet.difference(providedSet).toList()
    ..sort());
  final List<String> unexpected =
      (providedSet.difference(declaredSet).toList()..sort());
  if (missing.isNotEmpty) {
    throw ArgumentError(
      'Missing declared extra binaries: ${missing.join(', ')}',
    );
  }
  if (unexpected.isNotEmpty) {
    throw ArgumentError(
      'Unexpected extra binaries not declared in manifest: ${unexpected.join(', ')}',
    );
  }

  for (final String name in declaredNames) {
    _copyBinaryPayload(
      binaryPath: providedByName[name]!,
      installDirectory: installDirectory,
    );
  }
}

/// Writes lightweight install metadata for staged test apps.
///
/// Purpose:
/// Keeps staged test installs aligned with the normal installed layout by
/// emitting a small `install_metadata.json` file.
///
/// Parameters:
/// - [manifest]: Parsed app manifest.
/// - [manifestFile]: Source manifest file.
/// - [installDirectory]: Staging install directory to describe.
///
/// Return value:
/// - None.
///
/// Requirements/Preconditions:
/// - [installDirectory] already contains the staged app payload.
///
/// Guarantees/Postconditions:
/// - `<installDirectory>/install_metadata.json` exists after this call.
///
/// Invariants:
/// - Metadata generation does not modify staged payload files.
void _writeInstallMetadata({
  required Map<String, dynamic> manifest,
  required File manifestFile,
  required Directory installDirectory,
}) {
  final List<String> installedFiles = _iterInstalledFiles(installDirectory)
    ..add(_metadataName)
    ..sort();
  final JsonEncoder encoder = const JsonEncoder.withIndent('  ');
  final Map<String, Object?> metadata = <String, Object?>{
    'schemaVersion': 1,
    'tool': 'dogpaw_test',
    'appName': manifest['name'],
    'sourceManifest': manifestFile.absolute.path,
    'manifest': _manifestName,
    'installedFiles': installedFiles,
  };
  File(path.join(installDirectory.path, _metadataName)).writeAsStringSync(
    '${encoder.convert(metadata)}\n',
  );
}

/// Lists staged files below one installed app directory as POSIX paths.
///
/// Purpose:
/// Gives install metadata a stable relative file list independent of host path
/// separators.
///
/// Parameters:
/// - [installDirectory]: Staged app directory to inspect.
///
/// Return value:
/// - Sorted relative file paths using `/` separators.
///
/// Requirements/Preconditions:
/// - [installDirectory] exists and is readable.
///
/// Guarantees/Postconditions:
/// - Only regular files are returned.
///
/// Invariants:
/// - The filesystem is read only.
List<String> _iterInstalledFiles(Directory installDirectory) {
  final List<String> files = <String>[];
  for (final FileSystemEntity entity
      in installDirectory.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    files.add(
      path.posix.joinAll(
        path.split(
          path.relative(entity.path, from: installDirectory.path),
        ),
      ),
    );
  }
  files.sort();
  return files;
}

/// Builds the package-owned launch-test stub and returns it as an install source.
///
/// Purpose:
/// Gives public integration tests one portable staged-install fixture that is
/// owned by `dogpaw_test` rather than by internal headless-app sources.
///
/// Parameters:
/// - None.
///
/// Return value:
/// - Future resolving to a binary-based install source for `launch_test_stub`.
///
/// Requirements/Preconditions:
/// - A Dart SDK must be available on `PATH`.
/// - The `dogpaw_test` package must have a readable `.dart_tool/package_config.json`.
///
/// Guarantees/Postconditions:
/// - Compiles the fixture executable when missing or stale.
/// - Returns a source description whose manifest and binary both exist.
///
/// Invariants:
/// - Reuses one in-process future so repeated callers do not compile the same
///   fixture concurrently.
Future<DogpawAppInstallSource> buildLaunchTestStubInstallSource() {
  return _launchTestStubInstallSourceFuture ??=
      _buildLaunchTestStubInstallSourceInternal();
}

/// Builds the launch-test stub install source once for this process.
///
/// Purpose:
/// Resolves the package-owned fixture files, compiles the Dart executable when
/// needed, and materializes the install-source description returned to tests.
///
/// Parameters:
/// - None.
///
/// Return value:
/// - Future resolving to the package-owned launch-test stub install source.
///
/// Requirements/Preconditions:
/// - The package-owned fixture manifest and Dart source must exist.
///
/// Guarantees/Postconditions:
/// - The returned source points at existing files suitable for staged install.
///
/// Invariants:
/// - Does not modify the fixture manifest or Dart source.
Future<DogpawAppInstallSource> _buildLaunchTestStubInstallSourceInternal() async {
  final Directory packageRoot = resolveDogpawTestPackageRoot();
  final Directory fixtureRoot = Directory(
    path.join(packageRoot.path, 'test_fixtures', 'launch_test_stub'),
  );
  final File manifestFile = File(path.join(fixtureRoot.path, _manifestName));
  final File sourceFile =
      File(path.join(fixtureRoot.path, 'bin', 'launch_test_stub.dart'));
  if (!manifestFile.existsSync()) {
    throw StateError('Launch test stub manifest not found: ${manifestFile.path}');
  }
  if (!sourceFile.existsSync()) {
    throw StateError('Launch test stub source not found: ${sourceFile.path}');
  }

  final File compiledBinary = await _compileLaunchTestStubIfNeeded(
    packageRoot: packageRoot,
    manifestFile: manifestFile,
    sourceFile: sourceFile,
  );
  return DogpawAppInstallSource.binary(
    manifestPath: manifestFile.path,
    binaryPath: compiledBinary.path,
  );
}

/// Compiles the package-owned launch-test stub when missing or stale.
///
/// Purpose:
/// Keeps the shipped fixture source small and portable while still letting tests
/// launch a real executable through Epiphany.
///
/// Parameters:
/// - [packageRoot]: `dogpaw_test` package root directory.
/// - [manifestFile]: Fixture manifest file.
/// - [sourceFile]: Fixture Dart source file.
///
/// Return value:
/// - Future resolving to the compiled executable file.
///
/// Requirements/Preconditions:
/// - `dart` must be on `PATH`.
/// - The package config under [packageRoot] must already exist.
///
/// Guarantees/Postconditions:
/// - Returns an existing executable file path on success.
///
/// Invariants:
/// - Only the cache/output directory is written; the fixture source stays
///   unchanged.
Future<File> _compileLaunchTestStubIfNeeded({
  required Directory packageRoot,
  required File manifestFile,
  required File sourceFile,
}) async {
  final File packageConfig =
      File(path.join(packageRoot.path, '.dart_tool', 'package_config.json'));
  if (!packageConfig.existsSync()) {
    throw StateError('dogpaw_test package config not found: ${packageConfig.path}');
  }

  final Directory outputDirectory = Directory(
    path.join(
      Directory.systemTemp.path,
      'dogpaw_test_fixture_cache',
      'launch_test_stub',
    ),
  )..createSync(recursive: true);
  final String executableName =
      Platform.isWindows ? 'launch_test_stub.exe' : 'launch_test_stub';
  final File outputBinary = File(path.join(outputDirectory.path, executableName));

  final bool binaryIsFresh = outputBinary.existsSync() &&
      outputBinary.lastModifiedSync().isAfter(sourceFile.lastModifiedSync()) &&
      outputBinary.lastModifiedSync().isAfter(manifestFile.lastModifiedSync());
  if (binaryIsFresh) {
    return outputBinary;
  }

  final ProcessResult result = await Process.run(
    'dart',
    <String>[
      'compile',
      'exe',
      '--packages=${packageConfig.path}',
      sourceFile.path,
      '-o',
      outputBinary.path,
    ],
  );
  if (result.exitCode != 0 || !outputBinary.existsSync()) {
    final String stdoutText = (result.stdout ?? '').toString();
    final String stderrText = (result.stderr ?? '').toString();
    throw StateError(
      'Failed to compile launch test stub.\nstdout:\n$stdoutText\n\nstderr:\n$stderrText',
    );
  }
  return outputBinary;
}
