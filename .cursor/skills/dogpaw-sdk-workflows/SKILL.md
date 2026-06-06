---
name: dogpaw-sdk-workflows
description: Explains the public Dog Paw SDK workflow surface. Use when the user asks how to create or run an emulator, install an app, or understand which commands and directories are part of the supported SDK flow.
---

# Dog Paw SDK Workflows

## Use These Entry Points

- `tools/dogpaw emulator create --name <name>` creates a local emulator from the SDK seed payload.
- `tools/dogpaw emulator run --name <name>` starts the screen, bridge, and controls together.
- `tools/dogpaw emulator screen --name <name>` starts only the screen/runtime stack.
- `tools/dogpaw emulator install-flutter --name <name> --manifest <path>` installs a Flutter app into the emulator app registry.
- `tools/dogpaw emulator install-headless --name <name> --manifest <path>` installs a headless app into the emulator app registry.

## SDK Layout

- `examples/` contains the teaching apps.
- `packages/` contains `dogpaw`, `dogpaw_widgets`, and `dogpaw_test`.
- `runtime/` is a seed payload copied into emulator-owned roots.

## Guidance

- Prefer `hello_dogpaw` as the first example and first install target.
- Do not teach direct edits inside `runtime/`.
- Do not replace `tools/dogpaw` with lower-level Python commands unless the user is explicitly working on maintainer-facing internals.
