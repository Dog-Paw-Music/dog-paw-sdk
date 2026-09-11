#!/usr/bin/env bash
# Linux-side Dog Paw WSL setup (invoked from Setup-DogPawWsl.ps1 or directly).
#
# Purpose:
#   Configure apt packages, a pinned Flutter SDK, the JACK→pacat user-systemd
#   audio stack for WSLg speakers, and the WSLg /mnt/shared_memory workaround
#   inside one WSL distro.
# Inputs:
#   --sdk-root PATH     Absolute path to the dog-paw-sdk checkout (required).
#   --flutter-version V Flutter stable version to install (default: 3.44.6).
#   --dry-run           Print actions without changing the system.
#   --skip-apt          Skip apt install.
#   --skip-flutter      Skip Flutter download/install.
#   --skip-audio        Skip audio unit install.
#   --skip-smoke        Skip paplay / metronome smoke tests.
#   DOGPAW_SOURCE_ONLY  When set to 1, define helpers and return (for tests).
# Output:
#   Exit 0 on success; prints next-step hints for Cursor Remote-WSL.
# Preconditions:
#   Ubuntu-like apt host. Audio units must run as the interactive WSL user (not
#   root). Root is OK for apt-only portions when called via sudo.
# Postconditions:
#   On a full run: packages present, Flutter on PATH for the user, Dog Paw audio
#   user units enabled unless skipped, and /mnt/shared_memory fstab/wsl.conf
#   entries present.
# Invariants:
#   Does not modify Windows host state. Intended for the dedicated DogPaw distro.

set -euo pipefail

ensure_wslg_shared_memory_files() {
    # Purpose:
    #   Ensure fstab + wsl.conf enable a tmpfs at /mnt/shared_memory so WSLg can
    #   allocate shared framebuffers (avoids invisible windows titled
    #   [WARN:COPY MODE]; see microsoft/wslg#1456).
    # Parameters:
    #   $1 - Optional filesystem root prefix for tests (empty = live system /).
    # Return value:
    #   0 on success; non-zero if required writes fail.
    # Requirements:
    #   Write access under root/etc (direct) or sudo on the live system.
    # Guarantees:
    #   Creates <root>/mnt/shared_memory; ensures one active fstab tmpfs line for
    #   /mnt/shared_memory; ensures mountFsTab=true under [automount] in wsl.conf.
    # Invariants:
    #   Does not remove unrelated fstab/wsl.conf entries. With a root prefix does
    #   not mount filesystems and does not invoke sudo.
    local root="${1:-}"
    local fstab wslconf shared_dir

    if [[ -n "$root" ]]; then
        fstab="$root/etc/fstab"
        wslconf="$root/etc/wsl.conf"
        shared_dir="$root/mnt/shared_memory"
        run_root() { "$@"; }
        mkdir -p "$root/etc" "$shared_dir"
    else
        fstab="/etc/fstab"
        wslconf="/etc/wsl.conf"
        shared_dir="/mnt/shared_memory"
        run_root() {
            if [[ "$(id -u)" -eq 0 ]]; then
                "$@"
            else
                sudo "$@"
            fi
        }
        run_root mkdir -p "$shared_dir"
    fi

    if [[ ! -f "$fstab" ]]; then
        if [[ -n "$root" ]]; then
            : >"$fstab"
        else
            run_root touch "$fstab"
        fi
    fi
    if ! grep -qE '^[^#]*[[:space:]]+/mnt/shared_memory[[:space:]]' "$fstab"; then
        if [[ -n "$root" ]]; then
            printf '\n# Dog Paw WSLg shared memory (microsoft/wslg#1456)\ntmpfs /mnt/shared_memory tmpfs defaults 0 0\n' >>"$fstab"
        else
            printf '\n# Dog Paw WSLg shared memory (microsoft/wslg#1456)\ntmpfs /mnt/shared_memory tmpfs defaults 0 0\n' \
                | run_root tee -a "$fstab" >/dev/null
        fi
    fi

    if [[ ! -f "$wslconf" ]]; then
        if [[ -n "$root" ]]; then
            : >"$wslconf"
        else
            run_root touch "$wslconf"
        fi
    fi

    local tmp
    tmp="$(mktemp)"
    # Merge mountFsTab into wsl.conf without dropping unrelated sections.
    awk '
        BEGIN { in_automount=0; saw_automount=0; saw_mountfstab=0 }
        /^\[.*\]$/ {
            if (in_automount && !saw_mountfstab) { print "mountFsTab=true"; saw_mountfstab=1 }
            in_automount = ($0 == "[automount]")
            if (in_automount) saw_automount=1
            print
            next
        }
        in_automount && $0 ~ /^mountFsTab=/ {
            print "mountFsTab=true"
            saw_mountfstab=1
            next
        }
        { print }
        END {
            if (in_automount && !saw_mountfstab) print "mountFsTab=true"
            if (!saw_automount) {
                if (NR > 0) print ""
                print "[automount]"
                print "mountFsTab=true"
            }
        }
    ' "$wslconf" >"$tmp"
    if [[ -n "$root" ]]; then
        cat "$tmp" >"$wslconf"
    else
        run_root cp "$tmp" "$wslconf"
    fi
    rm -f "$tmp"
}

ensure_wslg_shared_memory_mounted() {
    # Purpose:
    #   Mount tmpfs on /mnt/shared_memory for the current session when missing.
    # Parameters: none
    # Return value: 0 always (mount failures become warnings)
    # Requirements: Live system; sudo if not root
    # Guarantees: Best-effort mount; prints mount status
    # Invariants: No-op when already mounted
    if findmnt -n /mnt/shared_memory >/dev/null 2>&1; then
        echo "WSLg shared_memory: mounted ($(findmnt -n -o FSTYPE /mnt/shared_memory))"
        return 0
    fi
    if [[ "$(id -u)" -eq 0 ]]; then
        mkdir -p /mnt/shared_memory
        if mount -t tmpfs tmpfs /mnt/shared_memory; then
            echo "WSLg shared_memory: mounted tmpfs for this session"
        else
            echo "warning: failed to mount tmpfs on /mnt/shared_memory" >&2
        fi
    else
        sudo mkdir -p /mnt/shared_memory
        if sudo mount -t tmpfs tmpfs /mnt/shared_memory; then
            echo "WSLg shared_memory: mounted tmpfs for this session"
        else
            echo "warning: failed to mount tmpfs on /mnt/shared_memory" >&2
        fi
    fi
}

warn_if_wslg_copy_mode() {
    # Purpose:
    #   Detect WSLg COPY MODE from weston.log and print remediation.
    # Parameters:
    #   $1 - Optional path to weston.log (default: /mnt/wslg/weston.log)
    # Return value: 0 always
    # Requirements: none
    # Guarantees: Prints a warning when use_gfxredir=0 or copy warning is enabled
    # Invariants: Read-only; does not restart Weston or WSL
    local log="${1:-/mnt/wslg/weston.log}"
    if [[ ! -f "$log" ]]; then
        return 0
    fi
    if grep -q 'use_gfxredir = 0' "$log" 2>/dev/null \
        || grep -q 'enable_copy_warning_title = 1' "$log" 2>/dev/null; then
        echo "warning: WSLg looks stuck in COPY MODE (invisible GUI / [WARN:COPY MODE])." >&2
        echo "  Config files are ensured; restart WSLg from PowerShell:" >&2
        echo "    wsl --shutdown" >&2
        echo "  Then reopen this distro and re-check:" >&2
        echo "    grep -E 'use_gfxredir|enable_copy_warning' /mnt/wslg/weston.log | tail -5" >&2
    fi
}

if [[ "${DOGPAW_SOURCE_ONLY:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

SDK_ROOT=""
FLUTTER_VERSION="3.44.6"
DRY_RUN=0
SKIP_APT=0
SKIP_FLUTTER=0
SKIP_AUDIO=0
SKIP_SMOKE=0

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sdk-root)
            SDK_ROOT="${2:-}"
            shift 2
            ;;
        --flutter-version)
            FLUTTER_VERSION="${2:-}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-apt)
            SKIP_APT=1
            shift
            ;;
        --skip-flutter)
            SKIP_FLUTTER=1
            shift
            ;;
        --skip-audio)
            SKIP_AUDIO=1
            shift
            ;;
        --skip-smoke)
            SKIP_SMOKE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$SDK_ROOT" ]]; then
    echo "error: --sdk-root is required" >&2
    exit 2
fi
if [[ ! -d "$SDK_ROOT" ]]; then
    echo "error: SDK root not found: $SDK_ROOT" >&2
    exit 1
fi
if [[ -z "$FLUTTER_VERSION" ]]; then
    echo "error: --flutter-version must be non-empty" >&2
    exit 2
fi

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "dry-run:" "$@"
    else
        "$@"
    fi
}

as_root() {
    # Run a command as root: directly when already root, otherwise via sudo.
    # sudo resets the environment, so pass variables with `env VAR=...` inside
    # the command rather than exporting them.
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

ensure_path_line() {
    local line="$1"
    local rc_file="$2"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "dry-run: ensure PATH line in $rc_file: $line"
        return
    fi
    touch "$rc_file"
    if ! grep -Fqx "$line" "$rc_file"; then
        printf '\n%s\n' "$line" >> "$rc_file"
    fi
}

echo "== Dog Paw WSL setup =="
echo "SDK root: $SDK_ROOT"
echo "Flutter version: $FLUTTER_VERSION"
echo "User: $(id -un) (uid=$(id -u))"
echo "Dry run: $DRY_RUN"

echo
echo "== Display environment =="
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>}"
echo "DISPLAY=${DISPLAY:-<unset>}"
echo "PULSE_SERVER=${PULSE_SERVER:-<unset>}"
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
    echo "warning: neither WAYLAND_DISPLAY nor DISPLAY is set; WSLg may be inactive."
fi
if [[ -S /mnt/wslg/PulseServer ]]; then
    echo "WSLg Pulse socket: present (/mnt/wslg/PulseServer)"
else
    echo "warning: /mnt/wslg/PulseServer missing; Windows speaker bridge will not work until WSLg audio is up."
fi

echo
echo "== WSLg shared memory =="
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "dry-run: ensure /mnt/shared_memory fstab entry and mountFsTab=true"
else
    ensure_wslg_shared_memory_files
    ensure_wslg_shared_memory_mounted
fi
warn_if_wslg_copy_mode

APT_PACKAGES=(
    clang
    cmake
    ninja-build
    pkg-config
    libgtk-3-dev
    liblzma-dev
    curl
    ca-certificates
    git
    unzip
    xz-utils
    zip
    sway
    jackd2
    jack-tools
    alsa-utils
    x11-apps
    libgtk-layer-shell0
    pulseaudio-utils
)

if [[ "$SKIP_APT" -eq 0 ]]; then
    echo
    echo "== apt packages =="
    # apt-get -y does not answer debconf questions. jackd2 asks one at priority
    # "high" (jackd/tweak_rt_limits), which blocks forever when the caller cannot
    # see or answer it (Setup-DogPawWsl.ps1, CI, agents). So:
    #   - force the noninteractive frontend (passed via env so it survives sudo),
    #   - preseed the jackd2 answer explicitly,
    #   - give apt/dpkg </dev/null so any prompt that slips through fails fast,
    #   - bound the wait on a dpkg lock held by apt-daily/unattended-upgrades.
    # jackd/tweak_rt_limits=false is the package default (no limits.d/audio.conf).
    # Set true and add the user to the audio group if jackd should get RT priority.
    APT_ENV=(env DEBIAN_FRONTEND=noninteractive)
    APT_OPTS=(
        -y
        -o DPkg::Lock::Timeout=600
        -o Dpkg::Options::=--force-confdef
        -o Dpkg::Options::=--force-confold
    )
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "dry-run: debconf-set-selections <<< 'jackd2 jackd/tweak_rt_limits boolean false'"
    else
        printf '%s\n' "jackd2 jackd/tweak_rt_limits boolean false" \
            | as_root debconf-set-selections
    fi
    # Finish any configure step left behind by an interrupted earlier run.
    run as_root "${APT_ENV[@]}" dpkg --force-confdef --force-confold --configure -a </dev/null
    run as_root "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" update </dev/null
    run as_root "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" install "${APT_PACKAGES[@]}" </dev/null
else
    echo "== apt packages skipped =="
fi

if [[ "$SKIP_FLUTTER" -eq 0 ]]; then
    echo
    echo "== Flutter $FLUTTER_VERSION =="
    if [[ "$(id -u)" -eq 0 ]]; then
        echo "error: Flutter install must run as the normal WSL user (not root)." >&2
        exit 1
    fi
    FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"
    WANT_MARKER="$FLUTTER_HOME/.dogpaw-flutter-version"
    ARCHIVE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
    NEED_INSTALL=1
    if [[ -x "$FLUTTER_HOME/bin/flutter" && -f "$WANT_MARKER" ]]; then
        if [[ "$(cat "$WANT_MARKER")" == "$FLUTTER_VERSION" ]]; then
            NEED_INSTALL=0
            echo "Flutter $FLUTTER_VERSION already installed at $FLUTTER_HOME"
        fi
    fi
    if [[ "$NEED_INSTALL" -eq 1 ]]; then
        TMP_DIR="$(mktemp -d)"
        ARCHIVE="$TMP_DIR/flutter.tar.xz"
        echo "Downloading $ARCHIVE_URL"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "dry-run: curl -fsSL $ARCHIVE_URL -o $ARCHIVE"
            echo "dry-run: extract into $FLUTTER_HOME"
        else
            curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE"
            rm -rf "$FLUTTER_HOME"
            mkdir -p "$(dirname "$FLUTTER_HOME")"
            tar -xJf "$ARCHIVE" -C "$(dirname "$FLUTTER_HOME")"
            # Official archive extracts to a top-level "flutter/" directory.
            if [[ ! -d "$FLUTTER_HOME" ]]; then
                echo "error: expected Flutter directory at $FLUTTER_HOME after extract" >&2
                exit 1
            fi
            printf '%s\n' "$FLUTTER_VERSION" > "$WANT_MARKER"
            "$FLUTTER_HOME/bin/flutter" --disable-analytics >/dev/null 2>&1 || true
            "$FLUTTER_HOME/bin/flutter" precache --linux
        fi
        rm -rf "$TMP_DIR"
    fi
    ensure_path_line "export PATH=\"\$HOME/flutter/bin:\$PATH\"" "$HOME/.bashrc"
    ensure_path_line "export PATH=\"\$HOME/flutter/bin:\$PATH\"" "$HOME/.profile"
    export PATH="$HOME/flutter/bin:$PATH"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        flutter --version | sed -n '1,3p' || true
    fi
else
    echo "== Flutter skipped =="
fi

AUDIO_INSTALL="$SDK_ROOT/scripts/wsl-audio/install-user-units.sh"
if [[ "$SKIP_AUDIO" -eq 0 ]]; then
    echo
    echo "== JACK -> pacat audio units =="
    if [[ "$(id -u)" -eq 0 ]]; then
        echo "error: audio unit install must run as the normal WSL user (not root)." >&2
        echo "Re-run without root, or use Setup-DogPawWsl.ps1 which separates root apt from user audio." >&2
        exit 1
    fi
    if [[ ! -f "$AUDIO_INSTALL" ]]; then
        echo "error: missing $AUDIO_INSTALL" >&2
        exit 1
    fi
    chmod +x "$AUDIO_INSTALL" \
        "$SDK_ROOT/scripts/wsl-audio/"*.sh \
        "$SDK_ROOT/scripts/wsl-audio/dogpaw-jack-to-pulse" \
        "$SDK_ROOT/scripts/wsl-audio/dogpaw-jack-mirror" 2>/dev/null || true
    run "$AUDIO_INSTALL"
else
    echo "== audio units skipped =="
fi

if [[ "$SKIP_SMOKE" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
    echo
    echo "== smoke tests =="
    export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"
    if command -v paplay >/dev/null 2>&1 && [[ -f /usr/share/sounds/alsa/Front_Center.wav ]]; then
        echo "Playing Front_Center.wav via WSLg Pulse (you should hear a chirp)..."
        # paplay blocks indefinitely if the WSLg socket exists but the server is
        # not servicing streams (e.g. after sleep or an RDP reconnect).
        timeout 15 paplay /usr/share/sounds/alsa/Front_Center.wav \
            || echo "warning: paplay failed or timed out (WSLg Pulse not responding?)"
    else
        echo "warning: paplay or sample wav missing; skip Pulse smoke"
    fi
    SMOKE_METRO="$SDK_ROOT/scripts/wsl-audio/smoke-metro.sh"
    if [[ -f "$SMOKE_METRO" ]]; then
        chmod +x "$SMOKE_METRO" || true
        echo "Running JACK metronome smoke (you should hear clicks)..."
        timeout 30 "$SMOKE_METRO" \
            || echo "warning: metro smoke failed or timed out (is the audio stack enabled?)"
    fi
elif [[ "$SKIP_SMOKE" -eq 0 && "$DRY_RUN" -eq 1 ]]; then
    echo "== smoke tests skipped (dry-run) =="
else
    echo "== smoke tests skipped =="
fi

echo
echo "== dogpaw CLI on PATH =="
DOGPAW_TOOL="$SDK_ROOT/tools/dogpaw"
if [[ ! -f "$DOGPAW_TOOL" ]]; then
    echo "warning: missing $DOGPAW_TOOL; skip /usr/local/bin/dogpaw symlink" >&2
else
    chmod +x "$DOGPAW_TOOL" || true
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "dry-run: ln -sfn $DOGPAW_TOOL /usr/local/bin/dogpaw"
    else
        as_root ln -sfn "$DOGPAW_TOOL" /usr/local/bin/dogpaw
        echo "Linked /usr/local/bin/dogpaw -> $DOGPAW_TOOL"
    fi
fi
# Profile exports belong to the normal WSL user (root apt-only passes skip this).
if [[ "$(id -u)" -ne 0 ]]; then
    # WSLg: prefer X11 for a movable nested Sway window (see choose_wlr_backends).
    ensure_path_line 'export DOGPAW_EMULATOR_WLR_BACKENDS=x11' "$HOME/.bashrc"
    ensure_path_line 'export DOGPAW_EMULATOR_WLR_BACKENDS=x11' "$HOME/.profile"
    export DOGPAW_EMULATOR_WLR_BACKENDS="${DOGPAW_EMULATOR_WLR_BACKENDS:-x11}"

    echo
    echo "== Next steps =="
    echo "1. In Cursor: Remote-WSL → open the DogPaw distro → open $SDK_ROOT"
    echo "2. Open a new shell (or: source ~/.bashrc) so dogpaw and WLR defaults apply"
    echo "3. dogpaw emulator doctor"
    echo "4. dogpaw emulator create --name default"
    echo "5. dogpaw emulator run --name default"
    echo "Done."
else
    echo "Skipping user shell profile / next-steps (running as root)."
fi
