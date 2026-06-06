#!/usr/bin/env python3
"""Shared helpers for source-input fingerprints used by Dog Paw installs."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse, unquote


FINGERPRINT_VERSION = "sha256-v1"

_PACKAGE_SOURCE_NAMES = (
    "lib",
    "src",
    "bin",
    "linux",
    "android",
    "ios",
    "macos",
    "windows",
    "web",
    "assets",
    "shaders",
    "fonts",
    "pubspec.yaml",
    "pubspec.lock",
    "analysis_options.yaml",
    "build.yaml",
    "native_assets.yaml",
    "ffigen.yaml",
)


def _path_key(path: Path) -> str:
    return str(path.resolve())


def _iter_directory_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*") if path.is_file())


def _update_hash_for_path(hasher: "hashlib._Hash", path: Path) -> None:
    resolved = path.resolve()
    path_key = _path_key(resolved).encode("utf-8")
    if not resolved.exists():
        hasher.update(b"MISSING\0")
        hasher.update(path_key)
        hasher.update(b"\0")
        return
    if resolved.is_file():
        hasher.update(b"FILE\0")
        hasher.update(path_key)
        hasher.update(b"\0")
        hasher.update(resolved.read_bytes())
        hasher.update(b"\0")
        return
    if resolved.is_dir():
        hasher.update(b"DIR\0")
        hasher.update(path_key)
        hasher.update(b"\0")
        for file_path in _iter_directory_files(resolved):
            hasher.update(file_path.relative_to(resolved).as_posix().encode("utf-8"))
            hasher.update(b"\0")
            hasher.update(file_path.read_bytes())
            hasher.update(b"\0")
        return
    raise ValueError(f"Unsupported source input path type: {resolved}")


def normalize_source_inputs(paths: Iterable[Path]) -> list[Path]:
    """Return stable, de-duplicated source input paths."""

    unique: dict[str, Path] = {}
    for path in paths:
        resolved = Path(path).resolve()
        unique[_path_key(resolved)] = resolved
    return [unique[key] for key in sorted(unique)]


def fingerprint_source_inputs(paths: Iterable[Path]) -> tuple[list[str], str]:
    """Return normalized source inputs and a stable content fingerprint."""

    normalized = normalize_source_inputs(paths)
    hasher = hashlib.sha256()
    hasher.update(FINGERPRINT_VERSION.encode("utf-8"))
    hasher.update(b"\0")
    for path in normalized:
        _update_hash_for_path(hasher, path)
    return [str(path) for path in normalized], f"{FINGERPRINT_VERSION}:{hasher.hexdigest()}"


def dart_package_source_inputs(package_dir: Path) -> list[Path]:
    """Return the relevant source inputs for one Dart/Flutter package directory."""

    inputs: list[Path] = []
    package_root = package_dir.resolve()
    for name in _PACKAGE_SOURCE_NAMES:
        candidate = package_root / name
        if candidate.exists():
            inputs.append(candidate)
    return normalize_source_inputs(inputs)


def _package_root_from_uri(config_dir: Path, root_uri: str) -> Path | None:
    parsed = urlparse(root_uri)
    if parsed.scheme not in {"", "file"}:
        return None
    raw_path = unquote(parsed.path) if parsed.scheme == "file" else root_uri
    if not raw_path:
        return None
    if parsed.scheme == "file" and raw_path.startswith("/") and root_uri.startswith("file://"):
        resolved = Path(raw_path).resolve()
    else:
        resolved = (config_dir / raw_path).resolve()
    if ".pub-cache" in resolved.parts:
        return None
    return resolved


def flutter_path_dependency_inputs(project_dir: Path) -> list[Path]:
    """Return local path dependency package roots referenced by package_config."""

    package_config_path = project_dir / ".dart_tool" / "package_config.json"
    if not package_config_path.is_file():
        return []
    payload = json.loads(package_config_path.read_text(encoding="utf-8"))
    packages = payload.get("packages", [])
    if not isinstance(packages, list):
        return []

    project_root = project_dir.resolve()
    config_dir = package_config_path.parent
    roots: list[Path] = []
    for package in packages:
        if not isinstance(package, dict):
            continue
        root_uri = package.get("rootUri")
        if not isinstance(root_uri, str):
            continue
        root = _package_root_from_uri(config_dir, root_uri)
        if root is None:
            continue
        if root == project_root:
            continue
        roots.extend(dart_package_source_inputs(root))
    return normalize_source_inputs(roots)


def flutter_project_source_inputs(project_dir: Path) -> list[Path]:
    """Return source inputs for one Flutter project, including local path deps."""

    project_root = project_dir.resolve()
    inputs = dart_package_source_inputs(project_root)
    inputs.extend(flutter_path_dependency_inputs(project_root))
    return normalize_source_inputs(inputs)
