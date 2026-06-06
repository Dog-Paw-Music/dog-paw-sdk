# dogpaw_widgets

Reusable musician-facing Flutter widgets for Dog Paw UI apps.

The package now includes:

- shared editor widgets for `ScaleData`, `ThemeData`, and focused endpoint routing
- thin dialog launchers so apps can open a consistent popup with one call
- the original `PianoKeyboard` and `NoteUtils` primitives
- a small preview-controller contract so apps can hook editor changes into live instrument feedback without baking Epiphany behavior into the widgets themselves

## Package Surface

`dogpaw_widgets` exports:

- `PianoKeyboard`
- `HsvColorPicker`
- `NoteUtils`
- `EditorPreviewController<T>`
- `ScaleEditor`
- `ThemeEditor`
- `ConnectionPicker`
- `showScaleEditorDialog()`
- `showThemeEditorDialog()`
- `showConnectionPickerDialog()`

## Live Preview

Editors stay presentation-focused. If an app wants LED updates, preview notes, or other live instrument feedback while the user edits, it can provide an `EditorPreviewController<T>`.

```dart
class MyThemePreviewController implements EditorPreviewController<ThemeData> {
  @override
  Future<void> preview(ThemeData value) async {
    // Send live preview messages through your app's DogPawEntity integration.
  }

  @override
  Future<void> clear() async {
    // Clear preview state when the dialog closes.
  }
}
```

## Dialog Examples

### Scale dialog

```dart
final ScaleData? editedScale = await showScaleEditorDialog(
  context: context,
  initialValue: currentScale,
  previewController: myScalePreviewController,
);

if (editedScale != null) {
  setState(() {
    currentScale = editedScale;
  });
}
```

### Theme dialog

```dart
final ThemeData? editedTheme = await showThemeEditorDialog(
  context: context,
  initialValue: currentTheme,
  previewController: myThemePreviewController,
);

if (editedTheme != null) {
  setState(() {
    currentTheme = editedTheme;
  });
}
```

### Connection dialog

```dart
await showConnectionPickerDialog(
  context: context,
  entity: dogPawEntity,
  focusedEndpoint: cutoffEndpoint,
  onRefresh: refreshRoutingState,
);
```

The connection dialog is intentionally host-friendly: the app passes the `DogPawEntity` plus the focused endpoint, and the widget handles compatible-endpoint lookup, grouping, and connect/disconnect actions internally.

## Embedded Widget Examples

### Embedded `ScaleEditor`

```dart
ScaleEditor(
  value: currentScale,
  onChanged: (ScaleData nextValue) {
    setState(() {
      currentScale = nextValue;
    });
  },
  previewController: myScalePreviewController,
)
```

### Embedded `ThemeEditor`

```dart
ThemeEditor(
  value: currentTheme,
  onChanged: (ThemeData nextValue) {
    setState(() {
      currentTheme = nextValue;
    });
  },
  previewController: myThemePreviewController,
)
```

### Embedded `ConnectionPicker`

```dart
ConnectionPicker(
  entity: dogPawEntity,
  focusedEndpoint: cutoffEndpoint,
  onRefresh: refreshRoutingState,
)
```

## Piano Keyboard Primitive

`PianoKeyboard` remains available for apps that want a lower-level one-octave keyboard widget.

```dart
PianoKeyboard(
  height: 160,
  colorForNote: (int noteIndex) {
    if (noteIndex == 0) {
      return Colors.red;
    }
    return Colors.white;
  },
  onNoteTap: (int noteIndex) {
    debugPrint('Tapped note: ${NoteUtils.noteNames[noteIndex]}');
  },
  onNoteLongPress: (int noteIndex) {
    debugPrint('Long-pressed note: ${NoteUtils.noteNames[noteIndex]}');
  },
  showNoteLabels: true,
)
```

### Embedded `HsvColorPicker`

```dart
HsvColorPicker(
  initialHexColor: '#2196f3',
  presetHexColors: const <String>[
    '#f44336',
    '#4caf50',
    '#2196f3',
    '#101010',
  ],
  onChanged: (String nextHexColor) {
    debugPrint('Picker changed to $nextHexColor');
  },
  showPreviewBar: false,
)
```

## Notes for App Authors

- `ScaleEditor` is domain-aware. It speaks in roots, named scales, and note membership rather than exposing the underlying stored category model directly.
- `ThemeEditor` uses the four musician-facing roles `Root`, `In Scale`, `Background`, and `Highlight`.
- `HsvColorPicker` provides the touch-friendly beveled-swatch plus HSV editing panel used by `ThemeEditor`, and can hide its preview bar when another part of the UI already shows the active color.
- `ConnectionPicker` hides raw JACK names and instead derives grouped, musician-facing routing rows from endpoint metadata already present in the system.
