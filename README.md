# Dog Paw SDK

Dog Paw SDK packages the public Flutter and Dart packages, curated teaching examples, and a local emulator workflow behind the `dogpaw` CLI.

## Start Here

- Read `docs/getting-started.md` for the first end-to-end newcomer flow.
- Start with `examples/hello_dogpaw` before moving on to `examples/rain_pond` and `examples/namer`.
- Use `tools/dogpaw` as the public command entrypoint.

## First Newcomer Flow

1. Create an emulator with `tools/dogpaw emulator create --name default`.
2. Run it with `tools/dogpaw emulator run --name default`.
3. Install `examples/hello_dogpaw` with `tools/dogpaw emulator install-flutter --name default --manifest examples/hello_dogpaw/dogpawapp.json`.
4. Edit the app, run `flutter test` from the app directory, then reinstall it into the emulator.

## Example Progression

- `examples/hello_dogpaw` is the minimal starting point.
- `examples/rain_pond` is the intermediate example with services and multiple runtime interactions.
- `examples/namer` is the fuller reference example.

## SDK Layout

- `packages/` contains the public Dart packages.
- `examples/` contains the curated teaching apps.
- `tools/dogpaw` is the public workflow front door.
- `runtime/` is the tooling-owned seed payload used to create or update local emulators.
- `.cursor/` contains public SDK guidance for agents working inside this repo.
- `devcontainer/` contains a minimal reproducible container setup for SDK work.
