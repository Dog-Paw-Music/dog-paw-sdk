# Dog Paw SDK

Welcome to the Dog Paw SDK! It's still very much an alpha WIP. Message me with any questions. Thanks for being a part of it!

This Dog Paw SDK packages the public Flutter and Dart packages, curated teaching examples, and a local emulator workflow behind the `dogpaw` CLI.

As of this first version, there's an emulator and a few reference apps. Launching the emulator should bring up two windows. One is a simulated touch screen. The other simulates the keys and knobs. Read on to see how to run the emulator and create your first app!

## First Newcomer Flow

1. Create an emulator with `tools/dogpaw emulator create`.
2. Run it with `tools/dogpaw emulator run`.
3. Install `examples/hello_dogpaw` with `tools/dogpaw emulator install-flutter --manifest examples/hello_dogpaw/dogpawapp.json`.
4. Edit the app, run `flutter test` from the app directory, then reinstall it into the emulator.

## Example Apps

- `examples/hello_dogpaw` is the minimal starting point. It shows how apps interact with the user and the keys.
- `examples/rain_pond` is the intermediate example with services and multiple runtime interactions.
- `examples/namer` is the fuller reference example (still WIP).

## SDK Layout

- `packages/` contains the public Dart packages.
- `examples/` contains the curated teaching apps.
- `tools/dogpaw` is the public workflow front door.
- `runtime/` is the tooling-owned seed payload used to create or update local emulators.
- `.cursor/` contains public SDK guidance for agents working inside this repo.
- `devcontainer/` contains a minimal reproducible container setup for SDK work.
