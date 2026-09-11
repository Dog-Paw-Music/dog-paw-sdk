# dogpaw_widgets

Reusable musician-facing Flutter widgets for Dog Paw UI apps.

The package now includes:

- shared editor widgets for `ScaleData`, `ThemeData`, and focused endpoint routing
- thin dialog launchers so apps can open a consistent popup with one call
- system keyboard text input (`SystemKeyboardTextField` and `showSystemKeyboardTextInputDialog`)
- the original `PianoKeyboard` and `NoteUtils` primitives
- a small preview-controller contract so apps can hook editor changes into live instrument feedback without baking Epiphany behavior into the widgets themselves

## Package Surface

`dogpaw_widgets` exports:

- `PianoKeyboard`
- `HsvColorPicker`
- `NoteUtils`
- `CompositorKeyboardControl`
- `SystemKeyboardTextField`
- `EditorPreviewController<T>`
- `SharedOverrideEditorValue<T>`
- `ScaleEditor`
- `ThemeEditor`
- `LayoutEditor`
- `ConnectionPicker`
- `showScaleEditorDialog()`
- `showThemeEditorDialog()`
- `showLayoutEditorDialog()`
- `showConnectionPickerDialog()`
- `showSystemKeyboardTextInputDialog()`
- `ConnectionPickerMode`, `EndpointDirectionFilter`, `ConnectionPickerLeafChrome`
- `EndpointLeafSelection`, `ConnectionPickerLeafChromeResolver`
- `ConnectionRuleMutation`, `ConnectionRuleMutationKind`
- `ConnectionPickerResult`, `ConnectionPickerDismissed`,
  `ConnectionPickerMutated`, `ConnectionPickerEndpointsSelected`

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
final SharedOverrideEditorValue<ScaleData>? editedScale = await showScaleEditorDialog(
  context: context,
  initialValue: SharedOverrideEditorValue<ScaleData>(
    activeSource: LayoutChoiceActiveSource.shared,
    sharedValue: currentScale,
  ),
  previewController: myScalePreviewController,
);

if (editedScale != null) {
  setState(() {
    currentScale = editedScale.sharedValue;
  });
}
```

### Theme dialog

```dart
final SharedOverrideEditorValue<ThemeData>? editedTheme = await showThemeEditorDialog(
  context: context,
  initialValue: SharedOverrideEditorValue<ThemeData>(
    activeSource: LayoutChoiceActiveSource.shared,
    sharedValue: currentTheme,
  ),
  previewController: myThemePreviewController,
);

if (editedTheme != null) {
  setState(() {
    currentTheme = editedTheme.sharedValue;
  });
}
```

### Connection dialog

`ConnectionPicker` and `showConnectionPickerDialog` share one dual-mode API:
`ConnectionPickerMode.connection` (the default) mutates this entity's
`ConnectionRule`s, and `ConnectionPickerMode.endpoint` is a non-mutating
endpoint browser/selector for hosts that want to pick an endpoint without
touching routing state.

```dart
final ConnectionPickerResult result = await showConnectionPickerDialog(
  context: context,
  entity: dogPawEntity,
  focusedEndpoint: cutoffEndpoint,
  onRefresh: refreshRoutingState,
);

switch (result) {
  case ConnectionPickerMutated(mutations: final mutations):
    // mutations is a List<ConnectionRuleMutation> (created/deleted/skippedExisting),
    // each with an opaque ruleName plus sourceRef/destinationRef pair identity.
    break;
  case ConnectionPickerDismissed():
    break;
  case ConnectionPickerEndpointsSelected():
    // Never returned in connection mode.
    break;
}
```

The connection dialog is host-friendly: the app passes the `DogPawEntity` plus the
focused endpoint, and the widget handles compatible-endpoint lookup, folder
navigation, search, and connect/disconnect actions internally.

Chrome lives in the picker’s top band (Back, breadcrumb, focus context, search,
dismiss). Back at the root is a no-op; the explicit dismiss control closes the
dialog. Compatible peers appear as a horizontal free-scrolling card rail of
folder and leaf cards (pairs share one leaf). Hierarchy comes from
`EndpointDisplaySpec` plus owner display names via `ConnectionNavigationModel`;
`groupKey` still pairs members for a single connect/disconnect gesture.
Leaf cards show a top row with direction text (`input` / `output`) and a
type icon (audio / MIDI / data), then the endpoint name below using the
remaining card height. Connected and selected state is conveyed by fill
chrome only — there is no SELECT/CONNECT status label.

**Create semantics:** new rules get an opaque, UUID-like name (not encoded
from the pair). Because names are no longer pair-derived, connecting a pair
that this entity has already connected is detected by matching the pair
identity (source/destination refs) against this entity's existing rules
rather than by name — a repeat connect is reported as
`ConnectionRuleMutationKind.skippedExisting` and creates **no** additional
rule; this entity still owns exactly one rule for that pair.

**Leaf chrome:** the picker only knows three generic UI tokens —
`ConnectionPickerLeafChrome.unlit` (idle), `.lit` (emphasized/active), and
`.muted` (present but de-emphasized). It does not know app-domain concepts
like "ours" vs "external"; hosts map their own domain state onto these
tokens with an optional `leafChrome` resolver:

```dart
ConnectionPickerLeafChrome myChromeResolver(EndpointLeafSelection leaf) {
  if (isExternalRule(leaf)) {
    return ConnectionPickerLeafChrome.muted;
  }
  return isConnectedByUs(leaf)
      ? ConnectionPickerLeafChrome.lit
      : ConnectionPickerLeafChrome.unlit;
}

ConnectionPicker(
  entity: dogPawEntity,
  focusedEndpoint: cutoffEndpoint,
  leafChrome: myChromeResolver,
)
```

Leaving `leafChrome` unset falls back to the picker's own default: this-entity
rule match ⇒ `lit`, else `unlit` (existing hosts keep today's binary
lit/unlit behavior unchanged). Tap policy follows chrome: `unlit` connects,
`lit` disconnects, and `muted` blocks delete via the picker (hosts that want a
de-emphasized "linked but not ours" leaf to stay non-destructive return
`muted`). The picker never bakes a realized-connection-list query into its
chrome when a host supplies `leafChrome`; it only ever renders whatever token
the resolver returns.

### Endpoint-selection mode

```dart
final ConnectionPickerResult result = await showConnectionPickerDialog(
  context: context,
  entity: dogPawEntity,
  mode: ConnectionPickerMode.endpoint,
  directionFilter: EndpointDirectionFilter.sources,
  multiSelect: false,
);

if (result is ConnectionPickerEndpointsSelected) {
  final EndpointLeafSelection leaf = result.leaves.first;
  // leaf.members has more than one entry when leaf.groupKey pairs endpoints
  // (e.g. a stereo pair) that should be treated as one selection.
}
```

`directionFilter` selects `sources` (outputs), `destinations` (inputs), or
`both`. With `multiSelect: true` the picker shows an explicit Confirm/Cancel
bar instead of returning immediately on the first tap; Confirm returns every
selected leaf as `ConnectionPickerEndpointsSelected.leaves`, and Cancel
returns `ConnectionPickerDismissed` without reporting a selection. Endpoint
mode never mutates routing state — no `ConnectionRuleMutation`s are produced,
and `focusedEndpoint` is ignored (and may be omitted).

## Embedded Widget Examples

### Embedded `ScaleEditor`

```dart
ScaleEditor(
  value: SharedOverrideEditorValue<ScaleData>(
    activeSource: LayoutChoiceActiveSource.shared,
    sharedValue: currentScale,
  ),
  onChanged: (SharedOverrideEditorValue<ScaleData> nextValue) {
    setState(() {
      currentScale = nextValue.sharedValue;
    });
  },
  previewController: myScalePreviewController,
)
```

### Embedded `ThemeEditor`

```dart
ThemeEditor(
  value: SharedOverrideEditorValue<ThemeData>(
    activeSource: LayoutChoiceActiveSource.shared,
    sharedValue: currentTheme,
  ),
  onChanged: (SharedOverrideEditorValue<ThemeData> nextValue) {
    setState(() {
      currentTheme = nextValue.sharedValue;
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
  // Optional: show dismiss in the top band (dialogs wire this to Navigator.pop).
  // onDismiss: () => Navigator.of(context).pop(),
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

## System Keyboard Text Input

On Pi targets, text entry uses **wvkbd** (compositor on-screen keyboard). Use
`showSystemKeyboardTextInputDialog` for save-as and other naming prompts. The
dialog leaves bottom inset room so wvkbd does not cover action buttons.

```dart
final String? name = await showSystemKeyboardTextInputDialog(
  context: context,
  title: 'Save Layout As',
  initialValue: 'User 1',
  hintText: 'Layout name',
);

if (name != null) {
  // Persist under the confirmed name.
}
```

For inline fields, embed `SystemKeyboardTextField`:

```dart
final TextEditingController textController = TextEditingController();

SystemKeyboardTextField(
  textController: textController,
  hintText: 'Name',
  onSubmitted: () {
    FocusScope.of(context).unfocus();
  },
)
```

Password-style fields can set `obscureText: true`. That starts with masked
characters and shows a visibility toggle so the user can reveal or hide the
text while typing.

wvkbd must be running in the Sway session (typically via the host `wvkbd.service`
unit).
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
- `ConnectionPicker` hides raw JACK names and presents compatible peers (or, in
  endpoint mode, direction-filtered endpoints) as a folder-navigable horizontal
  rail driven by `ConnectionNavigationModel` (display hierarchy + owner display
  names). In connection mode, leaf taps toggle connect/disconnect (subject to
  `leafChrome` tap policy); in endpoint mode, leaf taps report a selection and
  never mutate routing state. Same-path `groupKey` members stay one paired
  action/selection in both modes.
