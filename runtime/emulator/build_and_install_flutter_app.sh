#!/usr/bin/env bash
#
# Build and install one Flutter UI app into the Dog Paw app registry layout.
#
# Usage:
#   uiApps/tools/build_and_install_flutter_app.sh --manifest PATH --app-root DIR
#   uiApps/tools/build_and_install_flutter_app.sh --dry-run --manifest PATH --app-root DIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_APPS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -x "$SCRIPT_DIR/install_app.py" ]]; then
    INSTALL_TOOL="$SCRIPT_DIR/install_app.py"
else
    INSTALL_TOOL="$UI_APPS_ROOT/../tools/install_app.py"
fi

MANIFEST=""
APP_ROOT="${DOGPAW_APP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dogpaw/apps}"
BUILD_MODE="release"
HOST_SOURCE_FINGERPRINT=""
HOST_BUILD_MODE=""
DRY_RUN=false
KEEP_CACHE_ON_INSTALL=false

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

read_manifest_string_field() {
    local manifest_path="$1"
    local field_name="$2"
    python3 - "$manifest_path" "$field_name" <<'PY'
import json
import sys

manifest_path = sys.argv[1]
field_name = sys.argv[2]
with open(manifest_path, "r", encoding="utf-8") as manifest_file:
    manifest = json.load(manifest_file)
value = manifest.get(field_name)
if not isinstance(value, str) or not value:
    raise SystemExit(f"Manifest requires non-empty string field: {field_name}")
print(value)
PY
}

# Purpose:
#   Print a visible build-phase banner before Flutter dependency resolution and
#   build output so remote logs stay attributable to one app.
# Parameters:
#   $1: Dog Paw app name from the source manifest. Must be a non-empty string.
#   $2: Flutter build mode such as release or debug. Must be a non-empty string.
# Return value:
#   None. Writes banner lines to stdout.
# Requirements/Preconditions:
#   Caller passes both arguments explicitly.
# Guarantees/Postconditions:
#   Emits a stable three-line ASCII banner suitable for dry-run and real builds.
# Invariants:
#   Does not mutate files, environment, or build inputs.
print_flutter_build_header() {
    local app_name="$1"
    local build_mode="$2"
    echo "========================================"
    echo "==== Building Flutter app: $app_name ($build_mode) ===="
    echo "========================================"
}

host_arch() {
    case "$(uname -m)" in
        aarch64|arm64)
            echo "arm64"
            ;;
        x86_64|amd64)
            echo "x64"
            ;;
        *)
            uname -m
            ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --manifest)
            MANIFEST="${2:-}"
            shift 2
            ;;
        --app-root)
            APP_ROOT="${2:-}"
            shift 2
            ;;
        --build-mode)
            BUILD_MODE="${2:-}"
            shift 2
            ;;
        --host-source-fingerprint)
            HOST_SOURCE_FINGERPRINT="${2:-}"
            shift 2
            ;;
        --host-build-mode)
            HOST_BUILD_MODE="${2:-}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-cache-on-install)
            KEEP_CACHE_ON_INSTALL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$MANIFEST" ]]; then
    echo "Error: --manifest is required" >&2
    exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: manifest not found: $MANIFEST" >&2
    exit 1
fi
if [[ ! -x "$INSTALL_TOOL" ]]; then
    echo "Error: install tool not found: $INSTALL_TOOL" >&2
    exit 1
fi
if [[ -n "$HOST_SOURCE_FINGERPRINT" && -z "$HOST_BUILD_MODE" ]]; then
    echo "Error: --host-source-fingerprint requires --host-build-mode" >&2
    exit 1
fi
if [[ -z "$HOST_SOURCE_FINGERPRINT" && -n "$HOST_BUILD_MODE" ]]; then
    echo "Error: --host-build-mode requires --host-source-fingerprint" >&2
    exit 1
fi

MANIFEST_ABS="$(realpath "$MANIFEST")"
APP_NAME="$(read_manifest_string_field "$MANIFEST_ABS" "name")"
APP_DIR="$(dirname "$MANIFEST_ABS")"
FLUTTER_PROJECT_REL="$(read_manifest_string_field "$MANIFEST_ABS" "flutterApp")"
FLUTTER_PROJECT_DIR="$APP_DIR/$FLUTTER_PROJECT_REL"
ARCH="$(host_arch)"
BUNDLE_DIR="$FLUTTER_PROJECT_DIR/build/linux/$ARCH/$BUILD_MODE/bundle"

if [[ ! -d "$FLUTTER_PROJECT_DIR" ]]; then
    echo "Error: Flutter project not found: $FLUTTER_PROJECT_DIR" >&2
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    print_flutter_build_header "$APP_NAME" "$BUILD_MODE"
    echo "cd '$FLUTTER_PROJECT_DIR' && flutter pub get && flutter build linux --$BUILD_MODE"
    INSTALL_COMMAND="python3 '$INSTALL_TOOL' --manifest '$MANIFEST_ABS' --app-root '$APP_ROOT' --bundle '$BUNDLE_DIR'"
    if [[ -n "$HOST_SOURCE_FINGERPRINT" ]]; then
        INSTALL_COMMAND+=" --host-source-fingerprint '$HOST_SOURCE_FINGERPRINT' --host-build-mode '$HOST_BUILD_MODE'"
    fi
    if [[ "$KEEP_CACHE_ON_INSTALL" == true ]]; then
        INSTALL_COMMAND+=" --keep-cache-on-install"
    fi
    echo "$INSTALL_COMMAND"
    exit 0
fi

print_flutter_build_header "$APP_NAME" "$BUILD_MODE"
(
    cd "$FLUTTER_PROJECT_DIR"
    flutter pub get
    flutter build linux "--$BUILD_MODE"
)

if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "Error: expected Flutter bundle not found: $BUNDLE_DIR" >&2
    exit 1
fi

FLUTTER_SDK_VERSION="$(flutter --version | sed -n '1p')"

INSTALL_ARGS=(
    "$INSTALL_TOOL"
    --manifest "$MANIFEST_ABS"
    --app-root "$APP_ROOT"
    --bundle "$BUNDLE_DIR"
    --flutter-sdk-version "$FLUTTER_SDK_VERSION"
)
if [[ -n "$HOST_SOURCE_FINGERPRINT" ]]; then
    INSTALL_ARGS+=(
        --host-source-fingerprint "$HOST_SOURCE_FINGERPRINT"
        --host-build-mode "$HOST_BUILD_MODE"
    )
fi
if [[ "$KEEP_CACHE_ON_INSTALL" == true ]]; then
    INSTALL_ARGS+=(--keep-cache-on-install)
fi

python3 "${INSTALL_ARGS[@]}"
