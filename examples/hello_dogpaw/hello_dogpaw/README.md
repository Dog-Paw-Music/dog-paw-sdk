# hello_dogpaw

This example lights each key as you play it. Use it to learn the smallest useful
Dog Paw app shape before moving on to `rain_pond` and `namer`.

| File | Role |
|------|------|
| `lib/main.dart` | Creates the Dog Paw entity and wires the controller into Flutter |
| `lib/app.dart` | Touchscreen layout (status + color pickers) |
| `lib/controllers/hello_controller.dart` | Connects to Epiphany, handles keys, drives LEDs |

## Dog Paw Entity

Every app talks to the instrument through a **Dog Paw Entity** (DPE). The entity:

- registers with **Epiphany**, the central server running on each Dog Paw and emulator
- owns **endpoints** (named mailboxes for sending and receiving data)
- describes **connection policies** so Epiphany can auto-link those mailboxes to
  other apps (for example BladeHW for keys, LEDComms for lights)

In this example:

1. `main.dart` constructs `DogPawEntity('HelloDogPaw')` and passes it to
   `HelloController`.
2. `HelloController.start()` (near the top of the controller file) calls
   `connect()` so the entity joins Epiphany.
3. It then creates two endpoints with dogpaw package helpers and starts polling
   for key events.

## Endpoints

Created inside `start()` via:

- `dp.EndpointInfo.forKeyPressInput(...)` → local **`key_input`**, auto-connected
  to BladeHW's `key_press` output
- `dp.EndpointInfo.forLedOverlayOutput(...)` → local **`led_output`**,
  auto-connected to LEDComms's `led_overlay_input`

Pass `autoConnectToDefault: false` if you want to wire connections yourself
(or use `EndpointInfo.defaultKeyPressOutputCriteria` /
`EndpointInfo.defaultLedOverlayInputCriteria` when building a custom
`EndpointSpec`).

## Key presses

BladeHW publishes `KeyEvent` messages whenever a key changes state. This app
polls `_keyInputEndpoint` on a short timer (`processPendingKeyEvents`).

Each event has a grid position (`column`, `row`) and a `newState`:

| State | Hardware meaning | App reaction |
|-------|------------------|--------------|
| `activated` | Key moving, not fully bottomed | Retained highlight in the **Active** color |
| `pressed` | Key at the bottom (aftertouch region) | Retained highlight in the **Pressed** color |
| `rest` | Key released | Cancel that key's highlight |

## LED animations

Highlights are **retained animations**: they stay lit until we cancel them.

- First light on a key → `KeyHighlightLEDMessage` with a fresh client animation id
- Same key, new color/state → `AnimationColorUpdateLEDMessage` for that id
- Key returns to rest → `AnimationCancelLEDMessage`

Changing a color chip in the UI also pushes live updates to any keys that are
currently held in that state (`selectColor`).

## Try it

From this Flutter package directory (the folder that contains `pubspec.yaml`):

```bash
flutter test --concurrency=1
flutter run -d linux
```

Install into an emulator (SDK layout shown):

```bash
dogpaw emulator install --name default --manifest examples/hello_dogpaw/dogpawapp.json
```
