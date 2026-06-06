import 'dart:io';
import 'package:path/path.dart' as path;

/// Directory that contains `pubspec.yaml` for the current Flutter app, or the
/// built bundle root when running from packaged desktop output.
///
/// Purpose:
/// Resolves asset-relative paths in a way that stays correct for both source
/// runs and built desktop bundles without depending on the current working
/// directory.
///
/// Parameters:
/// - `scriptUri`: Optional override for the running script URI. Defaults to
///   `Platform.script`.
/// - `resolvedExecutablePath`: Optional override for the executable path.
///   Defaults to `Platform.resolvedExecutable`; symlinks are resolved before
///   bundle-root detection.
/// - `currentWorkingDirectory`: Optional override for the current working
///   directory. Defaults to `Directory.current.path`.
///
/// Return value:
/// - Absolute path to the Flutter package root for source runs.
/// - Absolute path to the Flutter package root when a built app still lives
///   inside its source checkout.
/// - Absolute path to the built bundle directory for out-of-tree packaged
///   desktop apps without a nearby `pubspec.yaml`.
///
/// Requirements/Preconditions:
/// - Any override paths must already be absolute or meaningful to `path.absolute`.
///
/// Guarantees/Postconditions:
/// - Uses the cached production result only when no overrides are supplied.
///
/// Invariants:
/// - Out-of-tree bundles still resolve to the bundle directory when no source
///   package root is present.
String getFlutterPackageRoot({
  Uri? scriptUri,
  String? resolvedExecutablePath,
  String? currentWorkingDirectory,
}) {
  final bool useCache = scriptUri == null &&
      resolvedExecutablePath == null &&
      currentWorkingDirectory == null;
  if (useCache && _cachedFlutterPackageRoot != null) {
    return _cachedFlutterPackageRoot!;
  }

  final Uri effectiveScriptUri = scriptUri ?? Platform.script;
  final String effectiveExecutablePath = _resolveExecutablePathForLookup(
    resolvedExecutablePath ?? Platform.resolvedExecutable,
  );
  final String effectiveWorkingDirectory =
      currentWorkingDirectory ?? Directory.current.path;

  // 1) From script (e.g. lib/main.dart or kernel snapshot)
  if (effectiveScriptUri.scheme == 'file') {
    final String scriptPath = path.normalize(path.fromUri(effectiveScriptUri));
    final String scriptDirectory = path.dirname(scriptPath);
    final String? bundleDirectory = _tryResolveBundleDirectory(
      scriptPath: scriptPath,
      resolvedExecutablePath: effectiveExecutablePath,
    );
    final String? found = _findPackageRootFrom(scriptDirectory);
    if (found != null) {
      if (useCache) {
        _cachedFlutterPackageRoot = found;
      }
      return found;
    }
    if (bundleDirectory != null) {
      if (useCache) {
        _cachedFlutterPackageRoot = bundleDirectory;
      }
      return bundleDirectory;
    }
  }

  // 2) From resolved executable (release binary)
  if (effectiveExecutablePath.isNotEmpty) {
    final String executableDirectory = path.dirname(effectiveExecutablePath);
    final String normalizedExecutableDirectory = path.normalize(
      path.absolute(executableDirectory),
    );
    final String? found = _findPackageRootFrom(normalizedExecutableDirectory);
    if (found != null) {
      if (useCache) {
        _cachedFlutterPackageRoot = found;
      }
      return found;
    }
    // No pubspec in bundle; use executable dir as app root so ../presets works next to bundle
    if (useCache) {
      _cachedFlutterPackageRoot = normalizedExecutableDirectory;
    }
    return normalizedExecutableDirectory;
  }

  // 3) From current working directory
  final String normalizedWorkingDirectory = path.normalize(
    path.absolute(effectiveWorkingDirectory),
  );
  final String? fromCwd = _findPackageRootFrom(normalizedWorkingDirectory);
  if (fromCwd != null) {
    if (useCache) {
      _cachedFlutterPackageRoot = fromCwd;
    }
    return fromCwd;
  }

  if (useCache) {
    _cachedFlutterPackageRoot = normalizedWorkingDirectory;
  }
  return normalizedWorkingDirectory;
}

/// Detect the built bundle directory for a desktop Flutter app script path.
///
/// Purpose:
/// Identifies when `Platform.script` points into `<bundle>/data/flutter_assets/`
/// so package-root discovery can stop at the bundle boundary instead of walking
/// upward into the source tree.
///
/// Parameters:
/// - `scriptPath`: Normalized file path for the running script.
/// - `resolvedExecutablePath`: Path reported by `Platform.resolvedExecutable`.
///
/// Return value:
/// - Normalized bundle directory path when `scriptPath` lives under that
///   bundle's `data/flutter_assets`.
/// - `null` otherwise.
///
/// Requirements/Preconditions:
/// - `scriptPath` should already be normalized.
///
/// Guarantees/Postconditions:
/// - Performs only string/path checks and no filesystem I/O.
///
/// Invariants:
/// - Returned bundle paths always equal `dirname(resolvedExecutablePath)`.
String? _tryResolveBundleDirectory({
  required String scriptPath,
  required String resolvedExecutablePath,
}) {
  if (resolvedExecutablePath.isEmpty) {
    return null;
  }

  final String bundleDirectory = path.normalize(
    path.absolute(path.dirname(resolvedExecutablePath)),
  );
  final String flutterAssetsDirectory = path.normalize(
    path.join(bundleDirectory, 'data', 'flutter_assets'),
  );
  if (scriptPath == flutterAssetsDirectory ||
      path.isWithin(flutterAssetsDirectory, scriptPath)) {
    return bundleDirectory;
  }
  return null;
}

/// Resolve an executable path into the filesystem location used for app assets.
///
/// Purpose:
/// Epiphany launches Flutter apps through runtime-directory symlinks so window
/// managers see a Dog Paw-specific app id. Preset and asset lookup still needs
/// the real bundle directory, so path resolution canonicalizes the executable
/// before higher-level package-root discovery uses it.
///
/// Parameters:
/// - `executablePath`: Path reported by the runtime for the current executable.
///   May be empty, absolute, relative, a normal file, or a symlink.
///
/// Return value:
/// - Absolute canonical path when the executable exists and symbolic links can
///   be resolved.
/// - Absolute normalized input path when resolution is unavailable.
///
/// Requirements/Preconditions:
/// - The caller may pass any string; missing files are handled by fallback.
///
/// Guarantees/Postconditions:
/// - Does not create, modify, or delete filesystem entries.
///
/// Invariants:
/// - Empty input remains empty so callers can continue to use it as "unknown".
String _resolveExecutablePathForLookup(String executablePath) {
  if (executablePath.isEmpty) {
    return executablePath;
  }

  final String normalizedPath = path.normalize(path.absolute(executablePath));
  try {
    return path.normalize(File(normalizedPath).resolveSymbolicLinksSync());
  } on FileSystemException {
    return normalizedPath;
  }
}

/// Walk up from `startDir` looking for a directory that contains `pubspec.yaml`.
///
/// Purpose:
/// Finds the nearest package root while optionally treating one ancestor as a
/// hard boundary that the search must not cross.
///
/// Parameters:
/// - `startDir`: Directory from which to begin the upward walk.
/// - `stopAtDir`: Optional inclusive boundary directory. If provided, the walk
///   checks that directory and stops there even when no `pubspec.yaml` exists.
///
/// Return value:
/// - Absolute package-root path when a `pubspec.yaml` is found.
/// - `null` when no matching directory exists before the filesystem root or the
///   optional boundary.
///
/// Requirements/Preconditions:
/// - `startDir` must describe a real or intended filesystem directory path.
///
/// Guarantees/Postconditions:
/// - Does not create, modify, or delete filesystem entries.
///
/// Invariants:
/// - When `stopAtDir` is provided, no ancestor above it is inspected.
String? _findPackageRootFrom(String startDir, {String? stopAtDir}) {
  Directory current = Directory(path.normalize(path.absolute(startDir)));
  final String? normalizedStopAtDir =
      stopAtDir == null ? null : path.normalize(path.absolute(stopAtDir));
  while (true) {
    final File pubspec = File(path.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      return path.normalize(path.absolute(current.path));
    }
    if (normalizedStopAtDir != null && current.path == normalizedStopAtDir) {
      return null;
    }
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      return null;
    }
    current = parent;
  }
}

String? _cachedFlutterPackageRoot;
