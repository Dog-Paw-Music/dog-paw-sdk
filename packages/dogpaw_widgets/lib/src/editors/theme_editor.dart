import 'dart:async';

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../models/editor_preview.dart';
import '../primitives/hsv_color_picker.dart';

/// Reusable musician-facing editor for one Dog Paw theme value.
///
/// Purpose:
/// Defines the shared package contract for theme editing while leaving storage
/// and preview ownership to the host app.
class ThemeEditor extends StatefulWidget {
  /// Current theme value being edited.
  final dp.ThemeData value;

  /// Callback that receives the next full theme value after user edits.
  final ValueChanged<dp.ThemeData> onChanged;

  /// Optional host-owned live preview integration.
  final EditorPreviewController<dp.ThemeData>? previewController;

  /// Create one reusable theme editor shell.
  ///
  /// Parameters:
  /// - `value`: Current theme value to present.
  /// - `onChanged`: Callback receiving the next full theme value.
  /// - `previewController`: Optional host-owned preview integration.
  /// Return value:
  /// - A new `ThemeEditor`.
  ///
  /// Requirements/Preconditions:
  /// - `value` should describe a valid theme.
  ///
  /// Guarantees/Postconditions:
  /// - The editor remains purely presentational and does not persist changes on
  ///   its own.
  ///
  /// Invariants:
  /// - Persistence and preview ownership remain outside the widget.
  const ThemeEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.previewController,
  });

  @override
  State<ThemeEditor> createState() => _ThemeEditorState();
}

/// Stateful theme-editor implementation that owns only local preview state.
class _ThemeEditorState extends State<ThemeEditor> {
  static const List<String> _presetThemeSwatchHexValues = <String>[
    '#f44336',
    '#ff9800',
    '#ffeb3b',
    '#4caf50',
    '#009688',
    '#2196f3',
    '#673ab7',
    '#e91e63',
    '#ffffff',
    '#101010',
  ];
  static const List<String> _roleOrder = <String>[
    'Root',
    'In Scale',
    'Background',
    'Highlight',
  ];
  String _selectedRoleLabel = 'Root';

  /// Emit one next theme value through the public callback and optional preview.
  ///
  /// Parameters:
  /// - `nextValue`: Full next theme value after one user interaction.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `nextValue` should describe a valid theme state.
  ///
  /// Guarantees/Postconditions:
  /// - `widget.onChanged` is invoked synchronously with `nextValue`.
  /// - The preview controller receives a best-effort preview request when present.
  ///
  /// Invariants:
  /// - The widget does not persist theme changes on its own.
  void _emitValue(dp.ThemeData nextValue) {
    widget.onChanged(nextValue);
    final EditorPreviewController<dp.ThemeData>? controller =
        widget.previewController;
    if (controller != null) {
      unawaited(controller.preview(nextValue));
    }
  }

  /// Build one next theme value with a single role color updated.
  ///
  /// Parameters:
  /// - `roleLabel`: Musician-facing role label being edited.
  /// - `hexColor`: New role color in `#rrggbb` format.
  ///
  /// Return value:
  /// - Updated `ThemeData` containing the requested role color change.
  ///
  /// Requirements/Preconditions:
  /// - `hexColor` should be a valid six-digit RGB hex string with leading `#`.
  ///
  /// Guarantees/Postconditions:
  /// - Only the color mapped to `roleLabel` changes.
  ///
  /// Invariants:
  /// - Display name is preserved.
  dp.ThemeData _themeWithRoleColor(String roleLabel, String hexColor) {
    switch (roleLabel) {
      case 'Root':
        return dp.ThemeData(
          displayName: widget.value.displayName,
          primaryColor: hexColor,
          secondaryColor: widget.value.secondaryColor,
          accentColor: widget.value.accentColor,
          backgroundColor: widget.value.backgroundColor,
        );
      case 'In Scale':
        return dp.ThemeData(
          displayName: widget.value.displayName,
          primaryColor: widget.value.primaryColor,
          secondaryColor: hexColor,
          accentColor: widget.value.accentColor,
          backgroundColor: widget.value.backgroundColor,
        );
      case 'Highlight':
        return dp.ThemeData(
          displayName: widget.value.displayName,
          primaryColor: widget.value.primaryColor,
          secondaryColor: widget.value.secondaryColor,
          accentColor: hexColor,
          backgroundColor: widget.value.backgroundColor,
        );
      case 'Background':
      default:
        return dp.ThemeData(
          displayName: widget.value.displayName,
          primaryColor: widget.value.primaryColor,
          secondaryColor: widget.value.secondaryColor,
          accentColor: widget.value.accentColor,
          backgroundColor: hexColor,
        );
    }
  }

  /// Return the stored color for one musician-facing theme role.
  ///
  /// Parameters:
  /// - `roleLabel`: Role being edited.
  ///
  /// Return value:
  /// - Stored role color in `#rrggbb` form.
  ///
  /// Requirements/Preconditions:
  /// - `roleLabel` should be one of the known theme role labels.
  ///
  /// Guarantees/Postconditions:
  /// - Returns the color currently associated with `roleLabel`.
  ///
  /// Invariants:
  /// - Reading the selected role color does not mutate editor state.
  String _hexColorForRole(String roleLabel) {
    switch (roleLabel) {
      case 'Root':
        return widget.value.primaryColor;
      case 'In Scale':
        return widget.value.secondaryColor;
      case 'Highlight':
        return widget.value.accentColor;
      case 'Background':
      default:
        return widget.value.backgroundColor;
    }
  }

  /// Select one musician-facing theme role for editing.
  ///
  /// Parameters:
  /// - `roleLabel`: Role that should drive the embedded color picker.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `roleLabel` should be one of the known theme role labels.
  ///
  /// Guarantees/Postconditions:
  /// - The selected role indicator updates immediately.
  ///
  /// Invariants:
  /// - Theme colors remain unchanged until the picker emits a new value.
  void _handleRoleSelected(String roleLabel) {
    setState(() {
      _selectedRoleLabel = roleLabel;
    });
  }

  /// Apply one live color change from the embedded picker.
  ///
  /// Parameters:
  /// - `hexColor`: New role color in `#rrggbb` format.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `_selectedRoleLabel` should identify a valid theme role.
  ///
  /// Guarantees/Postconditions:
  /// - The selected role updates immediately and the preview hook is invoked.
  ///
  /// Invariants:
  /// - Only the currently selected role changes.
  void _handlePickerColorChanged(String hexColor) {
    _emitValue(_themeWithRoleColor(_selectedRoleLabel, hexColor));
  }

  /// Build the full musician-facing theme editor.
  ///
  /// Parameters:
  /// - `context`: Build context for inherited widget lookup.
  ///
  /// Return value:
  /// - Theme role buttons plus one embedded reusable color picker.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The returned tree uses musician-facing labels rather than implementation
  ///   field names.
  ///
  /// Invariants:
  /// - The widget remains presentational and host-controlled.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Row(
                children: _roleOrder.map((String roleLabel) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: roleLabel == _roleOrder.last ? 0 : 12,
                      ),
                      child: _ThemeRoleCard(
                        key: Key('theme-role-$roleLabel'),
                        label: roleLabel,
                        color: parseHexColor(_hexColorForRole(roleLabel)),
                        isSelected: _selectedRoleLabel == roleLabel,
                        onTap: () {
                          _handleRoleSelected(roleLabel);
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          HsvColorPicker(
            initialHexColor: _hexColorForRole(_selectedRoleLabel),
            presetHexColors: _presetThemeSwatchHexValues,
            onChanged: _handlePickerColorChanged,
            showPreviewBar: false,
          ),
        ],
      ),
    );
  }
}

/// Fixed-size role card used by the theme editor.
class _ThemeRoleCard extends StatelessWidget {
  /// Musician-facing role label.
  final String label;

  /// Current role color preview.
  final Color color;

  /// Tap callback that opens the role picker.
  final VoidCallback onTap;

  /// Whether this role is currently selected for editing.
  final bool isSelected;

  /// Create one musician-facing theme role card.
  ///
  /// Parameters:
  /// - `label`: Role label shown to the user.
  /// - `color`: Current role color preview.
  /// - `isSelected`: Whether this role is the currently active picker target.
  /// - `onTap`: Callback invoked when the card is tapped.
  ///
  /// Return value:
  /// - A new `_ThemeRoleCard`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The card preserves a stable footprint for easy scanning.
  ///
  /// Invariants:
  /// - The widget is presentational and stateless.
  const _ThemeRoleCard({
    super.key,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  /// Build the role card.
  ///
  /// Parameters:
  /// - `context`: Build context used for theming.
  ///
  /// Return value:
  /// - A tappable role card containing a swatch and musician-facing label.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The card never exposes raw hex values in the main UI.
  ///
  /// Invariants:
  /// - Layout size is independent of the current role color.
  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(14);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: SizedBox(
          height: 120,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer.withOpacity(0.45)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: borderRadius,
              border: Border.all(
                color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                width: isSelected ? 4 : 2,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(isSelected ? 0.12 : 0.08),
                  blurRadius: isSelected ? 10 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
