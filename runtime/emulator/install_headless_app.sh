#!/usr/bin/env bash
#
# Install one headless Dog Paw app into an app registry.
#
# Usage:
#   tools/install_headless_app.sh --manifest PATH --app-root DIR [--build-dir DIR]
#   tools/install_headless_app.sh --manifest PATH --app-root DIR --binary PATH
#   tools/install_headless_app.sh --manifest PATH --local-dev [--build-dir DIR]
#
# The wrapper resolves the manifest's `executable` from <build-dir>/bin unless
# --binary is supplied, then delegates validated copying to tools/install_app.py.
# --local-dev installs into tmp/dogpaw-data/apps and prints matching runtime
# environment exports for local Epiphany runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MANIFEST=""
APP_ROOT=""
BUILD_DIR="$REPO_ROOT/emulator-build"
BINARY=""
LOCAL_DEV=false
LOCAL_DATA_ROOT="$REPO_ROOT/tmp/dogpaw-data"
EXTRA_BINARY_ARGS=()

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

##
# @brief Read a field from a manifest JSON file.
#
# @param $1 Manifest path.
# @param $2 Field name to read.
# @return Prints the field value to stdout.
#
# @pre $1 points to a readable JSON object and $2 is a top-level string field.
# @post Exits nonzero if the field is absent or not a string.
# @invariants Does not modify the manifest or process environment.
##
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

##
# @brief Resolve the binary payload for this headless app install.
#
# @return Prints the absolute binary path to stdout.
#
# @pre MANIFEST is set and either BINARY or BUILD_DIR is set.
# @post Exits nonzero with a clear error if no binary exists.
# @invariants Does not create, modify, or delete files.
##
resolve_binary_path() {
    if [[ -n "$BINARY" ]]; then
        if [[ ! -f "$BINARY" ]]; then
            echo "Error: binary not found: $BINARY" >&2
            exit 1
        fi
        realpath "$BINARY"
        return 0
    fi

    local executable_name
    executable_name="$(read_manifest_string_field "$MANIFEST" "executable")"
    local candidate="$BUILD_DIR/bin/$executable_name"
    if [[ ! -f "$candidate" ]]; then
        echo "Error: binary for executable '$executable_name' not found at $candidate" >&2
        echo "Build it first, or pass --binary PATH." >&2
        exit 1
    fi
    realpath "$candidate"
}

##
# @brief Resolve manifest-declared helper binaries from the build output.
#
# @return Prints one absolute helper binary path per line.
#
# @pre MANIFEST points to a readable manifest and BUILD_DIR exists.
# @post Exits nonzero if any declared helper binary is missing.
# @invariants Does not create, modify, or delete files.
##
resolve_extra_binary_paths() {
    local helper_names
    helper_names="$(python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as manifest_file:
    manifest = json.load(manifest_file)
install = manifest.get("install", {})
if not isinstance(install, dict):
    raise SystemExit("Manifest install field must be an object")
extra_binaries = install.get("extraBinaries", [])
if not isinstance(extra_binaries, list) or not all(isinstance(item, str) for item in extra_binaries):
    raise SystemExit("install.extraBinaries must be an array of strings")
for helper in extra_binaries:
    print(helper)
PY
)"

    while IFS= read -r helper_name; do
        [[ -z "$helper_name" ]] && continue
        local candidate="$BUILD_DIR/bin/$helper_name"
        if [[ ! -f "$candidate" ]]; then
            echo "Error: extra binary '$helper_name' not found at $candidate" >&2
            exit 1
        fi
        realpath "$candidate"
    done <<< "$helper_names"
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
        --local-dev)
            LOCAL_DEV=true
            shift
            ;;
        --build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        --binary)
            BINARY="${2:-}"
            shift 2
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
if [[ -z "$APP_ROOT" ]]; then
    if [[ "$LOCAL_DEV" == true ]]; then
        APP_ROOT="$LOCAL_DATA_ROOT/apps"
    else
        echo "Error: --app-root is required unless --local-dev is used" >&2
        exit 1
    fi
fi
if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: manifest not found: $MANIFEST" >&2
    exit 1
fi
if [[ -n "$BUILD_DIR" && ! -d "$BUILD_DIR" && -z "$BINARY" ]]; then
    echo "Error: build directory not found: $BUILD_DIR" >&2
    exit 1
fi

RESOLVED_BINARY="$(resolve_binary_path)"
while IFS= read -r extra_binary_path; do
    [[ -z "$extra_binary_path" ]] && continue
    EXTRA_BINARY_ARGS+=(--extra-binary "$extra_binary_path")
done < <(resolve_extra_binary_paths)

python3 "$SCRIPT_DIR/install_app.py" \
    --manifest "$MANIFEST" \
    --app-root "$APP_ROOT" \
    --binary "$RESOLVED_BINARY" \
    "${EXTRA_BINARY_ARGS[@]}"

if [[ "$LOCAL_DEV" == true ]]; then
    echo "export DOGPAW_DATA_DIR=$LOCAL_DATA_ROOT"
    echo "export DOGPAW_APP_DIR=$APP_ROOT"
fi
