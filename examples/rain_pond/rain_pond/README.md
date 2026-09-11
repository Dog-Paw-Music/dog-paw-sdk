# Rain Pond

Play keys (or a few QWERTY keys) and watch ripples spread across a pond surface.
Use this after `hello_dogpaw` to learn a more robust app layout: services,
models, a controller that owns simulation, and tests that run without Epiphany.

LED output is planned soon; today the focus is **input structure** and
**on-screen** visual feedback.

| Path | Role |
|------|------|
| `lib/main.dart` | Composition root: entity, settings, controller, Provider |
| `lib/app.dart` | Material shell |
| `lib/screens/pond_screen.dart` | Boots Dog Paw after first frame; keyboard fallback |
| `lib/controllers/pond_controller.dart` | Simulation, settings, routes note events into ripples |
| `lib/services/pond_key_input_service.dart` | Epiphany connect, endpoints, polling |
| `lib/services/visual_settings_store.dart` | Local prefs load/save (`SharedPreferences`) |
| `lib/models/` | Settings, key identity, note events, ripple state |
| `lib/widgets/` | Canvas, painter, teaching settings drawer |
| `lib/utils/` | Ripple physics + QWERTY key map |

**Suggested read order:** `main.dart` → `pond_screen.dart` (boot) →
`pond_key_input_service.dart` (`connect()` near the top) →
`pond_controller.dart` (note → ripple path) → widgets as needed.

## App structure

Rain Pond splits responsibilities on purpose:

1. **`main.dart`** builds a `DogPawEntity('RainPond')`, a shared `VisualSettings`,
   and a `PondController`, then hands them to Flutter via `MultiProvider`.
2. **`PondController`** owns the pond simulation (ripples, ambient rain, held-key
   expression). It does **not** declare endpoints itself.
3. **`PondKeyInputService`** owns Dog Paw I/O: `connect()`, create endpoints,
   poll, and forward normalized events into the controller.
4. **Models** (`RippleNoteEvent`, `RippleKeySource`, `SurfaceRipple`,
   `VisualSettings`) keep hardware and keyboard on one visual path.
5. **UI** paints and tunes a small teaching subset of settings; richer knobs can
   live in the model/tests without crowding the drawer.

Compared with hello (connect + endpoints inside one controller file), this is
the pattern suggested for larger apps: **thin composition root → controller
for domain state → service for Epiphany**.

## Dog Paw input

On boot, `PondScreen` calls `PondController.initialize()`, which:

1. Loads saved visual settings
2. Starts the simulation immediately (so the UI is alive while connect runs)
3. Asks `PondKeyInputService` to join Epiphany

If Epiphany is unreachable, the app stays up in **keyboard-only** mode
(`isConnected == false`). That is intentional for laptop iteration.

When connect succeeds, the screen completes the `ConnectionHandle` after the
first frame: connect and create endpoints first, then `handle.complete()` once
the UI is up and ready to exchange data (same idea as hello).

### Two endpoint shapes

`PondKeyInputService` creates two **input** endpoints with dogpaw package
helpers (same BladeHW targets hello uses for keys):

```dart
dp.EndpointInfo.forKeyPressInput(
  name: 'rain_pond_key_input',
  displayName: 'Key Input',
);
dp.EndpointInfo.forKeyPositionInput(
  name: 'rain_pond_key_position_input',
  displayName: 'Key Position Input',
);
```

| Local name | Category | Data | Auto-connects to |
|------------|----------|------|------------------|
| `rain_pond_key_input` | message queue | `key_press` | BladeHW `key_press` output |
| `rain_pond_key_position_input` | continuous | `key_position` | BladeHW `key_position` output |

**What are "message queue" and "continuous" categories?**

- **Message queue (`key_press`)** — discrete events that should be processed in
  order. If a key is pressed and released quickly, your app receives both.
- **Continuous (`key_position`)** — streaming data where dropped updates are OK.
  Between ticks, you simply read the latest sample.

Pick the category that matches how your data is produced/consumed when you add
endpoints. Cross-category wiring is still evolving (automatic translation is
planned); prefer matching shapes for now, as this example does.

Hand-built `SearchCriteria` / `EndpointSpec` (without these helpers) is covered
later in `namer`.

### From hardware to ripples

BladeHW events become `RippleNoteEvent`s (grid `RippleKeySource`, velocity,
down/up). Held keys also get expression updates from `PosData` on the continuous
endpoint (pressure and bend feed shimmer / follow-on ripples).

The app does **not** know which musical note is on each key — that is a
**layout** concept taught in `namer`.

## Keyboard fallback

With focus on the pond screen, a small QWERTY set (see `pond_keyboard_notes.dart`)
calls `PondController.submitKeyboardNote`. Same ripple pipeline as hardware.
Useful when you want to launch quickly without a full emulator run.

## Tests

Tests avoid needing Epiphany by:

- constructing `PondController` with `startInitialized: true` and a throwaway
  `DogPawEntity` name
- injecting notes through `submitKeyboardNote`
- unit-testing pure helpers (`isRippleNoteDownEvent`, poll collectors, physics)

From this package directory:

```bash
flutter test --concurrency=1
flutter run -d linux
```

Install into an emulator (SDK layout shown):

```bash
dogpaw emulator install --name default --manifest examples/rain_pond/dogpawapp.json
```
