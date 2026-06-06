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
DRY_RUN=false

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
        --dry-run)
            DRY_RUN=true
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

MANIFEST_ABS="$(realpath "$MANIFEST")"
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
    echo "cd '$FLUTTER_PROJECT_DIR' && flutter pub get && flutter build linux --$BUILD_MODE"
    echo "python3 '$INSTALL_TOOL' --manifest '$MANIFEST_ABS' --app-root '$APP_ROOT' --bundle '$BUNDLE_DIR'"
    exit 0
fi

(
    cd "$FLUTTER_PROJECT_DIR"
    flutter pub get
    flutter build linux "--$BUILD_MODE"
)

if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "Error: expected Flutter bundle not found: $BUNDLE_DIR" >&2
    exit 1
fi

python3 "$INSTALL_TOOL" \
    --manifest "$MANIFEST_ABS" \
    --app-root "$APP_ROOT" \
    --bundle "$BUNDLE_DIR"
