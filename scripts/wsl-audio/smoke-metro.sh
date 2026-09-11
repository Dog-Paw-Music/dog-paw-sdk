#!/usr/bin/env bash
# Smoke-test WSL JACK → pacat → Windows speakers.
#
# Purpose: start jack_metro, connect it to system:playback (metro does not
# autoconnect on dummy jackd), let dogpaw-jack-mirror copy links to the bridge.
# Inputs: optional BPM as $1 (default 120).
# Output: runs ~6s then exits 0; prints jack_lsp -c snapshot.
# Preconditions: dogpaw-jackd-dummy, dogpaw-jack-to-pulse, dogpaw-jack-mirror active.
# Postconditions: metro process stopped.

set -euo pipefail

BPM="${1:-120}"
if ! systemctl --user is-active --quiet dogpaw-jackd-dummy.service \
    || ! systemctl --user is-active --quiet dogpaw-jack-to-pulse.service \
    || ! systemctl --user is-active --quiet dogpaw-jack-mirror.service; then
    echo "error: enable the stack first: ./scripts/wsl-audio/install-user-units.sh" >&2
    exit 1
fi

pkill -x jack_metro 2>/dev/null || true
jack_metro -b "$BPM" &
MP=$!
sleep 0.5
jack_connect metro:120_bpm system:playback_1
jack_connect metro:120_bpm system:playback_2
sleep 1
jack_lsp -c
echo "Listening ~6s — expect metronome on Windows speakers"
sleep 6
kill "$MP" 2>/dev/null || true
wait "$MP" 2>/dev/null || true
echo "done"
