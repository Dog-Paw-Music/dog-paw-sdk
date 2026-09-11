#!/usr/bin/env bash
# Install and enable Dog Paw WSL audio user units (JACK dummy + pacat bridge).
#
# Purpose: copy units/scripts into the user config dirs and enable them.
# Inputs: none (uses this script's directory as the source tree).
# Output: enabled user units; prints status.
# Preconditions: jackd2, jack-tools, pulseaudio-utils installed; systemctl --user works;
#   WSLg Pulse socket available when sound is needed.
# Postconditions: dogpaw-jackd-dummy, dogpaw-jack-to-pulse, dogpaw-jack-mirror enabled;
#   PipeWire user units disabled so classic JACK owns the graph.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
RULE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dogpaw/wsl-audio"

if ! systemctl --user status >/dev/null 2>&1; then
    echo "error: systemctl --user is not available in this session" >&2
    exit 1
fi

for cmd in jackd jack_lsp jack_connect pacat python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: missing command '$cmd' (install jackd2 jack-tools pulseaudio-utils)" >&2
        exit 1
    fi
done

mkdir -p "$UNIT_DIR" "$RULE_DIR"
cp -f "$SRC/dogpaw-jackd-dummy.service" "$UNIT_DIR/"
cp -f "$SRC/dogpaw-jack-to-pulse.service" "$UNIT_DIR/"
cp -f "$SRC/dogpaw-jack-mirror.service" "$UNIT_DIR/"
cp -f "$SRC/dogpaw-jack-to-pulse" "$RULE_DIR/dogpaw-jack-to-pulse"
cp -f "$SRC/dogpaw-jack-mirror" "$RULE_DIR/dogpaw-jack-mirror"
chmod +x "$RULE_DIR/dogpaw-jack-to-pulse" "$RULE_DIR/dogpaw-jack-mirror"

systemctl --user disable --now \
    pipewire.socket pipewire.service \
    pipewire-pulse.socket pipewire-pulse.service \
    wireplumber.service 2>/dev/null || true

systemctl --user disable --now \
    dogpaw-zita-j2a-pulse.service \
    dogpaw-jack-plumbing.service 2>/dev/null || true

systemctl --user daemon-reload
systemctl --user enable \
    dogpaw-jackd-dummy.service \
    dogpaw-jack-to-pulse.service \
    dogpaw-jack-mirror.service

systemctl --user stop \
    dogpaw-jack-mirror.service \
    dogpaw-jack-plumbing.service \
    dogpaw-jack-to-pulse.service \
    dogpaw-jackd-dummy.service 2>/dev/null || true
pkill -x jackd jack-plumbing 2>/dev/null || true
sleep 0.5
systemctl --user start dogpaw-jackd-dummy.service
systemctl --user start dogpaw-jack-to-pulse.service
systemctl --user start dogpaw-jack-mirror.service

loginctl enable-linger "$(id -un)" 2>/dev/null || true

echo "Installed user audio units from $SRC"
systemctl --user --no-pager --full status \
    dogpaw-jackd-dummy.service \
    dogpaw-jack-to-pulse.service \
    dogpaw-jack-mirror.service || true
echo
echo "Smoke: jack_metro -b 120   # auto-mirrors system:playback -> pacat bridge"
