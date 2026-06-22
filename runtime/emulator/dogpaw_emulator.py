#!/usr/bin/env python3
"""Launch and supervise a local Dog Paw emulator runtime."""

from __future__ import annotations

import argparse
import http.server
import importlib.util
import json
import os
import re
import shlex
import shutil
import signal
import socket
import stat
import subprocess
import sys
import threading
import time
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Mapping, Sequence


@dataclass(frozen=True)
class RuntimeLayout:
    """Resolved repo-style or packaged-SDK filesystem layout for this script.

    Purpose:
        Describes where the emulator wrapper should find shared resources,
        packaged base apps, helper modules, and maintainer-facing UI sources when
        it runs either from the internal development repo or from an exported
        SDK's `runtime/emulator/` directory.
    Parameters:
        packaged: Whether the script path points at an exported SDK runtime tree.
        script_path: Absolute path to the executing `dogpaw_emulator.py`.
        workspace_root: Root directory used as the tool's logical working tree.
        runtime_root: Static runtime seed root that contains packaged binaries,
            resources, and base apps.
        resource_root: Directory containing shared runtime resources such as
            hardware profiles and `dogpawDataItems`.
        base_apps_root: Directory containing packaged base app seed payloads.
        rpi_tools_dir: Directory containing helper Python modules such as
            `install_app.py` and `install_fingerprint.py`.
        emulator_control_gui_dir: Source directory for the optional emulator
            control GUI.
    Return value:
        Dataclass instance with immutable fields.
    Requirements:
        `script_path` must be absolute or resolvable to an absolute path.
    Guarantees:
        Construction does not create files or inspect process state beyond the
        provided path.
    Invariants:
        The packaged and source-tree layouts expose the same logical fields even
        though the underlying directory shapes differ.
    """

    packaged: bool
    script_path: Path
    workspace_root: Path
    runtime_root: Path
    resource_root: Path
    base_apps_root: Path
    rpi_tools_dir: Path
    emulator_control_gui_dir: Path


def runtime_layout_from_script_path(script_path: Path) -> RuntimeLayout:
    """Resolve the logical runtime layout for one emulator script path.

    Purpose:
        Lets the same emulator implementation run both from the internal repo and
        from an exported SDK where lower-level implementation files live under
        `runtime/emulator/`.
    Parameters:
        script_path: Candidate `dogpaw_emulator.py` path to classify.
    Return value:
        Immutable `RuntimeLayout` describing the matching filesystem contract.
    Requirements:
        `script_path` should identify the actual emulator script location or a
        realistic test path.
    Guarantees:
        Detects packaged SDK layout when the script sits under `runtime/emulator`
        and packaged runtime resources exist alongside it; otherwise falls back to
        the internal repo layout.
    Invariants:
        Does not create directories or require the full runtime payload to exist.
    """

    resolved_script_path = script_path.resolve()
    script_dir = resolved_script_path.parent
    runtime_root = script_dir.parent
    packaged_candidate = (
        script_dir.name == "emulator"
        and runtime_root.name == "runtime"
        and (runtime_root / "resources").is_dir()
    )
    if packaged_candidate:
        workspace_root = runtime_root.parent
        return RuntimeLayout(
            packaged=True,
            script_path=resolved_script_path,
            workspace_root=workspace_root,
            runtime_root=runtime_root,
            resource_root=runtime_root / "resources",
            base_apps_root=runtime_root / "base_apps",
            rpi_tools_dir=script_dir,
            emulator_control_gui_dir=script_dir / "gui" / "emulator_control",
        )

    workspace_root = resolved_script_path.parents[1]
    helper_tools_dir = resolve_helper_modules_dir(
        script_dir=script_dir,
        workspace_root=workspace_root,
    )
    return RuntimeLayout(
        packaged=False,
        script_path=resolved_script_path,
        workspace_root=workspace_root,
        runtime_root=workspace_root / "runtime",
        resource_root=workspace_root / "runtime" / "resources",
        base_apps_root=workspace_root / "runtime" / "base_apps",
        rpi_tools_dir=helper_tools_dir,
        emulator_control_gui_dir=workspace_root / "emulator" / "gui" / "emulator_control",
    )


def helper_module_set_exists(candidate_dir: Path) -> bool:
    """Return whether one directory contains the emulator helper Python modules.

    Purpose:
        Lets the portable emulator implementation load shared install helpers from
        either the exported runtime directory or a nearby source checkout without
        naming repo-specific path prefixes in public code.
    Parameters:
        candidate_dir: Directory that may contain `install_app.py`,
            `install_fingerprint.py`, and `install_manifest_resolver.py`.
    Return value:
        `True` when both helper modules exist in `candidate_dir`.
    Requirements:
        `candidate_dir` may or may not exist.
    Guarantees:
        Performs file-existence checks only.
    Invariants:
        Does not import modules or modify filesystem state.
    """

    return (
        (candidate_dir / "install_app.py").is_file()
        and (candidate_dir / "install_fingerprint.py").is_file()
        and (candidate_dir / "install_manifest_resolver.py").is_file()
    )


def resolve_helper_modules_dir(script_dir: Path, workspace_root: Path) -> Path:
    """Resolve the directory that supplies shared emulator helper Python modules.

    Purpose:
        Keeps `dogpaw_emulator.py` portable by preferring helper modules shipped
        beside the script, then falling back to a shallow source-tree helper
        discovery pass when running from the development checkout.
    Parameters:
        script_dir: Directory containing `dogpaw_emulator.py`.
        workspace_root: Logical workspace root for this emulator invocation.
    Return value:
        Directory expected to contain `install_app.py`, `install_fingerprint.py`,
        and `install_manifest_resolver.py`.
    Requirements:
        `script_dir` and `workspace_root` should be absolute paths.
    Guarantees:
        Prefers `script_dir` when the helper modules are already packaged there.
    Invariants:
        Does not import helper modules or create files.
    """

    candidate_dirs = [script_dir, workspace_root / "tools"]
    if workspace_root.is_dir():
        child_candidates = sorted(
            child / "tools" for child in workspace_root.iterdir() if child.is_dir()
        )
        candidate_dirs.extend(child_candidates)
    for candidate_dir in candidate_dirs:
        if helper_module_set_exists(candidate_dir):
            return candidate_dir
    return script_dir


def resolve_source_layout_root(layout: RuntimeLayout) -> Path | None:
    """Resolve the optional source-layout root that owns dev-only emulator assets.

    Purpose:
        Distinguishes exported runtime layouts from source checkouts that still
        supply helper modules, shared resources, and app manifests from a nearby
        development tree.
    Parameters:
        layout: Resolved runtime layout for the current emulator tool instance.
    Return value:
        Source-layout root path, or `None` when no source helper tree is present.
    Requirements:
        `layout.rpi_tools_dir` should point at the resolved helper-module
        directory.
    Guarantees:
        Returns `None` for packaged layouts and for helper directories that do not
        imply a usable source tree.
    Invariants:
        Does not create directories or import modules.
    """

    if layout.packaged or layout.rpi_tools_dir.name != "tools":
        return None
    candidate_root = layout.rpi_tools_dir.parent
    if (candidate_root / "resources").is_dir() and (
        candidate_root / "headlessApps"
    ).is_dir():
        return candidate_root
    return None


def load_helper_module(module_name: str, helper_modules_dir: Path):
    """Load one helper Python module from the resolved helper-module directory.

    Purpose:
        Avoids relying on repo-specific `sys.path` setup while still sharing the
        existing Python install core between exported SDK and source-checkout
        emulator runs.
    Parameters:
        module_name: Basename of the helper module without the `.py` suffix.
        helper_modules_dir: Directory that should contain the helper module file.
    Return value:
        Loaded Python module object.
    Requirements:
        `<helper_modules_dir>/<module_name>.py` must exist and be importable.
    Guarantees:
        Registers the module in `sys.modules` using `module_name`.
    Invariants:
        Does not mutate helper source files.
    """

    module_path = helper_modules_dir / f"{module_name}.py"
    helper_dir_text = str(helper_modules_dir)
    if helper_dir_text not in sys.path:
        sys.path.insert(0, helper_dir_text)
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load helper module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def epiphany_working_directory_for_layout(layout: RuntimeLayout) -> Path:
    """Return the working directory Epiphany should use for one runtime layout.

    Purpose:
        Keeps Epiphany launch behavior consistent across source-repo and packaged
        SDK runs by pointing the process at the directory that owns its static
        runtime resources.
    Parameters:
        layout: Resolved runtime layout for the current emulator tool instance.
    Return value:
        Directory that should be used as Epiphany's subprocess working
        directory.
    Requirements:
        `layout` must describe either the source-repo or packaged-SDK runtime
        shape.
    Guarantees:
        Uses the exported-or-staged `runtime/` directory for packaged SDK runs.
        Uses the resolved source-layout root for source checkouts when available.
    Invariants:
        Does not create directories or inspect process state.
    """

    source_layout_root = resolve_source_layout_root(layout)
    if source_layout_root is not None:
        return source_layout_root
    return layout.runtime_root


RUNTIME_LAYOUT = runtime_layout_from_script_path(Path(__file__).resolve())
WORKSPACE_ROOT = RUNTIME_LAYOUT.workspace_root
RPI_TOOLS_DIR = RUNTIME_LAYOUT.rpi_tools_dir
SOURCE_LAYOUT_ROOT = resolve_source_layout_root(RUNTIME_LAYOUT)
install_app = load_helper_module("install_app", RPI_TOOLS_DIR)
install_fingerprint = load_helper_module("install_fingerprint", RPI_TOOLS_DIR)
install_manifest_resolver = load_helper_module("install_manifest_resolver", RPI_TOOLS_DIR)

DEFAULT_STARTUP_PLAN = RUNTIME_LAYOUT.script_path.parent / "startup" / "emulator_stack.json"
RPI_RESOURCE_ROOT = RUNTIME_LAYOUT.resource_root
PACKAGED_BASE_APPS_ROOT = RUNTIME_LAYOUT.base_apps_root
HEADLESS_INSTALL_WRAPPER = (
    SOURCE_LAYOUT_ROOT / "tools" / "install_headless_app.sh"
    if SOURCE_LAYOUT_ROOT is not None
    else RUNTIME_LAYOUT.script_path.parent / "install_headless_app.sh"
)
FLUTTER_INSTALL_WRAPPER = (
    SOURCE_LAYOUT_ROOT / "uiApps" / "tools" / "build_and_install_flutter_app.sh"
    if SOURCE_LAYOUT_ROOT is not None
    else RUNTIME_LAYOUT.script_path.parent / "build_and_install_flutter_app.sh"
)
NAME_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")
SMOKE_EXPECTED_UI_APPS = {"dog_paw_home_screen", "dog_paw_status_bar"}
SMOKE_EXPECTED_SWAY_APP_IDS = {"dogpaw-app-dog_paw_home_screen"}
DEFAULT_EXTRA_APP_NAMES = (
    "color_tree",
    "hello_dogpaw",
    "rain_pond",
    "Namer",
    "Voice2LED",
)
BRIDGE_INSTALL_NAME = "libdogpaw_bridge.so"
DEFAULT_SPLASH_BACKGROUND_PATH = "~/.local/share/dogpaw/resources/images/splashScreen.png"
EMULATOR_CONTROL_GUI_DIR = RUNTIME_LAYOUT.emulator_control_gui_dir
DEFAULT_BRIDGE_HOST = "127.0.0.1"
DEFAULT_BRIDGE_PORT = 8765
KEY_GRID_SIMULATOR_LOG_NAME = "picoComms.log"
KEY_GRID_SIMULATOR_CONTROL_SOCKET_NAME = "kg.sock"
BAK_SIMULATOR_CONTROL_SOCKET_NAME = "bak.sock"
LED_COMMS_INTROSPECTION_SOCKET_NAME = "led.sock"
KEY_GRID_SIMULATOR_CONNECTED_FRAGMENT = "Connected as BladeHW"
KEY_GRID_SIMULATOR_ENDPOINTS = (
    "key_position",
    "key_press",
    "mod_key_press",
    "near_press",
    "raw_sensors",
    "body_button_input",
)
LOG_HEALTH_SEVERITY_PATTERN = re.compile(
    r"\b(WARNING|ERROR|CRITICAL)\b|"
    r"WARNING \*\*|ERROR \*\*|CRITICAL \*\*|"
    r"AddressSanitizer|LeakSanitizer|Traceback|Fatal|fatal",
    re.IGNORECASE,
)


def source_resource_root() -> Path:
    """Return the shared-resource root used by the current emulator layout.

    Purpose:
        Keeps resource consumers on one portable access path while still allowing
        development checkouts to source shared assets from a nearby checked-in
        tree when available.
    Parameters:
        None.
    Return value:
        Resource root path for shared Dog Paw assets.
    Requirements:
        None.
    Guarantees:
        Prefers a resolved source-layout resource tree when available; otherwise
        returns the runtime-owned packaged resource root.
    Invariants:
        Does not check file contents or create directories.
    """

    if SOURCE_LAYOUT_ROOT is not None:
        return SOURCE_LAYOUT_ROOT / "resources"
    return RPI_RESOURCE_ROOT


def source_app_manifest_roots() -> list[Path]:
    """Return source-tree manifest roots that can back dev-checkout installs.

    Purpose:
        Separates exported packaged app seeds from optional source-checkout app
        trees so default emulator installs can stay portable without giving up
        local developer convenience.
    Parameters:
        None.
    Return value:
        Ordered list of source manifest root directories.
    Requirements:
        None.
    Guarantees:
        Returns an empty list when no source-layout root is available.
    Invariants:
        Does not recurse or inspect manifest contents.
    """

    if SOURCE_LAYOUT_ROOT is None:
        return []
    return [
        SOURCE_LAYOUT_ROOT / "headlessApps",
        SOURCE_LAYOUT_ROOT / "uiApps" / "apps",
    ]


def packaged_example_manifest_roots() -> list[Path]:
    """Return exported-SDK example roots that can seed default app installs.

    Purpose:
        Lets the packaged SDK install curated example apps such as
        `hello_dogpaw`, `rain_pond`, and `namer` when they are part of the
        default emulator app set.
    Parameters:
        None.
    Return value:
        Ordered list of packaged example root directories.
    Requirements:
        None.
    Guarantees:
        Returns an empty list for source checkouts or when no packaged examples
        are part of the current layout.
    Invariants:
        Does not recurse or inspect manifest contents.
    """

    if not RUNTIME_LAYOUT.packaged:
        return []
    return [RUNTIME_LAYOUT.workspace_root / "examples"]


def bridge_package_prebuilt_candidates() -> list[Path]:
    """Return source-checkout package-owned bridge artifact candidates.

    Purpose:
        Lets the emulator consume a prebuilt bridge artifact from the local
        `dogpaw` package when running inside the development checkout, without
        falling back to repo build-output directories.
    Parameters:
        None.
    Return value:
        Ordered bridge-artifact candidate paths.
    Requirements:
        None.
    Guarantees:
        Returns host-preferred triplet locations first when the source-layout root
        is available.
    Invariants:
        Only package-owned prebuilt artifacts are considered.
    """

    if SOURCE_LAYOUT_ROOT is None:
        return []
    prebuilt_root = (
        SOURCE_LAYOUT_ROOT / "uiApps" / "packages" / "dogpaw" / "linux" / "prebuilt"
    )
    candidates: list[Path] = []
    preferred_triplet = runtime_binary_arch_dir_name()
    if preferred_triplet:
        candidates.append(prebuilt_root / preferred_triplet / BRIDGE_INSTALL_NAME)
    if prebuilt_root.is_dir():
        triplet_dirs = sorted(path for path in prebuilt_root.iterdir() if path.is_dir())
        candidates.extend(triplet_dir / BRIDGE_INSTALL_NAME for triplet_dir in triplet_dirs)
    return candidates


@dataclass(frozen=True)
class AllowedLogPattern:
    """A known smoke-log finding that is temporarily allowed.

    Purpose:
        Keeps emulator smoke log-health exceptions visible and named so the
        allowlist can shrink over time instead of becoming an invisible sink.
    Parameters:
        reason: Short human-readable reason or cleanup bucket for this pattern.
        fragment: Case-sensitive substring that identifies allowed log lines.
    Return value:
        Dataclass instance with immutable fields.
    Requirements:
        `fragment` should be specific enough to avoid masking unrelated errors.
    Guarantees:
        Construction does not inspect logs or filesystem state.
    Invariants:
        Allowed patterns are report metadata only; they do not modify logs.
    """

    reason: str
    fragment: str


DEFAULT_ALLOWED_LOG_PATTERNS = (
    AllowedLogPattern("gtk accessibility noise", "Atk-CRITICAL **"),
    AllowedLogPattern(
        "gtk display teardown noise",
        "Error reading events from display: Broken pipe",
    ),
    AllowedLogPattern(
        "gtk display teardown noise",
        "Error reading events from display: Connection reset by peer",
    ),
    AllowedLogPattern(
        "gtk display teardown noise",
        "Error flushing display: Broken pipe",
    ),
)

DEFAULT_ALLOWED_TERMINAL_OUTPUT_PATTERNS = (
    AllowedLogPattern("nested sway environment", "No DRM backend supplied"),
    AllowedLogPattern("nested sway environment", "Cannot find Xwayland binary"),
    AllowedLogPattern("nested sway environment", "Failed to start Xwayland"),
    AllowedLogPattern("nested sway environment", "Found config * for output"),
    AllowedLogPattern("nested sway environment", "Destroying output"),
    AllowedLogPattern("local user bus unavailable", "Failed to connect to bus: No such file or directory"),
    AllowedLogPattern("local user bus unavailable", "unable to connect to D-Bus"),
    AllowedLogPattern("local user bus unavailable", "Failed to connect to user bus"),
    AllowedLogPattern("systemd fallback", "SystemdProcessRunner: systemd-run exited"),
    AllowedLogPattern("emulator startup", "EpiphanyComms: Initializing communication layer"),
    AllowedLogPattern("emulator startup", "EpiphanyComms: Starting communication layer"),
    AllowedLogPattern("emulator startup", "EpiphanyComms: WebSocket server started"),
    AllowedLogPattern("emulator startup", "EpiphanyComms: Server port"),
    AllowedLogPattern("emulator startup", "EpiphanyComms: Communication layer started"),
    AllowedLogPattern("emulator startup", "[Epiphany WARNING]: Not implemented"),
    AllowedLogPattern("emulator startup", "Failed to initialize LED shared memory"),
    AllowedLogPattern("emulator startup", "Item not found for immediate subscribe response"),
    AllowedLogPattern("emulator startup", "EpiphanyLauncher: Creating record for unknown entity"),
    AllowedLogPattern("emulator shutdown", "handle_read_frame error: websocketpp.transport:7 (End of File)"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: Unknown connection ID"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: Cannot post internal request - not running"),
    AllowedLogPattern("emulator shutdown", "Error getting remote endpoint: system:9 (Bad file descriptor)"),
    AllowedLogPattern("emulator shutdown", "asio async_shutdown error: system:9 (Bad file descriptor)"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: WebSocket error occurred"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: WebSocket error for unknown connection"),
    AllowedLogPattern("emulator shutdown", "handle_accept error: Operation canceled"),
    AllowedLogPattern("emulator shutdown", "Stopping acceptance of new connections"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: Server port file removed"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: WebSocket server stopped"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: Communication layer stopped"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: Stopping communication layer"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: Already stopped"),
    AllowedLogPattern("emulator shutdown", "EpiphanyComms: Shutting down communication layer"),
    AllowedLogPattern("sway command response", '"success": true'),
)


@dataclass(frozen=True)
class EmulatorConfig:
    """Resolved filesystem and process contract for one emulator run.

    Purpose:
        Carries the normalized launch configuration used by dry-run, prepare,
        dependency checking, and real nested-Sway startup.
    Parameters:
        emulator_name: User-facing emulator instance name. Valid values match
            `NAME_PATTERN`.
        instance_name: Epiphany runtime instance name for sockets and service
            names. Valid values match `NAME_PATTERN`.
        data_root: Base Dog Paw persistent data directory.
        runtime_root: Base Dog Paw runtime directory. Epiphany appends
            `instance_name` through RuntimePaths.
        app_dir: Installed app registry for this emulator.
        emulator_root: Persistent root for this emulator name.
        instance_runtime_dir: Runtime directory for this Epiphany instance.
        startup_plan: Startup plan JSON file passed to Epiphany.
        epiphany: Epiphany executable path or command name.
        sway: Sway executable path or command name.
        swaymsg: swaymsg executable path or command name.
        wlr_backends: wlroots backend list passed to nested Sway.
        hardware_profile: Runtime hardware profile whose Sway config is used
            for the nested compositor.
    Return value:
        Dataclass instance with immutable fields.
    Requirements:
        Paths should be absolute or intentionally command-like executable names.
    Guarantees:
        Construction does not create files or start processes.
    Invariants:
        The app directory remains below `emulator_root` unless explicitly
        changed by future contract revisions.
    """

    emulator_name: str
    instance_name: str
    data_root: Path
    runtime_root: Path
    app_dir: Path
    emulator_root: Path
    instance_runtime_dir: Path
    startup_plan: Path
    epiphany: str
    sway: str
    swaymsg: str
    wlr_backends: str
    hardware_profile: str


@dataclass(frozen=True)
class BridgeResponse:
    """HTTP-style response produced by the emulator bridge core.

    Purpose:
        Lets unit tests exercise the bridge API without starting a real network
        server, while the HTTP handler can serialize the same response object for
        Flutter GUI clients.
    Parameters:
        status: HTTP response status code.
        body: JSON-serializable response object.
    Return value:
        Dataclass instance with immutable fields.
    Requirements:
        `body` must be JSON-serializable.
    Guarantees:
        Construction does not inspect sockets or filesystem state.
    Invariants:
        Bridge response content stays independent from HTTP transport details.
    """

    status: int
    body: dict[str, object]


@dataclass(frozen=True)
class NestedDisplayEnvironment:
    """Display environment exported by one nested Sway compositor.

    Purpose:
        Carries the standard Linux display variables that Epiphany and launched
        UI apps need in order to target the nested Sway window.
    Parameters:
        xdg_runtime_dir: Runtime directory containing Wayland and Sway sockets.
        wayland_display: Wayland display socket basename, for example
            `wayland-1`.
        sway_socket: Full path to Sway's IPC socket.
    Return value:
        Dataclass instance with immutable fields.
    Requirements:
        The nested compositor should have already created the referenced
        sockets before this object is used for real process launch.
    Guarantees:
        Stores standard display variables separately from Dog Paw-owned
        `DOGPAW_*` runtime roots.
    Invariants:
        Does not imply ownership of the parent process environment.
    """

    xdg_runtime_dir: Path
    wayland_display: str
    sway_socket: Path


def validate_name(value: str, label: str) -> str:
    """Validate an emulator or Epiphany instance name.

    Purpose:
        Enforces the same conservative identifier shape used by RuntimePaths so
        generated paths, environment variables, and systemd unit names remain
        predictable.
    Parameters:
        value: Candidate name to validate.
        label: Human-readable label used in error messages.
    Return value:
        The original `value` when valid.
    Requirements:
        `value` must be non-empty and contain only ASCII letters, digits,
        hyphens, and underscores.
    Guarantees:
        Raises `ValueError` before invalid names reach filesystem or process
        launch code.
    Invariants:
        The function never normalizes or rewrites valid names.
    """

    if not value or not NAME_PATTERN.match(value):
        raise ValueError(f"{label} must contain only letters, digits, '-' and '_'")
    return value


def default_data_root(env: Mapping[str, str]) -> Path:
    """Resolve the default Dog Paw persistent data root.

    Purpose:
        Matches the RuntimePaths data-root contract for emulator runs when the
        caller does not pass `--data-root`.
    Parameters:
        env: Environment mapping used for `XDG_DATA_HOME` and `HOME` lookup.
    Return value:
        Absolute default data root path.
    Requirements:
        `HOME` must be available when `XDG_DATA_HOME` is unset.
    Guarantees:
        Does not create directories.
    Invariants:
        The returned path always ends with the `dogpaw` application directory.
    """

    if env.get("XDG_DATA_HOME"):
        return (Path(env["XDG_DATA_HOME"]) / "dogpaw").resolve()
    home = env.get("HOME")
    if not home:
        raise ValueError("HOME is required when --data-root and XDG_DATA_HOME are unset")
    return (Path(home) / ".local" / "share" / "dogpaw").resolve()


def default_runtime_root(env: Mapping[str, str]) -> Path:
    """Resolve the default Dog Paw emulator runtime root.

    Purpose:
        Provides a runtime base that Epiphany can use through
        `DOGPAW_RUNTIME_DIR` without relying on the source tree.
    Parameters:
        env: Environment mapping used for `XDG_RUNTIME_DIR` lookup.
    Return value:
        Absolute default runtime root path.
    Requirements:
        `XDG_RUNTIME_DIR` should be set for normal desktop runs.
    Guarantees:
        Falls back to `/tmp/dogpaw-emulator-runtime` for non-systemd shells.
    Invariants:
        The returned path is a base directory; the Epiphany instance name is not
        appended here.
    """

    if env.get("XDG_RUNTIME_DIR"):
        return (Path(env["XDG_RUNTIME_DIR"]) / "dogpaw-emulator").resolve()
    return Path("/tmp/dogpaw-emulator-runtime").resolve()


def choose_wlr_backends(env: Mapping[str, str], explicit: str | None) -> str:
    """Select wlroots backends for the nested Sway process.

    Purpose:
        Keeps the default faithful to a host-window emulator while allowing
        callers to override backend choice for diagnostics or CI.
    Parameters:
        env: Environment mapping used to detect host display availability.
        explicit: Caller-provided backend string, or `None` for auto selection.
    Return value:
        Backend string suitable for the `WLR_BACKENDS` environment variable.
    Requirements:
        No external tools are required.
    Guarantees:
        Prefers Wayland when available, then X11, then headless.
    Invariants:
        Explicit values are returned unchanged.
    """

    if explicit:
        return explicit
    if env.get("WAYLAND_DISPLAY"):
        return "wayland"
    if env.get("DISPLAY"):
        return "x11"
    return "headless"


def resolve_creation_hardware_profile(explicit: str | None) -> str:
    """Resolve the hardware profile stored when an emulator is created.

    Purpose:
        Mirrors the Pi runtime's profile-selection convention so nested Sway
        uses the same checked-in profile config as deployed runs.
    Parameters:
        explicit: Optional profile name from the CLI.
    Return value:
        Hardware profile directory name.
    Requirements:
        The resolved profile must exist under the active shared-resource root's
        `hardware/profiles` directory.
    Guarantees:
        Raises `ValueError` when the profile is unknown.
    Invariants:
        Explicit profile names take precedence over local development defaults
        during creation only.
    """

    profile_name = explicit
    if not profile_name:
        local_config = source_resource_root() / "scripts" / "dev" / "local_config.sh"
        if local_config.is_file():
            result = subprocess.run(
                [str(local_config), "--hardware-profile"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            profile_name = result.stdout.strip() if result.returncode == 0 else ""
    if not profile_name:
        profile_name = "p8_2"

    validate_name(profile_name, "hardware profile")
    profile_dir = source_resource_root() / "hardware" / "profiles" / profile_name
    if not profile_dir.is_dir():
        raise ValueError(f"hardware profile not found: {profile_name}")
    return profile_name


def emulator_metadata_for_root(emulator_root: Path) -> dict[str, object]:
    """Read lifecycle metadata for an existing emulator root.

    Purpose:
        Provides the persistent emulator contract used after creation.
    Parameters:
        emulator_root: Directory containing `emulator.json`.
    Return value:
        Parsed metadata object.
    Requirements:
        `emulator.json` must exist and contain a JSON object.
    Guarantees:
        Raises clear exceptions for missing or malformed metadata.
    Invariants:
        Does not create, rewrite, or infer metadata values.
    """

    metadata_path = emulator_root / "emulator.json"
    if not metadata_path.is_file():
        raise FileNotFoundError(f"Emulator does not exist: {emulator_root.name}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if not isinstance(metadata, dict):
        raise ValueError(f"Invalid emulator metadata: {metadata_path}")
    return metadata


def saved_hardware_profile(emulator_root: Path) -> str:
    """Return the hardware profile persisted for an existing emulator.

    Purpose:
        Ensures run-time commands use the profile selected at creation.
    Parameters:
        emulator_root: Existing emulator root containing `emulator.json`.
    Return value:
        Saved hardware profile name.
    Requirements:
        Metadata must include a string `hardwareProfile` field.
    Guarantees:
        Raises `ValueError` if metadata is missing the required field.
    Invariants:
        Does not fall back to local defaults for existing emulators.
    """

    metadata = emulator_metadata_for_root(emulator_root)
    profile_name = metadata.get("hardwareProfile")
    if not isinstance(profile_name, str) or not profile_name:
        raise ValueError(
            f"Emulator metadata missing hardwareProfile; recreate emulator: {emulator_root.name}"
        )
    validate_name(profile_name, "hardware profile")
    profile_dir = source_resource_root() / "hardware" / "profiles" / profile_name
    if not profile_dir.is_dir():
        raise ValueError(f"hardware profile not found: {profile_name}")
    return profile_name


def command_creates_emulator(args: argparse.Namespace) -> bool:
    """Return whether the parsed command is allowed to set creation metadata.

    Purpose:
        Keeps hardware profile selection scoped to emulator creation.
    Parameters:
        args: Parsed command-line arguments.
    Return value:
        `True` for `create` and `--prepare-only`; otherwise `False`.
    Requirements:
        `args` came from `build_parser()`.
    Guarantees:
        `run --create-if-missing` is not treated as a hardware-profile setting
        command.
    Invariants:
        Does not inspect filesystem state.
    """

    return getattr(args, "command", "run") == "create" or bool(getattr(args, "prepare_only", False))


def command_uses_existing_emulator_profile(args: argparse.Namespace, emulator_root: Path) -> bool:
    """Return whether config resolution must read saved profile metadata.

    Purpose:
        Separates existing-emulator runtime commands from commands that only
        inspect roots or create metadata.
    Parameters:
        args: Parsed command-line arguments.
        emulator_root: Resolved persistent emulator directory.
    Return value:
        `True` when the command should use `emulator.json.hardwareProfile`.
    Requirements:
        `args` came from `build_parser()`.
    Guarantees:
        Missing `run --create-if-missing` emulators can still resolve creation
        defaults before they exist.
    Invariants:
        Does not create or modify emulator metadata.
    """

    command = getattr(args, "command", "run")
    if command in {"info", "delete", "install-headless", "install-flutter", "smoke", "key", "bak", "led", "bridge"}:
        return True
    if command in {"screen", "run"} and emulator_root.exists():
        return True
    return False


def hardware_profile_sway_config(
    profile_name: str,
    prefer_emulator_variant: bool = False,
) -> Path:
    """Return the Sway config path for a hardware profile.

    Purpose:
        Centralizes the emulator-to-profile Sway config mapping, including the
        optional emulator-specific Sway variant for nested desktop runs.
    Parameters:
        profile_name: Existing hardware profile directory name.
        prefer_emulator_variant: When true, return `swayConfig.emulator` if that
            file exists for the selected profile.
    Return value:
        Path to that profile's selected Sway config file.
    Requirements:
        `profile_name` must have been validated by `resolve_hardware_profile`.
    Guarantees:
        Returns `swayConfig.emulator` when requested and present; otherwise
        falls back to `swayConfig`.
    Invariants:
        Does not inspect generated emulator runtime files.
    """

    profile_dir = source_resource_root() / "hardware" / "profiles" / profile_name
    if prefer_emulator_variant:
        emulator_sway_config = profile_dir / "swayConfig.emulator"
        if emulator_sway_config.is_file():
            return emulator_sway_config
    sway_config = profile_dir / "swayConfig"
    if not sway_config.is_file():
        raise FileNotFoundError(f"hardware profile has no swayConfig: {profile_name}")
    return sway_config


def resolve_config(args: argparse.Namespace, env: Mapping[str, str]) -> EmulatorConfig:
    """Resolve command-line arguments into an `EmulatorConfig`.

    Purpose:
        Centralizes the emulator launch contract so tests, dry runs, and real
        launches use identical roots and environment values.
    Parameters:
        args: Parsed command-line arguments.
        env: Environment mapping used for default root and backend resolution.
    Return value:
        Fully resolved immutable emulator configuration.
    Requirements:
        `args.name` and the derived instance name must satisfy `validate_name`.
    Guarantees:
        Returned paths are absolute.
    Invariants:
        `app_dir` is `data_root/emulators/<name>/apps`.
    """

    emulator_name = validate_name(args.name, "emulator name")
    instance_name = validate_name(args.instance or f"emulator-{emulator_name}", "instance name")
    data_root = Path(args.data_root).expanduser().resolve() if args.data_root else default_data_root(env)
    runtime_root = (
        Path(args.runtime_root).expanduser().resolve()
        if args.runtime_root
        else default_runtime_root(env)
    )
    emulator_root = data_root / "emulators" / emulator_name
    app_dir = emulator_root / "apps"
    instance_runtime_dir = runtime_root / instance_name
    startup_plan = Path(args.startup_plan).expanduser().resolve()
    if command_creates_emulator(args):
        hardware_profile = resolve_creation_hardware_profile(args.hardware_profile)
    elif command_uses_existing_emulator_profile(args, emulator_root):
        if args.hardware_profile:
            raise ValueError("--hardware-profile is only valid during create")
        hardware_profile = saved_hardware_profile(emulator_root)
    else:
        if args.hardware_profile:
            raise ValueError("--hardware-profile is only valid during create")
        hardware_profile = resolve_creation_hardware_profile(None)
    return EmulatorConfig(
        emulator_name=emulator_name,
        instance_name=instance_name,
        data_root=data_root,
        runtime_root=runtime_root,
        app_dir=app_dir,
        emulator_root=emulator_root,
        instance_runtime_dir=instance_runtime_dir,
        startup_plan=startup_plan,
        epiphany=resolve_command_path_argument(args.epiphany),
        sway=resolve_command_path_argument(args.sway),
        swaymsg=resolve_command_path_argument(args.swaymsg),
        wlr_backends=choose_wlr_backends(env, args.wlr_backends),
        hardware_profile=hardware_profile,
    )


def prepare_roots(config: EmulatorConfig) -> None:
    """Create the emulator's persistent and runtime directories.

    Purpose:
        Prepares isolated roots before dependency checks or process launch so
        Epiphany and child apps never need to write into the source tree.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        None.
    Requirements:
        The current user must be allowed to create directories under the
        configured roots.
    Guarantees:
        Creates app registry, app files, logs, and instance runtime directories.
    Invariants:
        Existing contents are preserved.
    """

    for path in (
        config.app_dir,
        config.emulator_root / "appFiles",
        config.emulator_root / "logs",
        config.emulator_root / "lib",
        config.instance_runtime_dir,
    ):
        path.mkdir(parents=True, exist_ok=True)
    stage_bridge_library(config)
    seed_runtime_resources(config)


def emulator_bridge_library_path(config: EmulatorConfig) -> Path:
    """Return the staged bridge library path for one emulator.

    Purpose:
        Gives Flutter apps a stable runtime-owned FFI bridge path that does not
        depend on source-tree lookup after installation.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        Path to the emulator-local `libdogpaw_bridge.so`.
    Requirements:
        `config.emulator_root` must identify the selected emulator root.
    Guarantees:
        Does not create, read, or modify filesystem state.
    Invariants:
        The installed filename stays ABI-neutral for Dart's
        `DOGPAW_BRIDGE_LIB` override.
    """

    return config.emulator_root / "lib" / BRIDGE_INSTALL_NAME


def bridge_source_candidates(env: Mapping[str, str] | None = None) -> list[Path]:
    """Return candidate built bridge libraries in lookup order.

    Purpose:
        Finds the native bridge artifact that emulator setup should stage into
        runtime-owned storage, preferring an explicit override, then any packaged
        SDK runtime copy, then package-owned prebuilt artifacts from a nearby
        source checkout when available.
    Parameters:
        env: Optional environment mapping. When `DOGPAW_BRIDGE_LIB` is set, it
            is preferred as an explicit source artifact.
    Return value:
        Ordered candidate paths.
    Requirements:
        None; candidates may not exist yet if the bridge target has not been
        built.
    Guarantees:
        Does not inspect file contents or create files.
    Invariants:
        Packaged runtime artifacts are preferred over source-checkout package
        prebuilt artifacts when both are available.
    """

    effective_env = env if env is not None else os.environ
    candidates: list[Path] = []
    explicit_bridge = effective_env.get("DOGPAW_BRIDGE_LIB")
    if explicit_bridge:
        candidates.append(Path(explicit_bridge))
    packaged_bridge = RUNTIME_LAYOUT.runtime_root / "lib" / "linux-x64" / BRIDGE_INSTALL_NAME
    candidates.append(packaged_bridge)
    candidates.extend(bridge_package_prebuilt_candidates())
    return candidates


def resolve_bridge_source_library(env: Mapping[str, str] | None = None) -> Path | None:
    """Resolve the built bridge library that should be staged for emulator use.

    Purpose:
        Separates source artifact discovery from the runtime staging location so
        emulator launches always point apps at a copied runtime-owned bridge.
    Parameters:
        env: Optional environment mapping used for the explicit
            `DOGPAW_BRIDGE_LIB` source override.
    Return value:
        First existing candidate path, or `None` when no built bridge exists.
    Requirements:
        None.
    Guarantees:
        Does not create, copy, or delete files.
    Invariants:
        The returned path is never the emulator-local destination unless the
        caller explicitly provided it.
    """

    for candidate in bridge_source_candidates(env):
        if candidate.is_file():
            return candidate.resolve()
    return None


def stage_bridge_library(config: EmulatorConfig, source_path: Path | None = None) -> Path | None:
    """Copy the built native bridge into the selected emulator root.

    Purpose:
        Installs the Dart FFI bridge beside other emulator runtime artifacts so
        launched Flutter apps can load it through `DOGPAW_BRIDGE_LIB`.
    Parameters:
        config: Resolved emulator configuration.
        source_path: Optional already-resolved bridge artifact. When omitted,
            source candidates are discovered from the local build environment.
    Return value:
        Destination path when a bridge was staged or already present; otherwise
        `None` when no source bridge exists yet.
    Requirements:
        The caller must have write access to `config.emulator_root`.
    Guarantees:
        Creates the emulator `lib` directory when a source bridge exists.
    Invariants:
        The source bridge is never modified.
    """

    source = source_path if source_path is not None else resolve_bridge_source_library()
    destination = emulator_bridge_library_path(config)
    if source is None:
        return destination if destination.is_file() else None
    source = source.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and destination.resolve() == source:
        return destination
    shutil.copy2(source, destination)
    return destination


def emulator_metadata_path(config: EmulatorConfig) -> Path:
    """Return the metadata path for one named emulator.

    Purpose:
        Centralizes the metadata location used by lifecycle commands so create,
        run, info, and delete agree on what it means for an emulator to exist.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        Path to `emulator.json` below the emulator root.
    Requirements:
        `config.emulator_root` must be resolved for the target emulator name.
    Guarantees:
        Does not create, read, or modify filesystem state.
    Invariants:
        Metadata always lives directly under the selected emulator root.
    """

    return config.emulator_root / "emulator.json"


def emulator_exists(config: EmulatorConfig) -> bool:
    """Return whether a named emulator has lifecycle metadata.

    Purpose:
        Distinguishes an intentionally created emulator from incidental
        directories that may exist under the data root.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        `True` when `emulator.json` exists, otherwise `False`.
    Requirements:
        None.
    Guarantees:
        Performs a read-only existence check.
    Invariants:
        App contents are not inspected when deciding existence.
    """

    return emulator_metadata_path(config).is_file()


def count_installed_apps(app_dir: Path) -> int:
    """Count installed app records in an app registry.

    Purpose:
        Provides lifecycle summaries without requiring callers to parse the
        installed app manifests themselves.
    Parameters:
        app_dir: App registry directory containing one subdirectory per app.
    Return value:
        Number of immediate child directories containing `dogpawapp.json`.
    Requirements:
        Missing registries are allowed and count as zero.
    Guarantees:
        Does not read manifest contents.
    Invariants:
        Non-directory files and directories without manifests are ignored.
    """

    if not app_dir.is_dir():
        return 0
    return sum(1 for path in app_dir.iterdir() if (path / "dogpawapp.json").is_file())


def emulator_info_payload(config: EmulatorConfig) -> dict[str, object]:
    """Build a JSON-serializable lifecycle summary for one emulator.

    Purpose:
        Backs `info` and `list` output with stable fields for SDK tooling and
        tests.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        Dictionary containing name, instance, app count, paths, and metadata.
    Requirements:
        The emulator metadata file should exist.
    Guarantees:
        Includes path strings instead of `Path` objects for JSON output.
    Invariants:
        Does not modify emulator state.
    """

    metadata_path = emulator_metadata_path(config)
    metadata: dict[str, object] = {}
    if metadata_path.is_file():
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    return {
        "name": config.emulator_name,
        "instanceName": config.instance_name,
        "appCount": count_installed_apps(config.app_dir),
        "paths": {
            "dataRoot": str(config.data_root),
            "emulatorRoot": str(config.emulator_root),
            "appDir": str(config.app_dir),
            "appFilesDir": str(config.emulator_root / "appFiles"),
            "logsDir": str(config.emulator_root / "logs"),
            "bridgeLibrary": str(emulator_bridge_library_path(config)),
            "runtimeRoot": str(config.runtime_root),
            "instanceRuntimeDir": str(config.instance_runtime_dir),
        },
        "metadata": metadata,
    }


def emulator_logs_payload(config: EmulatorConfig) -> dict[str, object]:
    """Build a JSON-serializable log-location summary for one emulator.

    Purpose:
        Gives SDK users one discoverable command for locating the main emulator
        and Epiphany log paths without requiring them to understand the runtime
        directory layout first.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        Dictionary containing the emulator name, instance name, key log paths,
        and any currently present per-app log files.
    Requirements:
        `config` must contain resolved name and root paths for the target
        emulator.
    Guarantees:
        Returned paths are absolute strings suitable for JSON or terminal output.
    Invariants:
        Reads filesystem metadata only; does not create or modify log files.
    """

    app_logs_dir = config.instance_runtime_dir / "app_logs"
    existing_app_logs = sorted(
        str(log_path)
        for log_path in app_logs_dir.glob("*.log")
        if log_path.is_file()
    ) if app_logs_dir.is_dir() else []
    return {
        "name": config.emulator_name,
        "instanceName": config.instance_name,
        "paths": {
            "emulatorLogsDir": str(config.emulator_root / "logs"),
            "runtimeDir": str(config.instance_runtime_dir),
            "appLogsDir": str(app_logs_dir),
            "epiphanyStdoutLog": str(config.instance_runtime_dir / "epiphany_stdout.log"),
        },
        "existingAppLogs": existing_app_logs,
    }


def print_emulator_logs_summary(payload: Mapping[str, object]) -> None:
    """Print a concise human-readable log-location summary.

    Purpose:
        Keeps `dogpaw emulator logs` useful for humans by highlighting the
        runtime paths that matter most during local debugging.
    Parameters:
        payload: Mapping in the shape returned by `emulator_logs_payload()`.
    Return value:
        None.
    Requirements:
        `payload["paths"]` must contain the documented log-path string fields.
    Guarantees:
        Writes a stable summary to stdout and lists currently present app logs
        when available.
    Invariants:
        Does not touch the filesystem beyond formatting the provided payload.
    """

    paths = payload["paths"]
    if not isinstance(paths, Mapping):
        raise ValueError("logs payload paths must be a mapping")
    print(f"Dog Paw emulator logs: {payload['name']}")
    print(f"Persistent emulator log dir: {paths['emulatorLogsDir']}")
    print(f"Runtime app log dir: {paths['appLogsDir']}")
    print(f"Epiphany stdout log: {paths['epiphanyStdoutLog']}")
    existing_app_logs = payload.get("existingAppLogs")
    if isinstance(existing_app_logs, list) and existing_app_logs:
        print("Existing app logs:")
        for log_path in existing_app_logs:
            print(f"  {log_path}")
    else:
        print("Existing app logs: none")


def create_emulator(config: EmulatorConfig) -> dict[str, object]:
    """Create or refresh one named emulator environment.

    Purpose:
        Owns the persistent setup step for emulator lifecycle management:
        directory creation, managed runtime resource seeding, and metadata
        writing.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        JSON-serializable lifecycle summary after creation.
    Requirements:
        The caller must have write access to the configured data and runtime
        roots.
    Guarantees:
        Preserves installed apps and app files while refreshing metadata and
        shared resources.
    Invariants:
        Existing app registry contents are not deleted or rewritten.
    """

    prepare_roots(config)
    metadata = {
        "schemaVersion": 1,
        "name": config.emulator_name,
        "instanceName": config.instance_name,
        "startupPlan": str(config.startup_plan),
        "hardwareProfile": config.hardware_profile,
    }
    metadata_path = emulator_metadata_path(config)
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return emulator_info_payload(config)


def default_app_names(startup_plan: Path) -> list[str]:
    """Return the app names installed by the default emulator app set.

    Purpose:
        Derives the emulator's default app registry from the same startup plan
        Epiphany will run, then adds developer-facing test apps that should be
        present but not launched on startup.
    Parameters:
        startup_plan: JSON startup plan containing `launch_app` actions.
    Return value:
        Ordered app names, with duplicates removed by first occurrence.
    Requirements:
        `startup_plan` must be a readable JSON object with an `actions` list.
    Guarantees:
        Includes startup-plan launch apps and `DEFAULT_EXTRA_APP_NAMES`.
    Invariants:
        Does not modify emulator state or app manifests.
    """

    payload = json.loads(startup_plan.read_text(encoding="utf-8"))
    actions = payload.get("actions", [])
    if not isinstance(actions, list):
        raise ValueError(f"startup plan actions must be a list: {startup_plan}")

    names: list[str] = []
    seen: set[str] = set()
    for action in actions:
        if not isinstance(action, dict):
            continue
        if action.get("type") != "launch_app":
            continue
        app_name = action.get("app")
        if not isinstance(app_name, str):
            continue
        if app_name not in seen:
            names.append(app_name)
            seen.add(app_name)
    for app_name in DEFAULT_EXTRA_APP_NAMES:
        if app_name not in seen:
            names.append(app_name)
            seen.add(app_name)
    return names


def manifest_name(manifest_path: Path) -> str | None:
    """Read a Dog Paw manifest name without enforcing install semantics.

    Purpose:
        Supports source-tree manifest lookup for default emulator installs.
    Parameters:
        manifest_path: Path to a candidate `dogpawapp.json`.
    Return value:
        Manifest `name` when present and string-valued, otherwise `None`.
    Requirements:
        Caller should only pass readable JSON manifest files.
    Guarantees:
        JSON parse failures propagate to the caller.
    Invariants:
        Does not modify the manifest or app registry.
    """

    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    name = payload.get("name")
    return name if isinstance(name, str) else None


def manifest_is_flutter_app(manifest_path: Path) -> bool:
    """Return whether a Dog Paw manifest describes a Flutter app.

    Purpose:
        Selects the existing install wrapper appropriate for a default app.
    Parameters:
        manifest_path: Path to a valid Dog Paw app manifest.
    Return value:
        `True` when the manifest has a string `flutterApp` field.
    Requirements:
        `manifest_path` must point to readable JSON.
    Guarantees:
        Headless manifests without `flutterApp` return `False`.
    Invariants:
        Does not infer app type from directory layout.
    """

    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    return isinstance(payload.get("flutterApp"), str)


def manifest_is_packaged_app_seed(manifest_path: Path) -> bool:
    """Return whether one manifest belongs to the packaged runtime base-app set.

    Purpose:
        Distinguishes SDK-shipped app seed payloads from source-tree manifests so
        default emulator installs can either copy a packaged payload directly or
        route through the development install wrappers.
    Parameters:
        manifest_path: Path to a candidate Dog Paw app manifest.
    Return value:
        `True` when the manifest lives below `PACKAGED_BASE_APPS_ROOT`.
    Requirements:
        `manifest_path` should be absolute or resolvable to an absolute path.
    Guarantees:
        Returns `False` when packaged base apps are not present in the current
        layout.
    Invariants:
        Performs path checks only; it does not read the manifest body.
    """

    if not PACKAGED_BASE_APPS_ROOT.exists():
        return False
    try:
        manifest_path.resolve().relative_to(PACKAGED_BASE_APPS_ROOT.resolve())
        return True
    except ValueError:
        return False


def install_packaged_app_seed(manifest_path: Path, app_root: Path) -> Path:
    """Copy one packaged base-app seed payload into an emulator app registry.

    Purpose:
        Lets exported SDK emulators install their shipped base apps without
        depending on internal repo wrappers, source manifests, or mutable build
        directories.
    Parameters:
        manifest_path: Manifest path inside the packaged `runtime/base_apps`
            payload.
        app_root: Emulator app registry root that should receive the installed
            app directory.
    Return value:
        Installed app directory path under `app_root`.
    Requirements:
        `manifest_path` must point to a packaged app seed manifest containing a
        valid string `name` field.
    Guarantees:
        Replaces any existing app directory with the packaged seed contents and
        does not create `install_metadata.json`.
    Invariants:
        The packaged seed source directory is never modified.
    """

    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    app_name = payload.get("name")
    if not isinstance(app_name, str) or not app_name:
        raise ValueError(f"Packaged app seed missing name: {manifest_path}")
    seed_root = manifest_path.parent
    install_dir = app_root / app_name
    if install_dir.exists():
        shutil.rmtree(install_dir)
    install_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(seed_root, install_dir)
    metadata_path = install_dir / "install_metadata.json"
    if metadata_path.exists():
        metadata_path.unlink()
    return install_dir


def default_app_manifest_index() -> dict[str, Path]:
    """Build an app-name to manifest-path index for default emulator installs.

    Purpose:
        Lets the default install set refer to app names from startup plans while
        resolving either packaged SDK app seeds or source-tree manifests.
    Parameters:
        None.
    Return value:
        Mapping from manifest `name` values to `dogpawapp.json` paths.
    Requirements:
        Candidate packaged or source-tree manifests must be valid JSON.
    Guarantees:
        Packaged app seeds take precedence over source-tree manifests, and later
        duplicate names do not replace earlier matches.
    Invariants:
        Only scans the packaged base-app seed directory and known Dog Paw app
        source directories.
    """

    search_roots = [
        PACKAGED_BASE_APPS_ROOT,
        *packaged_example_manifest_roots(),
        *source_app_manifest_roots(),
    ]
    index: dict[str, Path] = {}
    for search_root in search_roots:
        if not search_root.is_dir():
            continue
        for manifest_path in sorted(search_root.glob("**/dogpawapp.json")):
            name = manifest_name(manifest_path)
            if name and name not in index:
                index[name] = manifest_path
    return index


def install_default_apps(
    config: EmulatorConfig,
    startup_plan: Path,
    build_dir: str,
    build_mode: str,
    runner: Callable[..., subprocess.CompletedProcess[object]] = subprocess.run,
) -> list[str]:
    """Install the default app set into one emulator registry.

    Purpose:
        Populates a newly created emulator with the apps needed by its startup
        plan plus a small developer test app, using the same install wrappers as
        explicit `install-headless` and `install-flutter` commands.
    Parameters:
        config: Resolved emulator configuration whose app registry is targeted.
        startup_plan: Startup plan used to derive required launch apps.
        build_dir: Native build directory passed to headless installs.
        build_mode: Flutter Linux build mode passed to Flutter installs.
        runner: Command runner compatible with `subprocess.run`, injectable for
            tests.
    Return value:
        Ordered list of app names successfully installed.
    Requirements:
        The emulator root must already exist, and all default app manifests must
        be present in the source tree.
    Guarantees:
        Raises `RuntimeError` on the first failed child installer command.
    Invariants:
        Does not delete existing app registry entries.
    """

    manifest_index = default_app_manifest_index()
    installed: list[str] = []
    for app_name in default_app_names(startup_plan):
        manifest_path = manifest_index.get(app_name)
        if manifest_path is None:
            raise FileNotFoundError(f"default app manifest not found: {app_name}")

        if manifest_is_packaged_app_seed(manifest_path):
            install_packaged_app_seed(manifest_path, config.app_dir)
            installed.append(app_name)
            continue

        if manifest_is_flutter_app(manifest_path):
            command = [
                str(FLUTTER_INSTALL_WRAPPER),
                "--manifest",
                str(manifest_path),
                "--app-root",
                str(config.app_dir),
                "--build-mode",
                build_mode,
            ]
        else:
            command = [
                str(HEADLESS_INSTALL_WRAPPER),
                "--manifest",
                str(manifest_path),
                "--app-root",
                str(config.app_dir),
                "--build-dir",
                build_dir,
            ]

        result = runner(command, cwd=str(SOURCE_LAYOUT_ROOT or WORKSPACE_ROOT), check=False)
        if result.returncode != 0:
            raise RuntimeError(f"default app install failed for {app_name}")
        installed.append(app_name)
    return installed


def installed_app_staleness(installed_app_dir: Path) -> dict[str, object]:
    """Report whether one installed app is stale relative to its source inputs.

    Purpose:
        Reads `install_metadata.json`, recomputes the current source fingerprint
        from the stored source-input list, and explains whether the installed app
        should be reinstalled before launch.
    Parameters:
        installed_app_dir: Installed app directory inside an emulator app
            registry.
    Return value:
        JSON-serializable report containing `stale`, `reason`, `appName`, and
        `sourceManifest`.
    Requirements:
        `installed_app_dir` should point to one installed app directory.
    Guarantees:
        Missing or incomplete metadata reports staleness instead of raising.
    Invariants:
        Reads install metadata and source files only; it does not reinstall apps.
    """
    metadata_path = installed_app_dir / "install_metadata.json"
    report: dict[str, object] = {
        "appName": installed_app_dir.name,
        "sourceManifest": None,
        "stale": True,
        "reason": "install-metadata-missing",
    }
    if not metadata_path.is_file():
        return report
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        report["reason"] = "install-metadata-invalid"
        return report
    if not isinstance(metadata, dict):
        report["reason"] = "install-metadata-invalid"
        return report

    app_name = metadata.get("appName")
    if isinstance(app_name, str) and app_name:
        report["appName"] = app_name
    source_manifest = metadata.get("sourceManifest")
    if isinstance(source_manifest, str) and source_manifest:
        report["sourceManifest"] = source_manifest

    source_inputs = metadata.get("sourceInputs")
    source_fingerprint = metadata.get("sourceFingerprint")
    if not isinstance(source_inputs, list) or not all(isinstance(item, str) for item in source_inputs):
        report["reason"] = "source-fingerprint-missing"
        return report
    if not isinstance(source_fingerprint, str) or not source_fingerprint:
        report["reason"] = "source-fingerprint-missing"
        return report

    _, current_fingerprint = install_fingerprint.fingerprint_source_inputs(
        [Path(item) for item in source_inputs]
    )
    if current_fingerprint != source_fingerprint:
        report["reason"] = "source-fingerprint-changed"
        return report

    report["stale"] = False
    report["reason"] = "current"
    return report


def install_updated_apps(
    config: EmulatorConfig,
    build_dir: str,
    build_mode: str,
    runner: Callable[..., subprocess.CompletedProcess[object]] = subprocess.run,
) -> list[str]:
    """Reinstall stale apps already present in one emulator app registry.

    Purpose:
        Supports `--install-updated` by checking installed apps against their
        stored source fingerprints and routing stale entries back through the
        existing headless or Flutter install wrappers.
    Parameters:
        config: Resolved emulator configuration whose app registry is targeted.
        build_dir: Native build directory passed to headless reinstalls.
        build_mode: Flutter Linux build mode passed to Flutter reinstalls.
        runner: Command runner compatible with `subprocess.run`, injectable for
            tests.
    Return value:
        Ordered list of app names reinstalled during this check.
    Requirements:
        Installed apps should have been created by the Dog Paw install tools so
        `sourceManifest` points back to source-tree manifests.
    Guarantees:
        Warns and removes orphaned installed apps whose source manifest was
        removed from the repo. Raises `RuntimeError` on the first failed
        reinstall command.
    Invariants:
        Leaves current app registry entries untouched when they are already
        up-to-date.
    """
    if not config.app_dir.is_dir():
        return []

    updated: list[str] = []
    for installed_app_dir in sorted(path for path in config.app_dir.iterdir() if path.is_dir()):
        report = installed_app_staleness(installed_app_dir)
        if not report["stale"]:
            continue
        source_manifest = report.get("sourceManifest")
        if not isinstance(source_manifest, str) or not source_manifest:
            continue
        manifest_path = Path(source_manifest)
        if not manifest_path.is_file():
            print(
                "Warning: Removing orphaned installed app "
                f"'{report['appName']}' because its source manifest no longer exists: "
                f"{manifest_path}",
                file=sys.stderr,
            )
            shutil.rmtree(installed_app_dir)
            continue

        if manifest_is_flutter_app(manifest_path):
            command = [
                str(FLUTTER_INSTALL_WRAPPER),
                "--manifest",
                str(manifest_path),
                "--app-root",
                str(config.app_dir),
                "--build-mode",
                build_mode,
            ]
        else:
            command = [
                str(HEADLESS_INSTALL_WRAPPER),
                "--manifest",
                str(manifest_path),
                "--app-root",
                str(config.app_dir),
                "--build-dir",
                build_dir,
            ]
        result = runner(command, cwd=str(SOURCE_LAYOUT_ROOT or WORKSPACE_ROOT), check=False)
        if result.returncode != 0:
            raise RuntimeError(f"updated install failed for {report['appName']}")
        updated.append(str(report["appName"]))
    return updated


def list_emulators(data_root: Path, runtime_root: Path) -> list[dict[str, object]]:
    """List lifecycle-managed emulators below one data root.

    Purpose:
        Implements the `list` command without relying on source-tree state or
        scanning unrelated Dog Paw data directories.
    Parameters:
        data_root: Base Dog Paw persistent data directory.
        runtime_root: Base Dog Paw runtime directory used to reconstruct
            per-emulator runtime paths.
    Return value:
        Sorted list of lifecycle summaries.
    Requirements:
        Emulator directories are expected under `data_root/emulators`.
    Guarantees:
        Missing data roots produce an empty list.
    Invariants:
        Only directories containing `emulator.json` are reported.
    """

    emulators_root = data_root / "emulators"
    if not emulators_root.is_dir():
        return []
    summaries: list[dict[str, object]] = []
    for metadata_path in sorted(emulators_root.glob("*/emulator.json")):
        try:
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        name = metadata.get("name")
        if not isinstance(name, str):
            continue
        instance_name = metadata.get("instanceName")
        args = argparse.Namespace(
            name=name,
            instance=instance_name if isinstance(instance_name, str) else None,
            data_root=str(data_root),
            runtime_root=str(runtime_root),
            startup_plan=metadata.get("startupPlan", str(DEFAULT_STARTUP_PLAN)),
            epiphany="",
            sway="",
            swaymsg="",
            wlr_backends=None,
            hardware_profile=None,
        )
        summaries.append(emulator_info_payload(resolve_config(args, os.environ)))
    return summaries


def delete_emulator(config: EmulatorConfig, force: bool) -> None:
    """Delete one named emulator environment.

    Purpose:
        Removes a selected emulator root for cleanup while making destructive
        behavior explicit for automation.
    Parameters:
        config: Resolved emulator configuration.
        force: Must be `True` to actually remove the emulator root.
    Return value:
        None.
    Requirements:
        The emulator must exist and `force` must be set.
    Guarantees:
        Removes only `config.emulator_root`.
    Invariants:
        Other emulator directories and shared data-root resources are untouched.
    """

    if not force:
        raise ValueError("delete requires --force")
    if not emulator_exists(config):
        raise FileNotFoundError(missing_emulator_message(config, os.environ))
    shutil.rmtree(config.emulator_root)


def prepare_run_runtime(config: EmulatorConfig) -> None:
    """Create runtime-only directories needed for one emulator launch.

    Purpose:
        Keeps `run` from reseeding persistent resources while still ensuring
        nested Sway can write its generated config and runtime files.
    Parameters:
        config: Resolved emulator configuration for an existing emulator.
    Return value:
        None.
    Requirements:
        The emulator should already exist according to `emulator_exists()`.
    Guarantees:
        Creates `instance_runtime_dir` if missing and refreshes the staged
        native bridge when a built source artifact is available.
    Invariants:
        Persistent app registries, app files, and shared resources are not
        copied or modified.
    """

    config.instance_runtime_dir.mkdir(parents=True, exist_ok=True)
    nested_socket = nested_sway_socket_path(config)
    if nested_socket.exists() or nested_socket.is_symlink():
        nested_socket.unlink()
    stage_bridge_library(config)


def missing_emulator_message_for_lookup(
    emulator_name: str,
    data_root: Path,
    runtime_root: Path,
    env: Mapping[str, str],
) -> str:
    """Build a user-facing error for one unresolved emulator lookup.

    Purpose:
        Explains which roots were used to look up an emulator by name and, when
        the caller chose non-default roots, points them back at the standard
        Linux/XDG-backed flow where only the emulator name is normally needed.
    Parameters:
        emulator_name: Requested emulator name.
        data_root: Persistent Dog Paw data root used for the lookup.
        runtime_root: Runtime root paired with the lookup.
        env: Environment mapping used to derive the standard default roots.
    Return value:
        Multi-line human-readable error message.
    Requirements:
        `emulator_name` must already be validated and both roots must be
        resolved absolute paths.
    Guarantees:
        Includes the effective lookup roots and, when possible, a hint about the
        standard default-root workflow.
    Invariants:
        Does not create files or modify emulator state.
    """

    lines = [
        f"Emulator does not exist: {emulator_name}",
        f"Looked in data root: {data_root}",
        f"Looked in runtime root: {runtime_root}",
    ]
    try:
        default_data = default_data_root(env)
        default_runtime = default_runtime_root(env)
    except ValueError:
        return "\n".join(lines)

    if data_root != default_data or runtime_root != default_runtime:
        default_emulator_root = default_data / "emulators" / emulator_name
        if (default_emulator_root / "emulator.json").is_file():
            lines.append(
                f"An emulator named '{emulator_name}' exists in the standard location: "
                f"{default_emulator_root}"
            )
        lines.append(
            "If you created this emulator with the standard locations, omit "
            "--data-root and --runtime-root."
        )
    return "\n".join(lines)


def missing_emulator_message(config: EmulatorConfig, env: Mapping[str, str]) -> str:
    """Build the standard missing-emulator error for one resolved config.

    Purpose:
        Keeps lifecycle-dependent commands consistent by routing all
        name-plus-root lookup failures through one explanation helper.
    Parameters:
        config: Resolved emulator configuration whose lookup failed.
        env: Environment mapping used to derive the standard default roots.
    Return value:
        Multi-line human-readable error message.
    Requirements:
        `config` must contain resolved name and root paths.
    Guarantees:
        Returns the same guidance shape used by early config-resolution failures.
    Invariants:
        Pure formatter with no filesystem side effects.
    """

    return missing_emulator_message_for_lookup(
        config.emulator_name,
        config.data_root,
        config.runtime_root,
        env,
    )


def lookup_roots_from_args(
    args: argparse.Namespace,
    env: Mapping[str, str],
) -> tuple[str, Path, Path]:
    """Resolve emulator name and lookup roots without full config loading.

    Purpose:
        Supports early error reporting when config resolution fails before the
        emulator's saved metadata can be loaded, such as when a command was
        pointed at the wrong roots.
    Parameters:
        args: Parsed emulator CLI arguments.
        env: Environment mapping used for default root resolution.
    Return value:
        Tuple of validated emulator name, resolved data root, and resolved
        runtime root.
    Requirements:
        `args` must come from `build_parser()`.
    Guarantees:
        Uses the same name and root resolution rules as `resolve_config()`.
    Invariants:
        Does not read metadata or inspect existing emulator directories.
    """

    emulator_name = validate_name(args.name, "emulator name")
    data_root = Path(args.data_root).expanduser().resolve() if args.data_root else default_data_root(env)
    runtime_root = (
        Path(args.runtime_root).expanduser().resolve()
        if args.runtime_root
        else default_runtime_root(env)
    )
    return emulator_name, data_root, runtime_root


def require_existing_emulator(config: EmulatorConfig) -> bool:
    """Report whether an emulator exists, printing a standard error if not.

    Purpose:
        Gives lifecycle-dependent commands the same user-facing failure mode
        when the selected named emulator has not been created.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        `True` when the emulator exists, otherwise `False`.
    Requirements:
        None.
    Guarantees:
        Missing emulators produce a clear stderr message.
    Invariants:
        Does not create or modify emulator state.
    """

    if emulator_exists(config):
        return True
    print(missing_emulator_message(config, os.environ), file=sys.stderr)
    return False


def resolve_cli_manifest_path(manifest: str) -> Path:
    """Resolve an install manifest path from the caller's current directory.

    Purpose:
        Lets emulator install commands accept the same relative paths a user
        would expect from their shell, regardless of where the emulator tool's
        internal helper code lives.
    Parameters:
        manifest: Absolute path or path relative to the current working
            directory where `dogpaw_emulator.py` was invoked.
    Return value:
        Absolute, resolved path to the manifest.
    Requirements:
        The path must identify an existing file.
    Guarantees:
        Raises `FileNotFoundError` with the original user-supplied path when the
        manifest is absent.
    Invariants:
        Does not try alternate roots or rewrite app ownership boundaries.
    """

    manifest_path = Path(manifest)
    if not manifest_path.is_absolute():
        manifest_path = Path(os.path.abspath(manifest))
    if not manifest_path.is_file():
        raise FileNotFoundError(f"manifest not found: {manifest}")
    return manifest_path.resolve()


def resolve_cli_existing_path(path_value: str, label: str) -> Path:
    """Resolve one existing CLI-supplied file or directory path.

    Purpose:
        Keeps emulator install commands consistent with normal shell semantics by
        resolving relative paths from the caller's current working directory
        instead of from any internal helper location.
    Parameters:
        path_value: Absolute path or path relative to the current working
            directory where `dogpaw_emulator.py` was invoked.
        label: Human-readable path label used in error messages.
    Return value:
        Absolute, resolved filesystem path.
    Requirements:
        `path_value` must identify an existing file or directory.
    Guarantees:
        Raises `FileNotFoundError` with the original user-supplied path when the
        target is absent.
    Invariants:
        Does not try fallback roots or mutate filesystem state.
    """

    candidate = Path(path_value).expanduser()
    if not candidate.is_absolute():
        candidate = Path(os.path.abspath(str(candidate)))
    if not candidate.exists():
        raise FileNotFoundError(f"{label} not found: {path_value}")
    return candidate.resolve()


def host_flutter_arch() -> str:
    """Return the Flutter Linux bundle architecture directory for this host.

    Purpose:
        Matches Flutter's Linux bundle directory naming so emulator-local UI app
        installs can locate the expected `build/linux/<arch>/<mode>/bundle`
        output without relying on the old shell wrapper.
    Parameters:
        None.
    Return value:
        Architecture directory name such as `x64` or `arm64`.
    Requirements:
        None.
    Guarantees:
        Known desktop architectures are normalized to Flutter's expected names.
        Unknown architectures fall back to the raw machine identifier.
    Invariants:
        Reads host architecture only; it does not inspect build outputs.
    """

    machine = os.uname().machine
    if machine in {"aarch64", "arm64"}:
        return "arm64"
    if machine in {"x86_64", "amd64"}:
        return "x64"
    return machine


def runtime_binary_arch_dir_name() -> str:
    """Return the packaged runtime binary architecture directory for this host.

    Purpose:
        Maps the current host architecture onto the exported SDK runtime's
        `runtime/bin/linux-<arch>/` directory naming convention.
    Parameters:
        None.
    Return value:
        Runtime binary architecture directory name such as `linux-x64` or
        `linux-arm64`.
    Requirements:
        None.
    Guarantees:
        Reuses `host_flutter_arch()` for shared architecture normalization.
    Invariants:
        Does not inspect the filesystem or validate that packaged binaries exist.
    """

    return f"linux-{host_flutter_arch()}"


def default_epiphany_executable_for_layout(layout: RuntimeLayout) -> Path:
    """Return the default Epiphany executable path for one runtime layout.

    Purpose:
        Keeps the emulator CLI usable without extra flags in both the internal
        repo and the exported SDK by selecting the natural Epiphany binary
        location for each layout.
    Parameters:
        layout: Resolved runtime layout for the current emulator tool instance.
    Return value:
        Absolute path to the default Epiphany executable for that layout.
    Requirements:
        `layout` must describe either the source-repo or packaged-SDK runtime
        shape.
    Guarantees:
        Points into `runtime/bin/linux-<arch>/Epiphany` for both packaged SDK and
        source-checkout runs.
    Invariants:
        Path construction is deterministic and does not check whether the binary
        exists yet.
    """

    return layout.runtime_root / "bin" / runtime_binary_arch_dir_name() / "Epiphany"


def resolve_command_path_argument(value: str) -> str:
    """Resolve one CLI command argument that may be a relative filesystem path.

    Purpose:
        Preserves shell-relative path expectations for executable arguments such
        as `--epiphany` while leaving bare command names like `sway` unchanged so
        normal `PATH` lookup still works.
    Parameters:
        value: Raw CLI argument value for an executable or command.
    Return value:
        Absolute path string when the argument looks path-like; otherwise the
        original command string.
    Requirements:
        `value` must be a non-empty string.
    Guarantees:
        Relative paths are resolved from the caller's current working directory.
    Invariants:
        Does not check executability or create files.
    """

    if "/" not in value and not value.startswith("~"):
        return value
    return str(Path(os.path.abspath(os.path.expanduser(value))))


def resolve_manifest_required_string_field(manifest_path: Path, field_name: str) -> str:
    """Read one required top-level string field from an app manifest.

    Purpose:
        Reuses the common Python install manifest parser while letting emulator
        install commands validate the specific fields they need for payload
        resolution.
    Parameters:
        manifest_path: Source `dogpawapp.json` path.
        field_name: Required top-level manifest field name.
    Return value:
        Non-empty string value of the requested field.
    Requirements:
        `manifest_path` must point to a readable Dog Paw manifest JSON object.
    Guarantees:
        Raises `ValueError` when the requested field is missing or not a
        non-empty string.
    Invariants:
        Reads manifest contents only; it does not copy or modify files.
    """

    manifest = install_app.load_manifest(manifest_path)
    value = manifest.get(field_name)
    if not isinstance(value, str) or not value:
        raise ValueError(f"Manifest requires non-empty string field: {field_name}")
    return value


def resolve_headless_install_binary_path(
    manifest_path: Path,
    build_dir: str,
    explicit_binary: str | None,
) -> Path:
    """Resolve the primary executable payload for one headless app install.

    Purpose:
        Preserves the existing install contract where a headless manifest's
        `executable` is loaded from `<build-dir>/bin/` unless the caller provides
        an explicit binary override.
    Parameters:
        manifest_path: Source `dogpawapp.json` for the headless app.
        build_dir: Build root whose `bin/` directory should contain the manifest
            executable when `explicit_binary` is not supplied.
        explicit_binary: Optional direct executable path that overrides build-dir
            lookup.
    Return value:
        Absolute path to the binary payload that should be installed.
    Requirements:
        The chosen binary must exist as a regular file.
    Guarantees:
        Raises `ValueError` with a clear install-focused message when the binary
        cannot be resolved.
    Invariants:
        Does not build binaries or modify the source tree.
    """

    if explicit_binary:
        binary_path = resolve_cli_existing_path(explicit_binary, "binary")
        if not binary_path.is_file():
            raise ValueError(f"Binary not found: {explicit_binary}")
        return binary_path

    resolved_build_dir = resolve_cli_existing_path(build_dir, "build directory")
    executable_name = resolve_manifest_required_string_field(manifest_path, "executable")
    candidate = resolved_build_dir / "bin" / executable_name
    if not candidate.is_file():
        raise ValueError(
            f"binary for executable '{executable_name}' not found at {candidate}. "
            "Build it first, or pass --binary PATH."
        )
    return candidate.resolve()


def resolve_headless_extra_binary_paths(manifest_path: Path, build_dir: str) -> list[Path]:
    """Resolve manifest-declared helper binaries for one headless install.

    Purpose:
        Keeps `install.extraBinaries` behavior aligned with the shared install
        contract by looking up each helper beside the primary headless build
        output.
    Parameters:
        manifest_path: Source `dogpawapp.json` declaring any helper binaries.
        build_dir: Build root whose `bin/` directory should contain the helper
            executables.
    Return value:
        Ordered list of absolute helper binary paths.
    Requirements:
        `build_dir/bin/` must contain every helper binary declared in the
        manifest.
    Guarantees:
        Raises `ValueError` when any declared helper binary is missing.
    Invariants:
        Does not copy files or inspect any binaries beyond existence checks.
    """

    manifest = install_app.load_manifest(manifest_path)
    declared_names = install_app.declared_extra_binaries(manifest)
    if not declared_names:
        return []
    resolved_build_dir = resolve_cli_existing_path(build_dir, "build directory")
    paths: list[Path] = []
    for helper_name in declared_names:
        candidate = resolved_build_dir / "bin" / helper_name
        if not candidate.is_file():
            raise ValueError(f"extra binary '{helper_name}' not found at {candidate}")
        paths.append(candidate.resolve())
    return paths


def resolve_flutter_project_dir(manifest_path: Path) -> Path:
    """Resolve the Flutter project directory declared by one app manifest.

    Purpose:
        Lets emulator-local Flutter installs work directly from the source app
        tree by reading the manifest's `flutterApp` relative path.
    Parameters:
        manifest_path: Source `dogpawapp.json` for a Flutter app.
    Return value:
        Absolute path to the Flutter project directory.
    Requirements:
        The manifest must contain a valid non-empty `flutterApp` field and the
        resolved project directory must exist.
    Guarantees:
        Raises `ValueError` with a clear message when the project is missing.
    Invariants:
        The returned project path always stays beneath the manifest directory.
    """

    flutter_project_rel = resolve_manifest_required_string_field(manifest_path, "flutterApp")
    project_dir = (manifest_path.parent / flutter_project_rel).resolve()
    if not project_dir.is_dir():
        raise ValueError(f"Flutter project not found: {project_dir}")
    return project_dir


def resolve_flutter_bundle_dir(manifest_path: Path, build_mode: str) -> Path:
    """Resolve the expected Flutter Linux bundle directory for one app build.

    Purpose:
        Encodes Flutter's Linux build-output contract so emulator-local installs
        can find the built runtime bundle after `flutter build linux`.
    Parameters:
        manifest_path: Source `dogpawapp.json` for a Flutter app.
        build_mode: Flutter build mode string such as `debug` or `release`.
    Return value:
        Absolute path to the expected bundle directory.
    Requirements:
        `build_mode` must match the mode passed to the Flutter build command.
    Guarantees:
        Returns the bundle path even when it does not exist yet.
    Invariants:
        Path construction depends only on the manifest location, host
        architecture, and build mode.
    """

    project_dir = resolve_flutter_project_dir(manifest_path)
    return (
        project_dir
        / "build"
        / "linux"
        / host_flutter_arch()
        / build_mode
        / "bundle"
    ).resolve()


def flutter_build_command(project_dir: Path, build_mode: str) -> list[str]:
    """Build the `flutter build linux` command for one install request.

    Purpose:
        Centralizes the exact local build command shared by dry-run reporting and
        real emulator-local Flutter installs.
    Parameters:
        project_dir: Flutter project directory being built.
        build_mode: Flutter build mode such as `debug` or `release`.
    Return value:
        Command vector suitable for `subprocess.run`.
    Requirements:
        `project_dir` must be a Flutter project directory.
    Guarantees:
        The returned command matches Flutter's Linux build CLI shape.
    Invariants:
        Does not execute the build or touch the filesystem.
    """

    return ["flutter", "build", "linux", f"--{build_mode}"]


def print_flutter_install_dry_run(manifest_path: Path, app_root: Path, build_mode: str) -> None:
    """Print the local Flutter build-and-install steps for dry-run mode.

    Purpose:
        Keeps `install-flutter --dry-run` readable for developers while matching
        the real local install steps closely enough to debug missing bundles or
        wrong app roots without executing a build.
    Parameters:
        manifest_path: Source `dogpawapp.json` for the requested app.
        app_root: Emulator app registry root that would receive the install.
        build_mode: Flutter build mode that would be used for the build.
    Return value:
        None.
    Requirements:
        `manifest_path` must resolve to a valid Flutter app manifest.
    Guarantees:
        Prints the `flutter pub get`, `flutter build linux`, and install steps in
        execution order without creating files or subprocesses.
    Invariants:
        Output references only the resolved local install paths.
    """

    project_dir = resolve_flutter_project_dir(manifest_path)
    bundle_dir = resolve_flutter_bundle_dir(manifest_path, build_mode)
    install_tool_path = Path(install_app.__file__).resolve()
    print(f"cd '{project_dir}' && flutter pub get && {' '.join(flutter_build_command(project_dir, build_mode))}")
    print(
        f"python3 '{install_tool_path}' --manifest '{manifest_path}' "
        f"--app-root '{app_root}' --bundle '{bundle_dir}'"
    )


def find_free_tcp_port(host: str = DEFAULT_BRIDGE_HOST) -> int:
    """Reserve and return a currently available TCP port on one host.

    Purpose:
        Lets the one-command emulator control workflow avoid hard-coded bridge
        ports while still passing an explicit URL to the Flutter GUI.
    Parameters:
        host: Local interface to probe. Valid values are bindable TCP host names
            or addresses; the default is loopback.
    Return value:
        TCP port number that was free at probe time.
    Requirements:
        The caller must tolerate the normal race where another process can bind
        the returned port before the bridge starts.
    Guarantees:
        Closes the temporary socket before returning.
    Invariants:
        Does not start the bridge or modify emulator state.
    """

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind((host, 0))
        return int(probe.getsockname()[1])


def control_bridge_port(args: argparse.Namespace) -> int:
    """Resolve the bridge port for a control workflow invocation.

    Purpose:
        Keeps `bridge` using its stable default while `control` can auto-select
        an available port when the user did not request one.
    Parameters:
        args: Parsed emulator CLI arguments.
    Return value:
        Bridge TCP port.
    Requirements:
        If `args.bridge_port` is provided it must be a valid integer port.
    Guarantees:
        Returns the user-supplied port unchanged when present.
    Invariants:
        Does not inspect currently running bridge processes except when probing
        for an automatically selected free port.
    """

    if args.bridge_port is not None:
        return int(args.bridge_port)
    return find_free_tcp_port(args.bridge_host)


def dogpaw_emulator_child_base_args(
    config: EmulatorConfig,
    args: argparse.Namespace,
) -> list[str]:
    """Build shared CLI arguments for child `dogpaw_emulator.py` commands.

    Purpose:
        Ensures `control` launches `run` and `bridge` against the same emulator
        profile, roots, startup plan, and executable overrides as the parent.
    Parameters:
        config: Resolved emulator configuration.
        args: Parsed parent CLI arguments.
    Return value:
        Argument list beginning with Python and `dogpaw_emulator.py`.
    Requirements:
        `args` must include parser fields produced by `build_parser()`.
    Guarantees:
        Includes Python and `dogpaw_emulator.py`, but not a subcommand; callers
        insert `run` or `bridge`.
    Invariants:
        Does not create files or start processes.
    """

    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--name",
        config.emulator_name,
        "--instance",
        config.instance_name,
        "--data-root",
        str(config.data_root),
        "--runtime-root",
        str(config.runtime_root),
        "--startup-plan",
        str(config.startup_plan),
        "--epiphany",
        config.epiphany,
        "--sway",
        config.sway,
        "--swaymsg",
        config.swaymsg,
    ]
    if args.wlr_backends:
        command.extend(["--wlr-backends", str(args.wlr_backends)])
    if args.verbose:
        command.append("--verbose")
    return command


def control_child_commands(
    config: EmulatorConfig,
    args: argparse.Namespace,
    bridge_port: int,
) -> tuple[list[str], list[str], list[str]]:
    """Build child commands supervised by `dogpaw_emulator.py control`.

    Purpose:
        Centralizes the command contract for the screen/runtime process, bridge,
        and Flutter control GUI so dry-run output and real execution stay in
        sync.
    Parameters:
        config: Resolved emulator configuration.
        args: Parsed parent CLI arguments.
        bridge_port: TCP port assigned to the bridge.
    Return value:
        Tuple of `(emulator_command, bridge_command, gui_command)`.
    Requirements:
        `bridge_port` must be the same port passed to the GUI URL.
    Guarantees:
        Does not start any process.
    Invariants:
        The GUI remains an external control surface over the Python bridge.
    """

    base = dogpaw_emulator_child_base_args(config, args)
    emulator_command = [base[0], base[1], "screen", *base[2:]]
    bridge_command = [
        base[0],
        base[1],
        "bridge",
        *base[2:],
        "--bridge-host",
        args.bridge_host,
        "--bridge-port",
        str(bridge_port),
    ]
    gui_command = [
        "flutter",
        "run",
        "-d",
        "linux",
        "-a",
        f"--bridge-url=http://{args.bridge_host}:{bridge_port}",
    ]
    return emulator_command, bridge_command, gui_command


def format_shell_command(command: Sequence[str]) -> str:
    """Format an argument vector for human-readable dry-run output.

    Purpose:
        Makes `control --dry-run` understandable while preserving enough quoting
        for copy/paste diagnostics.
    Parameters:
        command: Executable and arguments.
    Return value:
        Shell-style command string.
    Requirements:
        `command` should contain string-like arguments.
    Guarantees:
        Does not execute the command.
    Invariants:
        Formatting has no effect on the real command vectors.
    """

    return " ".join(shlex.quote(str(part)) for part in command)


def control_dry_run_lines(
    config: EmulatorConfig,
    args: argparse.Namespace,
    bridge_port: int,
) -> list[str]:
    """Describe the control workflow without launching child processes.

    Purpose:
        Gives tests and users a clear view of the one-command orchestration
        contract.
    Parameters:
        config: Resolved emulator configuration.
        args: Parsed parent CLI arguments.
        bridge_port: TCP port that would be used by the bridge and GUI.
    Return value:
        Human-readable output lines.
    Requirements:
        `bridge_port` must be resolved before calling.
    Guarantees:
        Includes emulator, bridge, and GUI commands.
    Invariants:
        Does not create files, start processes, or mutate emulator state.
    """

    emulator_command, bridge_command, gui_command = control_child_commands(config, args, bridge_port)
    return [
        "Dog Paw emulator run would start:",
        f"  screen: {format_shell_command(emulator_command)}",
        f"  bridge: {format_shell_command(bridge_command)}",
        f"  controls: {format_shell_command(gui_command)}",
        "First child exit stops the full control session.",
    ]


def start_control_bridge_process(
    config: EmulatorConfig,
    args: argparse.Namespace,
    base_env: Mapping[str, str],
    output_threads: list[threading.Thread],
) -> tuple[int, subprocess.Popen[object]]:
    """Start the control bridge, retrying auto-selected ports after bind races.

    Purpose:
        Keeps `control` robust when an automatically probed localhost port is
        claimed by another process before the bridge child binds it.
    Parameters:
        config: Resolved emulator configuration.
        args: Parsed control-mode CLI arguments.
        base_env: Environment passed to the bridge child.
        output_threads: Output forwarders owned by the parent control workflow.
    Return value:
        Tuple of `(bridge_port, bridge_process)` for the started bridge child.
    Requirements:
        `control` must already have started any prerequisite emulator runtime.
        If `args.bridge_port` is set explicitly, the caller accepts immediate
        failure instead of an automatic retry on another port.
    Guarantees:
        Retries a small number of auto-selected ports when the bridge child exits
        immediately during startup. Leaves successful bridge children running.
    Invariants:
        Does not start the Flutter GUI and does not modify emulator state.
    """

    max_attempts = 1 if args.bridge_port is not None else 5
    last_return_code: int | None = None
    for attempt in range(max_attempts):
        bridge_port = control_bridge_port(args)
        _, bridge_command, _ = control_child_commands(config, args, bridge_port)
        bridge_process = start_supervised_process(
            bridge_command,
            base_env,
            WORKSPACE_ROOT,
            args.verbose,
            output_threads,
        )

        startup_deadline = time.monotonic() + 0.5
        while time.monotonic() < startup_deadline:
            return_code = bridge_process.poll()
            if return_code is not None:
                last_return_code = int(return_code)
                break
            time.sleep(0.05)
        else:
            return bridge_port, bridge_process

        if args.bridge_port is not None:
            raise RuntimeError(
                f"bridge failed to start on explicit port {bridge_port} "
                f"(exit code {last_return_code})"
            )
        if attempt + 1 < max_attempts:
            print(
                f"Bridge startup on auto-selected port {bridge_port} exited early; retrying.",
                file=sys.stderr,
            )

    raise RuntimeError(
        "bridge failed to start after retrying auto-selected ports"
        if args.bridge_port is None
        else f"bridge failed to start (exit code {last_return_code})"
    )


def install_headless_for_emulator(config: EmulatorConfig, args: argparse.Namespace) -> int:
    """Install a headless app into one emulator's app registry.

    Purpose:
        Installs one headless app into the selected emulator's app registry while
        keeping the caller focused on the emulator name instead of the registry
        path.
    Parameters:
        config: Resolved emulator configuration for the target emulator.
        args: Parsed CLI arguments containing manifest, build-dir, and optional
            binary override.
    Return value:
        Child installer process exit code.
    Requirements:
        The emulator must already exist and `args.manifest` must be provided.
    Guarantees:
        Resolves the requested binaries and installs the app into this
        emulator's app registry through the shared Python install core.
    Invariants:
        Does not install into any emulator other than `config.emulator_name`.
    """

    if not require_existing_emulator(config):
        return 1
    if not args.manifest:
        print("Error: --manifest is required", file=sys.stderr)
        return 1
    try:
        manifest_path = resolve_cli_manifest_path(args.manifest)
        installed_dir = install_headless_manifest_for_emulator(
            config,
            manifest_path,
            resolved_emulator_build_dir(args.build_dir),
            args.binary,
        )
    except (FileNotFoundError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    print(installed_dir)
    return 0


def resolved_emulator_build_dir(build_dir: str) -> str:
    """Resolve the build directory text for local emulator app installs.

    Purpose:
        Gives unified emulator install a deterministic native build directory
        when the user does not provide `--build-dir`.
    Parameters:
        build_dir: Raw CLI build directory value, possibly empty.
    Return value:
        Build directory path string.
    Requirements:
        None.
    Guarantees:
        Empty input resolves to the source checkout's native build directory
        when available, otherwise the current runtime workspace's native build
        directory.
    Invariants:
        Does not check whether the directory exists or run a build.
    """

    if build_dir != "":
        return build_dir
    default_native_build_dir = "build" + "-native"
    if SOURCE_LAYOUT_ROOT is not None:
        return str(SOURCE_LAYOUT_ROOT / default_native_build_dir)
    return str(WORKSPACE_ROOT / default_native_build_dir)


def install_headless_manifest_for_emulator(
    config: EmulatorConfig,
    manifest_path: Path,
    build_dir: str,
    explicit_binary: str | None,
) -> Path:
    """Install one resolved headless manifest into an emulator registry.

    Purpose:
        Provides the single-headless-app execution primitive used by both legacy
        and unified emulator install commands.
    Parameters:
        config: Target emulator configuration.
        manifest_path: Source or packaged headless app manifest.
        build_dir: Native build directory containing the app executable.
        explicit_binary: Optional direct binary override for this manifest.
    Return value:
        Installed app directory path.
    Requirements:
        The resolved binary and any helper binaries must exist.
    Guarantees:
        Copies the manifest, binary payload, assets, and install metadata through
        the shared install core.
    Invariants:
        Does not install any dependency manifests by itself.
    """

    binary_path = resolve_headless_install_binary_path(
        manifest_path,
        build_dir,
        explicit_binary,
    )
    extra_binary_paths = resolve_headless_extra_binary_paths(
        manifest_path,
        build_dir,
    )
    return install_app.install_app(
        manifest_path,
        config.app_dir,
        binary_path,
        None,
        extra_binary_paths,
    )


def install_flutter_for_emulator(config: EmulatorConfig, args: argparse.Namespace) -> int:
    """Build and install a Flutter app into one emulator's app registry.

    Purpose:
        Builds and installs one Flutter app into the selected emulator's app
        registry using the same manifest-and-bundle install core as other local
        install flows.
    Parameters:
        config: Resolved emulator configuration for the target emulator.
        args: Parsed CLI arguments containing manifest, build mode, and dry-run
            intent.
    Return value:
        Child installer process exit code.
    Requirements:
        The emulator must already exist and `args.manifest` must be provided.
    Guarantees:
        Dry-run prints the local build/install plan, and real installs build the
        Flutter Linux bundle before copying it through the shared Python install
        core.
    Invariants:
        Does not infer or rewrite the manifest's Flutter project path.
    """

    if not require_existing_emulator(config):
        return 1
    if not args.manifest:
        print("Error: --manifest is required", file=sys.stderr)
        return 1
    try:
        manifest_path = resolve_cli_manifest_path(args.manifest)
        if args.dry_run:
            print_flutter_install_dry_run(manifest_path, config.app_dir, args.build_mode)
            return 0
        flutter_project_dir = resolve_flutter_project_dir(manifest_path)
    except (FileNotFoundError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    try:
        pub_get_result = subprocess.run(
            ["flutter", "pub", "get"],
            cwd=str(flutter_project_dir),
            check=False,
        )
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    if pub_get_result.returncode != 0:
        return int(pub_get_result.returncode)
    try:
        build_result = subprocess.run(
            flutter_build_command(flutter_project_dir, args.build_mode),
            cwd=str(flutter_project_dir),
            check=False,
        )
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    if build_result.returncode != 0:
        return int(build_result.returncode)
    try:
        bundle_dir = resolve_flutter_bundle_dir(manifest_path, args.build_mode)
        if not bundle_dir.is_dir():
            raise ValueError(f"expected Flutter bundle not found: {bundle_dir}")
        installed_dir = install_app.install_app(
            manifest_path,
            config.app_dir,
            None,
            bundle_dir,
            [],
        )
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    print(installed_dir)
    return 0


def build_emulator_manifest_index(
    seed_manifests: Sequence[install_manifest_resolver.DogpawAppManifest],
) -> dict[str, install_manifest_resolver.DogpawAppManifest]:
    """Build the manifest lookup index for emulator install dependency resolution.

    Purpose:
        Lets emulator installs resolve dependencies from packaged base apps,
        packaged examples, source app trees, and the explicitly requested seed.
    Parameters:
        seed_manifests: User-requested manifests that should also be available
            for dependency lookup.
    Return value:
        Mapping from app name to manifest facts.
    Requirements:
        Discoverable manifests must be valid Dog Paw app manifests.
    Guarantees:
        Packaged/source discovery keeps its existing precedence, while explicit
        seeds override matching discovered names.
    Invariants:
        Reads manifests only; it does not build or install apps.
    """

    index = install_manifest_resolver.build_manifest_index(
        list(default_app_manifest_index().values())
    )
    for manifest in seed_manifests:
        index[manifest.name] = manifest
    return index


def resolve_emulator_install_manifests(
    manifest_path: Path,
) -> tuple[install_manifest_resolver.DogpawAppManifest, ...]:
    """Resolve one emulator install manifest and its dependencies.

    Purpose:
        Provides the emulator's shared dependency expansion step before local app
        build/install execution.
    Parameters:
        manifest_path: User-selected manifest path.
    Return value:
        Dependency-expanded manifests in install order.
    Requirements:
        `manifest_path` and every dependency manifest must be valid.
    Guarantees:
        Dependencies appear before the selected manifest.
    Invariants:
        Does not build, copy, or install app payloads.
    """

    seed_manifest = install_manifest_resolver.manifest_from_path(manifest_path)
    manifest_index = build_emulator_manifest_index((seed_manifest,))
    return install_manifest_resolver.expand_manifests_with_install_dependencies(
        (seed_manifest,),
        manifest_index,
    )


def print_headless_install_dry_run(manifest_path: Path, app_root: Path, build_dir: str) -> None:
    """Print the local headless install steps for dry-run mode.

    Purpose:
        Makes unified emulator install dry-runs show how resolved headless
        dependencies would be copied into the app registry.
    Parameters:
        manifest_path: Manifest that would be installed.
        app_root: Emulator app registry root.
        build_dir: Native build directory used for executable lookup.
    Return value:
        None.
    Requirements:
        `manifest_path` must describe a valid headless app.
    Guarantees:
        Prints readable commands without checking binary existence.
    Invariants:
        Does not create files, build targets, or install apps.
    """

    manifest = install_manifest_resolver.manifest_from_path(manifest_path)
    executable = manifest.executable or ""
    install_tool_path = Path(install_app.__file__).resolve()
    print(
        "python3 "
        f"'{install_tool_path}' --manifest '{manifest_path}' --app-root '{app_root}' "
        f"--binary '{Path(build_dir) / 'bin' / executable}'"
    )


def print_emulator_build_dry_run(build_dir: str, targets: Sequence[str]) -> None:
    """Print the native CMake build command for emulator install dry-runs.

    Purpose:
        Shows the target union that unified emulator install would build before
        copying resolved app payloads.
    Parameters:
        build_dir: Native CMake build directory.
        targets: CMake targets in requested order.
    Return value:
        None.
    Requirements:
        `targets` may be empty.
    Guarantees:
        Prints nothing when no targets are requested.
    Invariants:
        Does not run CMake or inspect the build directory.
    """

    if not targets:
        return
    command = ["cmake", "--build", build_dir]
    for target in targets:
        command.extend(["--target", target])
    print(shlex.join(command))


def build_emulator_install_targets(build_dir: str, targets: Sequence[str]) -> int:
    """Build native targets needed by a real emulator install.

    Purpose:
        Ensures headless dependencies and shared runtime artifacts exist before
        local install copying begins.
    Parameters:
        build_dir: Native CMake build directory.
        targets: CMake targets to build.
    Return value:
        Zero on success, otherwise the CMake process exit code.
    Requirements:
        `build_dir` must name a configured CMake build directory for real runs.
    Guarantees:
        Runs at most one CMake build command.
    Invariants:
        Does not install app registry entries.
    """

    if not targets:
        return 0
    command = ["cmake", "--build", build_dir]
    for target in targets:
        command.extend(["--target", target])
    completed = subprocess.run(command, cwd=str(SOURCE_LAYOUT_ROOT or WORKSPACE_ROOT), check=False)
    return int(completed.returncode)


def install_resolved_manifest_for_emulator(
    config: EmulatorConfig,
    manifest: install_manifest_resolver.DogpawAppManifest,
    args: argparse.Namespace,
    build_dir: str,
    explicit_binary: str | None,
) -> Path:
    """Install one resolved manifest into the emulator app registry.

    Purpose:
        Chooses the correct local install primitive after shared dependency
        resolution has already selected the manifest order.
    Parameters:
        config: Target emulator configuration.
        manifest: Resolved manifest facts for one app.
        args: Parsed emulator CLI options.
        build_dir: Native build directory used for headless payloads.
        explicit_binary: Optional binary override for a single headless app.
    Return value:
        Installed app directory path.
    Requirements:
        Flutter apps must be buildable locally; headless binaries must exist.
    Guarantees:
        Installs exactly one app.
    Invariants:
        Does not resolve or install dependencies by itself.
    """

    if manifest.is_flutter:
        flutter_project_dir = resolve_flutter_project_dir(manifest.manifest_path)
        pub_get_result = subprocess.run(
            ["flutter", "pub", "get"],
            cwd=str(flutter_project_dir),
            check=False,
        )
        if pub_get_result.returncode != 0:
            raise RuntimeError(f"flutter pub get failed for {manifest.name}")
        build_result = subprocess.run(
            flutter_build_command(flutter_project_dir, args.build_mode),
            cwd=str(flutter_project_dir),
            check=False,
        )
        if build_result.returncode != 0:
            raise RuntimeError(f"flutter build failed for {manifest.name}")
        bundle_dir = resolve_flutter_bundle_dir(manifest.manifest_path, args.build_mode)
        if not bundle_dir.is_dir():
            raise ValueError(f"expected Flutter bundle not found: {bundle_dir}")
        return install_app.install_app(
            manifest.manifest_path,
            config.app_dir,
            None,
            bundle_dir,
            [],
        )
    return install_headless_manifest_for_emulator(
        config,
        manifest.manifest_path,
        build_dir,
        explicit_binary,
    )


def install_manifest_set_for_emulator(config: EmulatorConfig, args: argparse.Namespace) -> int:
    """Install a manifest and its dependencies into one emulator.

    Purpose:
        Implements the unified `dogpaw emulator install` command using shared
        dependency resolution and local app install primitives.
    Parameters:
        config: Target emulator configuration.
        args: Parsed emulator CLI options.
    Return value:
        Zero on success, otherwise non-zero failure status.
    Requirements:
        The emulator must exist and `args.manifest` must be provided.
    Guarantees:
        Installs dependencies before dependents. Dry-run prints the build/install
        plan without modifying the filesystem.
    Invariants:
        Does not install into any emulator other than `config.emulator_name`.
    """

    if not require_existing_emulator(config):
        return 1
    if not args.manifest:
        print("Error: --manifest is required", file=sys.stderr)
        return 1
    try:
        manifest_path = resolve_cli_manifest_path(args.manifest)
        scoped_manifests = resolve_emulator_install_manifests(manifest_path)
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    build_dir = resolved_emulator_build_dir(args.build_dir)
    headless_manifests = tuple(manifest for manifest in scoped_manifests if not manifest.is_flutter)
    if args.binary is not None and len(headless_manifests) != 1:
        print(
            "Error: --binary is only supported when the resolved install set has one headless app",
            file=sys.stderr,
        )
        return 1
    build_targets = install_manifest_resolver.build_targets_for_manifests(scoped_manifests)
    if args.dry_run:
        print_emulator_build_dry_run(build_dir, build_targets)
        for manifest in scoped_manifests:
            if manifest.is_flutter:
                print_flutter_install_dry_run(manifest.manifest_path, config.app_dir, args.build_mode)
            else:
                print_headless_install_dry_run(manifest.manifest_path, config.app_dir, build_dir)
        return 0

    build_result = build_emulator_install_targets(build_dir, build_targets)
    if build_result != 0:
        return build_result
    try:
        for manifest in scoped_manifests:
            installed_dir = install_resolved_manifest_for_emulator(
                config,
                manifest,
                args,
                build_dir,
                args.binary if len(headless_manifests) == 1 and not manifest.is_flutter else None,
            )
            print(installed_dir)
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


def apps_list_smoke_report(config: EmulatorConfig, expected_apps: set[str]) -> dict[str, object]:
    """Validate that Epiphany published expected apps for a smoke run.

    Purpose:
        Confirms the emulator's runtime app registry reached Epiphany and was
        written to the `apps_list.json` runtime/debug artifact.
    Parameters:
        config: Resolved emulator configuration whose runtime directory should
            contain `apps_list.json`.
        expected_apps: App names that must appear in the published apps list.
    Return value:
        JSON-serializable report with `ok`, `path`, `found`, and `missing`.
    Requirements:
        A smoke run should have already started Epiphany for this instance.
    Guarantees:
        Missing or malformed files produce `ok: false` instead of exceptions.
    Invariants:
        Does not modify runtime files.
    """

    apps_list_path = config.instance_runtime_dir / "apps_list.json"
    if not apps_list_path.is_file():
        return {
            "ok": False,
            "path": str(apps_list_path),
            "found": [],
            "missing": sorted(expected_apps),
            "error": "apps_list.json not found",
        }
    try:
        payload = json.loads(apps_list_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return {
            "ok": False,
            "path": str(apps_list_path),
            "found": [],
            "missing": sorted(expected_apps),
            "error": str(exc),
        }
    apps = payload.get("apps", [])
    found = sorted(
        app.get("name")
        for app in apps
        if isinstance(app, dict) and isinstance(app.get("name"), str)
    )
    missing = sorted(expected_apps - set(found))
    return {
        "ok": not missing,
        "path": str(apps_list_path),
        "found": found,
        "missing": missing,
    }


def key_grid_simulator_smoke_report(
    config: EmulatorConfig,
    control_socket_available: bool | None = None,
) -> dict[str, object]:
    """Validate the PicoComms BladeHW simulation log from an emulator smoke run.

    Purpose:
        Confirms the emulator's simulated key-grid hardware path connected as
        `BladeHW` and created the endpoint surface downstream apps expect.
    Parameters:
        config: Resolved emulator configuration whose instance runtime directory
            contains process-level app logs.
        control_socket_available: Optional control socket state captured while
            the simulator was still running. When omitted, the report checks the
            socket path at report time.
    Return value:
        JSON-serializable report with `ok`, `path`, `connected`,
        `missingEndpoints`, control socket availability, and optional `error`.
    Requirements:
        A smoke run should have already launched the startup plan that includes
        `picoComms --simulate`.
    Guarantees:
        Missing or unreadable logs produce `ok: false` instead of exceptions.
    Invariants:
        Reads only the simulator app log and does not modify runtime files.
    """

    log_path = config.instance_runtime_dir / "app_logs" / KEY_GRID_SIMULATOR_LOG_NAME
    if not log_path.is_file():
        return {
            "ok": False,
            "path": str(log_path),
            "connected": False,
            "missingEndpoints": list(KEY_GRID_SIMULATOR_ENDPOINTS),
            "error": "picoComms.log not found",
        }
    try:
        log_text = log_path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return {
            "ok": False,
            "path": str(log_path),
            "connected": False,
            "missingEndpoints": list(KEY_GRID_SIMULATOR_ENDPOINTS),
            "error": str(exc),
        }

    connected = KEY_GRID_SIMULATOR_CONNECTED_FRAGMENT in log_text
    missing_endpoints = [
        endpoint
        for endpoint in KEY_GRID_SIMULATOR_ENDPOINTS
        if f"CPP: Creating endpoint: {endpoint}" not in log_text
    ]
    control_socket = key_grid_control_socket_path(config)
    resolved_control_socket_available = (
        control_socket.exists()
        if control_socket_available is None
        else control_socket_available
    )
    return {
        "ok": connected and not missing_endpoints and resolved_control_socket_available,
        "path": str(log_path),
        "connected": connected,
        "missingEndpoints": missing_endpoints,
        "controlSocket": str(control_socket),
        "controlSocketAvailable": resolved_control_socket_available,
    }


def key_grid_control_socket_path(config: EmulatorConfig) -> Path:
    """Return the private key-grid control socket path.

    Purpose:
        Gives emulator CLI controls a simulator-owned transport that does not
        expose test/simulation controls through the public Dog Paw endpoint
        model.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        Path to the Unix socket used by the running simulated BladeHW worker.
    Requirements:
        The simulator must be running for the socket to exist.
    Guarantees:
        Does not create, connect, or delete the socket.
    Invariants:
        The path stays below the instance runtime directory.
    """

    return config.instance_runtime_dir / KEY_GRID_SIMULATOR_CONTROL_SOCKET_NAME


def bak_control_socket_path(config: EmulatorConfig) -> Path:
    """Return the private ButtonsAndKnobs simulator control socket path.

    Purpose:
        Gives emulator CLI controls direct access to the BAK simulated hardware
        interface without routing simulator-only commands through public Dog Paw
        endpoints.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        Path to the Unix socket used by running `buttonsAndKnobs --simulator`.
    Requirements:
        The simulator must be running for the socket to exist.
    Guarantees:
        Does not create, connect, or delete the socket.
    Invariants:
        The path stays below the instance runtime directory.
    """

    return config.instance_runtime_dir / BAK_SIMULATOR_CONTROL_SOCKET_NAME


def led_comms_introspection_socket_path(config: EmulatorConfig) -> Path:
    """Return the private LEDComms simulator introspection socket path.

    Purpose:
        Gives emulator CLI controls and the future GUI read-only access to
        simulated LED state without exposing simulator-only data through public
        Dog Paw endpoints.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        Path to the Unix socket used by running `LEDComms --simulate`.
    Requirements:
        LEDComms must be running in simulation mode for the socket to exist.
    Guarantees:
        Does not create, connect, or delete the socket.
    Invariants:
        The path stays below the instance runtime directory.
    """

    return config.instance_runtime_dir / LED_COMMS_INTROSPECTION_SOCKET_NAME


def _parse_key_coordinate(raw_col: str, raw_row: str) -> list[int]:
    """Parse and validate one compact key coordinate.

    Purpose:
        Keeps CLI `key tap/down/up` arguments aligned with the simulator's
        fixed 8x8 hardware-emulation grid.
    Parameters:
        raw_col: Column argument from the CLI.
        raw_row: Row argument from the CLI.
    Return value:
        Two-item `[col, row]` list suitable for JSON control payloads.
    Requirements:
        Arguments must parse as integers in the range 0 through 7.
    Guarantees:
        Raises `ValueError` with a user-facing message for invalid coordinates.
    Invariants:
        Does not inspect emulator state.
    """

    try:
        col = int(raw_col)
        row = int(raw_row)
    except ValueError as exc:
        raise ValueError("key coordinates must be integers") from exc
    if col < 0 or col > 7 or row < 0 or row > 7:
        raise ValueError("key coordinates must be in the range 0..7")
    return [col, row]


def _validate_key_pattern_payload(payload: object, pattern_path: Path) -> dict[str, object]:
    """Validate a key-pattern JSON payload loaded from disk.

    Purpose:
        Defines the saved pattern-file contract before it is sent to the
        simulator. Pattern event timing is relative and must use `delayMs`.
    Parameters:
        payload: Decoded JSON document.
        pattern_path: Source path used in error messages.
    Return value:
        Validated JSON object.
    Requirements:
        Pattern files must be JSON objects with an `events` array. Event entries
        must not use `atMs`.
    Guarantees:
        Raises `ValueError` for malformed pattern documents.
    Invariants:
        Does not modify files or emulator state.
    """

    if not isinstance(payload, dict):
        raise ValueError(f"key pattern must be a JSON object: {pattern_path}")
    events = payload.get("events")
    if not isinstance(events, list) or not events:
        raise ValueError(f"key pattern requires a non-empty events array: {pattern_path}")
    for index, event in enumerate(events):
        if not isinstance(event, dict):
            raise ValueError(f"key pattern event {index} must be an object")
        if "atMs" in event:
            raise ValueError("key pattern events use relative delayMs, not atMs")
        if "delayMs" in event and (
            not isinstance(event["delayMs"], int) or event["delayMs"] < 0
        ):
            raise ValueError(f"key pattern event {index} delayMs must be non-negative")
        if event.get("type") not in {"down", "up", "tap"}:
            raise ValueError(f"key pattern event {index} type must be down, up, or tap")
        key = event.get("key")
        if (
            not isinstance(key, list)
            or len(key) != 2
            or not isinstance(key[0], int)
            or not isinstance(key[1], int)
            or key[0] < 0
            or key[0] > 7
            or key[1] < 0
            or key[1] > 7
        ):
            raise ValueError(f"key pattern event {index} key must be [col, row] in 0..7")
    return payload


def load_key_pattern_payload(pattern_path: Path) -> dict[str, object]:
    """Load and validate a saved key-pattern JSON file.

    Purpose:
        Supports reusable emulator key-press patterns for demos, debugging, and
        future automated hardware-path checks.
    Parameters:
        pattern_path: JSON pattern file path.
    Return value:
        Validated pattern object.
    Requirements:
        `pattern_path` must be readable JSON using relative `delayMs` timing.
    Guarantees:
        Does not alter the loaded pattern before returning it.
    Invariants:
        File contents remain unchanged.
    """

    payload = json.loads(pattern_path.read_text(encoding="utf-8"))
    return _validate_key_pattern_payload(payload, pattern_path)


def key_control_payload(args: argparse.Namespace) -> dict[str, object]:
    """Build the simulator control JSON payload from compact CLI arguments.

    Purpose:
        Converts `dogpaw_emulator.py key ...` syntax into the private JSON-lines
        protocol consumed by the PicoComms simulator.
    Parameters:
        args: Parsed CLI namespace with `key_action`, `key_args`, and optional
        `key_duration_ms`.
    Return value:
        JSON-serializable control payload.
    Requirements:
        `key_action` must be one of `tap`, `down`, `up`, `play`, `loop`,
        `stop`, `auto-on`, or `auto-off`.
    Guarantees:
        Pattern files are validated before a payload is returned.
    Invariants:
        Does not connect to the simulator or mutate emulator state.
    """

    action = args.key_action
    key_args = list(args.key_args or [])
    if action in {"tap", "down", "up"}:
        if len(key_args) != 2:
            raise ValueError(f"key {action} requires: <col> <row>")
        payload: dict[str, object] = {
            "command": action,
            "key": _parse_key_coordinate(key_args[0], key_args[1]),
        }
        duration_ms = getattr(args, "key_duration_ms", None)
        if action == "tap" and duration_ms is not None:
            if duration_ms < 0:
                raise ValueError("tap duration must be non-negative")
            payload["durationMs"] = duration_ms
        return payload

    if action in {"play", "loop"}:
        if len(key_args) != 1:
            raise ValueError(f"key {action} requires: <pattern.json>")
        payload = load_key_pattern_payload(Path(key_args[0]))
        payload["command"] = action
        return payload

    if action == "stop":
        if key_args:
            raise ValueError("key stop does not accept additional arguments")
        return {"command": "stop"}

    if action == "auto-on":
        if key_args:
            raise ValueError("key auto-on does not accept additional arguments")
        return {"command": "auto_on"}

    if action == "auto-off":
        if key_args:
            raise ValueError("key auto-off does not accept additional arguments")
        return {"command": "auto_off"}

    raise ValueError(f"unknown key action: {action}")


def _parse_bak_index(raw_index: str, label: str) -> int:
    """Parse and validate one ButtonsAndKnobs control index.

    Purpose:
        Keeps emulator CLI arguments aligned with BAK's six physical controls.
    Parameters:
        raw_index: CLI index string.
        label: Human-readable control type for error messages.
    Return value:
        Integer index in range 0 through 5.
    Requirements:
        `raw_index` must parse as an integer.
    Guarantees:
        Raises `ValueError` for invalid input before socket payload creation.
    Invariants:
        Does not inspect emulator state or mutate hardware simulation state.
    """

    try:
        index = int(raw_index)
    except ValueError as exc:
        raise ValueError(f"{label} index must be an integer") from exc
    if index < 0 or index > 5:
        raise ValueError(f"{label} index must be in the range 0..5")
    return index


def bak_control_payload(args: argparse.Namespace) -> dict[str, object]:
    """Build the ButtonsAndKnobs simulator control JSON payload.

    Purpose:
        Converts `dogpaw_emulator.py bak ...` syntax into the private JSON-lines
        protocol consumed by `buttonsAndKnobs --simulator`.
    Parameters:
        args: Parsed CLI namespace with `key_action`, `key_args`, and optional
            `bak_duration_ms`.
    Return value:
        JSON-serializable BAK control payload.
    Requirements:
        Target must be `button` or `knob`. Button actions are `down`, `up`, and
        `tap`; knob actions are `rotate`, `set`, and `setNormalized`.
    Guarantees:
        Raises `ValueError` before a malformed command is sent.
    Invariants:
        Does not connect to the simulator or mutate emulator state.
    """

    target = args.key_action
    bak_args = list(args.key_args or [])
    if target == "button":
        if len(bak_args) != 2:
            raise ValueError("bak button requires: <down|up|tap> <index>")
        action = bak_args[0]
        if action not in {"down", "up", "tap"}:
            raise ValueError("bak button action must be down, up, or tap")
        payload: dict[str, object] = {
            "target": "button",
            "action": action,
            "index": _parse_bak_index(bak_args[1], "button"),
        }
        duration_ms = getattr(args, "bak_duration_ms", None)
        if action == "tap" and duration_ms is not None:
            if duration_ms < 0:
                raise ValueError("button tap duration must be non-negative")
            payload["durationMs"] = duration_ms
        return payload

    if target == "knob":
        if len(bak_args) != 3:
            raise ValueError(
                "bak knob requires: <rotate|set|setNormalized> <index> <value>"
            )
        action = bak_args[0]
        index = _parse_bak_index(bak_args[1], "knob")
        if action == "setNormalized":
            try:
                normalized_value = float(bak_args[2])
            except ValueError as exc:
                raise ValueError("normalized knob value must be numeric") from exc
            if normalized_value < 0.0 or normalized_value > 1.0:
                raise ValueError("normalized knob value must be in the range 0.0..1.0")
            return {
                "target": "knob",
                "action": action,
                "index": index,
                "normalizedValue": normalized_value,
            }
        if action not in {"rotate", "set"}:
            raise ValueError("bak knob action must be rotate, set, or setNormalized")
        try:
            value = int(bak_args[2])
        except ValueError as exc:
            raise ValueError("knob value must be an integer") from exc
        return {
            "target": "knob",
            "action": action,
            "index": index,
            "value": value,
        }

    raise ValueError("bak command target must be button or knob")


def send_key_control(config: EmulatorConfig, args: argparse.Namespace) -> int:
    """Send one key-control command to the running simulator.

    Purpose:
        Implements the emulator CLI frontend for compact key actions and saved
        pattern playback.
    Parameters:
        config: Resolved emulator configuration.
        args: Parsed key-control CLI arguments.
    Return value:
        Process exit code: 0 on simulator acceptance, 1 on validation or socket
        failure.
    Requirements:
        The named emulator must be running with the simulated BladeHW worker
        launched.
    Guarantees:
        Sends exactly one JSON-line control payload when validation succeeds.
    Invariants:
        Does not start or stop the emulator itself.
    """

    try:
        payload = key_control_payload(args)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"Invalid key control command: {exc}", file=sys.stderr)
        return 1

    socket_path = key_grid_control_socket_path(config)
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as control_socket:
            control_socket.connect(str(socket_path))
            line = json.dumps(payload, separators=(",", ":")) + "\n"
            control_socket.sendall(line.encode("utf-8"))
            response = control_socket.recv(4096).decode("utf-8", errors="replace").strip()
    except OSError as exc:
        print(
            f"Could not contact key-grid simulator at {socket_path}: {exc}",
            file=sys.stderr,
        )
        return 1

    if response == "OK":
        print("PicoCommsSimulator control: OK")
        return 0
    print(f"PicoCommsSimulator control failed: {response}", file=sys.stderr)
    return 1


def send_bak_control(config: EmulatorConfig, args: argparse.Namespace) -> int:
    """Send one BAK-control command to the running simulator.

    Purpose:
        Implements the emulator CLI frontend for compact BAK button and knob
        actions.
    Parameters:
        config: Resolved emulator configuration.
        args: Parsed BAK-control CLI arguments.
    Return value:
        Process exit code: 0 on simulator acceptance, 1 on validation or socket
        failure.
    Requirements:
        The named emulator must be running with `buttonsAndKnobs --simulator`.
    Guarantees:
        Sends exactly one JSON-line control payload when validation succeeds.
    Invariants:
        Does not start or stop the emulator itself.
    """

    try:
        payload = bak_control_payload(args)
    except ValueError as exc:
        print(f"Invalid BAK control command: {exc}", file=sys.stderr)
        return 1

    socket_path = bak_control_socket_path(config)
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as control_socket:
            control_socket.connect(str(socket_path))
            line = json.dumps(payload, separators=(",", ":")) + "\n"
            control_socket.sendall(line.encode("utf-8"))
            response = control_socket.recv(4096).decode("utf-8", errors="replace").strip()
    except OSError as exc:
        print(
            f"Could not contact ButtonsAndKnobs simulator at {socket_path}: {exc}",
            file=sys.stderr,
        )
        return 1

    if response == "OK":
        print("ButtonsAndKnobs simulator control: OK")
        return 0
    print(f"ButtonsAndKnobs simulator control failed: {response}", file=sys.stderr)
    return 1


def send_led_snapshot_request(config: EmulatorConfig, args: argparse.Namespace) -> int:
    """Read one LEDComms simulator introspection snapshot.

    Purpose:
        Implements the emulator CLI frontend for read-only simulated LED state
        inspection. The same socket response is intended to feed the future
        emulator GUI.
    Parameters:
        config: Resolved emulator configuration.
        args: Parsed LED CLI arguments. `key_action` must be `snapshot`.
    Return value:
        Process exit code: 0 when a JSON snapshot is printed, 1 on validation
        or socket failure.
    Requirements:
        The named emulator must be running with `LEDComms --simulate` or
        `LEDComms --simulator`.
    Guarantees:
        Sends exactly one `snapshot` request and prints the simulator response.
    Invariants:
        Does not start or stop the emulator itself.
    """

    if args.key_action != "snapshot" or args.key_args:
        print("Invalid LED command: led snapshot does not accept arguments", file=sys.stderr)
        return 1

    socket_path = led_comms_introspection_socket_path(config)
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as control_socket:
            control_socket.connect(str(socket_path))
            control_socket.sendall(b"snapshot\n")
            response = control_socket.recv(65536).decode("utf-8", errors="replace").strip()
    except OSError as exc:
        print(
            f"Could not contact LEDComms simulator at {socket_path}: {exc}",
            file=sys.stderr,
        )
        return 1

    try:
        payload = json.loads(response)
    except json.JSONDecodeError:
        print(f"LEDComms simulator introspection failed: {response}", file=sys.stderr)
        return 1

    print(json.dumps(payload, indent=2))
    return 0


def unix_socket_line_request(socket_path: Path, line: str, recv_size: int = 4096) -> str:
    """Send one line-oriented request to a private emulator Unix socket.

    Purpose:
        Centralizes the tiny JSON-lines/string request pattern used by the
        bridge service so GUI-facing HTTP handlers do not know socket details.
    Parameters:
        socket_path: Unix stream socket path owned by one simulator process.
        line: Request line without a trailing newline.
        recv_size: Preferred chunk size for incremental response reads.
    Return value:
        Decoded response text with surrounding whitespace stripped.
    Requirements:
        The simulator socket must exist and accept one request per connection.
    Guarantees:
        Appends exactly one newline to the outbound request and keeps reading
        until the simulator closes the connection.
    Invariants:
        Does not start, stop, or mutate emulator processes directly.
    """

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as control_socket:
        control_socket.connect(str(socket_path))
        control_socket.sendall((line + "\n").encode("utf-8"))
        response_chunks: list[bytes] = []
        while True:
            chunk = control_socket.recv(recv_size)
            if not chunk:
                break
            response_chunks.append(chunk)
        return b"".join(response_chunks).decode("utf-8", errors="replace").strip()


def sanitize_led_snapshot_payload(payload: dict[str, object]) -> dict[str, object]:
    """Return the lean LED snapshot payload exposed by the emulator bridge.

    Purpose:
        Keeps the control GUI's LED snapshot API stable and small enough for
        repeated polling by dropping the very large per-command debug dump while
        preserving the state and counters needed for UI rendering and diagnosis.
    Parameters:
        payload: Decoded LEDComms snapshot JSON object from the simulator socket.
    Return value:
        Sanitized JSON object containing the bridge-visible LED snapshot fields.
    Requirements:
        `payload` must already be a decoded JSON object from LEDComms.
    Guarantees:
        Preserves `ok`, `keyLayers`, and lightweight render-state fields when
        present.
    Invariants:
        Does not mutate the input `payload`.
    """

    allowed_fields = (
        "ok",
        "keyLayers",
        "messageCount",
        "renderedFrameCount",
        "wasCleared",
    )
    return {
        field_name: payload[field_name]
        for field_name in allowed_fields
        if field_name in payload
    }


def disable_control_mode_key_grid_auto_playback(
    config: EmulatorConfig,
    timeout_seconds: float = 10.0,
) -> bool:
    """Disable deterministic key-grid auto playback for control-mode sessions.

    Purpose:
        Makes the control GUI start in manual-input mode so key taps are not
        rejected by the simulator's deterministic/manual exclusivity guard.
    Parameters:
        config: Resolved emulator configuration whose runtime owns the
            key-grid control socket.
        timeout_seconds: Maximum time to wait for the simulator socket to appear.
    Return value:
        `True` when the simulator accepted `auto_off`, otherwise `False`.
    Requirements:
        The control-mode emulator runtime should already be starting.
    Guarantees:
        Emits warnings instead of raising if the socket never appears or the
        simulator rejects the command.
    Invariants:
        Does not start or stop emulator processes; sends at most one control
        command to the simulator.
    """

    socket_path = key_grid_control_socket_path(config)
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if socket_path.exists():
            try:
                response = unix_socket_line_request(
                    socket_path,
                    json.dumps({"command": "auto_off"}, separators=(",", ":")),
                )
            except OSError as exc:
                print(
                    "Dog Paw emulator control warning: could not disable key-grid "
                    f"auto playback: {exc}",
                    file=sys.stderr,
                )
                return False
            if response != "OK":
                print(
                    "Dog Paw emulator control warning: key-grid simulator rejected "
                    f"auto-off command: {response}",
                    file=sys.stderr,
                )
                return False
            return True
        time.sleep(0.1)
    print(
        "Dog Paw emulator control warning: key-grid control socket did not appear "
        f"within {timeout_seconds:.1f}s; manual key taps may be rejected",
        file=sys.stderr,
    )
    return False


def bridge_socket_status(name: str, socket_path: Path) -> dict[str, object]:
    """Build one simulator socket status entry for bridge health responses.

    Purpose:
        Gives the GUI a compact readiness model for each simulator backend.
    Parameters:
        name: Stable GUI-facing simulator name.
        socket_path: Expected Unix socket path for that simulator.
    Return value:
        JSON-serializable status object with name, path, and availability.
    Requirements:
        `socket_path` should already be resolved from an `EmulatorConfig`.
    Guarantees:
        Does not connect to or create the socket.
    Invariants:
        Availability is a filesystem existence check only.
    """

    return {"name": name, "path": str(socket_path), "available": socket_path.exists()}


def parse_bridge_json_body(body: bytes) -> dict[str, object]:
    """Decode a bridge request JSON object.

    Purpose:
        Provides consistent validation for GUI POST bodies before they become
        simulator socket payloads.
    Parameters:
        body: Raw HTTP request body bytes.
    Return value:
        Parsed JSON object.
    Requirements:
        Body must contain a JSON object encoded as UTF-8.
    Guarantees:
        Raises `ValueError` for malformed JSON or non-object payloads.
    Invariants:
        Does not inspect emulator state.
    """

    try:
        payload = json.loads(body.decode("utf-8") if body else "{}")
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("request body must be a JSON object") from exc
    if not isinstance(payload, dict):
        raise ValueError("request body must be a JSON object")
    return payload


def bridge_required_int(
    payload: Mapping[str, object],
    field_name: str,
    minimum: int | None = None,
    maximum: int | None = None,
) -> int:
    """Read and range-check a required integer bridge field.

    Purpose:
        Keeps HTTP bridge validation aligned across key-grid and BAK controls.
    Parameters:
        payload: Parsed bridge JSON object.
        field_name: Required field name.
        minimum: Optional inclusive minimum.
        maximum: Optional inclusive maximum.
    Return value:
        Integer field value.
    Requirements:
        The field must be present and integer-typed.
    Guarantees:
        Raises `ValueError` with a user-facing message for invalid input.
    Invariants:
        Does not mutate the payload.
    """

    value = payload.get(field_name)
    if not isinstance(value, int):
        raise ValueError(f"{field_name} must be an integer")
    if minimum is not None and value < minimum:
        raise ValueError(f"{field_name} must be at least {minimum}")
    if maximum is not None and value > maximum:
        raise ValueError(f"{field_name} must be at most {maximum}")
    return value


def bridge_optional_non_negative_int(
    payload: Mapping[str, object],
    field_name: str,
) -> int | None:
    """Read an optional non-negative integer bridge field.

    Purpose:
        Supports optional tap durations without accepting invalid sleep values.
    Parameters:
        payload: Parsed bridge JSON object.
        field_name: Optional field name.
    Return value:
        Integer value when present, otherwise `None`.
    Requirements:
        Present values must be integer-typed and non-negative.
    Guarantees:
        Raises `ValueError` for invalid input.
    Invariants:
        Does not mutate the payload.
    """

    if field_name not in payload:
        return None
    value = payload[field_name]
    if not isinstance(value, int):
        raise ValueError(f"{field_name} must be an integer")
    if value < 0:
        raise ValueError(f"{field_name} must be non-negative")
    return value


def bridge_required_number(
    payload: Mapping[str, object],
    field_name: str,
    minimum: float | None = None,
    maximum: float | None = None,
) -> float:
    """Read and range-check a required numeric bridge field.

    Purpose:
        Supports normalized GUI controls whose values are floats rather than
        raw integer encoder positions.
    Parameters:
        payload: Parsed bridge JSON object.
        field_name: Required field name.
        minimum: Optional inclusive minimum.
        maximum: Optional inclusive maximum.
    Return value:
        Numeric field value as a float.
    Requirements:
        The field must be present and numeric, but not boolean.
    Guarantees:
        Raises `ValueError` with a user-facing message for invalid input.
    Invariants:
        Does not mutate the payload.
    """

    value = payload.get(field_name)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field_name} must be a number")
    numeric_value = float(value)
    if minimum is not None and numeric_value < minimum:
        raise ValueError(f"{field_name} must be at least {minimum}")
    if maximum is not None and numeric_value > maximum:
        raise ValueError(f"{field_name} must be at most {maximum}")
    return numeric_value


def bridge_key_payload(action: str, request_body: bytes) -> dict[str, object]:
    """Build a PicoComms simulator socket payload from a bridge key request.

    Purpose:
        Defines the GUI-facing key action schema while reusing the existing
        simulator socket protocol underneath.
    Parameters:
        action: Key action from the URL path: `tap`, `down`, `up`, `set`,
            `play`, `loop`, or `stop`.
        request_body: Raw JSON HTTP request body.
    Return value:
        JSON payload accepted by the PicoComms simulator.
    Requirements:
        Key actions must provide the fields required by the chosen action.
    Guarantees:
        Pattern paths are loaded and validated before bridge submission.
    Invariants:
        Does not connect to the simulator.
    """

    if action in {"tap", "down", "up"}:
        payload = parse_bridge_json_body(request_body)
        control_payload: dict[str, object] = {
            "command": action,
            "key": [
                bridge_required_int(payload, "col", 0, 7),
                bridge_required_int(payload, "row", 0, 7),
            ],
        }
        duration_ms = bridge_optional_non_negative_int(payload, "durationMs")
        if action == "tap" and duration_ms is not None:
            control_payload["durationMs"] = duration_ms
        return control_payload
    if action == "set":
        payload = parse_bridge_json_body(request_body)
        state = payload.get("state")
        if state not in {"rest", "active", "pressed"}:
            raise ValueError("key state must be rest, active, or pressed")
        return {
            "command": "set_key",
            "key": [
                bridge_required_int(payload, "col", 0, 7),
                bridge_required_int(payload, "row", 0, 7),
            ],
            "state": state,
            "velocity": bridge_required_number(payload, "velocity", 0.0, 1.0),
            "vertical": bridge_required_number(payload, "vertical", -1.0, 1.0),
            "horizontal": bridge_required_number(payload, "horizontal", -1.0, 1.0),
        }
    if action in {"play", "loop"}:
        payload = parse_bridge_json_body(request_body)
        raw_path = payload.get("path")
        if not isinstance(raw_path, str) or not raw_path:
            raise ValueError(f"key {action} requires a non-empty pattern path")
        control_payload = load_key_pattern_payload(Path(raw_path))
        control_payload["command"] = action
        return control_payload
    if action == "stop":
        return {"command": "stop"}
    raise ValueError("key action must be tap, down, up, set, play, loop, or stop")


def bridge_bak_payload(target: str, action: str, request_body: bytes) -> dict[str, object]:
    """Build a ButtonsAndKnobs socket payload from a bridge request.

    Purpose:
        Defines the GUI-facing BAK control schema while preserving the
        simulator-owned private socket protocol.
    Parameters:
        target: BAK target from URL path: `button` or `knob`.
        action: Target action from URL path.
        request_body: Raw JSON HTTP request body.
    Return value:
        JSON payload accepted by the BAK simulator socket.
    Requirements:
        Button and knob indices must be integers in range 0..5.
    Guarantees:
        Raises `ValueError` for unsupported target/action combinations.
    Invariants:
        Does not connect to the simulator.
    """

    payload = parse_bridge_json_body(request_body)
    if target == "button":
        if action not in {"tap", "down", "up"}:
            raise ValueError("button action must be tap, down, or up")
        control_payload: dict[str, object] = {
            "target": "button",
            "action": action,
            "index": bridge_required_int(payload, "index", 0, 5),
        }
        duration_ms = bridge_optional_non_negative_int(payload, "durationMs")
        if action == "tap" and duration_ms is not None:
            control_payload["durationMs"] = duration_ms
        return control_payload
    if target == "knob":
        if action not in {"rotate", "set", "setNormalized"}:
            raise ValueError("knob action must be rotate, set, or setNormalized")
        if action == "setNormalized":
            return {
                "target": "knob",
                "action": action,
                "index": bridge_required_int(payload, "index", 0, 5),
                "normalizedValue": bridge_required_number(payload, "value", 0.0, 1.0),
            }
        return {
            "target": "knob",
            "action": action,
            "index": bridge_required_int(payload, "index", 0, 5),
            "value": bridge_required_int(payload, "value"),
        }
    raise ValueError("BAK target must be button or knob")


def bridge_ok_from_socket_response(response: str, label: str) -> BridgeResponse:
    """Convert a simulator control socket response into a bridge response.

    Purpose:
        Keeps bridge control endpoints consistent when simulators accept or
        reject commands.
    Parameters:
        response: Raw one-line simulator response.
        label: Human-readable simulator label for error messages.
    Return value:
        `BridgeResponse` with status 200 for `OK`, otherwise 502.
    Requirements:
        `response` should be stripped text returned by a simulator socket.
    Guarantees:
        Does not throw.
    Invariants:
        Simulator response text is preserved in failure details.
    """

    if response == "OK":
        return BridgeResponse(200, {"ok": True})
    return BridgeResponse(
        502,
        {"ok": False, "error": f"{label} rejected command", "detail": response},
    )


def emulator_bridge_response(
    config: EmulatorConfig,
    method: str,
    raw_path: str,
    body: bytes,
) -> BridgeResponse:
    """Handle one GUI-facing emulator bridge request.

    Purpose:
        Defines the localhost HTTP API consumed by the Flutter emulator GUI
        without requiring tests to open a real TCP listener.
    Parameters:
        config: Resolved emulator configuration.
        method: HTTP method, usually `GET` or `POST`.
        raw_path: Request path, optionally including query parameters.
        body: Raw request body bytes.
    Return value:
        `BridgeResponse` containing status and JSON body.
    Requirements:
        The target emulator should already be running for socket-backed actions.
    Guarantees:
        Validation and socket failures become JSON error responses.
    Invariants:
        The bridge never starts or stops emulator processes.
    """

    path = urllib.parse.urlparse(raw_path).path.rstrip("/") or "/"
    try:
        if method == "GET" and path == "/api/health":
            return BridgeResponse(
                200,
                {
                    "ok": True,
                    "emulator": config.emulator_name,
                    "instance": config.instance_name,
                    "sockets": {
                        "keyGrid": bridge_socket_status(
                            "keyGrid",
                            key_grid_control_socket_path(config),
                        ),
                        "buttonsAndKnobs": bridge_socket_status(
                            "buttonsAndKnobs",
                            bak_control_socket_path(config),
                        ),
                        "ledComms": bridge_socket_status(
                            "ledComms",
                            led_comms_introspection_socket_path(config),
                        ),
                    },
                },
            )

        if method == "GET" and path == "/api/led/snapshot":
            response = unix_socket_line_request(
                led_comms_introspection_socket_path(config),
                "snapshot",
                65536,
            )
            payload = json.loads(response)
            if not isinstance(payload, dict):
                raise ValueError("LED snapshot response must be a JSON object")
            return BridgeResponse(200, sanitize_led_snapshot_payload(payload))

        if method == "GET" and path == "/api/bak/snapshot":
            response = unix_socket_line_request(
                bak_control_socket_path(config),
                "snapshot",
                65536,
            )
            payload = json.loads(response)
            if not isinstance(payload, dict):
                raise ValueError("BAK snapshot response must be a JSON object")
            return BridgeResponse(200, payload)

        if method == "POST" and path.startswith("/api/key/"):
            action = path.removeprefix("/api/key/")
            payload = bridge_key_payload(action, body)
            response = unix_socket_line_request(
                key_grid_control_socket_path(config),
                json.dumps(payload, separators=(",", ":")),
            )
            return bridge_ok_from_socket_response(response, "PicoCommsSimulator")

        if method == "POST" and path.startswith("/api/bak/"):
            parts = path.removeprefix("/api/bak/").split("/")
            if len(parts) != 2:
                raise ValueError("BAK endpoint must be /api/bak/<target>/<action>")
            payload = bridge_bak_payload(parts[0], parts[1], body)
            response = unix_socket_line_request(
                bak_control_socket_path(config),
                json.dumps(payload, separators=(",", ":")),
            )
            return bridge_ok_from_socket_response(response, "ButtonsAndKnobs")

        return BridgeResponse(404, {"ok": False, "error": "unknown bridge endpoint"})
    except ValueError as exc:
        return BridgeResponse(400, {"ok": False, "error": str(exc)})
    except (OSError, json.JSONDecodeError) as exc:
        return BridgeResponse(502, {"ok": False, "error": str(exc)})


class EmulatorBridgeRequestHandler(http.server.BaseHTTPRequestHandler):
    """HTTP adapter for the emulator bridge core.

    Purpose:
        Serves localhost JSON endpoints for the Flutter emulator GUI while
        delegating all behavior to `emulator_bridge_response()`.
    Requirements:
        `backend_config` must be set before the server handles requests.
    Guarantees:
        Every supported response is JSON and includes permissive local CORS
        headers for desktop/web-style GUI clients.
    Invariants:
        This adapter does not know simulator socket protocols.
    """

    backend_config: EmulatorConfig

    def _send_bridge_response(self, response: BridgeResponse) -> None:
        """Serialize and send one bridge response.

        Purpose:
            Keeps GET, POST, and OPTIONS response formatting consistent.
        Parameters:
            response: Bridge response produced by the core handler.
        Return value:
            None.
        Requirements:
            Called while handling an active HTTP request.
        Guarantees:
            Sends status, JSON content type, CORS headers, and body.
        Invariants:
            Does not alter emulator state.
        """

        payload = json.dumps(response.body, indent=2).encode("utf-8")
        self.send_response(response.status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(payload)

    def do_OPTIONS(self) -> None:
        """Handle CORS preflight requests.

        Purpose:
            Allows browser-style clients to call the local bridge during
            development.
        Parameters:
            None.
        Return value:
            None.
        Requirements:
            None.
        Guarantees:
            Returns a JSON `ok` response with CORS headers.
        Invariants:
            Does not inspect emulator sockets.
        """

        self._send_bridge_response(BridgeResponse(200, {"ok": True}))

    def do_GET(self) -> None:
        """Handle bridge GET requests.

        Purpose:
            Serves health and LED snapshot reads to GUI clients.
        Parameters:
            None.
        Return value:
            None.
        Requirements:
            `backend_config` has been initialized.
        Guarantees:
            Sends a JSON bridge response.
        Invariants:
            Does not start or stop emulator processes.
        """

        self._send_bridge_response(
            emulator_bridge_response(self.backend_config, "GET", self.path, b"")
        )

    def do_POST(self) -> None:
        """Handle bridge POST requests.

        Purpose:
            Serves key-grid and BAK control actions to GUI clients.
        Parameters:
            None.
        Return value:
            None.
        Requirements:
            `Content-Length` should be a valid integer when a body is present.
        Guarantees:
            Sends a JSON bridge response.
        Invariants:
            Does not start or stop emulator processes.
        """

        content_length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(content_length) if content_length > 0 else b""
        self._send_bridge_response(
            emulator_bridge_response(self.backend_config, "POST", self.path, body)
        )

    def log_message(self, format: str, *args: object) -> None:
        """Suppress default HTTP request logging.

        Purpose:
            Keeps the emulator bridge terminal quiet by default, matching the
            rest of the emulator wrapper.
        Parameters:
            format: BaseHTTPRequestHandler format string.
            args: Format arguments.
        Return value:
            None.
        Requirements:
            None.
        Guarantees:
            No output is emitted.
        Invariants:
            Request handling behavior is unchanged.
        """

        _ = (format, args)


def run_bridge(config: EmulatorConfig, host: str, port: int) -> int:
    """Run the localhost emulator bridge until interrupted.

    Purpose:
        Provides the GUI-facing HTTP API that translates friendly JSON requests
        into the simulator-owned Unix socket protocols.
    Parameters:
        config: Resolved emulator configuration.
        host: TCP bind host, normally `127.0.0.1`.
        port: TCP bind port for the bridge service.
    Return value:
        Process exit code.
    Requirements:
        The named emulator should already be running for control endpoints to
        succeed.
    Guarantees:
        Prints the bridge URL and shuts down cleanly on keyboard interrupt.
    Invariants:
        Does not launch the emulator runtime itself.
    """

    EmulatorBridgeRequestHandler.backend_config = config
    server = http.server.ThreadingHTTPServer((host, port), EmulatorBridgeRequestHandler)
    print(f"Dog Paw emulator bridge listening on http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    finally:
        server.server_close()
    return 0


def collect_sway_tree_app_ids(tree_node: object) -> list[str]:
    """Collect Sway `app_id` values from a parsed tree node.

    Purpose:
        Gives smoke checks a small structured parser for `swaymsg -t get_tree`
        output instead of searching raw JSON text.
    Parameters:
        tree_node: Parsed JSON value from Sway. Dictionaries may contain
            `app_id`, `nodes`, and `floating_nodes`; other values are ignored.
    Return value:
        Ordered list of app IDs found in depth-first traversal order.
    Requirements:
        `tree_node` must come from JSON-compatible data.
    Guarantees:
        Non-dictionary and malformed child containers are ignored.
    Invariants:
        Does not mutate the parsed tree.
    """

    if not isinstance(tree_node, dict):
        return []
    app_ids: list[str] = []
    app_id = tree_node.get("app_id")
    if isinstance(app_id, str):
        app_ids.append(app_id)
    for child_key in ("nodes", "floating_nodes"):
        children = tree_node.get(child_key, [])
        if not isinstance(children, list):
            continue
        for child in children:
            app_ids.extend(collect_sway_tree_app_ids(child))
    return app_ids


def sway_tree_smoke_report(
    tree_json: str | None,
    expected_app_ids: set[str],
    error: str | None = None,
) -> dict[str, object]:
    """Validate expected normal Sway windows from a captured tree.

    Purpose:
        Confirms the emulator's normal Sway-managed UI windows are visible to
        the compositor before the smoke run cleans up the nested display.
    Parameters:
        tree_json: Raw JSON text returned by `swaymsg -t get_tree`, or `None`
            when tree capture failed.
        expected_app_ids: Sway `app_id` values that must be present.
        error: Optional capture error to include in the report.
    Return value:
        JSON-serializable report with `ok`, `foundAppIds`, `missingAppIds`,
        and optional `error`.
    Requirements:
        Expected app IDs should describe normal Sway-managed windows, not
        layer-shell surfaces.
    Guarantees:
        Invalid or missing tree JSON produces `ok: false` instead of raising.
    Invariants:
        Does not start processes or query the compositor.
    """

    if tree_json is None:
        return {
            "ok": False,
            "foundAppIds": [],
            "missingAppIds": sorted(expected_app_ids),
            "error": error or "Sway tree was not captured",
        }
    try:
        tree = json.loads(tree_json)
    except json.JSONDecodeError as exc:
        return {
            "ok": False,
            "foundAppIds": [],
            "missingAppIds": sorted(expected_app_ids),
            "error": str(exc),
        }

    found_app_ids = sorted(set(collect_sway_tree_app_ids(tree)))
    missing_app_ids = sorted(expected_app_ids - set(found_app_ids))
    report: dict[str, object] = {
        "ok": not missing_app_ids,
        "foundAppIds": found_app_ids,
        "missingAppIds": missing_app_ids,
    }
    if error:
        report["error"] = error
    return report


def capture_sway_tree(
    config: EmulatorConfig,
    nested_display: NestedDisplayEnvironment,
    env: Mapping[str, str],
) -> tuple[str | None, str | None]:
    """Capture the current nested Sway tree.

    Purpose:
        Lets smoke tests inspect compositor state while the emulator is still
        running, before normal cleanup removes the nested Sway socket.
    Parameters:
        config: Resolved emulator configuration containing the `swaymsg` command.
        nested_display: Display environment for the nested Sway compositor.
        env: Environment for invoking `swaymsg`.
    Return value:
        `(tree_json, error)` where `tree_json` is raw Sway JSON on success and
        `error` is a human-readable failure description on failure.
    Requirements:
        Nested Sway should still be running and `nested_display.sway_socket`
        should identify its IPC socket.
    Guarantees:
        Command failures are reported as strings instead of exceptions.
    Invariants:
        Does not mutate emulator runtime files or process state.
    """

    try:
        result = subprocess.run(
            [config.swaymsg, "-s", str(nested_display.sway_socket), "-t", "get_tree"],
            env=dict(env),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError as exc:
        return None, str(exc)
    if result.returncode != 0:
        detail = result.stderr.strip() or f"swaymsg exited with {result.returncode}"
        return None, detail
    return result.stdout, None


def capture_sway_outputs(
    config: EmulatorConfig,
    nested_display: NestedDisplayEnvironment,
    env: Mapping[str, str],
) -> tuple[str | None, str | None]:
    """Capture nested Sway output state.

    Purpose:
        Lets the emulator wrapper notice when the visible nested-Sway window has
        been closed even if the Sway process remains alive without outputs.
    Parameters:
        config: Resolved emulator configuration containing the `swaymsg` command.
        nested_display: Display environment for the nested Sway compositor.
        env: Environment for invoking `swaymsg`.
    Return value:
        `(outputs_json, error)` where `outputs_json` is raw Sway JSON on success
        and `error` is a human-readable failure description on failure.
    Requirements:
        Nested Sway should have published its IPC socket.
    Guarantees:
        Command failures are reported as strings instead of exceptions.
    Invariants:
        Does not mutate emulator runtime files or process state.
    """

    try:
        result = subprocess.run(
            [config.swaymsg, "-s", str(nested_display.sway_socket), "-t", "get_outputs"],
            env=dict(env),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError as exc:
        return None, str(exc)
    if result.returncode != 0:
        detail = result.stderr.strip() or f"swaymsg exited with {result.returncode}"
        return None, detail
    return result.stdout, None


def sway_outputs_available(outputs_json: str | None, error: str | None = None) -> bool:
    """Return whether nested Sway still has an active output.

    Purpose:
        Defines the emulator-window lifetime signal used by `run`: once Sway has
        no active output, closing the visible emulator window should stop the
        whole emulator stack.
    Parameters:
        outputs_json: Raw JSON text returned by `swaymsg -t get_outputs`, or
            `None` when capture failed.
        error: Optional capture error from `capture_sway_outputs`.
    Return value:
        `true` when at least one active output is present, otherwise `false`.
    Requirements:
        `outputs_json`, when provided, should be a JSON list from Sway.
    Guarantees:
        Invalid JSON, capture errors, and empty output lists are treated as
        unavailable output.
    Invariants:
        Does not query Sway or mutate process state.
    """

    if error is not None or outputs_json is None:
        return False
    try:
        outputs = json.loads(outputs_json)
    except json.JSONDecodeError:
        return False
    if not isinstance(outputs, list):
        return False
    for output in outputs:
        if isinstance(output, dict) and output.get("active") is True:
            return True
    return False


def log_line_severity(line: str) -> str | None:
    """Classify one log line for smoke log-health reporting.

    Purpose:
        Gives the emulator smoke scanner a small, shared severity heuristic for
        native, Flutter, GTK, sanitizer, and Python-style failure lines.
    Parameters:
        line: One decoded log line without its trailing newline.
    Return value:
        `"ERROR"`, `"WARNING"`, or `None` when the line is not health-relevant.
    Requirements:
        `line` must be text decoded from a process log.
    Guarantees:
        Error-like terms take precedence over warning-like terms.
    Invariants:
        Does not inspect neighboring lines or mutate scanner state.
    """

    lower_line = line.lower()
    if (
        "error" in lower_line
        or "critical" in lower_line
        or "fatal" in lower_line
        or "traceback" in lower_line
        or "addresssanitizer" in lower_line
        or "leaksanitizer" in lower_line
    ):
        return "ERROR"
    if "warning" in lower_line:
        return "WARNING"
    return None


def allowed_log_pattern_for_line(
    line: str,
    allowed_patterns: Sequence[AllowedLogPattern],
) -> AllowedLogPattern | None:
    """Return the allowlist entry that matches a log line, if any.

    Purpose:
        Keeps allowlist matching centralized so reports and tests use the same
        exact substring behavior.
    Parameters:
        line: One decoded log line.
        allowed_patterns: Ordered allowed finding definitions.
    Return value:
        The first matching `AllowedLogPattern`, or `None`.
    Requirements:
        Pattern fragments should be non-empty.
    Guarantees:
        Matching is case-sensitive and deterministic.
    Invariants:
        Does not modify the supplied pattern sequence.
    """

    for pattern in allowed_patterns:
        if pattern.fragment and pattern.fragment in line:
            return pattern
    return None


def terminal_output_pattern_for_line(
    line: str,
    allowed_patterns: Sequence[AllowedLogPattern] = DEFAULT_ALLOWED_TERMINAL_OUTPUT_PATTERNS,
) -> AllowedLogPattern | None:
    """Return the expected terminal-output pattern matching a child line.

    Purpose:
        Keeps interactive emulator runs quiet by recognizing process stdout and
        stderr lines that are expected in the local nested-Sway environment.
    Parameters:
        line: One decoded line from a child process output stream.
        allowed_patterns: Terminal-output allowlist entries, separate from app
            log-health allowlist entries.
    Return value:
        The matching pattern, or `None` when the line should be shown.
    Requirements:
        `line` should represent exactly one child-process output line.
    Guarantees:
        Exact JSON punctuation from Sway command responses is only suppressed
        when the whole stripped line matches that punctuation.
    Invariants:
        Does not mutate allowlist entries or process state.
    """

    if line.strip() in {"[", "{", "}", "},", "]"}:
        return AllowedLogPattern("sway command response", line.strip())
    return allowed_log_pattern_for_line(line, allowed_patterns)


def forward_terminal_output_line(line: str, verbose: bool, stream: object | None = None) -> None:
    """Forward one child-process terminal line when it should be user-visible.

    Purpose:
        Implements the clean-default emulator terminal contract: expected
        environment and shutdown noise is hidden, unexpected output is still
        visible, and `--verbose` bypasses filtering for troubleshooting.
    Parameters:
        line: Decoded child-process output line, with or without a trailing
            newline.
        verbose: When true, print all lines regardless of allowlist matches.
        stream: Text stream to write to. Defaults to `sys.stderr` so JSON stdout
            stays machine-readable during smoke runs.
    Return value:
        None.
    Requirements:
        `line` must be text, not bytes.
    Guarantees:
        Unexpected lines and all verbose lines are printed exactly once.
    Invariants:
        Does not write to child processes or modify filter configuration.
    """

    output_stream = sys.stderr if stream is None else stream
    if verbose or terminal_output_pattern_for_line(line) is None:
        print(line.rstrip("\n"), file=output_stream)


def forward_process_output(process: subprocess.Popen[object], verbose: bool) -> None:
    """Drain and filter one supervised child process output stream.

    Purpose:
        Prevents child stdout/stderr pipes from blocking while preserving a clean
        default terminal for emulator users.
    Parameters:
        process: Child process created with combined text stdout when filtering
            is enabled.
        verbose: Whether output should bypass filtering.
    Return value:
        None.
    Requirements:
        `process.stdout` must be a readable text stream when this function is
        used.
    Guarantees:
        Reads until EOF and forwards each line through
        `forward_terminal_output_line()`.
    Invariants:
        Does not wait for or terminate the child process.
    """

    if process.stdout is None:
        return
    for line in process.stdout:
        forward_terminal_output_line(str(line), verbose)


def start_supervised_process(
    command: Sequence[str],
    env: Mapping[str, str],
    cwd: Path,
    verbose: bool,
    output_threads: list[threading.Thread],
) -> subprocess.Popen[object]:
    """Start one emulator child process with clean-default output handling.

    Purpose:
        Centralizes child launch behavior so nested Sway and Epiphany use the
        same terminal filtering and verbose escape hatch.
    Parameters:
        command: Executable and arguments to launch.
        env: Environment passed to the child.
        cwd: Working directory for the child process.
        verbose: When true, child output is inherited directly by the terminal.
        output_threads: Mutable list that receives filter-drain threads for
            later joining.
    Return value:
        Started child process.
    Requirements:
        `command[0]` must resolve to an executable.
    Guarantees:
        In quiet mode stdout and stderr are combined and drained by a daemon
        thread; in verbose mode child output is not intercepted.
    Invariants:
        Does not add the process to the caller's process ownership list.
    """

    if verbose:
        return subprocess.Popen(command, env=env, cwd=str(cwd), start_new_session=True)

    process = subprocess.Popen(
        command,
        env=env,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    output_thread = threading.Thread(
        target=forward_process_output,
        args=(process, verbose),
        daemon=True,
    )
    output_thread.start()
    output_threads.append(output_thread)
    return process


def app_log_health_report(
    log_paths: Sequence[Path],
    allowed_patterns: Sequence[AllowedLogPattern] = DEFAULT_ALLOWED_LOG_PATTERNS,
    max_findings: int = 80,
) -> dict[str, object]:
    """Scan app logs for warning/error-like smoke findings.

    Purpose:
        Provides one general smoke-health view over app output so developers can
        care about warnings and errors instead of manually inspecting each log.
    Parameters:
        log_paths: App log files to scan.
        allowed_patterns: Temporarily allowed known-noise patterns. Matches are
            reported separately and still counted.
        max_findings: Maximum unallowed and allowed finding samples to include.
    Return value:
        JSON-serializable report with `ok`, counts, scanned logs, unallowed
        `findings`, `allowedFindings`, and the active allowlist.
    Requirements:
        `log_paths` should refer to logs from the current smoke run.
    Guarantees:
        Unreadable logs are reported as unallowed error findings.
    Invariants:
        Does not modify or delete log files.
    """

    findings: list[dict[str, object]] = []
    allowed_findings: list[dict[str, object]] = []
    warning_count = 0
    error_count = 0
    allowed_count = 0
    scanned_logs: list[str] = []

    for log_path in sorted(log_paths, key=lambda path: path.name):
        scanned_logs.append(log_path.name)
        try:
            lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError as exc:
            error_count += 1
            if len(findings) < max_findings:
                findings.append(
                    {
                        "log": log_path.name,
                        "lineNumber": 0,
                        "severity": "ERROR",
                        "line": f"Could not read log: {exc}",
                    }
                )
            continue

        for line_number, line in enumerate(lines, start=1):
            if LOG_HEALTH_SEVERITY_PATTERN.search(line) is None:
                continue
            severity = log_line_severity(line)
            if severity is None:
                continue
            if severity == "ERROR":
                error_count += 1
            else:
                warning_count += 1

            allowed_pattern = allowed_log_pattern_for_line(line, allowed_patterns)
            entry = {
                "log": log_path.name,
                "lineNumber": line_number,
                "severity": severity,
                "line": line,
            }
            if allowed_pattern is not None:
                allowed_count += 1
                if len(allowed_findings) < max_findings:
                    allowed_entry = dict(entry)
                    allowed_entry["reason"] = allowed_pattern.reason
                    allowed_entry["pattern"] = allowed_pattern.fragment
                    allowed_findings.append(allowed_entry)
            elif len(findings) < max_findings:
                findings.append(entry)

    return {
        "ok": not findings,
        "scannedLogs": scanned_logs,
        "warningCount": warning_count,
        "errorCount": error_count,
        "allowedCount": allowed_count,
        "findings": findings,
        "allowedFindings": allowed_findings,
        "allowlist": [
            {"reason": pattern.reason, "fragment": pattern.fragment}
            for pattern in allowed_patterns
        ],
    }


def app_logs_smoke_report(
    app_logs_dir: Path,
    min_mtime: float,
    allowed_patterns: Sequence[AllowedLogPattern] = DEFAULT_ALLOWED_LOG_PATTERNS,
) -> dict[str, object]:
    """Build a smoke log-health report from current-run app logs.

    Purpose:
        Avoids stale app logs from previous emulator sessions while still
        checking all app logs touched during the current smoke run.
    Parameters:
        app_logs_dir: Directory containing `<entity>.log` files.
        min_mtime: Earliest modification time accepted for current-run logs.
        allowed_patterns: Temporarily allowed known-noise patterns.
    Return value:
        JSON-serializable log-health report.
    Requirements:
        `min_mtime` should be captured immediately before starting the smoke run.
    Guarantees:
        Missing app-log directory produces an empty passing report.
    Invariants:
        Does not create or modify log files.
    """

    if not app_logs_dir.is_dir():
        report = app_log_health_report([], allowed_patterns)
        report["path"] = str(app_logs_dir)
        return report
    log_paths = [
        log_path
        for log_path in app_logs_dir.glob("*.log")
        if log_path.is_file() and log_path.stat().st_mtime >= min_mtime
    ]
    report = app_log_health_report(log_paths, allowed_patterns)
    report["path"] = str(app_logs_dir)
    return report


def current_process_lines() -> list[str]:
    """Return the current process table as plain command lines.

    Purpose:
        Supports smoke cleanup checks without depending on systemd or procfs
        implementation details in the rest of the emulator code.
    Parameters:
        None.
    Return value:
        List of `pid command` lines.
    Requirements:
        The host should provide `ps`.
    Guarantees:
        Returns an empty list if `ps` is unavailable or fails.
    Invariants:
        Does not signal or modify any processes.
    """

    try:
        result = subprocess.run(
            ["ps", "-eo", "pid=,args="],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        return []
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def cleanup_smoke_report(
    instance_name: str,
    process_lines: Sequence[str] | None = None,
) -> dict[str, object]:
    """Report whether emulator-owned processes remain after cleanup.

    Purpose:
        Checks the most important cleanup invariant for repeated smoke runs:
        no Epiphany instance or Dog Paw app process for this emulator should
        remain after the wrapper exits.
    Parameters:
        instance_name: Epiphany instance name used by the emulator run.
        process_lines: Optional process-table lines for tests; when omitted the
            current process table is inspected.
    Return value:
        JSON-serializable report with `ok` and remaining process lines.
    Requirements:
        Process lines should contain both pid and command text.
    Guarantees:
        Filters for emulator-specific instance names and Dog Paw app process
        names.
    Invariants:
        This function reports only; it never kills processes.
    """

    lines = list(process_lines) if process_lines is not None else current_process_lines()
    remaining = [
        line
        for line in lines
        if instance_name in line or "dogpaw-app-" in line or "sway-emulator.conf" in line
    ]
    return {"ok": not remaining, "remaining": remaining}


def smoke_emulator(config: EmulatorConfig, args: argparse.Namespace, base_env: Mapping[str, str]) -> int:
    """Run a bounded emulator smoke test and report the result.

    Purpose:
        Provides one SDK-facing command that verifies dependencies, starts the
        nested display stack briefly, validates Epiphany's app list, checks the
        simulated key-grid hardware app, and verifies cleanup.
    Parameters:
        config: Resolved emulator configuration.
        args: Parsed CLI arguments containing JSON and smoke duration options.
        base_env: Environment inherited by child processes.
    Return value:
        Process exit code: `0` for a passing smoke, `1` for any failed stage.
    Requirements:
        The named emulator must already exist and have the apps required by the
        startup plan installed.
    Guarantees:
        Emits structured JSON when `--json` is passed.
    Invariants:
        Does not create the emulator implicitly.
    """

    if not require_existing_emulator(config):
        return 1
    dependencies = dependency_report(config, base_env)
    if not dependencies["ok"]:
        payload = {"ok": False, "stage": "dependencies", "dependencies": dependencies}
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            missing = ", ".join(dependencies["missing"]) if dependencies["missing"] else "none"
            print(f"Dog Paw emulator smoke failed dependency check: {missing}", file=sys.stderr)
            print(f"Host display mode: {dependencies['hostDisplay']['mode']}", file=sys.stderr)
        return 1
    duration = args.smoke_seconds if args.smoke_seconds is not None else 5.0
    log_scan_start = time.time()
    sway_tree_json: str | None = None
    sway_tree_error: str | None = None
    key_grid_control_socket_seen = False

    def capture_runtime_state_for_smoke(
        nested_display: NestedDisplayEnvironment,
        env: Mapping[str, str],
    ) -> None:
        """Capture runtime state for the enclosing smoke run.

        Purpose:
            Bridges `run_emulator()` process supervision with `smoke_emulator()`
            reporting by saving runtime facts that vanish during normal cleanup,
            such as the nested compositor tree and simulator control socket.
        Parameters:
            nested_display: Display environment for the active nested Sway
                compositor.
            env: Environment used by Epiphany and suitable for `swaymsg`.
        Return value:
            None.
        Requirements:
            Called only while the nested compositor is still running.
        Guarantees:
            Stores either tree JSON or a capture error in the enclosing scope,
            plus whether the simulator control socket existed during the run.
        Invariants:
            Does not stop or modify emulator processes.
        """

        nonlocal sway_tree_json
        nonlocal sway_tree_error
        nonlocal key_grid_control_socket_seen
        sway_tree_json, sway_tree_error = capture_sway_tree(config, nested_display, env)
        key_grid_control_socket_seen = key_grid_control_socket_path(config).exists()

    run_code = run_emulator(
        config,
        base_env,
        duration,
        capture_runtime_state_for_smoke,
        args.verbose,
    )
    apps_report = apps_list_smoke_report(config, SMOKE_EXPECTED_UI_APPS)
    key_grid_report = key_grid_simulator_smoke_report(
        config,
        key_grid_control_socket_seen,
    )
    sway_tree_report = sway_tree_smoke_report(
        sway_tree_json,
        SMOKE_EXPECTED_SWAY_APP_IDS,
        sway_tree_error,
    )
    log_health_report = app_logs_smoke_report(
        config.instance_runtime_dir / "app_logs",
        log_scan_start,
    )
    cleanup_report = cleanup_smoke_report(config.instance_name)
    payload = {
        "ok": (
            run_code == 0
            and apps_report["ok"]
            and key_grid_report["ok"]
            and sway_tree_report["ok"]
            and log_health_report["ok"]
            and cleanup_report["ok"]
        ),
        "stage": "complete",
        "runExitCode": run_code,
        "appsList": apps_report,
        "keyGridSimulator": key_grid_report,
        "swayTree": sway_tree_report,
        "logHealth": log_health_report,
        "cleanup": cleanup_report,
    }
    if args.json:
        print(json.dumps(payload, indent=2))
    elif payload["ok"]:
        print("Dog Paw emulator smoke: OK")
    else:
        print("Dog Paw emulator smoke: FAILED", file=sys.stderr)
        if run_code != 0:
            print(f"Run exit code: {run_code}", file=sys.stderr)
        if not apps_report["ok"]:
            print(f"Missing apps: {', '.join(apps_report['missing'])}", file=sys.stderr)
        if not key_grid_report["ok"]:
            print("PicoCommsSimulator health check failed.", file=sys.stderr)
        if not sway_tree_report["ok"]:
            print("Sway tree health check failed.", file=sys.stderr)
        if not log_health_report["ok"]:
            print("App log health check failed.", file=sys.stderr)
        if not cleanup_report["ok"]:
            print("Remaining emulator processes detected.", file=sys.stderr)
    return 0 if payload["ok"] else 1


def copy_tree_contents(source_dir: Path, destination_dir: Path) -> None:
    """Copy directory contents without deleting destination-only files.

    Purpose:
        Installs shared runtime resources into an emulator data root while
        preserving user-created files in the same persistent root.
    Parameters:
        source_dir: Existing directory whose contents should be copied.
        destination_dir: Directory receiving copied files.
    Return value:
        None.
    Requirements:
        `source_dir` must exist and be a directory.
    Guarantees:
        Creates `destination_dir` and copies files/directories recursively.
    Invariants:
        Destination-only files are left untouched.
    """

    destination_dir.mkdir(parents=True, exist_ok=True)
    for source_path in source_dir.iterdir():
        destination_path = destination_dir / source_path.name
        if source_path.is_dir():
            shutil.copytree(source_path, destination_path, dirs_exist_ok=True)
        else:
            shutil.copy2(source_path, destination_path)


def seed_runtime_resources(config: EmulatorConfig) -> None:
    """Install shared Dog Paw runtime resources into the emulator data root.

    Purpose:
        Gives Epiphany default layouts, scales, themes, and shared images through
        the same deployment-safe `<DOGPAW_DATA_DIR>/resources` contract used on
        the Pi.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        None.
    Requirements:
        The resolved shared resource directories must exist either in the
        development repo or in the packaged SDK runtime payload.
    Guarantees:
        Copies known shared resource directories into `config.data_root`.
    Invariants:
        Existing emulator app registries and app files are preserved.
    """

    resource_root = config.data_root / "resources"
    for resource_name in ("dogpawDataItems", "images"):
        source_dir = source_resource_root() / resource_name
        if source_dir.is_dir():
            copy_tree_contents(source_dir, resource_root / resource_name)


def dogpaw_runtime_environment(config: EmulatorConfig, base_env: Mapping[str, str]) -> dict[str, str]:
    """Build the Dog Paw-owned runtime environment values.

    Purpose:
        Encodes the public emulator runtime contract in environment variables
        understood by RuntimePaths and DogPawEntity without changing display
        discovery variables owned by the host desktop session.
    Parameters:
        config: Resolved emulator configuration.
        base_env: Existing process environment.
    Return value:
        Mutable environment dictionary with Dog Paw-owned variables applied.
    Requirements:
        `prepare_roots()` should run before passing this environment to child
        processes.
    Guarantees:
        Sets emulator, app, data, runtime, and instance values.
    Invariants:
        Does not remove or overwrite `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`,
        `DISPLAY`, or `SWAYSOCK`.
    """

    child_env = dict(base_env)
    child_env["DOGPAW_EMULATOR_NAME"] = config.emulator_name
    child_env["DOGPAW_DATA_DIR"] = str(config.data_root)
    child_env["DOGPAW_APP_DIR"] = str(config.app_dir)
    child_env["DOGPAW_RUNTIME_DIR"] = str(config.runtime_root)
    child_env["EPIPHANY_INSTANCE"] = config.instance_name
    staged_bridge = emulator_bridge_library_path(config)
    if staged_bridge.is_file():
        child_env["DOGPAW_BRIDGE_LIB"] = str(staged_bridge)
    return child_env


def sway_environment(config: EmulatorConfig, base_env: Mapping[str, str]) -> dict[str, str]:
    """Build the environment for starting nested Sway.

    Purpose:
        Preserves the inherited host display variables so nested Sway can connect
        to the developer's real desktop compositor, including forwarded Wayland
        sockets from a container.
    Parameters:
        config: Resolved emulator configuration.
        base_env: Existing process environment containing host display vars.
    Return value:
        Mutable environment dictionary for the Sway process.
    Requirements:
        Host display variables must be valid for a visible nested window unless
        `WLR_BACKENDS=headless` is intentionally selected.
    Guarantees:
        Sets `WLR_BACKENDS` and Dog Paw-owned variables, but preserves inherited
        `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`, and `DISPLAY`.
    Invariants:
        Does not point Sway at `DOGPAW_RUNTIME_DIR`; Wayland uses standard
        desktop env vars, while Dog Paw runtime files use `DOGPAW_RUNTIME_DIR`.
    """

    child_env = dogpaw_runtime_environment(config, base_env)
    child_env["WLR_BACKENDS"] = config.wlr_backends
    child_env["SWAYSOCK"] = str(nested_sway_socket_path(config))
    return child_env


def epiphany_environment(
    config: EmulatorConfig,
    base_env: Mapping[str, str],
    nested_display: NestedDisplayEnvironment,
) -> dict[str, str]:
    """Build the environment for Epiphany and its launched app children.

    Purpose:
        Combines Dog Paw-owned runtime roots with the standard display variables
        exported by the nested Sway compositor.
    Parameters:
        config: Resolved emulator configuration.
        base_env: Existing process environment.
        nested_display: Display variables discovered from nested Sway.
    Return value:
        Mutable environment dictionary for Epiphany.
    Requirements:
        Nested Sway has created its Wayland and IPC sockets.
    Guarantees:
        Sets Dog Paw runtime variables and targets UI apps at the nested Sway
        compositor via `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`, and `SWAYSOCK`.
    Invariants:
        Does not mutate the parent process environment.
    """

    child_env = dogpaw_runtime_environment(config, base_env)
    child_env["XDG_RUNTIME_DIR"] = str(nested_display.xdg_runtime_dir)
    child_env["WAYLAND_DISPLAY"] = nested_display.wayland_display
    child_env["SWAYSOCK"] = str(nested_display.sway_socket)
    return child_env


def launch_environment(config: EmulatorConfig, base_env: Mapping[str, str]) -> dict[str, str]:
    """Build a backwards-compatible Dog Paw runtime environment.

    Purpose:
        Supports older tests or callers that only need the Dog Paw-owned part of
        the emulator environment. New process launch code should use
        `sway_environment()` and `epiphany_environment()` instead.
    Parameters:
        config: Resolved emulator configuration.
        base_env: Existing process environment.
    Return value:
        Mutable environment dictionary with Dog Paw-owned variables.
    Requirements:
        None.
    Guarantees:
        Does not overwrite host display variables.
    Invariants:
        Equivalent to `dogpaw_runtime_environment()`.
    """

    return dogpaw_runtime_environment(config, base_env)


def command_available(command: str) -> bool:
    """Return whether an executable command can be launched.

    Purpose:
        Supports dependency reporting for both absolute paths and command names.
    Parameters:
        command: Executable path or command name.
    Return value:
        `True` when the command resolves to an executable, otherwise `False`.
    Requirements:
        None.
    Guarantees:
        Performs a read-only filesystem or PATH lookup.
    Invariants:
        Does not execute the command.
    """

    path = Path(command)
    if path.parent != Path(".") or path.is_absolute():
        return path.is_file() and os.access(path, os.X_OK)
    return shutil.which(command) is not None


def host_display_report(env: Mapping[str, str]) -> dict[str, object]:
    """Describe the host display environment available to nested Sway.

    Purpose:
        Gives developers a concrete diagnosis of whether the emulator can open a
        nested display window through Wayland, X11, or neither.
    Parameters:
        env: Environment mapping to inspect for standard display variables.
    Return value:
        JSON-serializable report with display mode and relevant variable values.
    Requirements:
        None.
    Guarantees:
        Does not validate socket reachability; it only reports configured env.
    Invariants:
        Does not mutate or normalize environment variables.
    """

    wayland_display = env.get("WAYLAND_DISPLAY")
    display = env.get("DISPLAY")
    mode = "none"
    if wayland_display:
        mode = "wayland"
    elif display:
        mode = "x11"
    return {
        "mode": mode,
        "xdgRuntimeDir": env.get("XDG_RUNTIME_DIR", ""),
        "waylandDisplay": wayland_display or "",
        "display": display or "",
    }


def run_diagnostic_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    """Run one read-only host diagnostic command.

    Purpose:
        Gives doctor checks a small injectable command boundary so tests can
        define host JACK/PipeWire conditions without depending on the machine
        running the tests.
    Parameters:
        command: Argument vector for the command to run.
    Return value:
        Completed process with text stdout/stderr.
    Requirements:
        The command should be read-only and safe to run during `doctor`.
    Guarantees:
        Does not raise for non-zero command exit status.
    Invariants:
        Does not mutate emulator roots or runtime state.
    """

    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def parse_jack_lsp_typed_ports(output: str) -> dict[str, list[str]]:
    """Parse `jack_lsp -t` output into audio and MIDI port lists.

    Purpose:
        Converts JACK's human-readable typed port listing into the small host
        graph summary needed by emulator doctor diagnostics.
    Parameters:
        output: Text emitted by `jack_lsp -t`.
    Return value:
        Dictionary with `audioPorts`, `midiPorts`, and `otherPorts` lists.
    Requirements:
        Port names should appear on unindented lines; following indented lines
        may include type descriptions containing `audio` or `midi`.
    Guarantees:
        Unknown or malformed entries are classified as `otherPorts`.
    Invariants:
        Preserves port order and does not interpret System endpoint semantics.
    """

    audio_ports: list[str] = []
    midi_ports: list[str] = []
    other_ports: list[str] = []
    current_port: str | None = None
    current_type_lines: list[str] = []

    def flush_current_port() -> None:
        nonlocal current_port, current_type_lines
        if current_port is None:
            return
        port_type = " ".join(current_type_lines).lower()
        if "midi" in port_type:
            midi_ports.append(current_port)
        elif "audio" in port_type:
            audio_ports.append(current_port)
        else:
            other_ports.append(current_port)
        current_port = None
        current_type_lines = []

    for raw_line in output.splitlines():
        if not raw_line.strip():
            continue
        if raw_line[0].isspace():
            if current_port is not None:
                current_type_lines.append(raw_line.strip())
            continue
        flush_current_port()
        current_port = raw_line.strip()
    flush_current_port()

    return {
        "audioPorts": audio_ports,
        "midiPorts": midi_ports,
        "otherPorts": other_ports,
    }


def pipewire_jack_provider_report(
    runner: Callable[[list[str]], subprocess.CompletedProcess[str]] = run_diagnostic_command,
) -> dict[str, object]:
    """Report whether a PipeWire session is visible to the current user.

    Purpose:
        Adds informational host-stack metadata for users running JACK through
        PipeWire compatibility without making PipeWire itself a v1 requirement.
    Parameters:
        runner: Command runner used for test injection.
    Return value:
        JSON-serializable provider report with `jackProvider` and `evidence`.
    Requirements:
        None; missing `pw-cli` is reported as unknown provider metadata.
    Guarantees:
        Never raises for missing commands or non-zero command exits.
    Invariants:
        Provider metadata never changes doctor pass/fail status by itself.
    """

    try:
        result = runner(["pw-cli", "info", "0"])
    except FileNotFoundError:
        return {
            "jackProvider": "unknown",
            "pipewireDetected": False,
            "evidence": "pw-cli not found",
        }
    except OSError as exception:
        return {
            "jackProvider": "unknown",
            "pipewireDetected": False,
            "evidence": str(exception),
        }

    output = f"{result.stdout}\n{result.stderr}"
    if result.returncode == 0 and "pipewire" in output.lower():
        return {
            "jackProvider": "pipewire",
            "pipewireDetected": True,
            "evidence": "pw-cli info 0 reported PipeWire",
        }
    return {
        "jackProvider": "unknown",
        "pipewireDetected": False,
        "evidence": "pw-cli did not report a PipeWire core",
    }


def audio_midi_report(
    runner: Callable[[list[str]], subprocess.CompletedProcess[str]] = run_diagnostic_command,
) -> dict[str, object]:
    """Check host JACK audio/MIDI readiness for emulator runs.

    Purpose:
        Implements the SDK emulator v1 doctor contract: JACK server absence is
        a failure, missing visible JACK MIDI ports is a warning, and PipeWire
        detection is informational host-stack metadata.
    Parameters:
        runner: Command runner used for test injection.
    Return value:
        JSON-serializable report with `ok`, `failures`, `warnings`, `jack`, and
        `hostAudioStack` fields.
    Requirements:
        The host should provide `jack_lsp` for complete diagnostics.
    Guarantees:
        Does not start JACK, bridge ALSA MIDI, or create Dog Paw endpoints.
    Invariants:
        The System worker remains the runtime owner of JACK endpoint adoption.
    """

    failures: list[str] = []
    warnings: list[str] = []
    jack_error = ""
    try:
        jack_lsp = runner(["jack_lsp", "-t"])
    except FileNotFoundError:
        jack_lsp = subprocess.CompletedProcess(["jack_lsp", "-t"], 127, "", "jack_lsp not found")
    except OSError as exception:
        jack_lsp = subprocess.CompletedProcess(["jack_lsp", "-t"], 1, "", str(exception))

    if jack_lsp.returncode != 0:
        failures.append("jack_server_unavailable")
        jack_error = (jack_lsp.stderr or jack_lsp.stdout or "jack_lsp failed").strip()
        return {
            "ok": False,
            "failures": failures,
            "warnings": warnings,
            "jack": {
                "server": "unavailable",
                "audioPorts": [],
                "midiPorts": [],
                "otherPorts": [],
                "error": jack_error,
            },
            "hostAudioStack": pipewire_jack_provider_report(runner),
        }

    parsed_ports = parse_jack_lsp_typed_ports(jack_lsp.stdout)
    if not parsed_ports["midiPorts"]:
        warnings.append("jack_midi_ports_missing")

    return {
        "ok": True,
        "failures": failures,
        "warnings": warnings,
        "jack": {
            "server": "available",
            "audioPorts": parsed_ports["audioPorts"],
            "midiPorts": parsed_ports["midiPorts"],
            "otherPorts": parsed_ports["otherPorts"],
            "error": jack_error,
        },
        "hostAudioStack": pipewire_jack_provider_report(runner),
    }


def dependency_report(config: EmulatorConfig, env: Mapping[str, str] | None = None) -> dict[str, object]:
    """Check external executables needed for emulator startup.

    Purpose:
        Gives SDK users and tests a structured way to diagnose missing runtime
        dependencies before trying to launch the full emulator.
    Parameters:
        config: Resolved emulator configuration.
        env: Environment mapping used for host display diagnostics.
    Return value:
        JSON-serializable report with `ok`, `missing`, host display, and
        audio/MIDI diagnostic fields.
    Requirements:
        None.
    Guarantees:
        Does not create directories or start processes.
    Invariants:
        Dependency names are stable public labels.
    """

    required = {
        "epiphany": config.epiphany,
        "sway": config.sway,
        "swaymsg": config.swaymsg,
    }
    missing = [name for name, command in required.items() if not command_available(command)]
    staged_bridge = emulator_bridge_library_path(config)
    if not staged_bridge.is_file() and resolve_bridge_source_library() is None:
        missing.append("dogpaw_bridge")
    display_report = host_display_report(env or os.environ)
    audio_report = audio_midi_report()
    return {
        "ok": not missing and display_report["mode"] != "none" and bool(audio_report["ok"]),
        "missing": missing,
        "hostDisplay": display_report,
        "audioMidi": audio_report,
        "warnings": list(audio_report["warnings"]),
    }


def print_dependency_report_summary(report: Mapping[str, object], stream: object) -> None:
    """Print a concise human-readable dependency and doctor summary.

    Purpose:
        Keeps `doctor` and `--check-dependencies` text output aligned with the
        structured JSON report while avoiding large raw diagnostic dumps.
    Parameters:
        report: Dependency report returned by `dependency_report()`.
        stream: Text stream that receives the summary.
    Return value:
        None.
    Requirements:
        `report` should contain `missing`, `hostDisplay`, and `audioMidi`.
    Guarantees:
        Prints stable, actionable lines for host display and JACK/MIDI status.
    Invariants:
        Does not mutate the report or perform additional diagnostics.
    """

    missing = ", ".join(report["missing"]) if report["missing"] else "none"
    host_display = report["hostDisplay"]
    audio_midi = report["audioMidi"]
    jack = audio_midi["jack"]
    host_audio_stack = audio_midi["hostAudioStack"]
    warnings = ", ".join(audio_midi["warnings"]) if audio_midi["warnings"] else "none"
    failures = ", ".join(audio_midi["failures"]) if audio_midi["failures"] else "none"

    print(f"Missing dependencies: {missing}", file=stream)
    print(f"Host display mode: {host_display['mode']}", file=stream)
    print(f"JACK server: {jack['server']}", file=stream)
    if jack["server"] == "available":
        print(f"JACK audio ports visible: {len(jack['audioPorts'])}", file=stream)
        print(f"JACK MIDI ports visible: {len(jack['midiPorts'])}", file=stream)
    elif jack.get("error"):
        print(f"JACK diagnostic: {jack['error']}", file=stream)
    print(f"Host audio stack: {host_audio_stack['jackProvider']}", file=stream)
    print(f"Audio/MIDI failures: {failures}", file=stream)
    print(f"Audio/MIDI warnings: {warnings}", file=stream)


def config_payload(config: EmulatorConfig) -> dict[str, str]:
    """Convert emulator configuration to stable JSON fields.

    Purpose:
        Backs `--print-config-json` and test assertions without exposing Python
        dataclass internals.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        JSON-serializable dictionary of public contract fields.
    Requirements:
        None.
    Guarantees:
        Includes emulator name, instance name, roots, executables, and startup
        plan path.
    Invariants:
        Field names are stable CLI output contract.
    """

    return {
        "emulatorName": config.emulator_name,
        "instanceName": config.instance_name,
        "dataRoot": str(config.data_root),
        "runtimeRoot": str(config.runtime_root),
        "appDir": str(config.app_dir),
        "emulatorRoot": str(config.emulator_root),
        "instanceRuntimeDir": str(config.instance_runtime_dir),
        "bridgeLibrary": str(emulator_bridge_library_path(config)),
        "startupPlan": str(config.startup_plan),
        "epiphany": config.epiphany,
        "sway": config.sway,
        "swaymsg": config.swaymsg,
        "wlrBackends": config.wlr_backends,
        "hardwareProfile": config.hardware_profile,
    }


def dry_run_lines(config: EmulatorConfig, smoke_seconds: float | None = None) -> list[str]:
    """Build human-readable dry-run output for the launch contract.

    Purpose:
        Shows users exactly which roots, environment values, and commands the
        emulator wrapper would use without starting processes.
    Parameters:
        config: Resolved emulator configuration.
        smoke_seconds: Optional bounded run duration for smoke tests.
    Return value:
        Ordered output lines.
    Requirements:
        None.
    Guarantees:
        Output includes all environment variables needed by Epiphany runtime
        path resolution.
    Invariants:
        Does not inspect or mutate filesystem state.
    """

    lines = [
        f"Dog Paw emulator: {config.emulator_name}",
        f"DOGPAW_EMULATOR_NAME={config.emulator_name}",
        f"DOGPAW_DATA_DIR={config.data_root}",
        f"DOGPAW_APP_DIR={config.app_dir}",
        f"DOGPAW_RUNTIME_DIR={config.runtime_root}",
        f"EPIPHANY_INSTANCE={config.instance_name}",
        f"WLR_BACKENDS={config.wlr_backends}",
        f"DOGPAW_HW_PROFILE={config.hardware_profile}",
        "Sway display input: inherited XDG_RUNTIME_DIR/WAYLAND_DISPLAY/DISPLAY",
        "Epiphany display input: nested Sway XDG_RUNTIME_DIR/WAYLAND_DISPLAY/SWAYSOCK",
        "Sway command: " f"{config.sway} --config <copied-hardware-profile-sway-config>",
        "Epiphany command: " + " ".join(epiphany_launch_command(config)),
    ]
    staged_bridge = emulator_bridge_library_path(config)
    if staged_bridge.is_file():
        lines.insert(5, f"DOGPAW_BRIDGE_LIB={staged_bridge}")
    if smoke_seconds is not None:
        lines.append(f"Smoke duration: {smoke_seconds:.1f}s")
    return lines


def epiphany_launch_command(config: EmulatorConfig) -> list[str]:
    """Build the Epiphany process command used by emulator sessions.

    Purpose:
        Centralizes the wrapper-owned Epiphany process contract so dry-run
        output and real launches cannot drift. The emulator supervises Epiphany
        as a service process, so the interactive terminal loop is disabled.
    Parameters:
        config: Resolved emulator configuration containing executable path,
            instance name, and startup plan path.
    Return value:
        Argument vector suitable for `subprocess.Popen`.
    Requirements:
        `config.epiphany` must name an executable available at launch time.
    Guarantees:
        Includes `--no-term`, `--instance`, and `--startup-plan`.
    Invariants:
        Does not inspect stdin and does not start a process.
    """

    return [
        config.epiphany,
        "--no-term",
        "--instance",
        config.instance_name,
        "--startup-plan",
        str(config.startup_plan),
    ]


def write_sway_config(config: EmulatorConfig) -> Path:
    """Copy the selected hardware profile's Sway config for the emulator session.

    Purpose:
        Makes nested-Sway emulator runs use the selected hardware profile's
        checked-in emulator compositor policy when available, while still
        falling back to the deployed device config for profiles that do not yet
        define an emulator-specific variant.
    Parameters:
        config: Resolved emulator configuration.
    Return value:
        Path to the copied Sway config file.
    Requirements:
        `config.emulator_root` must be writable.
    Guarantees:
        Copies the selected profile's `swayConfig.emulator` when present, or
        `swayConfig` otherwise, into the emulator generated-file directory while
        resolving the splash background path against the selected data root.
    Invariants:
        The generated config stays outside Epiphany's instance runtime
        directory, which Epiphany cleans during startup.
    """

    source_config = hardware_profile_sway_config(
        config.hardware_profile,
        prefer_emulator_variant=True,
    )
    config_path = config.emulator_root / "generated" / "sway-emulator.conf"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    source_text = source_config.read_text(encoding="utf-8")
    config_path.write_text(
        resolve_sway_resource_paths(source_text, config.data_root),
        encoding="utf-8",
    )
    return config_path


def resolve_sway_resource_paths(source_text: str, data_root: Path) -> str:
    """Rewrite Sway resource references for the active emulator data root.

    Purpose:
        Keeps emulator-generated Sway configs aligned with the selected
        persistent data root so seeded resources are found even when the caller
        overrides the default XDG data location.
    Parameters:
        source_text: Checked-in Sway config text from the selected hardware
            profile.
        data_root: Active Dog Paw data root whose `resources/` subtree contains
            the seeded emulator images and data items.
    Return value:
        Sway config text with known resource references rewritten for the active
        data root.
    Requirements:
        `data_root` must be an absolute path chosen for the current emulator
        session.
    Guarantees:
        Rewrites the standard splash background image reference to point at
        `<data_root>/resources/images/splashScreen.png`.
    Invariants:
        Leaves unrelated compositor rules and settings unchanged.
    """

    splash_background = str(data_root / "resources" / "images" / "splashScreen.png")
    return source_text.replace(DEFAULT_SPLASH_BACKGROUND_PATH, splash_background)


def nested_sway_socket_path(config: EmulatorConfig) -> Path:
    """Return the deterministic IPC socket path for nested Sway.

    Purpose:
        Gives the emulator one per-instance IPC socket path instead of relying on
        runtime-directory scanning, which can vary across host compositor setups.
    Parameters:
        config: Resolved emulator configuration for the active instance.
    Return value:
        Full path to the nested Sway IPC socket inside the instance runtime dir.
    Requirements:
        `config.instance_runtime_dir` must identify the current emulator session.
    Guarantees:
        Returns a path under `config.instance_runtime_dir`.
    Invariants:
        The path is stable for repeated launches of the same emulator instance.
    """

    return config.instance_runtime_dir / "sway.sock"


def socket_path_state_summary(path: Path) -> str:
    """Describe one filesystem path that should point at a socket.

    Purpose:
        Gives emulator diagnostics a stable, human-readable summary of whether a
        configured socket pathname still exists, what file type it currently has,
        and whether its parent directory remains present.
    Parameters:
        path: Filesystem path to inspect.
    Return value:
        One summary string including `path=...`, `exists=...`, `type=...`, and
        parent-directory presence. Includes `inode=` when the path exists.
    Requirements:
        None.
    Guarantees:
        Missing paths are reported as `exists=no type=missing` instead of
        raising.
    Invariants:
        Performs only read-only filesystem inspection.
    """

    summary_parts = [f"path={path}"]
    try:
        status = path.lstat()
    except FileNotFoundError:
        summary_parts.append("exists=no")
        summary_parts.append("type=missing")
    except OSError as exc:
        summary_parts.append("exists=unknown")
        summary_parts.append(f"error={exc}")
    else:
        summary_parts.append("exists=yes")
        if stat.S_ISSOCK(status.st_mode):
            file_type = "socket"
        elif stat.S_ISDIR(status.st_mode):
            file_type = "directory"
        elif stat.S_ISREG(status.st_mode):
            file_type = "regular"
        elif stat.S_ISLNK(status.st_mode):
            file_type = "symlink"
        else:
            file_type = "other"
        summary_parts.append(f"type={file_type}")
        summary_parts.append(f"inode={status.st_ino}")

    summary_parts.append(
        f"parent_exists={'yes' if path.parent.exists() else 'no'}"
    )
    return " ".join(summary_parts)


def runtime_socket_inventory(runtime_dir: Path) -> list[str]:
    """List Sway-related socket path summaries in one runtime directory.

    Purpose:
        Gives emulator diagnostics a compact snapshot of the Wayland and Sway IPC
        pathnames visible in a runtime directory so socket replacement or unlink
        events are easier to spot.
    Parameters:
        runtime_dir: Directory to inspect for relevant socket-like entries.
    Return value:
        Sorted summaries for `sway.sock`, `sway-ipc.*.sock`, and `wayland-*`
        entries, excluding lock files.
    Requirements:
        `runtime_dir` may or may not exist.
    Guarantees:
        Missing directories return an empty list.
    Invariants:
        Performs only read-only directory and metadata inspection.
    """

    if not runtime_dir.is_dir():
        return []

    summaries: list[str] = []
    for path in sorted(runtime_dir.iterdir(), key=lambda entry: entry.name):
        name = path.name
        if name.endswith(".lock"):
            continue
        if name == "sway.sock" or name.startswith("sway-ipc.") or name.startswith("wayland-"):
            summaries.append(socket_path_state_summary(path))
    return summaries


def existing_sway_sockets(runtime_dir: Path) -> set[Path]:
    """List Sway IPC sockets already present in a runtime directory.

    Purpose:
        Lets the emulator distinguish a newly launched nested Sway socket from
        a host Sway socket or an earlier emulator run.
    Parameters:
        runtime_dir: Directory containing Sway IPC sockets.
    Return value:
        Set of existing socket paths.
    Requirements:
        `runtime_dir` may or may not exist.
    Guarantees:
        Missing directories produce an empty set.
    Invariants:
        Does not create, delete, or connect to sockets.
    """

    if not runtime_dir.is_dir():
        return set()
    return set(runtime_dir.glob("sway-ipc.*.sock"))


def existing_wayland_displays(runtime_dir: Path) -> set[str]:
    """List Wayland display socket names already present in a runtime directory.

    Purpose:
        Lets the emulator detect which display socket belongs to the nested Sway
        process it just launched.
    Parameters:
        runtime_dir: Directory containing Wayland sockets.
    Return value:
        Set of socket basenames such as `wayland-0`.
    Requirements:
        `runtime_dir` may or may not exist.
    Guarantees:
        Lock files and missing directories are ignored.
    Invariants:
        Does not create, delete, or connect to sockets.
    """

    if not runtime_dir.is_dir():
        return set()
    return {
        path.name
        for path in runtime_dir.glob("wayland-*")
        if not path.name.endswith(".lock")
    }


def select_nested_wayland_display(
    current_displays: set[str],
    previous_displays: set[str],
    host_display: str | None,
) -> str | None:
    """Select the Wayland display socket for nested Sway.

    Purpose:
        Chooses the newly created nested display when possible, while still
        handling forwarded/container environments where a stale socket can make
        strict before/after detection ambiguous.
    Parameters:
        current_displays: Wayland display socket names currently present.
        previous_displays: Display socket names present before Sway launch.
        host_display: Inherited host compositor display name.
    Return value:
        Selected nested display name, or `None` when no candidate exists.
    Requirements:
        `current_displays` should come from the runtime dir that nested Sway used
        as `XDG_RUNTIME_DIR`.
    Guarantees:
        Prefers new sockets, then falls back to any non-host socket.
    Invariants:
        Never returns the inherited host display when another candidate exists.
    """

    new_displays = sorted(current_displays - previous_displays)
    if new_displays:
        return new_displays[-1]
    non_host_displays = sorted(
        display for display in current_displays if display != host_display
    )
    if non_host_displays:
        return non_host_displays[-1]
    return None


def sway_socket_ready(swaymsg: str, socket_path: Path) -> bool:
    """Return whether a Sway IPC socket is ready for client requests.

    Purpose:
        Distinguishes a merely created socket path from a compositor that is
        ready to answer IPC requests, which avoids startup races during nested
        emulator launch.
    Parameters:
        swaymsg: Sway IPC client executable.
        socket_path: Expected IPC socket path for the nested compositor.
    Return value:
        `True` when `swaymsg` can query the socket successfully, else `False`.
    Requirements:
        `socket_path` should point at the configured nested Sway IPC socket.
    Guarantees:
        Returns `False` for missing sockets, refused connections, and other
        command failures.
    Invariants:
        Does not mutate emulator runtime files or process state.
    """

    if not socket_path.exists():
        return False
    try:
        result = subprocess.run(
            [swaymsg, "-s", str(socket_path), "-t", "get_outputs"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        return False
    return result.returncode == 0


def wait_for_sway_socket(
    swaymsg: str,
    socket_path: Path,
    timeout_seconds: float = 10.0,
) -> Path:
    """Wait for nested Sway to publish a ready deterministic IPC socket.

    Purpose:
        Synchronizes Epiphany startup with the nested compositor becoming ready.
    Parameters:
        swaymsg: Sway IPC client executable used to probe readiness.
        socket_path: Expected IPC socket path configured for nested Sway.
        timeout_seconds: Maximum wait time before failing.
    Return value:
        Path to the discovered Sway IPC socket.
    Requirements:
        A Sway process should already be starting with `SWAYSOCK=socket_path`,
        and `swaymsg` should be available.
    Guarantees:
        Raises `TimeoutError` if the socket path does not become connectable in
        time.
    Invariants:
        Does not create or delete files.
    """

    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if sway_socket_ready(swaymsg, socket_path):
            return socket_path
        time.sleep(0.1)
    raise TimeoutError(f"Timed out waiting for Sway IPC socket at {socket_path}")


def wait_for_wayland_display(
    runtime_dir: Path,
    existing: set[str] | None = None,
    host_display: str | None = None,
    timeout_seconds: float = 5.0,
) -> str | None:
    """Wait for nested Sway to publish a new Wayland display socket.

    Purpose:
        Captures the display name that UI child processes need when launched by
        Epiphany.
    Parameters:
        runtime_dir: Directory used as `XDG_RUNTIME_DIR` for nested Sway.
        existing: Display sockets present before nested Sway started.
        host_display: Inherited host compositor display name to avoid selecting.
        timeout_seconds: Maximum wait time before returning `None`.
    Return value:
        Wayland display basename such as `wayland-1`, or `None`.
    Requirements:
        A Sway process should already be starting with the same runtime dir.
    Guarantees:
        Does not fail if the socket is unavailable; Epiphany can still report a
        display issue.
    Invariants:
        Does not create or delete files.
    """

    existing = existing or set()
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        display = select_nested_wayland_display(
            existing_wayland_displays(runtime_dir),
            existing,
            host_display,
        )
        if display:
            return display
        time.sleep(0.1)
    return None


def import_systemd_environment(env: Mapping[str, str]) -> None:
    """Import display environment into the user systemd manager when available.

    Purpose:
        EpiphanyLauncher currently reads display variables from
        `systemctl --user show-environment`; this keeps nested-Sway runs aligned
        with that launcher behavior.
    Parameters:
        env: Environment containing display variables to import.
    Return value:
        None.
    Requirements:
        `systemctl` may be unavailable; failure is non-fatal.
    Guarantees:
        Attempts to import only display-related keys.
    Invariants:
        Does not mutate the caller's Python environment mapping.
    """

    keys = ["DISPLAY", "WAYLAND_DISPLAY", "SWAYSOCK", "XDG_RUNTIME_DIR"]
    import_env = {key: env[key] for key in keys if env.get(key)}
    if not import_env:
        return
    try:
        subprocess.run(
            ["systemctl", "--user", "import-environment", *import_env.keys()],
            env={**os.environ, **import_env},
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        return


def stop_app_units(instance_name: str) -> None:
    """Stop app services launched by one emulator Epiphany instance.

    Purpose:
        Cleans up systemd-managed child apps when the wrapper exits.
    Parameters:
        instance_name: Epiphany instance name used in app unit names.
    Return value:
        None.
    Requirements:
        `systemctl --user` may be unavailable; failure is ignored.
    Guarantees:
        Best-effort stop for `dogpaw-<instance>-app-*.service`.
    Invariants:
        Does not stop services for other Epiphany instances.
    """

    try:
        subprocess.run(
            ["systemctl", "--user", "stop", f"dogpaw-{instance_name}-app-*.service"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        return


def resolve_host_display_runtime_dir(env: Mapping[str, str]) -> Path:
    """Resolve the runtime directory that contains host display sockets.

    Purpose:
        Keeps Wayland/Sway display socket discovery tied to the inherited
        desktop environment instead of Dog Paw's own runtime root.
    Parameters:
        env: Environment mapping used for `XDG_RUNTIME_DIR` lookup.
    Return value:
        Path from inherited `XDG_RUNTIME_DIR`, or `/tmp` when unavailable.
    Requirements:
        Visible nested Sway runs normally require a valid inherited
        `XDG_RUNTIME_DIR`.
    Guarantees:
        Does not create directories.
    Invariants:
        The returned path is never derived from `DOGPAW_RUNTIME_DIR`.
    """

    value = env.get("XDG_RUNTIME_DIR")
    if value:
        return Path(value)
    return Path("/tmp")


def terminate_processes(processes: Iterable[subprocess.Popen[object]], timeout_seconds: float = 5.0) -> None:
    """Terminate child processes started directly by the emulator wrapper.

    Purpose:
        Provides deterministic cleanup for nested Sway, Epiphany, Flutter tools,
        and their process children after normal exit, interruption, or startup
        failure.
    Parameters:
        processes: Processes to terminate in reverse startup order. Processes
            should have been launched in their own process session so child
            tools are also in the same process group.
        timeout_seconds: Grace period before killing a still-running process.
    Return value:
        None.
    Requirements:
        Processes must have been started by this wrapper.
    Guarantees:
        Sends SIGTERM to each process group first, then SIGKILL if needed.
    Invariants:
        Ignores processes that have already exited.
    """

    process_list = list(processes)
    for process in reversed(process_list):
        if process.poll() is not None:
            continue
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        except (OSError, ProcessLookupError):
            process.terminate()
    deadline = time.monotonic() + timeout_seconds
    for process in reversed(process_list):
        remaining = max(0.0, deadline - time.monotonic())
        try:
            process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except (OSError, ProcessLookupError):
                process.kill()
            process.wait()


def format_sway_socket_lifecycle_snapshot(
    label: str,
    *,
    socket_path: Path,
    instance_runtime_dir: Path,
    host_runtime_dir: Path,
    sway_process: subprocess.Popen[object],
    outputs_error: str | None = None,
) -> str:
    """Format one verbose diagnostic snapshot for the nested Sway socket state.

    Purpose:
        Correlates the configured `SWAYSOCK` pathname, visible runtime-directory
        entries, and the nested Sway process status at one moment in time so
        emulator repro logs can show whether the compositor stayed alive while
        the socket pathname changed.
    Parameters:
        label: Short description of the snapshot moment.
        socket_path: Configured nested Sway IPC socket path.
        instance_runtime_dir: Emulator-owned runtime directory containing
            `sway.sock`.
        host_runtime_dir: Host display runtime directory containing `wayland-*`
            sockets.
        sway_process: Running nested Sway child process.
        outputs_error: Optional recent `swaymsg get_outputs` failure text.
    Return value:
        One human-readable diagnostic line suitable for stderr logging.
    Requirements:
        `sway_process` must refer to the nested Sway child launched for the
        current emulator run.
    Guarantees:
        Includes process liveness plus current socket-path summaries without
        mutating runtime state.
    Invariants:
        Performs only read-only inspection of the process and filesystem.
    """

    sway_returncode = sway_process.poll()
    process_state = (
        f"running pid={sway_process.pid}"
        if sway_returncode is None
        else f"exited pid={sway_process.pid} returncode={sway_returncode}"
    )
    summary_parts = [
        f"[dogpaw_emulator] {label}",
        f"sway_process={process_state}",
        f"configured_socket=({socket_path_state_summary(socket_path)})",
        "instance_runtime_entries="
        + (
            "; ".join(runtime_socket_inventory(instance_runtime_dir))
            if runtime_socket_inventory(instance_runtime_dir)
            else "<none>"
        ),
        "host_runtime_entries="
        + (
            "; ".join(runtime_socket_inventory(host_runtime_dir))
            if runtime_socket_inventory(host_runtime_dir)
            else "<none>"
        ),
    ]
    if outputs_error:
        summary_parts.append(f"outputs_error={outputs_error}")
    return " | ".join(summary_parts)


def run_emulator(
    config: EmulatorConfig,
    base_env: Mapping[str, str],
    smoke_seconds: float | None = None,
    smoke_probe: Callable[[NestedDisplayEnvironment, Mapping[str, str]], None] | None = None,
    verbose: bool = False,
) -> int:
    """Start nested Sway and Epiphany for one emulator session.

    Purpose:
        Implements the interactive SDK emulator runtime: isolated roots,
        nested-Sway display, imported display environment, Epiphany startup plan,
        and cleanup.
    Parameters:
        config: Resolved emulator configuration.
        base_env: Environment inherited from the caller.
        smoke_seconds: Optional bounded run duration for automation smoke tests.
        smoke_probe: Optional callback invoked while nested Sway and Epiphany
            are still running, immediately before a bounded smoke run exits.
        verbose: When true, child process output is printed without filtering.
    Return value:
        Epiphany process exit code, or `1` for wrapper startup failure.
    Requirements:
        Dependencies must be installed and the startup plan must exist.
    Guarantees:
        Stops directly started processes and app services before returning.
    Invariants:
        The persistent emulator root is not deleted during cleanup.
    """

    report = dependency_report(config)
    if not report["ok"]:
        print(json.dumps(report, indent=2), file=sys.stderr)
        return 1
    if not config.startup_plan.is_file():
        print(f"Startup plan not found: {config.startup_plan}", file=sys.stderr)
        return 1

    prepare_run_runtime(config)
    sway_env = sway_environment(config, base_env)
    host_display_runtime_dir = resolve_host_display_runtime_dir(sway_env)
    previous_wayland_displays = existing_wayland_displays(host_display_runtime_dir)
    sway_config = write_sway_config(config)
    processes: list[subprocess.Popen[object]] = []
    output_threads: list[threading.Thread] = []

    interrupted = False
    cleanup_notice_printed = False
    missing_sway_output_checks = 0
    last_sway_output_check = 0.0

    def handle_signal(signum: int, _frame: object) -> None:
        nonlocal interrupted, cleanup_notice_printed
        if interrupted and not cleanup_notice_printed:
            print("Dog Paw emulator cleanup is already in progress...", file=sys.stderr)
            cleanup_notice_printed = True
        interrupted = True
        for process in processes:
            if process.poll() is None:
                process.terminate()

    original_int = signal.signal(signal.SIGINT, handle_signal)
    original_term = signal.signal(signal.SIGTERM, handle_signal)
    try:
        if not verbose:
            print(
                f"Dog Paw emulator '{config.emulator_name}' starting. "
                "Use --verbose for raw process output.",
                file=sys.stderr,
            )
        sway_process = start_supervised_process(
            [config.sway, "--config", str(sway_config)],
            sway_env,
            WORKSPACE_ROOT,
            verbose,
            output_threads,
        )
        processes.append(sway_process)
        sway_socket = wait_for_sway_socket(
            config.swaymsg,
            nested_sway_socket_path(config),
        )
        wayland_display = wait_for_wayland_display(
            host_display_runtime_dir,
            previous_wayland_displays,
            base_env.get("WAYLAND_DISPLAY"),
        )
        if not wayland_display:
            raise RuntimeError("Nested Sway did not publish a Wayland display socket")
        nested_display = NestedDisplayEnvironment(
            xdg_runtime_dir=host_display_runtime_dir,
            wayland_display=wayland_display,
            sway_socket=sway_socket,
        )
        epiphany_env = epiphany_environment(config, base_env, nested_display)
        import_systemd_environment(epiphany_env)

        epiphany_process = start_supervised_process(
            epiphany_launch_command(config),
            epiphany_env,
            epiphany_working_directory_for_layout(RUNTIME_LAYOUT),
            verbose,
            output_threads,
        )
        processes.append(epiphany_process)

        smoke_deadline = time.monotonic() + smoke_seconds if smoke_seconds is not None else None
        while epiphany_process.poll() is None and not interrupted:
            if sway_process.poll() is not None:
                if verbose:
                    print(
                        format_sway_socket_lifecycle_snapshot(
                            "nested sway process exited",
                            socket_path=nested_sway_socket_path(config),
                            instance_runtime_dir=config.instance_runtime_dir,
                            host_runtime_dir=host_display_runtime_dir,
                            sway_process=sway_process,
                        ),
                        file=sys.stderr,
                    )
                if not verbose:
                    print("Dog Paw emulator window closed; stopping.", file=sys.stderr)
                return 0
            now = time.monotonic()
            if now - last_sway_output_check >= 1.0:
                last_sway_output_check = now
                outputs_json, outputs_error = capture_sway_outputs(
                    config,
                    nested_display,
                    epiphany_env,
                )
                if sway_outputs_available(outputs_json, outputs_error):
                    missing_sway_output_checks = 0
                else:
                    missing_sway_output_checks += 1
                    if missing_sway_output_checks >= 2:
                        if verbose:
                            print(
                                format_sway_socket_lifecycle_snapshot(
                                    "nested sway output probe reached shutdown threshold",
                                    socket_path=nested_sway_socket_path(config),
                                    instance_runtime_dir=config.instance_runtime_dir,
                                    host_runtime_dir=host_display_runtime_dir,
                                    sway_process=sway_process,
                                    outputs_error=outputs_error,
                                ),
                                file=sys.stderr,
                            )
                        if not verbose:
                            print(
                                "Dog Paw emulator display closed; stopping.",
                                file=sys.stderr,
                            )
                        return 0
            if smoke_deadline is not None and time.monotonic() >= smoke_deadline:
                if smoke_probe is not None:
                    smoke_probe(nested_display, epiphany_env)
                return 0
            time.sleep(0.2)
        return epiphany_process.returncode if epiphany_process.returncode is not None else 130
    except Exception as exc:
        print(f"Dog Paw emulator failed to start: {exc}", file=sys.stderr)
        return 1
    finally:
        stop_app_units(config.instance_name)
        terminate_processes(processes)
        for output_thread in output_threads:
            output_thread.join(timeout=1.0)
        signal.signal(signal.SIGINT, original_int)
        signal.signal(signal.SIGTERM, original_term)


def run_control(
    config: EmulatorConfig,
    args: argparse.Namespace,
    base_env: Mapping[str, str],
) -> int:
    """Run the emulator screen, bridge, and controls GUI as one session.

    Purpose:
        Provides the SDK-facing "one command starts the emulator" workflow while
        preserving existing `run`, `bridge`, and direct Flutter commands as
        debuggable building blocks.
    Parameters:
        config: Resolved emulator configuration.
        args: Parsed CLI arguments, including bridge host/port and verbosity.
        base_env: Environment inherited from the caller.
    Return value:
        Exit code from the first child process that exits, or `130` for an
        interrupted cleanup.
    Requirements:
        The named emulator must already exist, and the Flutter GUI project must
        be available at `EMULATOR_CONTROL_GUI_DIR`.
    Guarantees:
        Starts the emulator runtime, bridge, and GUI with one bridge URL, then
        terminates all remaining owned children when any primary child exits.
    Invariants:
        Does not alter simulator protocols or app startup plans.
    """

    if not EMULATOR_CONTROL_GUI_DIR.is_dir():
        print(f"Emulator control GUI not found: {EMULATOR_CONTROL_GUI_DIR}", file=sys.stderr)
        return 1

    emulator_command, _, _ = control_child_commands(
        config,
        args,
        args.bridge_port if args.bridge_port is not None else DEFAULT_BRIDGE_PORT,
    )
    output_threads: list[threading.Thread] = []
    processes: list[subprocess.Popen[object]] = []
    interrupted = False

    def handle_signal(_signum: int, _frame: object) -> None:
        nonlocal interrupted
        interrupted = True
        for process in processes:
            if process.poll() is None:
                process.terminate()

    original_int = signal.signal(signal.SIGINT, handle_signal)
    original_term = signal.signal(signal.SIGTERM, handle_signal)
    try:
        processes.append(
            start_supervised_process(
                emulator_command,
                base_env,
                WORKSPACE_ROOT,
                args.verbose,
                output_threads,
            )
        )
        disable_control_mode_key_grid_auto_playback(config)
        bridge_port, bridge_process = start_control_bridge_process(
            config,
            args,
            base_env,
            output_threads,
        )
        _, _, gui_command = control_child_commands(config, args, bridge_port)
        print(
            f"Dog Paw emulator control starting '{config.emulator_name}' "
            f"with bridge http://{args.bridge_host}:{bridge_port}",
            file=sys.stderr,
        )
        processes.append(bridge_process)
        processes.append(
            start_supervised_process(
                gui_command,
                base_env,
                EMULATOR_CONTROL_GUI_DIR,
                args.verbose,
                output_threads,
            )
        )

        while not interrupted:
            for process in processes:
                return_code = process.poll()
                if return_code is not None:
                    return int(return_code)
            time.sleep(0.2)
        return 130
    except Exception as exc:
        print(f"Dog Paw emulator control failed to start: {exc}", file=sys.stderr)
        return 1
    finally:
        terminate_processes(processes)
        for output_thread in output_threads:
            output_thread.join(timeout=1.0)
        signal.signal(signal.SIGINT, original_int)
        signal.signal(signal.SIGTERM, original_term)


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line parser for the emulator wrapper.

    Purpose:
        Defines the public SDK-facing emulator command contract.
    Parameters:
        None.
    Return value:
        Configured `ArgumentParser`.
    Requirements:
        None.
    Guarantees:
        Parser includes dry-run, prepare, dependency, and launch modes.
    Invariants:
        Defaults stay appropriate for the current source-repo or packaged-SDK
        layout.
    """

    parser = argparse.ArgumentParser(description="Run the Dog Paw local emulator.")
    parser.add_argument(
        "command",
        nargs="?",
        choices=(
            "run",
            "screen",
            "doctor",
            "create",
            "list",
            "info",
            "logs",
            "delete",
            "install",
            "install-headless",
            "install-flutter",
            "smoke",
            "key",
            "bak",
            "led",
            "bridge",
        ),
        default="run",
        help=(
            "Command to run. 'run' starts screen plus controls, 'screen' starts "
            "only the screen/runtime stack, and 'doctor' checks dependencies."
        ),
    )
    parser.add_argument("--name", default="default", help="Emulator data-root name.")
    parser.add_argument("--instance", help="Epiphany instance name. Defaults to emulator-<name>.")
    parser.add_argument("--data-root", help="Dog Paw data root. Defaults to XDG data root.")
    parser.add_argument("--runtime-root", help="Dog Paw runtime root. Defaults to XDG runtime root.")
    parser.add_argument("--startup-plan", default=str(DEFAULT_STARTUP_PLAN), help="Startup plan JSON.")
    parser.add_argument(
        "--epiphany",
        default=str(default_epiphany_executable_for_layout(RUNTIME_LAYOUT)),
        help="Epiphany executable.",
    )
    parser.add_argument("--sway", default="sway", help="Nested Sway executable.")
    parser.add_argument("--swaymsg", default="swaymsg", help="swaymsg executable.")
    parser.add_argument("--wlr-backends", help="Override WLR_BACKENDS for nested Sway.")
    parser.add_argument(
        "--hardware-profile",
        help="Hardware profile whose Sway config should be used by the emulator.",
    )
    parser.add_argument("--manifest", help="Dog Paw app manifest for install commands.")
    parser.add_argument(
        "--build-dir",
        default="",
        help="Native build directory for headless app installs.",
    )
    parser.add_argument("--binary", help="Explicit headless app binary path.")
    parser.add_argument(
        "--build-mode",
        default="release",
        help="Flutter Linux build mode for install-flutter.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print launch contract without running.")
    parser.add_argument("--prepare-only", action="store_true", help="Create roots and exit.")
    parser.add_argument(
        "--create-if-missing",
        action="store_true",
        help="Create the named emulator before run when lifecycle metadata is missing.",
    )
    parser.add_argument(
        "--no-install-defaults",
        action="store_true",
        help="Skip default app installation when creating an emulator.",
    )
    parser.add_argument(
        "--install-updated",
        action="store_true",
        help="Reinstall already-installed apps whose recorded source fingerprint is stale.",
    )
    parser.add_argument("--force", action="store_true", help="Required for destructive lifecycle commands.")
    parser.add_argument("--print-config-json", action="store_true", help="Print resolved config JSON and exit.")
    parser.add_argument("--check-dependencies", action="store_true", help="Check external tools and exit.")
    parser.add_argument("--json", action="store_true", help="Emit JSON for dependency checks.")
    parser.add_argument("--verbose", action="store_true", help="Print raw emulator child process output.")
    parser.add_argument("--bridge-host", default=DEFAULT_BRIDGE_HOST, help="Host for the emulator GUI bridge.")
    parser.add_argument(
        "--bridge-port",
        type=int,
        help="Port for the emulator GUI bridge. Defaults to 8765 for bridge and auto-selects for run.",
    )
    parser.add_argument(
        "--smoke-seconds",
        type=float,
        help="Run for a bounded number of seconds, then clean up and exit successfully if still healthy.",
    )
    parser.add_argument(
        "key_action",
        nargs="?",
        choices=(
            "tap",
            "down",
            "up",
            "play",
            "loop",
            "stop",
            "auto-on",
            "auto-off",
            "button",
            "knob",
            "snapshot",
        ),
        help="Action or target for simulator control commands.",
    )
    parser.add_argument(
        "key_args",
        nargs="*",
        help="Key action arguments: col row for tap/down/up, or pattern path for play/loop.",
    )
    parser.add_argument(
        "--key-duration-ms",
        type=int,
        help="Duration for compact 'key tap <col> <row>' commands.",
    )
    parser.add_argument(
        "--bak-duration-ms",
        type=int,
        help="Duration for compact 'bak button tap <index>' commands.",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Run the Dog Paw emulator CLI.

    Purpose:
        Entry point that dispatches dry-run, prepare, dependency, and launch
        modes from one SDK-facing command.
    Parameters:
        argv: Optional argument sequence excluding program name.
    Return value:
        Process exit code.
    Requirements:
        Caller must pass arguments matching `build_parser()`.
    Guarantees:
        Invalid names and missing dependencies produce non-zero exits with clear
        messages.
    Invariants:
        Dry-run and config-print modes do not create files or start processes.
    """

    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        config = resolve_config(args, os.environ)
    except ValueError as exc:
        parser.error(str(exc))
    except FileNotFoundError as exc:
        if str(exc).startswith("Emulator does not exist:"):
            emulator_name, data_root, runtime_root = lookup_roots_from_args(args, os.environ)
            print(
                missing_emulator_message_for_lookup(
                    emulator_name,
                    data_root,
                    runtime_root,
                    os.environ,
                ),
                file=sys.stderr,
            )
            return 1
        print(str(exc), file=sys.stderr)
        return 1

    if args.command == "list":
        emulators = list_emulators(config.data_root, config.runtime_root)
        if args.json:
            print(json.dumps({"emulators": emulators}, indent=2))
        else:
            if not emulators:
                print("No Dog Paw emulators found.")
            for emulator in emulators:
                print(f"{emulator['name']} ({emulator['appCount']} apps)")
        return 0

    if args.command == "create" or args.prepare_only:
        payload = create_emulator(config)
        installed_defaults: list[str] = []
        if args.command == "create" and not args.no_install_defaults:
            try:
                installed_defaults = install_default_apps(
                    config,
                    config.startup_plan,
                    args.build_dir,
                    args.build_mode,
                )
            except (FileNotFoundError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
                print(f"Failed to install default apps: {exc}", file=sys.stderr)
                return 1
            payload["defaultInstalledApps"] = installed_defaults
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            print(f"Prepared Dog Paw emulator '{config.emulator_name}'")
            if installed_defaults:
                print(f"Installed default apps: {', '.join(installed_defaults)}")
            print(f"App registry: {config.app_dir}")
            print(f"Runtime dir: {config.instance_runtime_dir}")
        return 0

    if args.command == "info":
        if not emulator_exists(config):
            print(missing_emulator_message(config, os.environ), file=sys.stderr)
            return 1
        payload = emulator_info_payload(config)
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            print(f"Dog Paw emulator: {payload['name']}")
            print(f"Installed apps: {payload['appCount']}")
            print(f"App registry: {config.app_dir}")
        return 0

    if args.command == "logs":
        if not emulator_exists(config):
            print(missing_emulator_message(config, os.environ), file=sys.stderr)
            return 1
        payload = emulator_logs_payload(config)
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            print_emulator_logs_summary(payload)
        return 0

    if args.command == "delete":
        try:
            delete_emulator(config, args.force)
        except (FileNotFoundError, ValueError) as exc:
            print(str(exc), file=sys.stderr)
            return 1
        print(f"Deleted Dog Paw emulator '{config.emulator_name}'")
        return 0

    if args.command == "install":
        return install_manifest_set_for_emulator(config, args)

    if args.command == "install-headless":
        print(
            "Warning: 'dogpaw emulator install-headless' is deprecated; use "
            "'dogpaw emulator install --manifest PATH' instead.",
            file=sys.stderr,
        )
        return install_headless_for_emulator(config, args)

    if args.command == "install-flutter":
        print(
            "Warning: 'dogpaw emulator install-flutter' is deprecated; use "
            "'dogpaw emulator install --manifest PATH' instead.",
            file=sys.stderr,
        )
        return install_flutter_for_emulator(config, args)

    if args.command == "smoke":
        return smoke_emulator(config, args, os.environ)

    if args.command == "key":
        if args.key_action not in {
            "tap",
            "down",
            "up",
            "play",
            "loop",
            "stop",
            "auto-on",
            "auto-off",
        }:
            parser.error(
                "key command requires an action: tap, down, up, play, loop, "
                "stop, auto-on, or auto-off"
            )
        return send_key_control(config, args)

    if args.command == "bak":
        if args.key_action not in {"button", "knob"}:
            parser.error("bak command requires a target: button or knob")
        return send_bak_control(config, args)

    if args.command == "led":
        if args.key_action != "snapshot":
            parser.error("led command requires an action: snapshot")
        return send_led_snapshot_request(config, args)

    if args.command == "bridge":
        if args.key_action is not None:
            parser.error("bridge command does not accept simulator action arguments")
        return run_bridge(config, args.bridge_host, args.bridge_port or DEFAULT_BRIDGE_PORT)

    if args.command == "run" and not args.print_config_json and not args.check_dependencies:
        if args.key_action is not None:
            parser.error("run command does not accept simulator action arguments")
        if not emulator_exists(config):
            if args.create_if_missing:
                if not args.dry_run:
                    create_emulator(config)
                    if not args.no_install_defaults:
                        try:
                            install_default_apps(
                                config,
                                config.startup_plan,
                                args.build_dir,
                                args.build_mode,
                            )
                        except (
                            FileNotFoundError,
                            RuntimeError,
                            ValueError,
                            json.JSONDecodeError,
                        ) as exc:
                            print(f"Failed to install default apps: {exc}", file=sys.stderr)
                            return 1
            else:
                require_existing_emulator(config)
                print("Run `dogpaw emulator create --name <name>` first.", file=sys.stderr)
                return 1
        bridge_port = control_bridge_port(args)
        if args.dry_run:
            print("\n".join(control_dry_run_lines(config, args, bridge_port)))
            return 0
        if args.install_updated:
            try:
                updated_apps = install_updated_apps(config, args.build_dir, args.build_mode)
            except (FileNotFoundError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
                print(f"Failed to install updated apps: {exc}", file=sys.stderr)
                return 1
            if updated_apps:
                print(f"Updated installed apps: {', '.join(updated_apps)}")
        return run_control(config, args, os.environ)

    if args.print_config_json:
        print(json.dumps(config_payload(config), indent=2))
        return 0

    if args.check_dependencies:
        report = dependency_report(config, os.environ)
        if args.json:
            print(json.dumps(report, indent=2))
        elif report["ok"]:
            print("All Dog Paw emulator dependencies are available.")
            print_dependency_report_summary(report, sys.stdout)
        else:
            print("Dog Paw emulator dependency check failed.", file=sys.stderr)
            print_dependency_report_summary(report, sys.stderr)
        return 0 if report["ok"] else 1

    if args.command == "doctor":
        report = dependency_report(config, os.environ)
        if args.json:
            print(json.dumps(report, indent=2))
        elif report["ok"]:
            print("Dog Paw emulator doctor: OK")
            print_dependency_report_summary(report, sys.stdout)
        else:
            print("Dog Paw emulator doctor: FAILED", file=sys.stderr)
            print_dependency_report_summary(report, sys.stderr)
        return 0 if report["ok"] else 1

    if args.command == "screen" and not emulator_exists(config):
        if args.create_if_missing:
            if not args.dry_run:
                create_emulator(config)
                if not args.no_install_defaults:
                    try:
                        install_default_apps(
                            config,
                            config.startup_plan,
                            args.build_dir,
                            args.build_mode,
                        )
                    except (FileNotFoundError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
                        print(f"Failed to install default apps: {exc}", file=sys.stderr)
                        return 1
        else:
            require_existing_emulator(config)
            print("Run `dogpaw emulator create --name <name>` first.", file=sys.stderr)
            return 1

    if args.dry_run:
        print("\n".join(dry_run_lines(config, args.smoke_seconds)))
        return 0

    if args.install_updated:
        try:
            updated_apps = install_updated_apps(config, args.build_dir, args.build_mode)
        except (FileNotFoundError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
            print(f"Failed to install updated apps: {exc}", file=sys.stderr)
            return 1
        if updated_apps:
            print(f"Updated installed apps: {', '.join(updated_apps)}")

    return run_emulator(config, os.environ, args.smoke_seconds, verbose=args.verbose)


if __name__ == "__main__":
    raise SystemExit(main())