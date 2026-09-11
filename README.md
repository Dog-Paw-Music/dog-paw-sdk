# Dog Paw SDK

A complete toolkit for Dog Paw development.

## Installation

### Linux

#### Method 1: Directly on the machine

This is the standard path on a Linux desktop or laptop.

1. Install host packages (Ubuntu/Debian example):

   `sudo apt update && sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev curl git unzip xz-utils zip ca-certificates sway jackd2 jack-tools alsa-utils x11-apps libgtk-layer-shell0 pulseaudio-utils`

2. Install a current stable **Flutter Linux** SDK and confirm `flutter doctor` looks healthy for Linux desktop.
3. Clone this repository and add `tools/` to your `PATH` (see Quick Start).
4. Start a JACK server if one is not already running, for example:

   `jackd -d dummy`

   On many desktops PipeWire can provide JACK compatibility instead; what matters is that `jack_lsp` succeeds.
5. Run `dogpaw emulator doctor` and fix anything it reports missing.

#### Method 2: Cursor + Dev Container

Use `devcontainer/` when you want a pinned Flutter/toolchain environment for editing and testing without installing Flutter on the host first. See `devcontainer/README.md`. The container is great for `flutter test` and package work; the full nested emulator still needs a graphical Linux session with Sway/JACK available (often the host or a WSL distro).

### Windows

The supported Windows path is **Windows 11 + WSL2 + WSLg** via a dedicated `DogPaw` distro (not Docker for the emulator).

From **Windows PowerShell**:

```powershell
irm https://raw.githubusercontent.com/Dog-Paw-Music/dog-paw-sdk/development/scripts/windows/Setup-DogPawWsl.ps1 | iex
```

See `scripts/windows/README.md`. The script creates the isolated distro, writes `/etc/wsl.conf` (including WSLg `/mnt/shared_memory` support), clones this SDK into `~/dog-paw-sdk`, installs apt packages plus a pinned Flutter SDK, enables `scripts/wsl-audio` JACK→pacat units, puts `dogpaw` on your PATH, and sets `DOGPAW_EMULATOR_WLR_BACKENDS=x11` for WSLg.

Then open Cursor **Remote - WSL** → distro `DogPaw` → `~/dog-paw-sdk` and open a new shell so PATH / env defaults apply.

Run the emulator with `dogpaw emulator run --name default` (override backends with `--wlr-backends` if needed).

`libgtk-layer-shell0` is required for `dog_paw_status_bar` (included in the setup package list).

### macOS

Currently unsupported. Want to help bring the SDK to Mac? Shoot us a message!

## Quick Start

1. Finish Installation above.
2. Add the SDK tools to your `PATH` (Windows DogPaw setup already symlinks `dogpaw` into `/usr/local/bin`):

```bash
export DOGPAWSDK_PATH="/path/to/dog-paw-sdk"
export PATH="$PATH:$DOGPAWSDK_PATH/tools"
```

3. Check your environment:

```bash
cd "$DOGPAWSDK_PATH"
dogpaw emulator doctor
```

4. Create a virtual Dog Paw and run it.

**Note:** `run` opens a screen window and a hardware simulator. The first create/run can take a few minutes.

```bash
dogpaw emulator create
dogpaw emulator run
```

## Emulator

Create an emulator with `dogpaw emulator create --name instanceName`.
Multiple emulators can coexist with different filesystems and installed apps. The default name (when `--name` is omitted) is `default`.

Run it with `dogpaw emulator run --name instanceName`.

List emulators with `dogpaw emulator list`.

Delete an emulator with `dogpaw emulator delete --force --name instanceName`.

Install apps by pointing at their `dogpawapp.json`:

```bash
dogpaw emulator install --name instanceName --manifest examples/hello_dogpaw/dogpawapp.json
```

Multiple manifests are allowed:

```bash
dogpaw emulator install --name instanceName --manifest examples/hello_dogpaw/dogpawapp.json --manifest examples/rain_pond/dogpawapp.json
```

### Hardware simulation

#### Key grid

Dog Paw keys recognize three states:

- **Rest:** stationary and unpressed.
- **Active:** slightly pressed, not yet bottomed out (like a piano key in motion before the hammer).
- **Pressed:** at the bottom; further travel is aftertouch.

In the simulator, left-click to press a key fully. Right-click to activate it lightly. Velocity follows the vertical mouse position when you click; drag vertically/horizontally to move the key.

#### Encoders

The right half of the simulator is the six button-encoders below the screen. Each encoder exposes:

- **Raw:** integer steps (one detent = one step). Good for discrete selectors.
- **Normalized:** float 0–1 with acceleration on fast turns. Good for continuous parameters.

## Example Apps

- `examples/hello_dogpaw`: minimal starting point.
- `examples/rain_pond`: intermediate example for keys, service-structured code, and (soon) LEDs.
- `examples/namer`: fuller reference example with a broader test suite.

Each app ships tests:

```bash
cd "$DOGPAWSDK_PATH/examples/hello_dogpaw/hello_dogpaw"
flutter test --concurrency=1
```

## Create Your Own App

Copy `examples/hello_dogpaw/` anywhere you like. Rename it, edit `dogpawapp.json`, then change the behavior.

Flutter/Dart are performant and well supported, but can feel tricky at first. Coding agents (Cursor, Claude Code, and similar) work well for describing an app and iterating. Fun fact: Rain Pond's first version was written from a single prompt.

## SDK Layout

- `packages/` — Dart packages your app uses to talk to Dog Paw.
- `examples/` — curated teaching apps.
- `tools/dogpaw` — main command-line entrypoint.
- `.cursor/` — public SDK guidance for agents in this repo.
- `devcontainer/` — optional reproducible edit/test container.
- `runtime/` — seed content for `dogpaw emulator`. Prefer the CLI instead of editing it by hand.

## Known gaps

- `dogpaw emulator doctor` still prints some WSLg remediation lines even on native Linux hosts.
