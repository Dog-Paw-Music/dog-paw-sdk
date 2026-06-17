#!/usr/bin/env python3
"""Install a Dog Paw app into the installed-app registry layout."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

try:
    from . import install_fingerprint
except ImportError:
    import install_fingerprint


TOOL_VERSION = "0.1"
MANIFEST_NAME = "dogpawapp.json"
METADATA_NAME = "install_metadata.json"


def load_manifest(manifest_path: Path) -> dict:
    """Load and minimally validate a Dog Paw app manifest.

    Purpose:
        Reads the source `dogpawapp.json` used by install tooling and returns
        its JSON object for later copy decisions.
    Parameters:
        manifest_path: Path to the source manifest. Must point to a readable
            JSON object file.
    Return value:
        Parsed manifest dictionary.
    Requirements/Preconditions:
        `manifest_path` exists, is a file, and contains valid JSON.
    Guarantees/Postconditions:
        The returned object contains at least a string `name` field.
    Invariants:
        The source manifest is read but never modified.
    """
    with manifest_path.open("r", encoding="utf-8") as manifest_file:
        manifest = json.load(manifest_file)
    if not isinstance(manifest, dict):
        raise ValueError("Manifest must be a JSON object")
    app_name = manifest.get("name")
    if not isinstance(app_name, str) or not app_name:
        raise ValueError("Manifest requires a non-empty string name")
    return manifest


def require_relative_asset_path(asset_entry: str, manifest_dir: Path) -> Path:
    """Resolve one manifest asset path without allowing directory escape.

    Purpose:
        Converts a manifest-declared asset entry into an absolute source path
        while enforcing the install contract that assets are relative to the
        manifest directory.
    Parameters:
        asset_entry: Relative file or directory path from `install.assets` or
            `install.optionalAssets`. Must be a string and must not be absolute.
        manifest_dir: Directory containing the source manifest.
    Return value:
        Absolute normalized asset source path.
    Requirements/Preconditions:
        `manifest_dir` is an absolute or resolvable source directory.
    Guarantees/Postconditions:
        Raises ValueError if the resolved asset would escape `manifest_dir`.
    Invariants:
        This function performs path validation only; it does not copy files.
    """
    if not isinstance(asset_entry, str) or not asset_entry:
        raise ValueError("Asset entries must be non-empty strings")
    asset_path = Path(asset_entry)
    if asset_path.is_absolute():
        raise ValueError(f"Asset path must be relative: {asset_entry}")
    manifest_root = manifest_dir.resolve()
    resolved = (manifest_root / asset_path).resolve()
    try:
        resolved.relative_to(manifest_root)
    except ValueError as exc:
        raise ValueError(f"Asset path escapes manifest directory: {asset_entry}") from exc
    return resolved


def iter_installed_files(root: Path) -> list[str]:
    """List installed files below one installed app directory.

    Purpose:
        Produces stable relative paths for `install_metadata.json`.
    Parameters:
        root: Installed app staging directory to inspect.
    Return value:
        Sorted list of POSIX-style relative file paths.
    Requirements/Preconditions:
        `root` exists and is a directory.
    Guarantees/Postconditions:
        Directory entries are omitted; only regular files are returned.
    Invariants:
        The filesystem is read only.
    """
    files: list[str] = []
    for path in root.rglob("*"):
        if path.is_file():
            files.append(path.relative_to(root).as_posix())
    return sorted(files)


def copy_asset(source: Path, manifest_dir: Path, install_dir: Path) -> None:
    """Copy one validated asset into the installed app assets directory.

    Purpose:
        Preserves each manifest-declared asset's relative source structure under
        `<installed_app>/assets/`.
    Parameters:
        source: Absolute source file or directory already validated against the
            manifest directory.
        manifest_dir: Source manifest directory used to compute relative path.
        install_dir: Staging install directory for this app.
    Return value:
        None.
    Requirements/Preconditions:
        `source` exists and is inside `manifest_dir`.
    Guarantees/Postconditions:
        File assets are copied byte-for-byte. Directory assets are copied
        recursively. Parent directories are created as needed.
    Invariants:
        Destination paths never escape `install_dir/assets`.
    """
    relative_source = source.relative_to(manifest_dir.resolve())
    destination = install_dir / "assets" / relative_source
    if source.is_dir():
        shutil.copytree(source, destination, dirs_exist_ok=True)
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def declared_icon(manifest: dict) -> str | None:
    """Read the optional launcher icon path declared by a manifest.

    Purpose:
        Treats the top-level `icon` field as launcher metadata that must be
        installed beside the manifest so Epiphany can publish a valid absolute
        path to UI launchers.
    Parameters:
        manifest: Parsed app manifest dictionary.
    Return value:
        Non-empty icon path string, or `None` when no icon is declared.
    Requirements/Preconditions:
        `manifest` is a parsed Dog Paw app manifest.
    Guarantees/Postconditions:
        Raises ValueError if `icon` exists but is not a non-empty string.
    Invariants:
        The manifest is inspected but never modified.
    """
    value = manifest.get("icon")
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise ValueError("Manifest icon field must be a non-empty string")
    return value


def copy_manifest_icon(icon_entry: str, manifest_dir: Path, install_dir: Path) -> None:
    """Copy a manifest-declared icon beside the installed manifest.

    Purpose:
        Preserves the manifest `icon` relative path under the installed app
        directory so Epiphany's existing relative-path resolution publishes a
        file Home Screen can load directly.
    Parameters:
        icon_entry: Relative icon path from the manifest `icon` field.
        manifest_dir: Directory containing the source manifest.
        install_dir: Staging install directory for this app.
    Return value:
        None.
    Requirements/Preconditions:
        `icon_entry` must resolve to an existing file inside `manifest_dir`.
    Guarantees/Postconditions:
        The icon file exists at `<install_dir>/<icon_entry>`.
    Invariants:
        Icons are copied as launcher metadata, not under `assets/`.
    """
    source = require_relative_asset_path(icon_entry, manifest_dir)
    if not source.is_file():
        raise ValueError(f"Declared icon not found: {icon_entry}")
    relative_source = source.relative_to(manifest_dir.resolve())
    destination = install_dir / relative_source
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def copy_binary_payload(binary_path: Path, install_dir: Path) -> None:
    """Copy a single executable into the installed app bundle directory.

    Purpose:
        Installs native/headless app binaries into the common `bundle/` payload
        location used by EpiphanyLauncher.
    Parameters:
        binary_path: Source executable file to copy.
        install_dir: Staging install directory for this app.
    Return value:
        None.
    Requirements/Preconditions:
        `binary_path` exists and is a regular file.
    Guarantees/Postconditions:
        The executable is copied to `<install_dir>/bundle/<binary-name>` with
        metadata and mode preserved where the platform supports it.
    Invariants:
        Only the requested binary is copied.
    """
    if not binary_path.is_file():
        raise ValueError(f"Binary not found: {binary_path}")
    bundle_dir = install_dir / "bundle"
    bundle_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary_path, bundle_dir / binary_path.name)


def declared_extra_binaries(manifest: dict) -> list[str]:
    """Read helper binary names declared by a manifest.

    Purpose:
        Lets apps ship command-line helper tools alongside their primary
        executable without app-specific install wrappers.
    Parameters:
        manifest: Parsed app manifest.
    Return value:
        List of non-empty helper binary names from `install.extraBinaries`.
    Requirements/Preconditions:
        `manifest` is a parsed app manifest.
    Guarantees/Postconditions:
        Raises ValueError if the field exists but is not a string array of plain
        file names.
    Invariants:
        The manifest is inspected but never modified.
    """
    install = manifest.get("install", {})
    if not isinstance(install, dict):
        raise ValueError("Manifest install field must be an object")
    value = install.get("extraBinaries", [])
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError("install.extraBinaries must be an array of strings")
    for item in value:
        if not item or Path(item).name != item:
            raise ValueError(f"install.extraBinaries entries must be file names: {item}")
    return value


def copy_extra_binary_payloads(
    extra_binary_paths: list[Path],
    declared_names: list[str],
    install_dir: Path,
) -> None:
    """Copy manifest-declared helper binaries into the installed bundle.

    Purpose:
        Enforces that helper binaries shipped in the app bundle are explicitly
        declared in the manifest and supplied by the wrapper/tool caller.
    Parameters:
        extra_binary_paths: Source helper binary files passed on the CLI.
        declared_names: Expected helper binary basenames from the manifest.
        install_dir: Staging install directory for this app.
    Return value:
        None.
    Requirements/Preconditions:
        Each declared helper name must have exactly one matching source path.
    Guarantees/Postconditions:
        Each helper binary is copied to `<install_dir>/bundle/<name>`.
    Invariants:
        Only manifest-declared helper binaries are copied.
    """
    provided_by_name: dict[str, Path] = {}
    for extra_binary_path in extra_binary_paths:
        resolved = extra_binary_path.resolve()
        if not resolved.is_file():
            raise ValueError(f"Extra binary not found: {extra_binary_path}")
        name = resolved.name
        if name in provided_by_name:
            raise ValueError(f"Duplicate extra binary provided: {name}")
        provided_by_name[name] = resolved

    declared_set = set(declared_names)
    provided_set = set(provided_by_name)
    missing = sorted(declared_set - provided_set)
    unexpected = sorted(provided_set - declared_set)
    if missing:
        raise ValueError(f"Missing declared extra binaries: {', '.join(missing)}")
    if unexpected:
        raise ValueError(f"Unexpected extra binaries not declared in manifest: {', '.join(unexpected)}")

    for name in declared_names:
        copy_binary_payload(provided_by_name[name], install_dir)


def copy_bundle_payload(bundle_path: Path, install_dir: Path) -> None:
    """Copy a complete prebuilt runtime bundle into the install layout.

    Purpose:
        Supports Flutter or future multi-file runtime bundles whose executable
        is not the only required runtime artifact.
    Parameters:
        bundle_path: Source bundle directory.
        install_dir: Staging install directory for this app.
    Return value:
        None.
    Requirements/Preconditions:
        `bundle_path` exists and is a directory.
    Guarantees/Postconditions:
        Bundle contents are copied into `<install_dir>/bundle/`.
    Invariants:
        The bundle directory itself is not nested under `bundle/`; only its
        contents are copied.
    """
    if not bundle_path.is_dir():
        raise ValueError(f"Bundle directory not found: {bundle_path}")
    destination = install_dir / "bundle"
    shutil.copytree(bundle_path, destination, dirs_exist_ok=True)


def declared_assets(manifest: dict, key: str) -> list[str]:
    """Read one manifest install asset array.

    Purpose:
        Enforces the first-version schema where `assets` and `optionalAssets`
        contain strings only.
    Parameters:
        manifest: Parsed manifest dictionary.
        key: Install field name to read.
    Return value:
        List of string asset entries. Missing fields return an empty list.
    Requirements/Preconditions:
        `manifest` is a parsed app manifest.
    Guarantees/Postconditions:
        Raises ValueError if the field exists but is not a string array.
    Invariants:
        Mixed string/object arrays are not accepted.
    """
    install = manifest.get("install", {})
    if not isinstance(install, dict):
        raise ValueError("Manifest install field must be an object")
    value = install.get(key, [])
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"install.{key} must be an array of strings")
    return value


def build_source_inputs(
    manifest: dict,
    manifest_path: Path,
    binary_path: Path | None,
    bundle_path: Path | None,
    extra_binary_paths: Iterable[Path],
) -> list[Path]:
    """Collect the source paths that define one installed app version.

    Purpose:
        Builds the install-time source-input list used for stale-install
        detection, covering the manifest, copied payloads, manifest-declared
        assets, and Flutter project/path-dependency sources when applicable.
    Parameters:
        manifest: Parsed source manifest dictionary.
        manifest_path: Source manifest path for the app.
        binary_path: Optional native executable source path for headless apps.
        bundle_path: Optional prebuilt runtime bundle source directory.
        extra_binary_paths: Additional helper executable source paths copied into
            the installed bundle.
    Return value:
        Stable, de-duplicated list of absolute source paths and directories.
    Requirements/Preconditions:
        `manifest` and `manifest_path` refer to the same app source tree.
    Guarantees/Postconditions:
        Optional assets that are currently missing are still included as missing
        paths so a later appearance changes the fingerprint.
    Invariants:
        Reads manifest structure only; does not copy or modify files.
    """
    manifest_dir = manifest_path.parent.resolve()
    inputs: list[Path] = [manifest_path.resolve()]
    if binary_path is not None:
        inputs.append(binary_path.resolve())
    if bundle_path is not None:
        inputs.append(bundle_path.resolve())
    for extra_binary_path in extra_binary_paths:
        inputs.append(extra_binary_path.resolve())

    icon_entry = declared_icon(manifest)
    if icon_entry is not None:
        inputs.append(require_relative_asset_path(icon_entry, manifest_dir))
    for asset in declared_assets(manifest, "assets"):
        inputs.append(require_relative_asset_path(asset, manifest_dir))
    for asset in declared_assets(manifest, "optionalAssets"):
        inputs.append(require_relative_asset_path(asset, manifest_dir))

    flutter_app = manifest.get("flutterApp")
    if isinstance(flutter_app, str) and flutter_app:
        inputs.extend(
            install_fingerprint.flutter_project_source_inputs((manifest_dir / flutter_app).resolve())
        )
    return install_fingerprint.normalize_source_inputs(inputs)


def resolve_cache_root() -> Path:
    """Resolve the Dog Paw persistent cache root for install-time cleanup.

    Purpose:
        Mirrors the runtime cache-root contract so install workflows can clear
        one app's evictable cache without hard-coding one machine-specific path.
    Parameters:
        None.
    Return value:
        Absolute cache root path.
    Requirements/Preconditions:
        One of `DOGPAW_CACHE_DIR`, `XDG_CACHE_HOME`, or `HOME` must be set.
    Guarantees/Postconditions:
        Returns the root path only; does not create or delete anything.
    Invariants:
        `DOGPAW_CACHE_DIR` takes precedence over XDG defaults.
    """
    dogpaw_cache = os.environ.get("DOGPAW_CACHE_DIR", "")
    if dogpaw_cache != "":
        return Path(dogpaw_cache).resolve()
    xdg_cache_home = os.environ.get("XDG_CACHE_HOME", "")
    if xdg_cache_home != "":
        return (Path(xdg_cache_home).resolve() / "dogpaw")
    home = os.environ.get("HOME", "")
    if home != "":
        return (Path(home).resolve() / ".cache" / "dogpaw")
    raise ValueError(
        "Cannot resolve Dog Paw cache root; set DOGPAW_CACHE_DIR, XDG_CACHE_HOME, or HOME"
    )


def resolve_app_cache_dir(app_name: str) -> Path:
    """Resolve the evictable cache directory for one installed app.

    Purpose:
        Centralizes the shared app-cache layout so headless and Flutter installs
        clear the same cache directory shape that DogPawEntity exposes at runtime.
    Parameters:
        app_name: Installed Dog Paw app name from the manifest `name` field.
    Return value:
        Absolute cache directory path for that app.
    Requirements/Preconditions:
        `app_name` is a non-empty string.
    Guarantees/Postconditions:
        Returns the path only; does not touch the filesystem.
    Invariants:
        The returned path always lives under `<cacheRoot>/appCache/`.
    """
    if app_name == "":
        raise ValueError("app_name must be non-empty")
    cache_root = resolve_cache_root()
    emulator_name = os.environ.get("DOGPAW_EMULATOR_NAME", "")
    if emulator_name != "":
        return cache_root / "emulators" / emulator_name / "appCache" / app_name
    return cache_root / "appCache" / app_name


def clear_app_cache(app_name: str) -> None:
    """Remove one app's evictable cache directory when it exists.

    Purpose:
        Ensures installs replace any derived artifacts that may no longer match
        the newly installed app payload.
    Parameters:
        app_name: Installed Dog Paw app name whose cache should be cleared.
    Return value:
        None.
    Requirements/Preconditions:
        `app_name` is a non-empty string.
    Guarantees/Postconditions:
        The app cache directory is absent after this returns successfully.
    Invariants:
        Only the selected app cache directory is removed.
    """
    shutil.rmtree(resolve_app_cache_dir(app_name), ignore_errors=False)


def install_app(
    manifest_path: Path,
    app_root: Path,
    binary_path: Path | None,
    bundle_path: Path | None,
    extra_binary_paths: list[Path],
    *,
    keep_cache_on_install: bool = False,
) -> Path:
    """Install one Dog Paw app into an app registry root.

    Purpose:
        Copies the manifest, runtime payload, explicit assets, and generated
        metadata into the installed-app directory shape.
    Parameters:
        manifest_path: Source `dogpawapp.json`.
        app_root: Directory containing installed app subdirectories.
        binary_path: Optional single executable payload source.
        bundle_path: Optional complete runtime bundle source.
        extra_binary_paths: Additional helper executable files to copy into the
            installed bundle. Must match `install.extraBinaries`.
        keep_cache_on_install: When `True`, preserves any existing app cache
            instead of clearing it before install replacement.
    Return value:
        Path to the final installed app directory.
    Requirements/Preconditions:
        Exactly one of `binary_path` or `bundle_path` is provided.
    Guarantees/Postconditions:
        On success, `<app_root>/<app-name>` is replaced atomically enough for
        local filesystem install workflows. On validation failure, no final app
        directory is created by this invocation.
    Invariants:
        Source paths are never copied outside the selected app install
        directory.
    """
    if (binary_path is None) == (bundle_path is None):
        raise ValueError("Provide exactly one of --binary or --bundle")

    manifest_path = manifest_path.resolve()
    manifest_dir = manifest_path.parent
    manifest = load_manifest(manifest_path)
    app_name = manifest["name"]
    extra_binary_names = declared_extra_binaries(manifest)
    icon_entry = declared_icon(manifest)

    app_root.mkdir(parents=True, exist_ok=True)
    final_dir = app_root / app_name
    staging_dir = Path(
        tempfile.mkdtemp(prefix=f".installing_{app_name}_", dir=str(app_root))
    )

    skipped_optional: list[str] = []
    try:
        shutil.copy2(manifest_path, staging_dir / MANIFEST_NAME)
        if binary_path is not None:
            copy_binary_payload(binary_path.resolve(), staging_dir)
        if bundle_path is not None:
            copy_bundle_payload(bundle_path.resolve(), staging_dir)
        if icon_entry is not None:
            copy_manifest_icon(icon_entry, manifest_dir, staging_dir)
        copy_extra_binary_payloads(extra_binary_paths, extra_binary_names, staging_dir)

        for asset in declared_assets(manifest, "assets"):
            source = require_relative_asset_path(asset, manifest_dir)
            if not source.exists():
                raise ValueError(f"Required asset not found: {asset}")
            copy_asset(source, manifest_dir, staging_dir)

        for asset in declared_assets(manifest, "optionalAssets"):
            source = require_relative_asset_path(asset, manifest_dir)
            if not source.exists():
                skipped_optional.append(asset)
                continue
            copy_asset(source, manifest_dir, staging_dir)

        metadata = build_metadata(
            manifest,
            manifest_path,
            staging_dir,
            skipped_optional,
            binary_path=binary_path,
            bundle_path=bundle_path,
            extra_binary_paths=extra_binary_paths,
        )
        (staging_dir / METADATA_NAME).write_text(
            json.dumps(metadata, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        if not keep_cache_on_install:
            cache_dir = resolve_app_cache_dir(app_name)
            if cache_dir.exists():
                clear_app_cache(app_name)
        if final_dir.exists():
            shutil.rmtree(final_dir)
        staging_dir.rename(final_dir)
        return final_dir
    except Exception:
        shutil.rmtree(staging_dir, ignore_errors=True)
        raise


def build_metadata(
    manifest: dict,
    manifest_path: Path,
    install_dir: Path,
    skipped_optional_assets: Iterable[str],
    *,
    binary_path: Path | None,
    bundle_path: Path | None,
    extra_binary_paths: Iterable[Path],
) -> dict:
    """Build the generated install metadata document.

    Purpose:
        Records enough install information for debugging, auditing, and future
        uninstall support.
    Parameters:
        manifest: Parsed source manifest.
        manifest_path: Source manifest path.
        install_dir: Staging install directory whose files should be listed.
        skipped_optional_assets: Optional asset entries that were absent.
        binary_path: Optional native executable source path for this install.
        bundle_path: Optional prebuilt runtime bundle source directory.
        extra_binary_paths: Additional helper executable source paths included in
            the install bundle.
    Return value:
        JSON-serializable metadata dictionary.
    Requirements/Preconditions:
        `install_dir` contains the files that will become the installed app.
    Guarantees/Postconditions:
        Metadata includes sorted installed file paths relative to `install_dir`.
    Invariants:
        Metadata generation does not modify installed files.
    """
    source_inputs, source_fingerprint = install_fingerprint.fingerprint_source_inputs(
        build_source_inputs(
            manifest,
            manifest_path,
            binary_path=binary_path,
            bundle_path=bundle_path,
            extra_binary_paths=extra_binary_paths,
        )
    )
    return {
        "schemaVersion": 2,
        "tool": "install_app.py",
        "toolVersion": TOOL_VERSION,
        "installedAt": datetime.now(timezone.utc).isoformat(),
        "appName": manifest["name"],
        "version": manifest.get("version", ""),
        "sourceManifest": str(manifest_path),
        "sourceInputs": source_inputs,
        "sourceFingerprint": source_fingerprint,
        "manifest": MANIFEST_NAME,
        "installedFiles": iter_installed_files(install_dir),
        "skippedOptionalAssets": sorted(skipped_optional_assets),
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse command-line arguments for the install tool.

    Purpose:
        Provides a stable CLI for repo, Pi, and SDK install wrappers.
    Parameters:
        argv: Command-line arguments excluding program name.
    Return value:
        Parsed argparse namespace.
    Requirements/Preconditions:
        `argv` is a list of strings.
    Guarantees/Postconditions:
        Required argument shape is validated by argparse.
    Invariants:
        Filesystem state is unchanged.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--app-root", required=True, type=Path)
    payload = parser.add_mutually_exclusive_group(required=True)
    payload.add_argument("--binary", type=Path)
    payload.add_argument("--bundle", type=Path)
    parser.add_argument("--extra-binary", action="append", default=[], type=Path)
    parser.add_argument(
        "--keep-cache-on-install",
        action="store_true",
        help="Preserve the app's existing persistent cache instead of clearing it during install.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Run the install tool command-line entry point.

    Purpose:
        Converts CLI arguments into one install operation and user-readable
        success/failure output.
    Parameters:
        argv: Command-line arguments excluding program name.
    Return value:
        Process exit code: 0 on success, 1 on install/validation failure.
    Requirements/Preconditions:
        `argv` follows `parse_args` expectations.
    Guarantees/Postconditions:
        On success, stdout contains the installed app directory path. On failure,
        stderr contains the error.
    Invariants:
        Exceptions are contained and converted to nonzero process status.
    """
    args = parse_args(argv)
    try:
        installed_dir = install_app(
            args.manifest,
            args.app_root,
            args.binary,
            args.bundle,
            args.extra_binary,
            keep_cache_on_install=args.keep_cache_on_install,
        )
    except Exception as error:
        print(f"install_app.py: {error}", file=sys.stderr)
        return 1
    print(installed_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
