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

## Runtime Seed

The `runtime/` directory is tooling-owned seed content. Use `tools/dogpaw emulator create` and `tools/dogpaw emulator run` instead of editing `runtime/` directly.
