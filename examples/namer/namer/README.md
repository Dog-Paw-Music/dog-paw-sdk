# Namer - Chord Detection and Naming Tool

A Flutter UI app for detecting and displaying chord names from physical key
presses, with support for standard and jazz notation.

Within the SDK teaching progression, `namer` is the fuller reference example.
It is intentionally richer than `hello_dogpaw` and `rain_pond`, and its docs
and tests should model the deeper app structure we want developers to learn.

## Features

- **Real-time Chord Detection**: Detects chords as you play them on the physical keyboard
- **Dual Notation**: Toggle between standard (Cmin, G7) and jazz (C-, G7, C△7) notation
- **Chord Builder**: Interactive UI for selecting and exploring chords
- **LED Feedback**: "Show Me" button highlights selected chord notes on the physical keyboard
- **Slash Chord Support**: Displays inversions (e.g., C/E for first inversion)

## Architecture

The app follows the standardized architecture pattern:

```
main.dart (Composition Root)
├── DogPawEntity
├── NamerService (IPC layer)
├── NamingSchemeService (persistence)
└── HomeController (state + orchestration)
    └── Provider → HomeScreen (UI)
        ├── ChordDisplayPanel (shows detected chord)
        ├── ChordBuilderPanel (interactive selection)
        └── ShowMeButton (LED highlighting)
```

### Key Components

**NamerService** (`lib/services/namer_service.dart`)
- Manages connection to Epiphany
- Creates endpoints for key input and LED output
- Subscribes to the shared scoped layout view
- Provides callbacks for key events and layout updates

**NamingSchemeService** (`lib/services/naming_scheme_service.dart`)
- Persists user's notation preference (standard vs jazz)
- Loads/saves to local JSON file

**HomeController** (`lib/controllers/home_controller.dart`)
- Manages app state (connection, held notes, selected notes)
- Orchestrates services
- Provides state to UI via Provider/ChangeNotifier

**ChordUtils** (`lib/utils/chord_utils.dart`)
- Pure logic for chord detection from note sets
- Supports Major, Minor, Diminished, Augmented, 7ths, sus2/sus4
- Format chord names in standard or jazz notation

## Running the App

### Native (Linux)

From this directory:

```bash
flutter run -d linux
```

### Build a Linux Bundle

From this directory:

```bash
flutter build linux --debug
```

## Testing

Namer now keeps its tests with the owning app package.

- `test/public/` contains the export-facing unit tests that ship through the
  exported apps repo as a conventional `test/` directory.

### Current Test Coverage

- App-local command:

```bash
flutter test --concurrency=1
```

- Public-only suite:

```bash
flutter test test/public --concurrency=1
```

## Data Flow

1. **Key Press**: BladeHW → Epiphany → key_press endpoint → NamerService polls → callback to HomeController
2. **Chord Detection**: HomeController updates `_physicallyHeldNotes` → UI reads via Provider → ChordUtils.detectChord → ChordDisplayPanel shows result
3. **LED Highlighting**: User presses ShowMeButton → HomeController.highlightNotes() → NamerService sends LED messages → LEDComms → physical keyboard

## Configuration

The app stores notation preference in:
```
<persistent_app_data_directory>/namer_settings.json
```

Format:
```json
{
  "useJazzNotation": true
}
```

## Supported Chord Types

- Triads: Major, Minor, Diminished, Augmented
- Sevenths: Dominant 7th, Major 7th, Minor 7th, Half-diminished 7th, Diminished 7th
- Suspended: sus2, sus4

## Theme

The app uses a dark theme with:
- Primary: Cyan (#00E5FF) - for active/selected elements
- Secondary: Purple (#B040FF) - for chord flavors
- Background: Very dark gray (#121212)
- Surface: Dark gray (#1A1A1A) - for panels

All colors reference `Theme.of(context)` for consistency.

## Future Improvements

- Widget tests for UI components
- Support for extended chords (9ths, 11ths, 13ths)
- Chord progression memory/history
- MIDI output for selected chords
