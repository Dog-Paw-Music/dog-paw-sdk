import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as path;

const String _bridgeLibraryBaseName = 'libdogpaw_bridge.so';

/// Resolves an arbitrary Dart package root from the active package config.
///
/// Purpose:
/// Centralizes package-root discovery so `dogpaw_test` can locate both its own
/// fixtures and sibling package assets without depending on the current working
/// directory.
///
/// Parameters:
/// - [packageName]: Package name to resolve from the active package graph.
/// - [packageRootPath]: Optional explicit package root path to trust directly.
///
/// Return value:
/// - Directory for the resolved package root.
///
/// Requirements/Preconditions:
/// - [packageName] is non-empty.
/// - When [packageRootPath] is omitted, the current process must expose an
///   active `.dart_tool/package_config.json`.
///
/// Guarantees/Postconditions:
/// - Returns a directory containing the requested package's `lib/` subtree when
///   the package is present in the active package graph.
///
/// Invariants:
/// - Does not write to the filesystem.
Directory resolvePackageRoot({
  required String packageName,
  String? packageRootPath,
}) {
  if (packageRootPath != null && packageRootPath.isNotEmpty) {
    return Directory(packageRootPath);
  }

  final File packageConfig = findActivePackageConfig();
  final Map<String, dynamic> config = jsonDecode(
    packageConfig.readAsStringSync(),
  ) as Map<String, dynamic>;
  final List<dynamic> packages = config['packages'] as List<dynamic>? ?? <dynamic>[];
  for (final dynamic entry in packages) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    if (entry['name'] != packageName) {
      continue;
    }
    final String? rootUriText = entry['rootUri'] as String?;
    if (rootUriText == null || rootUriText.isEmpty) {
      break;
    }
    final Uri resolvedRoot = packageConfig.parent.uri.resolve(rootUriText);
    return Directory.fromUri(resolvedRoot);
  }

  throw StateError(
    'Could not resolve $packageName from package config: ${packageConfig.path}',
  );
}

/// Resolves the `dogpaw_test` package root on disk.
///
/// Purpose:
/// Gives public test helpers one shared way to find package-owned fixtures and
/// SDK-relative runtime assets without depending on the current working
/// directory.
///
/// Parameters:
/// - [packageRootPath]: Optional explicit package root path to trust directly.
///
/// Return value:
/// - Directory for the `dogpaw_test` package root.
///
/// Requirements/Preconditions:
/// - When [packageRootPath] is omitted, the current process must be running from
///   a workspace that exposes `.dart_tool/package_config.json`.
///
/// Guarantees/Postconditions:
/// - Returns a directory containing the package's `lib/` subtree.
///
/// Invariants:
/// - Does not write to the filesystem.
Directory resolveDogpawTestPackageRoot({String? packageRootPath}) {
  return resolvePackageRoot(
    packageName: 'dogpaw_test',
    packageRootPath: packageRootPath,
  );
}

/// Resolves the sibling `dogpaw` package root on disk.
///
/// Purpose:
/// Lets `dogpaw_test` discover shipped native bridge artifacts owned by the
/// public `dogpaw` package.
///
/// Parameters:
/// - [packageRootPath]: Optional explicit `dogpaw` package root path.
///
/// Return value:
/// - Directory for the `dogpaw` package root.
///
/// Requirements/Preconditions:
/// - When [packageRootPath] is omitted, the current process must expose an
///   active `.dart_tool/package_config.json` containing `dogpaw`.
///
/// Guarantees/Postconditions:
/// - Returns a directory containing the package's `lib/` subtree.
///
/// Invariants:
/// - Does not write to the filesystem.
Directory resolveDogpawPackageRoot({String? packageRootPath}) {
  return resolvePackageRoot(
    packageName: 'dogpaw',
    packageRootPath: packageRootPath,
  );
}

/// Finds the active package-config file for the current process.
///
/// Purpose:
/// Anchors package-root discovery to the same package graph used by the running
/// Dart or Flutter test process.
///
/// Parameters:
/// - [startPath]: Optional explicit starting path for the ancestor walk.
///
/// Return value:
/// - Existing `.dart_tool/package_config.json` file used by the current process.
///
/// Requirements/Preconditions:
/// - [startPath] or `Platform.script` must resolve under a package workspace or
///   generated package-config tree.
///
/// Guarantees/Postconditions:
/// - Returns a readable package-config file path when found.
///
/// Invariants:
/// - Walks ancestor directories only; does not modify any files.
File findActivePackageConfig({String? startPath}) {
  Directory current = startPath == null
      ? File.fromUri(Platform.script).absolute.parent
      : Directory(startPath).absolute;
  while (true) {
    final File candidate =
        File(path.join(current.path, '.dart_tool', 'package_config.json'));
    if (candidate.existsSync()) {
      return candidate;
    }
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  throw StateError(
    'Could not find .dart_tool/package_config.json from '
    '${startPath ?? Platform.script}',
  );
}

/// Builds ordered Epiphany-binary search paths for the public `dogpaw_test`
/// fixture.
///
/// Purpose:
/// Defines the portable search order used by `IntegrationTestFixture` without
/// encoding monorepo-specific build directories into the shipped package.
///
/// Parameters:
/// - [explicitPath]: Optional explicit Epiphany binary path from test
///   configuration.
/// - [environment]: Environment snapshot to inspect for `EPIPHANY_PATH`.
/// - [packageRootPath]: Optional explicit `dogpaw_test` package root.
///
/// Return value:
/// - Ordered candidate Epiphany binary paths.
///
/// Requirements/Preconditions:
/// - Any provided paths should already use host-platform separators.
///
/// Guarantees/Postconditions:
/// - Explicit configuration appears first when present.
/// - `EPIPHANY_PATH` appears next when present.
/// - SDK-runtime candidates are included after explicit overrides.
/// - Source-checkout build-output candidates are appended last as a temporary
///   convenience fallback.
///
/// Invariants:
/// - SDK/runtime candidates remain preferred over source-checkout build-output
///   convenience fallbacks.
List<String> buildEpiphanyBinarySearchPaths({
  required String? explicitPath,
  required Map<String, String> environment,
  String? packageRootPath,
}) {
  final List<String> searchPaths = <String>[];
  final Set<String> seenPaths = <String>{};

  void appendCandidate(String candidate) {
    if (candidate.isEmpty || seenPaths.contains(candidate)) {
      return;
    }
    seenPaths.add(candidate);
    searchPaths.add(candidate);
  }

  if (explicitPath != null && explicitPath.isNotEmpty) {
    appendCandidate(explicitPath);
  }

  final String? envPath = environment['EPIPHANY_PATH'];
  if (envPath != null && envPath.isNotEmpty) {
    appendCandidate(envPath);
  }

  final String? resolvedPackageRootPath = _tryResolveDogpawTestPackageRootPath(
    packageRootPath: packageRootPath,
  );
  if (resolvedPackageRootPath == null) {
    return searchPaths;
  }

  for (final String candidate
      in _buildSdkRuntimeEpiphanyCandidates(packageRootPath: resolvedPackageRootPath)) {
    appendCandidate(candidate);
  }

  for (final String candidate in _buildSourceCheckoutEpiphanyCandidates(
    packageRootPath: resolvedPackageRootPath,
  )) {
    appendCandidate(candidate);
  }

  return searchPaths;
}

/// Builds ordered native-bridge search paths for `dogpaw_test` fixtures.
///
/// Purpose:
/// Lets the public fixture set `DOGPAW_BRIDGE_LIB` automatically in source
/// checkouts and exported SDK trees before `DogPawBridge` is first created.
///
/// Parameters:
/// - [environment]: Environment snapshot to inspect for `DOGPAW_BRIDGE_LIB`.
/// - [dogpawTestPackageRootPath]: Optional explicit `dogpaw_test` package root.
/// - [dogpawPackageRootPath]: Optional explicit `dogpaw` package root.
///
/// Return value:
/// - Ordered candidate native-bridge library paths.
///
/// Requirements/Preconditions:
/// - Any provided paths should already use host-platform separators.
///
/// Guarantees/Postconditions:
/// - Explicit `DOGPAW_BRIDGE_LIB` appears first when present.
/// - SDK-runtime and package-owned bridge candidates appear after the explicit
///   override.
/// - Source-checkout build-output candidates are appended last as a temporary
///   convenience fallback.
///
/// Invariants:
/// - SDK/runtime and package-owned bridge candidates remain preferred over
///   source-checkout build-output convenience fallbacks.
List<String> buildBridgeLibrarySearchPaths({
  required Map<String, String> environment,
  String? dogpawTestPackageRootPath,
  String? dogpawPackageRootPath,
}) {
  final List<String> searchPaths = <String>[];
  final Set<String> seenPaths = <String>{};

  void appendCandidate(String candidate) {
    if (candidate.isEmpty || seenPaths.contains(candidate)) {
      return;
    }
    seenPaths.add(candidate);
    searchPaths.add(candidate);
  }

  final String? explicitPath = environment['DOGPAW_BRIDGE_LIB'];
  if (explicitPath != null && explicitPath.isNotEmpty) {
    appendCandidate(explicitPath);
  }

  final String? resolvedDogpawTestPackageRootPath =
      _tryResolveDogpawTestPackageRootPath(
    packageRootPath: dogpawTestPackageRootPath,
  );
  if (resolvedDogpawTestPackageRootPath != null) {
    for (final String candidate in _buildSdkRuntimeBridgeCandidates(
      packageRootPath: resolvedDogpawTestPackageRootPath,
    )) {
      appendCandidate(candidate);
    }
  }

  final String? resolvedDogpawPackageRootPath = _tryResolveDogpawPackageRootPath(
    packageRootPath: dogpawPackageRootPath,
  );
  if (resolvedDogpawPackageRootPath != null) {
    for (final String candidate in _buildDogpawPackageBridgeCandidates(
      packageRootPath: resolvedDogpawPackageRootPath,
    )) {
      appendCandidate(candidate);
    }
    for (final String candidate in _buildSourceCheckoutBridgeCandidates(
      packageRootPath: resolvedDogpawPackageRootPath,
    )) {
      appendCandidate(candidate);
    }
  }

  return searchPaths;
}

/// Resolves the first existing native-bridge library path for fixture setup.
///
/// Purpose:
/// Converts the ordered bridge search policy into the concrete library path used
/// to seed `DOGPAW_BRIDGE_LIB` before the first `DogPawBridge` instance.
///
/// Parameters:
/// - [environment]: Environment snapshot to inspect for `DOGPAW_BRIDGE_LIB`.
/// - [dogpawTestPackageRootPath]: Optional explicit `dogpaw_test` package root.
/// - [dogpawPackageRootPath]: Optional explicit `dogpaw` package root.
///
/// Return value:
/// - Existing native-bridge library path, or `null` when no candidate exists.
///
/// Requirements/Preconditions:
/// - Candidate paths, when present, point at regular files.
///
/// Guarantees/Postconditions:
/// - Returns the first existing path from [buildBridgeLibrarySearchPaths].
///
/// Invariants:
/// - Does not create or modify files.
String? resolveBridgeLibraryPathForFixture({
  required Map<String, String> environment,
  String? dogpawTestPackageRootPath,
  String? dogpawPackageRootPath,
}) {
  for (final String candidate in buildBridgeLibrarySearchPaths(
    environment: environment,
    dogpawTestPackageRootPath: dogpawTestPackageRootPath,
    dogpawPackageRootPath: dogpawPackageRootPath,
  )) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

/// Resolves the first existing Epiphany binary path for the public fixture.
///
/// Purpose:
/// Converts the ordered portable search policy into the concrete binary path used
/// to spawn Epiphany for integration tests.
///
/// Parameters:
/// - [explicitPath]: Optional explicit Epiphany binary path from test
///   configuration.
/// - [environment]: Environment snapshot to inspect for `EPIPHANY_PATH`.
/// - [packageRootPath]: Optional explicit `dogpaw_test` package root.
///
/// Return value:
/// - Existing Epiphany binary path, or `null` when no candidate exists.
///
/// Requirements/Preconditions:
/// - Candidate paths, when present, point at regular files.
///
/// Guarantees/Postconditions:
/// - Returns the first existing path from [buildEpiphanyBinarySearchPaths].
///
/// Invariants:
/// - Does not create or modify files.
String? resolveEpiphanyBinaryPath({
  required String? explicitPath,
  required Map<String, String> environment,
  String? packageRootPath,
}) {
  for (final String candidate in buildEpiphanyBinarySearchPaths(
    explicitPath: explicitPath,
    environment: environment,
    packageRootPath: packageRootPath,
  )) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

/// Best-effort package-root resolution that never throws.
///
/// Purpose:
/// Lets path-search helpers stay usable in partially configured environments by
/// treating package-root discovery failure as "no SDK-relative candidate".
///
/// Parameters:
/// - [packageRootPath]: Optional explicit package root path to trust directly.
///
/// Return value:
/// - Resolved package root path, or `null` when discovery fails.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Never throws.
///
/// Invariants:
/// - Does not write to the filesystem.
String? _tryResolveDogpawTestPackageRootPath({String? packageRootPath}) {
  try {
    return resolveDogpawTestPackageRoot(
      packageRootPath: packageRootPath,
    ).path;
  } catch (_) {
    return null;
  }
}

/// Best-effort `dogpaw` package-root resolution that never throws.
///
/// Purpose:
/// Lets bridge-library search helpers degrade cleanly when the sibling package
/// root is not discoverable in the active package graph.
///
/// Parameters:
/// - [packageRootPath]: Optional explicit `dogpaw` package root path.
///
/// Return value:
/// - Resolved package root path, or `null` when discovery fails.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Never throws.
///
/// Invariants:
/// - Does not write to the filesystem.
String? _tryResolveDogpawPackageRootPath({String? packageRootPath}) {
  try {
    return resolveDogpawPackageRoot(
      packageRootPath: packageRootPath,
    ).path;
  } catch (_) {
    return null;
  }
}

/// Builds SDK-runtime Epiphany candidates relative to the package root.
///
/// Purpose:
/// Finds the Epiphany binary shipped in the exported SDK runtime layout.
///
/// Parameters:
/// - [packageRootPath]: Absolute `dogpaw_test` package root path.
///
/// Return value:
/// - Ordered SDK-runtime candidate paths.
///
/// Requirements/Preconditions:
/// - [packageRootPath] points at the `packages/dogpaw_test` directory.
///
/// Guarantees/Postconditions:
/// - The host-runtime candidate appears first when its triplet is known.
///
/// Invariants:
/// - Does not inspect monorepo build directories.
List<String> _buildSdkRuntimeEpiphanyCandidates({
  required String packageRootPath,
}) {
  final String sdkRootPath = path.normalize(
    path.join(packageRootPath, '..', '..'),
  );
  final String runtimeBinRootPath = path.join(sdkRootPath, 'runtime', 'bin');
  final Directory runtimeBinRoot = Directory(runtimeBinRootPath);

  final List<String> candidates = <String>[];
  final Set<String> seenPaths = <String>{};

  void appendCandidate(String candidate) {
    if (candidate.isEmpty || seenPaths.contains(candidate)) {
      return;
    }
    seenPaths.add(candidate);
    candidates.add(candidate);
  }

  final String? preferredTriplet = _hostRuntimeTriplet();
  if (preferredTriplet != null) {
    appendCandidate(path.join(runtimeBinRootPath, preferredTriplet, 'Epiphany'));
  }

  appendCandidate(path.join(runtimeBinRootPath, 'Epiphany'));

  if (runtimeBinRoot.existsSync()) {
    final List<Directory> tripletDirectories = runtimeBinRoot
        .listSync(followLinks: false)
        .whereType<Directory>()
        .toList()
      ..sort((Directory left, Directory right) => left.path.compareTo(right.path));
    for (final Directory tripletDirectory in tripletDirectories) {
      appendCandidate(path.join(tripletDirectory.path, 'Epiphany'));
    }
  }

  return candidates;
}

/// Builds SDK-runtime bridge-library candidates relative to the package root.
///
/// Purpose:
/// Finds the bridge library shipped in the exported SDK runtime layout for
/// `dogpaw_test` integration runs that execute from the SDK tree.
///
/// Parameters:
/// - [packageRootPath]: Absolute `dogpaw_test` package root path.
///
/// Return value:
/// - Ordered SDK-runtime bridge-library candidate paths.
///
/// Requirements/Preconditions:
/// - [packageRootPath] points at the `packages/dogpaw_test` directory.
///
/// Guarantees/Postconditions:
/// - The host-runtime candidate appears when its triplet is known.
///
/// Invariants:
/// - Does not inspect source-checkout build directories.
List<String> _buildSdkRuntimeBridgeCandidates({
  required String packageRootPath,
}) {
  final String sdkRootPath = path.normalize(
    path.join(packageRootPath, '..', '..'),
  );
  final String runtimeLibRootPath = path.join(sdkRootPath, 'runtime', 'lib');
  final List<String> candidates = <String>[];
  final Set<String> seenPaths = <String>{};

  void appendCandidate(String candidate) {
    if (candidate.isEmpty || seenPaths.contains(candidate)) {
      return;
    }
    seenPaths.add(candidate);
    candidates.add(candidate);
  }

  final String? preferredTriplet = _hostRuntimeTriplet();
  if (preferredTriplet != null) {
    appendCandidate(
      path.join(runtimeLibRootPath, preferredTriplet, _bridgeLibraryBaseName),
    );
  }

  appendCandidate(path.join(runtimeLibRootPath, _bridgeLibraryBaseName));

  return candidates;
}

/// Builds `dogpaw` package-owned bridge-library candidates.
///
/// Purpose:
/// Gives source checkouts and exported SDK trees a stable public location for
/// the native bridge library without needing external environment setup.
///
/// Parameters:
/// - [packageRootPath]: Absolute `dogpaw` package root path.
///
/// Return value:
/// - Ordered package-owned bridge-library candidate paths.
///
/// Requirements/Preconditions:
/// - [packageRootPath] points at the `dogpaw` package directory.
///
/// Guarantees/Postconditions:
/// - The host-runtime candidate appears when its triplet is known.
///
/// Invariants:
/// - Only package-owned prebuilt assets are considered.
List<String> _buildDogpawPackageBridgeCandidates({
  required String packageRootPath,
}) {
  final List<String> candidates = <String>[];
  final Set<String> seenPaths = <String>{};

  void appendCandidate(String candidate) {
    if (candidate.isEmpty || seenPaths.contains(candidate)) {
      return;
    }
    seenPaths.add(candidate);
    candidates.add(candidate);
  }

  final String prebuiltRootPath = path.join(packageRootPath, 'linux', 'prebuilt');
  final String? preferredTriplet = _hostRuntimeTriplet();
  if (preferredTriplet != null) {
    appendCandidate(
      path.join(prebuiltRootPath, preferredTriplet, _bridgeLibraryBaseName),
    );
  }

  return candidates;
}

/// Builds temporary source-checkout bridge candidates from nearby build
/// directories.
///
/// Purpose:
/// Keeps manual dev-repo Flutter test runs convenient without requiring callers
/// to seed `DOGPAW_BRIDGE_LIB` for the common local-build case.
///
/// Parameters:
/// - [packageRootPath]: Absolute `dogpaw` package root path.
///
/// Return value:
/// - Ordered source-checkout bridge-library candidate paths.
///
/// Requirements/Preconditions:
/// - [packageRootPath] points somewhere inside a source checkout when this
///   fallback is expected to produce results.
///
/// Guarantees/Postconditions:
/// - Returns candidates from nearest matching ancestor build directories first.
///
/// Invariants:
/// - Runs after explicit, SDK-runtime, and package-owned candidates.
/// - TODO: Remove this source-checkout convenience fallback after dev-repo runs
///   use dedicated wrapper tooling again.
List<String> _buildSourceCheckoutBridgeCandidates({
  required String packageRootPath,
}) {
  final List<String> candidates = <String>[];
  final Set<String> seenPaths = <String>{};

  void appendCandidate(String candidate) {
    if (candidate.isEmpty || seenPaths.contains(candidate)) {
      return;
    }
    seenPaths.add(candidate);
    candidates.add(candidate);
  }

  for (final Directory ancestor in _ancestorDirectories(packageRootPath)) {
    if (!ancestor.existsSync()) {
      continue;
    }
    final List<Directory> buildDirectories = ancestor
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((Directory directory) =>
            path.basename(directory.path).startsWith('build'))
        .toList()
      ..sort((Directory left, Directory right) {
        final String leftName = path.basename(left.path);
        final String rightName = path.basename(right.path);
        final int leftPriority = leftName == 'build' ? 1 : 0;
        final int rightPriority = rightName == 'build' ? 1 : 0;
        if (leftPriority != rightPriority) {
          return leftPriority.compareTo(rightPriority);
        }
        return left.path.compareTo(right.path);
      });
    for (final Directory buildDirectory in buildDirectories) {
      appendCandidate(
        path.join(buildDirectory.path, 'lib', _bridgeLibraryBaseName),
      );
    }
  }

  return candidates;
}

/// Builds temporary source-checkout Epiphany candidates from nearby build
/// directories.
///
/// Purpose:
/// Keeps manual dev-repo test runs convenient without requiring callers to set
/// `EPIPHANY_PATH` for the common local-build case.
///
/// Parameters:
/// - [packageRootPath]: Absolute `dogpaw_test` package root path.
///
/// Return value:
/// - Ordered source-checkout Epiphany candidate paths.
///
/// Requirements/Preconditions:
/// - [packageRootPath] points somewhere inside a source checkout when this
///   fallback is expected to produce results.
///
/// Guarantees/Postconditions:
/// - Returns candidates from nearest matching ancestor build directories first.
///
/// Invariants:
/// - Runs after explicit and SDK-runtime candidates.
/// - TODO: Remove this source-checkout convenience fallback after dev-repo runs
///   use dedicated wrapper tooling again.
List<String> _buildSourceCheckoutEpiphanyCandidates({
  required String packageRootPath,
}) {
  final List<String> candidates = <String>[];
  final Set<String> seenPaths = <String>{};

  void appendCandidate(String candidate) {
    if (candidate.isEmpty || seenPaths.contains(candidate)) {
      return;
    }
    seenPaths.add(candidate);
    candidates.add(candidate);
  }

  for (final Directory ancestor in _ancestorDirectories(packageRootPath)) {
    if (!ancestor.existsSync()) {
      continue;
    }
    final List<Directory> buildDirectories = ancestor
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((Directory directory) =>
            path.basename(directory.path).startsWith('build'))
        .toList()
      ..sort((Directory left, Directory right) {
        final String leftName = path.basename(left.path);
        final String rightName = path.basename(right.path);
        final int leftPriority = leftName == 'build' ? 1 : 0;
        final int rightPriority = rightName == 'build' ? 1 : 0;
        if (leftPriority != rightPriority) {
          return leftPriority.compareTo(rightPriority);
        }
        return left.path.compareTo(right.path);
      });
    for (final Directory buildDirectory in buildDirectories) {
      appendCandidate(path.join(buildDirectory.path, 'bin', 'Epiphany'));
    }
  }

  return candidates;
}

/// Lists one directory followed by its ancestors.
///
/// Purpose:
/// Supports generic package-root-relative searches without baking in a specific
/// repository root name.
///
/// Parameters:
/// - [startPath]: Filesystem path to start from.
///
/// Return value:
/// - Ordered directories from nearest to farthest ancestor.
///
/// Requirements/Preconditions:
/// - [startPath] is non-empty.
///
/// Guarantees/Postconditions:
/// - Includes the starting directory itself.
///
/// Invariants:
/// - Stops at the filesystem root.
List<Directory> _ancestorDirectories(String startPath) {
  final List<Directory> directories = <Directory>[];
  Directory current = Directory(startPath).absolute;
  while (true) {
    directories.add(current);
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }
  return directories;
}

/// Maps the current Dart ABI to the SDK runtime triplet naming convention.
///
/// Purpose:
/// Lets SDK-runtime path resolution prefer the host platform's packaged binary
/// before trying other runtime-bin subdirectories.
///
/// Parameters:
/// - None.
///
/// Return value:
/// - SDK runtime triplet such as `linux-x64`, or `null` when unsupported.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Returns a stable triplet string for known host ABIs.
///
/// Invariants:
/// - Unknown ABIs return `null` instead of guessing.
String? _hostRuntimeTriplet() {
  switch (Abi.current()) {
    case Abi.linuxX64:
      return 'linux-x64';
    case Abi.linuxArm64:
      return 'linux-arm64';
    case Abi.macosX64:
      return 'macos-x64';
    case Abi.macosArm64:
      return 'macos-arm64';
    case Abi.windowsX64:
      return 'windows-x64';
    default:
      return null;
  }
}
