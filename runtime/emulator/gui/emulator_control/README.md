# Dog Paw Emulator Control

Flutter desktop GUI for controlling the local Dog Paw emulator stack.

This is a developer tool owned by `emulator/`, not a Dog Paw app registry entry.
It talks to the Python emulator bridge over localhost HTTP and lets a desktop
developer inspect bridge health, tap simulated key-grid keys, trigger
ButtonsAndKnobs controls, and view LEDComms key colors.

## Run

From the repository root, start the emulator screen, bridge, and controls GUI as
one supervised session:

```bash
dogpaw emulator run
```

The run command auto-selects a bridge port and passes it to the GUI. When any
primary child exits, the command stops the full control session.

To start only the screen and runtime stack without the control GUI:

```bash
dogpaw emulator screen
```

For bridge or GUI debugging, you can still run the pieces manually. Start or
reuse an emulator, then start the bridge:

```bash
dogpaw emulator bridge
```

Run the GUI from this directory:

```bash
flutter run -d linux
```

For a non-default bridge endpoint:

```bash
flutter run -d linux -a --bridge-url=http://127.0.0.1:8766
```

## Test And Build

```bash
flutter analyze
flutter test --concurrency=1
flutter build linux
```
