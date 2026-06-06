# Namer Architecture

**When to use**: Working on the Namer chord detection app.

## Overview

Namer follows the standard Flutter UI app architecture established by monolithController. See `uiApps/apps/monolithController/monolith_controller/.cursor/skills/architecture/SKILL.md` for the full reference pattern.

## Key Differences from monolithController

1. **Dual Services**: NamerService (IPC) + NamingSchemeService (persistence)
2. **Callbacks in Service**: NamerService accepts callbacks via constructor for key events and layout updates
3. **Polling Pattern**: NamerService polls key_press endpoint on 30ms timer (stays in service, not controller)
4. **Pure Logic**: ChordUtils contains stateless chord detection algorithms

## File Structure

```
lib/
├── main.dart                 # Composition root
├── app.dart                  # Theme configuration
├── controllers/
│   └── home_controller.dart  # State + orchestration
├── services/
│   ├── namer_service.dart    # IPC layer
│   └── naming_scheme_service.dart  # Persistence
├── screens/
│   └── home_screen.dart      # Container widget
├── widgets/
│   ├── chord_display_panel.dart  # Shows detected chord
│   ├── chord_builder_panel.dart  # Interactive selection
│   └── show_me_button.dart       # LED highlighting
└── utils/
    └── chord_utils.dart      # Pure chord detection logic
```

## Data Flow

**Key Events**: BladeHW → Epiphany → endpoint → NamerService polls → callback → HomeController updates `_physicallyHeldNotes` → notifyListeners() → UI

**Chord Detection**: UI reads `physicallyHeldNotes` → ChordUtils.detectChord() → display

**LED Control**: ShowMeButton pressed → HomeController.highlightNotes() → NamerService.highlightNotes() → LEDComms

## Testing

- Unit tests for ChordUtils (pure logic)
- Unit tests for controllers/services with MockDogPawEntity
- Integration tests with real Epiphany connection
- Use `--concurrency=1` for all tests

## Theme

All colors use `Theme.of(context)` references:
- `primary`: Cyan for selection
- `secondary`: Purple for flavors  
- `surfaceContainerHighest`: Panel backgrounds
- `surfaceContainerHigh`: Button backgrounds
- `onSurfaceVariant`: Label colors

No hardcoded Color(0xFF...) anywhere in UI code.
