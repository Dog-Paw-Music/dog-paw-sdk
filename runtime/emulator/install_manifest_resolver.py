"""Shared Dog Paw app manifest parsing and install dependency resolution."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Sequence


@dataclass(frozen=True)
class DogpawAppManifest:
    """Resolved Dog Paw app manifest facts used by install planners.

    Purpose:
        Carries deterministic app identity, type, build, and dependency metadata
        from one `dogpawapp.json` without coupling resolution to Pi or emulator
        install execution.
    Parameters:
        name: Manifest `name`, used as the installed app identity.
        manifest_path: Absolute path to the source or packaged manifest file.
        app_kind: Structural kind, either `flutter` or `headless`.
        is_flutter: Convenience flag mirroring `app_kind == "flutter"`.
        executable: Headless executable target name, or `None` for Flutter apps.
        flutter_app: Flutter project directory name, or `None` for headless apps.
        extra_binaries: Headless helper binaries declared by `install.extraBinaries`.
        build_dependencies: Extra CMake targets declared by `buildDependencies`.
        install_dependencies: App names declared by `installDependencies`.
    Return value:
        Immutable manifest summary.
    Requirements/Preconditions:
        Values must come from a successfully validated Dog Paw manifest.
    Guarantees/Postconditions:
        Exactly one of `executable` and `flutter_app` is non-`None`.
    Invariants:
        The dataclass does not read files, copy files, or mutate install state.
    """

    name: str
    manifest_path: Path
    app_kind: str
    is_flutter: bool
    executable: str | None
    flutter_app: str | None
    extra_binaries: tuple[str, ...]
    build_dependencies: tuple[str, ...]
    install_dependencies: tuple[str, ...]


def load_manifest_payload(manifest_path: Path) -> dict:
    """Load one Dog Paw app manifest JSON object.

    Purpose:
        Provides the shared manifest loading contract for install dependency
        resolution before Pi or emulator install execution begins.
    Parameters:
        manifest_path: Path to a `dogpawapp.json` file.
    Return value:
        Parsed JSON object.
    Requirements/Preconditions:
        `manifest_path` must name an existing readable JSON object file.
    Guarantees/Postconditions:
        Raises `ValueError` when the manifest is not a JSON object.
    Invariants:
        Reads the manifest only; it does not modify the filesystem.
    """

    with manifest_path.open("r", encoding="utf-8") as manifest_file:
        payload = json.load(manifest_file)
    if not isinstance(payload, dict):
        raise ValueError(f"Manifest must be a JSON object: {manifest_path}")
    return payload


def require_manifest_string_field(
    manifest_path: Path,
    payload: dict,
    field_name: str,
) -> str:
    """Return one required non-empty string field from a manifest.

    Purpose:
        Keeps validation errors clear and tied to the manifest that contains the
        invalid field.
    Parameters:
        manifest_path: Manifest path used for error context.
        payload: Parsed manifest JSON object.
        field_name: Field name to require.
    Return value:
        Non-empty string field value.
    Requirements/Preconditions:
        `payload` must be a parsed Dog Paw manifest object.
    Guarantees/Postconditions:
        Raises `ValueError` when the field is absent, empty, or not a string.
    Invariants:
        Does not mutate `payload`.
    """

    value = payload.get(field_name)
    if not isinstance(value, str) or value == "":
        raise ValueError(f"{manifest_path}: manifest requires non-empty string field: {field_name}")
    return value


def optional_manifest_string_field(
    manifest_path: Path,
    payload: dict,
    field_name: str,
) -> str | None:
    """Return one optional non-empty string field from a manifest.

    Purpose:
        Validates optional structural fields such as `flutterApp` and
        `executable` without treating absence as an error.
    Parameters:
        manifest_path: Manifest path used for error context.
        payload: Parsed manifest JSON object.
        field_name: Field name to read.
    Return value:
        Non-empty string value, or `None` when the field is absent.
    Requirements/Preconditions:
        `payload` must be a parsed Dog Paw manifest object.
    Guarantees/Postconditions:
        Raises `ValueError` when the field exists but is not a non-empty string.
    Invariants:
        Does not mutate `payload`.
    """

    value = payload.get(field_name)
    if value is None:
        return None
    if not isinstance(value, str) or value == "":
        raise ValueError(f"{manifest_path}: manifest field must be a non-empty string: {field_name}")
    return value


def parse_string_array_field(payload: dict, field_name: str) -> tuple[str, ...]:
    """Read one optional string-array manifest field.

    Purpose:
        Shares validation for dependency-oriented manifest fields used by install
        planning.
    Parameters:
        payload: Parsed manifest JSON object.
        field_name: Top-level field name to read.
    Return value:
        Tuple of strings, or an empty tuple when absent.
    Requirements/Preconditions:
        `payload` must be a parsed Dog Paw manifest object.
    Guarantees/Postconditions:
        Raises `ValueError` when the field exists but is not a string array.
    Invariants:
        Does not mutate `payload`.
    """

    value = payload.get(field_name, [])
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"{field_name} must be an array of strings")
    return tuple(value)


def parse_install_extra_binaries(payload: dict) -> tuple[str, ...]:
    """Read manifest `install.extraBinaries`.

    Purpose:
        Lets build-target planning include helper binaries installed beside a
        headless executable.
    Parameters:
        payload: Parsed manifest JSON object.
    Return value:
        Tuple of helper binary names, or an empty tuple when absent.
    Requirements/Preconditions:
        `payload` must be a parsed Dog Paw manifest object.
    Guarantees/Postconditions:
        Raises `ValueError` when `install` or `install.extraBinaries` has the
        wrong shape.
    Invariants:
        Does not inspect build outputs or mutate `payload`.
    """

    install = payload.get("install", {})
    if install is None:
        return ()
    if not isinstance(install, dict):
        raise ValueError("install field must be an object")
    value = install.get("extraBinaries", [])
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError("install.extraBinaries must be an array of strings")
    return tuple(value)


def classify_manifest_kind(manifest_path: Path, payload: dict) -> tuple[str, str | None, str | None]:
    """Classify one manifest from its structural runtime fields.

    Purpose:
        Makes app type deterministic without adding a second source of truth:
        `flutterApp` identifies Flutter apps and `executable` identifies
        headless apps.
    Parameters:
        manifest_path: Manifest path used for error context.
        payload: Parsed manifest JSON object.
    Return value:
        Tuple of `(app_kind, executable, flutter_app)`.
    Requirements/Preconditions:
        `payload` must be a parsed Dog Paw manifest object.
    Guarantees/Postconditions:
        Raises `ValueError` when both or neither structural fields are present,
        or when optional `type` disagrees with the structural kind.
    Invariants:
        Does not inspect directory layout or mutate `payload`.
    """

    executable = optional_manifest_string_field(manifest_path, payload, "executable")
    flutter_app = optional_manifest_string_field(manifest_path, payload, "flutterApp")
    if executable is not None and flutter_app is not None:
        raise ValueError(f"{manifest_path}: manifest must not declare both executable and flutterApp")
    if executable is None and flutter_app is None:
        raise ValueError(f"{manifest_path}: manifest must declare exactly one of executable or flutterApp")

    app_kind = "flutter" if flutter_app is not None else "headless"
    manifest_type = optional_manifest_string_field(manifest_path, payload, "type")
    if manifest_type is not None:
        allowed_types = {"flutter", "ui"} if app_kind == "flutter" else {"headless", "worker"}
        if manifest_type not in allowed_types:
            raise ValueError(
                f"{manifest_path}: manifest type '{manifest_type}' disagrees with {app_kind} app fields"
            )
    return app_kind, executable, flutter_app


def manifest_from_path(manifest_path: Path) -> DogpawAppManifest:
    """Parse and validate one Dog Paw app manifest for install planning.

    Purpose:
        Converts a full `dogpawapp.json` into the narrow manifest facts needed by
        shared dependency resolution.
    Parameters:
        manifest_path: Path to the manifest file.
    Return value:
        Parsed `DogpawAppManifest`.
    Requirements/Preconditions:
        `manifest_path` must exist and contain valid Dog Paw app metadata.
    Guarantees/Postconditions:
        Returned `manifest_path` is absolute and structural type is validated.
    Invariants:
        Does not install, build, or copy any app payloads.
    """

    resolved_path = manifest_path.resolve()
    payload = load_manifest_payload(resolved_path)
    name = require_manifest_string_field(resolved_path, payload, "name")
    app_kind, executable, flutter_app = classify_manifest_kind(resolved_path, payload)
    return DogpawAppManifest(
        name=name,
        manifest_path=resolved_path,
        app_kind=app_kind,
        is_flutter=app_kind == "flutter",
        executable=executable,
        flutter_app=flutter_app,
        extra_binaries=parse_install_extra_binaries(payload),
        build_dependencies=parse_string_array_field(payload, "buildDependencies"),
        install_dependencies=parse_string_array_field(payload, "installDependencies"),
    )


def build_manifest_index(manifest_paths: Sequence[Path]) -> dict[str, DogpawAppManifest]:
    """Build a manifest-name index from candidate manifest paths.

    Purpose:
        Lets install planners resolve `installDependencies` by manifest `name`
        using one deterministic lookup rule.
    Parameters:
        manifest_paths: Candidate manifest paths in precedence order.
    Return value:
        Mapping from app name to parsed manifest facts.
    Requirements/Preconditions:
        Candidate manifests must be readable and valid.
    Guarantees/Postconditions:
        Earlier paths win when duplicate app names are encountered.
    Invariants:
        Reads manifests only; it does not inspect installed app registries.
    """

    index: dict[str, DogpawAppManifest] = {}
    for manifest_path in manifest_paths:
        manifest = manifest_from_path(manifest_path)
        if manifest.name not in index:
            index[manifest.name] = manifest
    return index


def scan_manifest_roots(search_roots: Sequence[Path]) -> dict[str, DogpawAppManifest]:
    """Scan manifest roots and return an app-name manifest index.

    Purpose:
        Shares the recursive `dogpawapp.json` discovery rule used by install
        dependency resolution across source and packaged runtime layouts.
    Parameters:
        search_roots: Directories to scan recursively, in precedence order.
    Return value:
        Mapping from app name to parsed manifest facts.
    Requirements/Preconditions:
        Missing roots are allowed and skipped.
    Guarantees/Postconditions:
        Each root is scanned in sorted path order for deterministic results.
    Invariants:
        Does not mutate search roots or installed app registries.
    """

    manifest_paths: list[Path] = []
    for search_root in search_roots:
        if not search_root.is_dir():
            continue
        manifest_paths.extend(sorted(search_root.glob("**/dogpawapp.json")))
    return build_manifest_index(manifest_paths)


def expand_manifests_with_install_dependencies(
    seed_manifests: Sequence[DogpawAppManifest],
    manifest_index: dict[str, DogpawAppManifest],
) -> tuple[DogpawAppManifest, ...]:
    """Expand seed manifests with transitive install dependencies.

    Purpose:
        Produces one dependency-before-dependent manifest list for install
        execution, independent of whether the caller targets a Pi or emulator.
    Parameters:
        seed_manifests: Manifests explicitly requested by the user or planner.
        manifest_index: Mapping from app name to manifest facts for dependency
            lookup.
    Return value:
        Ordered tuple of unique manifests.
    Requirements/Preconditions:
        Every dependency name must resolve in `manifest_index` or among seeds.
    Guarantees/Postconditions:
        Dependencies appear before dependents. Circular references terminate
        without infinite recursion while preserving first-seen order.
    Invariants:
        Does not mutate manifests, the index, or install state.
    """

    index = dict(manifest_index)
    for manifest in seed_manifests:
        index.setdefault(manifest.name, manifest)

    ordered: list[DogpawAppManifest] = []
    seen_names: set[str] = set()
    visiting: set[str] = set()

    def visit(manifest: DogpawAppManifest) -> None:
        """Visit one manifest and recursively append its dependencies first.

        Purpose:
            Implements depth-first install ordering for one dependency graph node.
        Parameters:
            manifest: Manifest node to visit.
        Return value:
            None.
        Requirements/Preconditions:
            `index` must contain every dependency reachable from `manifest`.
        Guarantees/Postconditions:
            `ordered` receives each reachable manifest at most once.
        Invariants:
            Does not modify manifest objects or dependency declarations.
        """

        if manifest.name in seen_names:
            return
        if manifest.name in visiting:
            return
        visiting.add(manifest.name)
        for dependency_name in manifest.install_dependencies:
            dependency = index.get(dependency_name)
            if dependency is None:
                raise ValueError(f"install dependency has no host manifest: {dependency_name}")
            visit(dependency)
        visiting.discard(manifest.name)
        seen_names.add(manifest.name)
        ordered.append(manifest)

    for manifest in seed_manifests:
        visit(manifest)
    return tuple(ordered)


def build_targets_for_manifests(manifests: Sequence[DogpawAppManifest]) -> tuple[str, ...]:
    """Return the ordered CMake target union for an install manifest set.

    Purpose:
        Lets Pi and emulator install flows build the same target set before
        installing resolved apps.
    Parameters:
        manifests: Final manifest set in install order.
    Return value:
        Ordered tuple of unique CMake target names.
    Requirements/Preconditions:
        Manifest metadata must already be parsed and validated.
    Guarantees/Postconditions:
        Includes headless executables, helper binaries, build dependencies,
        `dogpaw_bridge` for Flutter apps, and `Epiphany`.
    Invariants:
        Does not inspect build outputs or run CMake.
    """

    targets: list[str] = []
    seen: set[str] = set()

    def append_target(name: str) -> None:
        """Append one CMake target if it has not already been requested.

        Purpose:
            Keeps target union construction deterministic while preserving first
            occurrence order.
        Parameters:
            name: CMake target name. Empty strings are ignored.
        Return value:
            None.
        Requirements/Preconditions:
            `targets` and `seen` belong to the current target-union build.
        Guarantees/Postconditions:
            Non-empty target names appear at most once in `targets`.
        Invariants:
            Does not inspect or build the target.
        """

        if name != "" and name not in seen:
            targets.append(name)
            seen.add(name)

    has_flutter = any(manifest.is_flutter for manifest in manifests)
    for manifest in manifests:
        if manifest.executable is not None:
            append_target(manifest.executable)
        for extra_binary in manifest.extra_binaries:
            append_target(extra_binary)
        for dependency in manifest.build_dependencies:
            append_target(dependency)
    if has_flutter:
        append_target("dogpaw_bridge")
    append_target("Epiphany")
    return tuple(targets)
