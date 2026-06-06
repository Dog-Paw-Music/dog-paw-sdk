# SDK Dev Container

This folder contains a minimal dev-container setup for editing the Dog Paw SDK
without installing Flutter directly on the host first.

## What it is for

- running `flutter pub get`
- running `flutter test`
- building Linux Flutter examples and apps
- editing the SDK packages and examples in a reproducible environment

## What it is not for

- Pi deployment workflows
- full internal monorepo development
- replacing the normal `tools/dogpaw` emulator flow

Open the SDK repo in a Dev Container using `devcontainer/devcontainer.json`, then
use the normal SDK commands from inside that environment.
