# Getting started

## First Workflow

1. Start with `examples/hello_dogpaw`.
2. Run `flutter test --concurrency=1` from `examples/hello_dogpaw/hello_dogpaw`.
3. Create a local emulator with `tools/dogpaw emulator create --name <name>`.
4. Run it with `tools/dogpaw emulator run --name <name>`.
5. Install the example with `tools/dogpaw emulator install-flutter --name <name> --manifest examples/hello_dogpaw/dogpawapp.json`.
6. After that flow works, move on to `examples/rain_pond`, then `examples/namer`.

Most users should omit `--data-root` and `--runtime-root`. Those flags are advanced overrides for isolated tests or maintainer workflows.

## App Creation Notes

- Keep `main.dart` thin and use it to wire dependencies.
- Put runtime logic in services or controllers so it can be tested.
- Keep `dogpawapp.json` accurate when changing names, icons, visibility, or runtime assets.
- Use `dogpaw_test` for Epiphany-backed integration coverage.

## Windows 11 Setup

The supported Windows host path is Windows 11 via WSL2 + WSLg.

1. Install WSL2 with a recent Ubuntu release and open the SDK checkout from inside that Linux environment.
2. Verify that WSLg is active by checking `echo $WAYLAND_DISPLAY` or `echo $DISPLAY` in the WSL shell.
3. Install Linux desktop and build dependencies:
   `sudo apt update && sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev curl git unzip xz-utils zip sway jackd2 jack-tools`
4. Install the Linux Flutter SDK in WSL and confirm `flutter doctor` succeeds before using the SDK.
5. Run `tools/dogpaw emulator doctor` from the SDK root and fix any reported missing dependencies before creating an emulator.

The emulator still requires JACK to be installed and healthy on WSL because `tools/dogpaw emulator doctor` remains strict about JACK readiness.

Audio is not yet supported on Windows hosts. Treat the WSL path as display and app-development support for now.

## Runtime Seed

The `runtime/` directory is tooling-owned seed content. Use `tools/dogpaw emulator create` and `tools/dogpaw emulator run` instead of editing `runtime/` directly.
