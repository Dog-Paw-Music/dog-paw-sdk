---
name: creating-dogpaw-apps
description: Guides creation and extension of Flutter apps for the Dog Paw SDK. Use when creating a new app, adding Dog Paw integration to a Flutter app, or deciding where manifests, services, tests, and assets should live.
---

# Creating Dog Paw Apps

## Start From The Teaching Ladder

- Copy `examples/hello_dogpaw` when you want the smallest readable starting point.
- Use `examples/rain_pond` when you need services and multiple endpoint shapes.
- Use `examples/namer` when you need a fuller controller-and-service structure.

## Required Pieces

- `dogpawapp.json` at the app root.
- An icon referenced by the manifest.
- A Flutter project directory referenced by `flutterApp`.
- Tests under the Flutter project `test/` directory.

## Edit Pattern

1. Keep `main.dart` focused on wiring dependencies.
2. Put runtime logic in services or controllers.
3. Add or update widget tests for UI behavior.
4. Add `dogpaw_test` integration coverage when the app talks to Epiphany.
5. Install into an emulator with `tools/dogpaw emulator install-flutter --name <name> --manifest <path>`.
