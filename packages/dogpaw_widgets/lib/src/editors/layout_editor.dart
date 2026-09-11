import 'dart:async';

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../dialogs/show_scale_editor_dialog.dart';
import '../dialogs/show_theme_editor_dialog.dart';
import '../models/editor_preview.dart';
import '../models/shared_override_editor_value.dart';

/// Visibility mode for one optional layout-editor field section.
enum LayoutEditorFieldVisibility {
  editable,
  readOnly,
  hidden,
}

/// One runtime target option shown by the reusable layout editor.
///
/// Purpose:
/// Gives the host a simple UI-facing model for target-picker choices without
/// forcing the editor widget to own DogPawEntity requests directly.
class LayoutEditorTargetOption {
  /// Target key persisted into `LayoutData.targetKey`.
  final String targetKey;

  /// Stable app/template name for the running entity.
  final String appName;

  /// Runtime entity name for the running entity.
  final String entityName;

  /// Create one reusable target-picker option.
  ///
  /// Parameters:
  /// - `targetKey`: persisted target key for targeted layouts.
  /// - `appName`: stable app/template name to show in the picker.
  /// - `entityName`: runtime entity identifier to show in the picker.
  ///
  /// Return value:
  /// - A new immutable `LayoutEditorTargetOption`.
  ///
  /// Requirements/Preconditions:
  /// - `targetKey`, `appName`, and `entityName` should be non-empty.
  ///
  /// Guarantees/Postconditions:
  /// - The option can be rendered directly by the layout editor.
  ///
  /// Invariants:
  /// - Construction performs no I/O.
  const LayoutEditorTargetOption({
    required this.targetKey,
    required this.appName,
    required this.entityName,
  });

  /// Purpose:
  /// Build the user-facing button label for this target option.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Combined app/entity label suitable for musician-facing picking UI.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returned text includes both the app name and entity name.
  ///
  /// Invariants:
  /// - Reading this property does not mutate state.
  String get label => '$appName · $entityName';
}

/// Reusable musician-facing editor for one Dog Paw layout draft.
///
/// Purpose:
/// Defines the shared package contract for editing interval-grid layout drafts
/// while leaving storage, target discovery, and preview ownership to the host.
class LayoutEditor extends StatelessWidget {
  /// Current editable layout draft value.
  final dp.LayoutDraft value;

  /// Callback that receives the next full draft after user edits.
  final ValueChanged<dp.LayoutDraft> onChanged;

  /// Optional host-owned live preview integration.
  final EditorPreviewController<dp.LayoutDraft>? previewController;

  /// Current shared theme supplied by the host app.
  final dp.ThemeData sharedTheme;

  /// Current shared scale supplied by the host app.
  final dp.ScaleData sharedScale;

  /// Callback that receives shared-theme edits emitted from the embedded theme editor.
  final ValueChanged<dp.ThemeData> onSharedThemeChanged;

  /// Callback that receives shared-scale edits emitted from the embedded scale editor.
  final ValueChanged<dp.ScaleData> onSharedScaleChanged;

  /// Target-picker choices supplied by the host.
  final List<LayoutEditorTargetOption> availableTargets;

  /// Visibility mode for the target section.
  final LayoutEditorFieldVisibility targetVisibility;

  /// Visibility mode for the theme section.
  final LayoutEditorFieldVisibility themeVisibility;

  /// Visibility mode for the scale section.
  final LayoutEditorFieldVisibility scaleVisibility;

  /// Create one reusable layout editor shell.
  ///
  /// Parameters:
  /// - `value`: current layout draft to present.
  /// - `onChanged`: callback receiving the next full layout draft.
  /// - `sharedTheme`: current host-owned shared theme shown to the editor.
  /// - `sharedScale`: current host-owned shared scale shown to the editor.
  /// - `onSharedThemeChanged`: callback for shared-theme edits.
  /// - `onSharedScaleChanged`: callback for shared-scale edits.
  /// - `previewController`: optional host-owned preview integration.
  /// - `availableTargets`: picker choices for editable targeted layouts.
  /// - `targetVisibility`: whether the target section is editable, read-only, or hidden.
  /// - `themeVisibility`: whether the theme section is editable, read-only, or hidden.
  /// - `scaleVisibility`: whether the scale section is editable, read-only, or hidden.
  ///
  /// Return value:
  /// - A new `LayoutEditor`.
  ///
  /// Requirements/Preconditions:
  /// - `value` should describe a valid editable layout draft.
  ///
  /// Guarantees/Postconditions:
  /// - The editor remains purely presentational and does not persist changes on
  ///   its own.
  ///
  /// Invariants:
  /// - Persistence and target discovery remain outside the widget.
  const LayoutEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.sharedTheme,
    required this.sharedScale,
    required this.onSharedThemeChanged,
    required this.onSharedScaleChanged,
    this.previewController,
    this.availableTargets = const <LayoutEditorTargetOption>[],
    this.targetVisibility = LayoutEditorFieldVisibility.editable,
    this.themeVisibility = LayoutEditorFieldVisibility.editable,
    this.scaleVisibility = LayoutEditorFieldVisibility.editable,
  });

  /// Purpose:
  /// Emit one next layout draft through the public callback and optional preview.
  ///
  /// Parameters:
  /// - `nextValue`: full next draft after one user interaction.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `nextValue` should describe a valid editable layout draft.
  ///
  /// Guarantees/Postconditions:
  /// - `onChanged` is invoked synchronously with `nextValue`.
  /// - The preview controller receives a best-effort preview request when present.
  ///
  /// Invariants:
  /// - The widget does not persist layout changes on its own.
  void _emitValue(dp.LayoutDraft nextValue) {
    onChanged(nextValue);
    final EditorPreviewController<dp.LayoutDraft>? controller = previewController;
    if (controller != null) {
      unawaited(controller.preview(nextValue));
    }
  }

  /// Purpose:
  /// Return the currently selected target option, if any.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Matching `LayoutEditorTargetOption`, or `null` for shared/unknown targets.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Matching is based on the current draft's `scope.targetKey`.
  ///
  /// Invariants:
  /// - Reading this helper does not mutate widget state.
  LayoutEditorTargetOption? _selectedTargetOption() {
    final String? targetKey = value.scope.targetKey;
    if (targetKey == null || targetKey.isEmpty) {
      return null;
    }
    for (final LayoutEditorTargetOption option in availableTargets) {
      if (option.targetKey == targetKey) {
        return option;
      }
    }
    return null;
  }

  /// Purpose:
  /// Open the target picker dialog and apply the chosen scope.
  ///
  /// Parameters:
  /// - `context`: build context used to present the picker dialog.
  ///
  /// Return value:
  /// - A future that completes once the picker is dismissed.
  ///
  /// Requirements/Preconditions:
  /// - `context` must be able to present dialogs.
  ///
  /// Guarantees/Postconditions:
  /// - Choosing "shared" emits a shared scope.
  /// - Choosing a target option emits a targeted scope with that target key.
  ///
  /// Invariants:
  /// - Target discovery remains host-owned.
  Future<void> _openTargetPicker(BuildContext context) async {
    final dp.LayoutScopeSettings? nextScope =
        await showDialog<dp.LayoutScopeSettings>(
      context: context,
      builder: (BuildContext dialogContext) {
        return SimpleDialog(
          title: const Text('Choose Target'),
          children: <Widget>[
            SimpleDialogOption(
              key: const Key('layout-target-option-shared'),
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  const dp.LayoutScopeSettings.shared(),
                );
              },
              child: const Text('SHARED'),
            ),
            for (final LayoutEditorTargetOption option in availableTargets)
              SimpleDialogOption(
                key: Key('layout-target-option-${option.targetKey}'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    dp.LayoutScopeSettings.targeted(option.targetKey),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(option.appName),
                    const SizedBox(height: 2),
                    Text(
                      option.entityName,
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );

    if (nextScope != null) {
      _emitValue(value.copyWith(scope: nextScope));
    }
  }

  /// Purpose:
  /// Build the generic theme-editor value from the current layout draft and
  /// host-owned shared theme.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Shared/override editor value for the reusable theme editor.
  ///
  /// Requirements/Preconditions:
  /// - `sharedTheme` should reflect the current host-owned shared theme.
  ///
  /// Guarantees/Postconditions:
  /// - The returned value preserves any dormant override stored in the draft.
  ///
  /// Invariants:
  /// - This helper is pure.
  SharedOverrideEditorValue<dp.ThemeData> _themeEditorValue() {
    return SharedOverrideEditorValue<dp.ThemeData>(
      activeSource: value.themeChoice.activeSource,
      sharedValue: sharedTheme,
      overrideValue: value.themeChoice.overrideTheme,
    );
  }

  /// Purpose:
  /// Build the generic scale-editor value from the current layout draft and
  /// host-owned shared scale.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Shared/override editor value for the reusable scale editor.
  ///
  /// Requirements/Preconditions:
  /// - `sharedScale` should reflect the current host-owned shared scale.
  ///
  /// Guarantees/Postconditions:
  /// - The returned value preserves any dormant override stored in the draft.
  ///
  /// Invariants:
  /// - This helper is pure.
  SharedOverrideEditorValue<dp.ScaleData> _scaleEditorValue() {
    return SharedOverrideEditorValue<dp.ScaleData>(
      activeSource: value.scaleChoice.activeSource,
      sharedValue: sharedScale,
      overrideValue: value.scaleChoice.overrideScale,
    );
  }

  /// Purpose:
  /// Convert one reusable theme-editor result back into the stored layout draft
  /// choice contract while forwarding shared edits to the host.
  ///
  /// Parameters:
  /// - `nextValue`: reusable editor value returned by the theme editor.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `nextValue` should describe a valid theme editor state.
  ///
  /// Guarantees/Postconditions:
  /// - Shared theme edits are forwarded through `onSharedThemeChanged`.
  /// - Layout override metadata is updated through `_emitValue`.
  ///
  /// Invariants:
  /// - Theme persistence remains host-controlled.
  void _applyThemeEditorValue(SharedOverrideEditorValue<dp.ThemeData> nextValue) {
    if (nextValue.sharedValue != sharedTheme) {
      onSharedThemeChanged(nextValue.sharedValue);
    }
    final dp.LayoutThemeChoice nextChoice =
        nextValue.activeSource == dp.LayoutChoiceActiveSource.overrideValue
            ? dp.LayoutThemeChoice.overrideValue(
                nextValue.overrideValue ?? nextValue.sharedValue,
              )
            : dp.LayoutThemeChoice.shared(
                overrideTheme: nextValue.overrideValue,
              );
    if (nextChoice != value.themeChoice) {
      _emitValue(value.copyWith(themeChoice: nextChoice));
    }
  }

  /// Purpose:
  /// Convert one reusable scale-editor result back into the stored layout draft
  /// choice contract while forwarding shared edits to the host.
  ///
  /// Parameters:
  /// - `nextValue`: reusable editor value returned by the scale editor.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `nextValue` should describe a valid scale editor state.
  ///
  /// Guarantees/Postconditions:
  /// - Shared scale edits are forwarded through `onSharedScaleChanged`.
  /// - Layout override metadata is updated through `_emitValue`.
  ///
  /// Invariants:
  /// - Scale persistence remains host-controlled.
  void _applyScaleEditorValue(SharedOverrideEditorValue<dp.ScaleData> nextValue) {
    if (nextValue.sharedValue != sharedScale) {
      onSharedScaleChanged(nextValue.sharedValue);
    }
    final dp.LayoutScaleChoice nextChoice =
        nextValue.activeSource == dp.LayoutChoiceActiveSource.overrideValue
            ? dp.LayoutScaleChoice.overrideValue(
                nextValue.overrideValue ?? nextValue.sharedValue,
              )
            : dp.LayoutScaleChoice.shared(
                overrideScale: nextValue.overrideValue,
              );
    if (nextChoice != value.scaleChoice) {
      _emitValue(value.copyWith(scaleChoice: nextChoice));
    }
  }

  /// Purpose:
  ///   Adapt the layout-level preview controller to the inline theme editor's
  ///   theme-only preview interface.
  ///
  /// Parameters:
  ///   - None.
  ///
  /// Return value:
  ///   - Preview adapter for the current layout draft, or `null` when no layout
  ///     preview controller was supplied.
  ///
  /// Requirements/Preconditions:
  ///   - The current draft should already represent the full layout state that
  ///     should wrap inline theme previews.
  ///
  /// Guarantees/Postconditions:
  ///   - Previewing a theme preserves the editor's shared/override active source
  ///     and forwards shared-value edits through `onSharedThemeChanged`.
  ///
  /// Invariants:
  ///   - Preview clear delegates to the outer layout preview controller.
  EditorPreviewController<SharedOverrideEditorValue<dp.ThemeData>>?
      _themePreviewController() {
    final EditorPreviewController<dp.LayoutDraft>? controller = previewController;
    if (controller == null) {
      return null;
    }
    return _LayoutThemePreviewController(
      baseDraft: value,
      onSharedThemeChanged: onSharedThemeChanged,
      layoutPreviewController: controller,
    );
  }

  /// Purpose:
  ///   Adapt the layout-level preview controller to the shared/override scale
  ///   editor's preview interface.
  ///
  /// Parameters:
  ///   - None.
  ///
  /// Return value:
  ///   - Preview adapter for the current layout draft, or `null` when no layout
  ///     preview controller was supplied.
  ///
  /// Requirements/Preconditions:
  ///   - The current draft should already represent the full layout state that
  ///     should wrap scale previews.
  ///
  /// Guarantees/Postconditions:
  ///   - Previewing a scale preserves the editor's shared/override active source
  ///     and forwards shared-value edits through `onSharedScaleChanged`.
  ///
  /// Invariants:
  ///   - Preview clear delegates to the outer layout preview controller.
  EditorPreviewController<SharedOverrideEditorValue<dp.ScaleData>>?
      _scalePreviewController() {
    final EditorPreviewController<dp.LayoutDraft>? controller = previewController;
    if (controller == null) {
      return null;
    }
    return _LayoutScalePreviewController(
      baseDraft: value,
      onSharedScaleChanged: onSharedScaleChanged,
      layoutPreviewController: controller,
    );
  }

  /// Purpose:
  ///   Build one oversized dialog title for the compact theme/scale choice
  ///   pickers.
  ///
  /// Parameters:
  ///   - `context`: Build context used for theme lookup.
  ///   - `label`: Title text to render.
  ///
  /// Return value:
  ///   - Styled title widget for the simple dialog.
  ///
  /// Requirements/Preconditions:
  ///   - `label` should be non-empty.
  ///
  /// Guarantees/Postconditions:
  ///   - The label uses a larger heading style than the default simple dialog
  ///     title.
  ///
  /// Invariants:
  ///   - Building the title does not mutate editor state.
  Widget _buildChoiceDialogTitle(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  /// Purpose:
  ///   Present the compact theme/scale choice dialog using two horizontal
  ///   selection buttons.
  ///
  /// Parameters:
  ///   - `context`: Build context used to present the dialog.
  ///   - `title`: Dialog title text.
  ///   - `currentButtonKey`: Stable key for the Current choice button.
  ///   - `customButtonKey`: Stable key for the Custom choice button.
  ///   - `rowKey`: Stable key for the horizontal choice row.
  ///   - `usesCustomChoice`: Whether the current draft already uses the inline
  ///     custom value.
  ///
  /// Return value:
  ///   - Selected choice id, or `null` when the dialog is dismissed.
  ///
  /// Requirements/Preconditions:
  ///   - `context` must be able to present dialogs.
  ///
  /// Guarantees/Postconditions:
  ///   - The dialog presents two touch-friendly horizontal buttons matching the
  ///     main mode selector style.
  ///
  /// Invariants:
  ///   - Showing the dialog does not mutate editor state until a choice is
  ///     returned.
  Future<String?> _showReferenceChoiceDialog({
    required BuildContext context,
    required String title,
    required Key currentButtonKey,
    required Key customButtonKey,
    required Key rowKey,
    required bool usesCustomChoice,
  }) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildChoiceDialogTitle(dialogContext, title),
                  const SizedBox(height: 24),
                  Row(
                    key: rowKey,
                    children: <Widget>[
                      Expanded(
                        child: _buildChoiceButton(
                          key: currentButtonKey,
                          label: 'CURRENT',
                          selected: !usesCustomChoice,
                          onPressed: () {
                            Navigator.of(dialogContext).pop('current');
                          },
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildChoiceButton(
                          key: customButtonKey,
                          label: 'CUSTOM',
                          selected: usesCustomChoice,
                          onPressed: () {
                            Navigator.of(dialogContext).pop('custom');
                          },
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Purpose:
  /// Build the full musician-facing layout editor.
  ///
  /// Parameters:
  /// - `context`: build context for inherited widget lookup.
  ///
  /// Return value:
  /// - Layout settings controls plus optional target/theme/scale sections.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The returned tree avoids exposing bend range.
  ///
  /// Invariants:
  /// - The widget remains presentational and host-controlled.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compactLayout = constraints.maxWidth < 620;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  compactLayout
                      ? _buildCompactTopLayout(context)
                      : _buildWideTopLayout(context),
                  const SizedBox(height: 12),
                  compactLayout
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _buildIntervalsCard(),
                            const SizedBox(height: 12),
                            _buildTransposeCard(),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: _buildIntervalsCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTransposeCard()),
                          ],
                        ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Purpose:
  /// Build the wide desktop-like top row that matches the hand-drawn mockup.
  ///
  /// Parameters:
  /// - `context`: build context used for dialogs and theming.
  ///
  /// Return value:
  /// - One row containing the dominant mode card and any visible option cards.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Mode expands when optional cards are hidden.
  ///
  /// Invariants:
  /// - Card ordering stays mode, theme, scale, target.
  Widget _buildWideTopLayout(BuildContext context) {
    final List<Widget> trailingCards = <Widget>[
      if (themeVisibility != LayoutEditorFieldVisibility.hidden)
        _buildThemeTopCard(context),
      if (scaleVisibility != LayoutEditorFieldVisibility.hidden)
        _buildScaleTopCard(context),
      if (targetVisibility != LayoutEditorFieldVisibility.hidden)
        _buildTargetTopCard(context),
    ];

    return Row(
      key: const Key('layout-editor-top-row'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: trailingCards.isEmpty ? 1 : 3,
          child: _buildModeCard(),
        ),
        for (int index = 0; index < trailingCards.length; index += 1) ...<Widget>[
          const SizedBox(width: 8),
          Expanded(
            child: trailingCards[index],
          ),
        ],
      ],
    );
  }

  /// Purpose:
  /// Build the compact/narrow top controls when the full desktop row would be
  /// too cramped.
  ///
  /// Parameters:
  /// - `context`: build context used for dialogs and theming.
  ///
  /// Return value:
  /// - Column layout with the mode card first and visible option cards below.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - All top controls remain visible on narrower widths.
  ///
  /// Invariants:
  /// - Control ordering stays mode, theme, scale, target.
  Widget _buildCompactTopLayout(BuildContext context) {
    final List<Widget> trailingCards = <Widget>[
      if (themeVisibility != LayoutEditorFieldVisibility.hidden)
        _buildThemeTopCard(context),
      if (scaleVisibility != LayoutEditorFieldVisibility.hidden)
        _buildScaleTopCard(context),
      if (targetVisibility != LayoutEditorFieldVisibility.hidden)
        _buildTargetTopCard(context),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildModeCard(),
        if (trailingCards.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            key: const Key('layout-editor-top-row'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int index = 0; index < trailingCards.length; index += 1) ...<Widget>[
                if (index > 0) const SizedBox(width: 8),
                Expanded(child: trailingCards[index]),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// Purpose:
  /// Build the dominant mode card shown on the left side of the mockup.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Top-row mode card with large scale/chromatic pill buttons.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The card always presents both mode choices.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildModeCard() {
    return _buildTopCard(
      key: const Key('layout-mode-card'),
      title: 'Mode',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stackedButtons = constraints.maxWidth < 340;
          if (stackedButtons) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildChoiceButton(
                  key: const Key('layout-mode-scale'),
                  label: 'SCALE',
                  selected: value.settings.layoutMode == 'scale',
                  onPressed: () {
                    _emitValue(
                      value.copyWith(
                        settings: value.settings.copyWith(layoutMode: 'scale'),
                      ),
                    );
                  },
                  compact: true,
                ),
                const SizedBox(height: 10),
                _buildChoiceButton(
                  key: const Key('layout-mode-chromatic'),
                  label: 'CHROMATIC',
                  selected: value.settings.layoutMode == 'chromatic',
                  onPressed: () {
                    _emitValue(
                      value.copyWith(
                        settings: value.settings.copyWith(layoutMode: 'chromatic'),
                      ),
                    );
                  },
                  compact: true,
                ),
              ],
            );
          }

          return Row(
            children: <Widget>[
              Expanded(
                child: _buildChoiceButton(
                  key: const Key('layout-mode-scale'),
                  label: 'SCALE',
                  selected: value.settings.layoutMode == 'scale',
                  onPressed: () {
                    _emitValue(
                      value.copyWith(
                        settings: value.settings.copyWith(layoutMode: 'scale'),
                      ),
                    );
                  },
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildChoiceButton(
                  key: const Key('layout-mode-chromatic'),
                  label: 'CHROMATIC',
                  selected: value.settings.layoutMode == 'chromatic',
                  onPressed: () {
                    _emitValue(
                      value.copyWith(
                        settings: value.settings.copyWith(layoutMode: 'chromatic'),
                      ),
                    );
                  },
                  compact: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Purpose:
  /// Build the compact theme card shown in the top row.
  ///
  /// Parameters:
  /// - `context`: build context used for dialogs and theming.
  ///
  /// Return value:
  /// - Top-row theme card with one status pill button.
  ///
  /// Requirements/Preconditions:
  /// - `themeVisibility` must not be `hidden`.
  ///
  /// Guarantees/Postconditions:
  /// - Editable mode opens the theme choice flow.
  /// - The card shows both the active source and a compact preview summary.
  ///
  /// Invariants:
  /// - Theme data remains host-controlled.
  Widget _buildThemeTopCard(BuildContext context) {
    final bool usesInlineTheme =
        value.themeChoice.activeSource == dp.LayoutChoiceActiveSource.overrideValue;
    final dp.ThemeData previewTheme = usesInlineTheme
        ? (value.themeChoice.overrideTheme ?? sharedTheme)
        : sharedTheme;
    return _buildTopCard(
      key: const Key('layout-theme-card'),
      title: 'Theme',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildChoiceButton(
            key: const Key('layout-theme-button'),
            label: usesInlineTheme ? 'OVERRIDE' : 'SHARED',
            selected: usesInlineTheme,
            onPressed: themeVisibility == LayoutEditorFieldVisibility.readOnly
                ? null
                : () {
                    _openThemeEditor(context);
                  },
            compact: true,
          ),
          const SizedBox(height: 8),
          _buildThemeTopSummary(previewTheme),
        ],
      ),
    );
  }

  /// Purpose:
  /// Build the compact scale card shown in the top row.
  ///
  /// Parameters:
  /// - `context`: build context used for dialogs and theming.
  ///
  /// Return value:
  /// - Top-row scale card with one status pill button.
  ///
  /// Requirements/Preconditions:
  /// - `scaleVisibility` must not be `hidden`.
  ///
  /// Guarantees/Postconditions:
  /// - Editable mode opens the scale choice flow.
  /// - The card shows both the active source and a compact preview summary.
  ///
  /// Invariants:
  /// - Scale data remains host-controlled.
  Widget _buildScaleTopCard(BuildContext context) {
    final bool usesInlineScale =
        value.scaleChoice.activeSource == dp.LayoutChoiceActiveSource.overrideValue;
    final dp.ScaleData previewScale = usesInlineScale
        ? (value.scaleChoice.overrideScale ?? sharedScale)
        : sharedScale;
    return _buildTopCard(
      key: const Key('layout-scale-card'),
      title: 'Scale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildChoiceButton(
            key: const Key('layout-scale-button'),
            label: usesInlineScale ? 'OVERRIDE' : 'SHARED',
            selected: usesInlineScale,
            onPressed: scaleVisibility == LayoutEditorFieldVisibility.readOnly
                ? null
                : () {
                    _openScaleEditor(context);
                  },
            compact: true,
          ),
          const SizedBox(height: 8),
          _buildScaleTopSummary(previewScale),
        ],
      ),
    );
  }

  /// Purpose:
  /// Build the compact swatch summary shown under the theme source button.
  ///
  /// Parameters:
  /// - `themeData`: active theme whose four role colors should be previewed.
  ///
  /// Return value:
  /// - Non-interactive row of four compact color swatches.
  ///
  /// Requirements/Preconditions:
  /// - `themeData` should contain valid hex color strings.
  ///
  /// Guarantees/Postconditions:
  /// - The row always shows the four active theme role colors in a stable order.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildThemeTopSummary(dp.ThemeData themeData) {
    final List<String> colors = <String>[
      themeData.primaryColor,
      themeData.secondaryColor,
      themeData.accentColor,
      themeData.backgroundColor,
    ];
    return Row(
      key: const Key('layout-theme-preview-swatches'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(colors.length, (int index) {
        return Padding(
          padding: EdgeInsets.only(right: index == colors.length - 1 ? 0 : 8),
          child: DecoratedBox(
            key: Key('layout-theme-swatch-$index'),
            decoration: BoxDecoration(
              color: _colorFromHex(colors[index]),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF5A5A5A),
              ),
            ),
            child: const SizedBox(width: 16, height: 16),
          ),
        );
      }),
    );
  }

  /// Purpose:
  /// Build the compact scale summary shown under the scale source button.
  ///
  /// Parameters:
  /// - `scaleData`: active scale whose label should be summarized.
  ///
  /// Return value:
  /// - Centered compact scale summary label.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Prefers `displayName` when present, otherwise falls back to a detected
  ///   named-scale label.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildScaleTopSummary(dp.ScaleData scaleData) {
    final String summaryText = _scaleSummaryText(scaleData);
    return Text(
      summaryText,
      key: const Key('layout-scale-summary'),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFFD7D7D7),
      ),
    );
  }

  /// Purpose:
  /// Convert one stored scale value into the compact summary label used by the
  /// top-row scale card.
  ///
  /// Parameters:
  /// - `scaleData`: scale value to summarize.
  ///
  /// Return value:
  /// - Display name when present, otherwise a detected named-scale label.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The returned string is non-empty.
  ///
  /// Invariants:
  /// - This helper is pure.
  String _scaleSummaryText(dp.ScaleData scaleData) {
    final String? displayName = scaleData.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return dp.ScaleCatalog.detectScaleName(scaleData);
  }

  /// Purpose:
  /// Convert one `#rrggbb` theme color string into a Flutter `Color`.
  ///
  /// Parameters:
  /// - `hexColor`: hex color string with or without a leading `#`.
  ///
  /// Return value:
  /// - Opaque Flutter color for the supplied RGB value.
  ///
  /// Requirements/Preconditions:
  /// - `hexColor` should be a six-digit RGB hex string.
  ///
  /// Guarantees/Postconditions:
  /// - Invalid input falls back to opaque black instead of throwing.
  ///
  /// Invariants:
  /// - This helper is pure.
  Color _colorFromHex(String hexColor) {
    final String normalized = hexColor.replaceFirst('#', '');
    if (normalized.length != 6) {
      return const Color(0xFF000000);
    }
    final int? parsedValue = int.tryParse(normalized, radix: 16);
    if (parsedValue == null) {
      return const Color(0xFF000000);
    }
    return Color(0xFF000000 | parsedValue);
  }

  /// Purpose:
  /// Build the compact target card shown in the top row.
  ///
  /// Parameters:
  /// - `context`: build context used for dialogs and theming.
  ///
  /// Return value:
  /// - Top-row target card with one status pill button.
  ///
  /// Requirements/Preconditions:
  /// - `targetVisibility` must not be `hidden`.
  ///
  /// Guarantees/Postconditions:
  /// - Editable mode opens the target picker.
  ///
  /// Invariants:
  /// - Target discovery remains host-owned.
  Widget _buildTargetTopCard(BuildContext context) {
    final LayoutEditorTargetOption? selectedOption = _selectedTargetOption();
    final bool isShared = value.scope.scope == 'shared';
    final String targetLabel = isShared
        ? 'SHARED'
        : (selectedOption?.entityName ?? value.scope.targetKey ?? 'TARGET');
    return _buildTopCard(
      key: const Key('layout-target-card'),
      title: 'Target',
      child: _buildChoiceButton(
        key: const Key('layout-target-button'),
        label: targetLabel,
        selected: !isShared,
        onPressed: targetVisibility == LayoutEditorFieldVisibility.readOnly
            ? null
            : () {
                _openTargetPicker(context);
              },
        compact: true,
      ),
    );
  }

  /// Purpose:
  /// Build the intervals panel shown on the lower-left side of the mockup.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Intervals card containing row and column controls.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Row and column controls share one common card.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildIntervalsCard() {
    return _buildSectionCard(
      title: 'Intervals',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stacked = constraints.maxWidth < 320;
          final Widget rowControl = _buildIntervalControl(
            label: 'Row',
            valueText: '${_displayedRowInterval()}',
            decrementKey: const Key('layout-row-interval-decrement'),
            incrementKey: const Key('layout-row-interval-increment'),
            directionKey: const Key('layout-row-direction-toggle'),
            directionLabel: 'FLIP',
            onDecrement: () {
              _emitValue(
                _copyWithDisplayedRowInterval(_displayedRowInterval() - 1),
              );
            },
            onIncrement: () {
              _emitValue(
                _copyWithDisplayedRowInterval(_displayedRowInterval() + 1),
              );
            },
            onToggleDirection: () {
              _emitValue(_copyWithDisplayedRowInterval(-_displayedRowInterval()));
            },
          );
          final Widget columnControl = _buildIntervalControl(
            label: 'Column',
            valueText: '${_displayedColumnInterval()}',
            decrementKey: const Key('layout-column-interval-decrement'),
            incrementKey: const Key('layout-column-interval-increment'),
            directionKey: const Key('layout-column-direction-toggle'),
            directionLabel: 'FLIP',
            onDecrement: () {
              _emitValue(
                _copyWithDisplayedColumnInterval(_displayedColumnInterval() - 1),
              );
            },
            onIncrement: () {
              _emitValue(
                _copyWithDisplayedColumnInterval(_displayedColumnInterval() + 1),
              );
            },
            onToggleDirection: () {
              _emitValue(
                _copyWithDisplayedColumnInterval(-_displayedColumnInterval()),
              );
            },
          );

          if (stacked) {
            return Column(
              children: <Widget>[
                rowControl,
                const SizedBox(height: 12),
                columnControl,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: rowControl),
              const SizedBox(width: 16),
              Expanded(child: columnControl),
            ],
          );
        },
      ),
    );
  }

  /// Purpose:
  /// Build the transpose panel shown on the lower-right side of the mockup.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Transpose card containing octave and semitone controls.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Octave and semitone controls share one common card.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildTransposeCard() {
    return _buildSectionCard(
      title: 'Transpose',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stacked = constraints.maxWidth < 320;
          final Widget octaveControl = _buildStepperControl(
            label: 'Octave',
            valueText: _signedValueText(value.settings.octaveTranspose),
            decrementKey: const Key('layout-octave-decrement'),
            incrementKey: const Key('layout-octave-increment'),
            onDecrement: () {
              _emitValue(
                value.copyWith(
                  settings: value.settings.copyWith(
                    octaveTranspose: value.settings.octaveTranspose - 1,
                  ),
                ),
              );
            },
            onIncrement: () {
              _emitValue(
                value.copyWith(
                  settings: value.settings.copyWith(
                    octaveTranspose: value.settings.octaveTranspose + 1,
                  ),
                ),
              );
            },
          );
          final Widget semitoneControl = _buildStepperControl(
            label: 'Semitone',
            valueText: _signedValueText(value.settings.semitoneTranspose),
            decrementKey: const Key('layout-semitone-decrement'),
            incrementKey: const Key('layout-semitone-increment'),
            onDecrement: () {
              _emitValue(
                value.copyWith(
                  settings: value.settings.copyWith(
                    semitoneTranspose: value.settings.semitoneTranspose - 1,
                  ),
                ),
              );
            },
            onIncrement: () {
              _emitValue(
                value.copyWith(
                  settings: value.settings.copyWith(
                    semitoneTranspose: value.settings.semitoneTranspose + 1,
                  ),
                ),
              );
            },
          );

          if (stacked) {
            return Column(
              children: <Widget>[
                octaveControl,
                const SizedBox(height: 12),
                semitoneControl,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: octaveControl),
              const SizedBox(width: 16),
              Expanded(child: semitoneControl),
            ],
          );
        },
      ),
    );
  }

  /// Purpose:
  /// Open the theme editor dialog directly from the compact top-row card.
  ///
  /// Parameters:
  /// - `context`: build context used to present dialogs.
  ///
  /// Return value:
  /// - A future that completes once the dialog closes.
  ///
  /// Requirements/Preconditions:
  /// - `context` must be able to present dialogs.
  ///
  /// Guarantees/Postconditions:
  /// - Confirming the dialog updates both the shared theme callback and the
  ///   stored layout override metadata.
  ///
  /// Invariants:
  /// - Theme storage remains host-controlled.
  Future<void> _openThemeEditor(BuildContext context) async {
    final SharedOverrideEditorValue<dp.ThemeData>? nextValue =
        await showThemeEditorDialog(
      context: context,
      initialValue: _themeEditorValue(),
      previewController: _themePreviewController(),
      showSourceSelector: true,
    );
    if (nextValue != null) {
      _applyThemeEditorValue(nextValue);
    }
  }

  /// Purpose:
  /// Open the scale editor dialog directly from the compact top-row card.
  ///
  /// Parameters:
  /// - `context`: build context used to present dialogs.
  ///
  /// Return value:
  /// - A future that completes once the dialog closes.
  ///
  /// Requirements/Preconditions:
  /// - `context` must be able to present dialogs.
  ///
  /// Guarantees/Postconditions:
  /// - Confirming the dialog updates both the shared scale callback and the
  ///   stored layout override metadata.
  ///
  /// Invariants:
  /// - Scale storage remains host-controlled.
  Future<void> _openScaleEditor(BuildContext context) async {
    final SharedOverrideEditorValue<dp.ScaleData>? nextValue =
        await showScaleEditorDialog(
      context: context,
      initialValue: _scaleEditorValue(),
      previewController: _scalePreviewController(),
      showSourceSelector: true,
    );
    if (nextValue != null) {
      _applyScaleEditorValue(nextValue);
    }
  }

  /// Purpose:
  /// Build one compact top-row card with a smaller header and tighter padding.
  ///
  /// Parameters:
  /// - `key`: stable widget key for tests and diagnostics.
  /// - `title`: user-facing card title.
  /// - `child`: card body widget.
  ///
  /// Return value:
  /// - Decorated compact card.
  ///
  /// Requirements/Preconditions:
  /// - `title` should be concise and user-facing.
  ///
  /// Guarantees/Postconditions:
  /// - The card matches the compact top-row style.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildTopCard({
    required Key key,
    required String title,
    required Widget child,
  }) {
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4A4A4A)),
        color: const Color(0xFF181818),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  /// Purpose:
  /// Format integer transpose values with explicit plus signs for positive values.
  ///
  /// Parameters:
  /// - `value`: signed integer to format.
  ///
  /// Return value:
  /// - Signed display string such as `+1`, `0`, or `-2`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Positive values always include a leading `+`.
  ///
  /// Invariants:
  /// - This helper is pure.
  String _signedValueText(int value) {
    if (value > 0) {
      return '+$value';
    }
    return '$value';
  }

  /// Purpose:
  /// Return the row interval as the musician-facing signed value shown by the
  /// editor.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Signed row interval value with the legacy direction flag folded in.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Negative values mean pitch moves in the opposite direction.
  ///
  /// Invariants:
  /// - This helper is pure.
  int _displayedRowInterval() {
    return value.settings.rowIntervalUp
        ? value.settings.rowInterval
        : -value.settings.rowInterval;
  }

  /// Purpose:
  /// Return the column interval as the musician-facing signed value shown by the
  /// editor.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Signed column interval value with the legacy direction flag folded in.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Negative values mean pitch moves in the opposite direction.
  ///
  /// Invariants:
  /// - This helper is pure.
  int _displayedColumnInterval() {
    return value.settings.columnIntervalRight
        ? value.settings.columnInterval
        : -value.settings.columnInterval;
  }

  /// Purpose:
  /// Produce one next draft whose row interval matches the signed value the user
  /// sees in the editor.
  ///
  /// Parameters:
  /// - `displayedInterval`: signed row interval chosen through the editor UI.
  ///
  /// Return value:
  /// - Next draft with the row interval updated.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The stored draft is normalized so the editor uses the signed interval as
  ///   the single visible direction source.
  ///
  /// Invariants:
  /// - Column and transpose settings remain unchanged.
  dp.LayoutDraft _copyWithDisplayedRowInterval(int displayedInterval) {
    return value.copyWith(
      settings: value.settings.copyWith(
        rowInterval: displayedInterval,
        rowIntervalUp: true,
      ),
    );
  }

  /// Purpose:
  /// Produce one next draft whose column interval matches the signed value the
  /// user sees in the editor.
  ///
  /// Parameters:
  /// - `displayedInterval`: signed column interval chosen through the editor UI.
  ///
  /// Return value:
  /// - Next draft with the column interval updated.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The stored draft is normalized so the editor uses the signed interval as
  ///   the single visible direction source.
  ///
  /// Invariants:
  /// - Row and transpose settings remain unchanged.
  dp.LayoutDraft _copyWithDisplayedColumnInterval(int displayedInterval) {
    return value.copyWith(
      settings: value.settings.copyWith(
        columnInterval: displayedInterval,
        columnIntervalRight: true,
      ),
    );
  }

  /// Purpose:
  /// Build one consistent section shell for the layout editor.
  ///
  /// Parameters:
  /// - `title`: section heading text.
  /// - `child`: section body widget.
  ///
  /// Return value:
  /// - Decorated card containing the supplied title and body.
  ///
  /// Requirements/Preconditions:
  /// - `title` should be short and user-facing.
  ///
  /// Guarantees/Postconditions:
  /// - All sections share consistent spacing and framing.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildSectionCard({
    required String title,
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4A4A4A)),
        color: const Color(0xFF181818),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  /// Purpose:
  /// Build one wide two-state choice button used by musician-facing sections.
  ///
  /// Parameters:
  /// - `key`: stable widget key for tests and diagnostics.
  /// - `label`: user-facing button text.
  /// - `selected`: whether the button is the current selection.
  /// - `onPressed`: action to run when tapped.
  ///
  /// Return value:
  /// - Touch-friendly selection button.
  ///
  /// Requirements/Preconditions:
  /// - `label` should be concise and user-facing.
  ///
  /// Guarantees/Postconditions:
  /// - Selected buttons are visually emphasized.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildChoiceButton({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
    bool compact = false,
  }) {
    final Size minimumSize = compact ? const Size(0, 50) : const Size(180, 56);
    final OutlinedBorder shape = const StadiumBorder();
    final ButtonStyle style = selected
        ? FilledButton.styleFrom(
            minimumSize: minimumSize,
            shape: shape,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 18, vertical: 14)
                : null,
          )
        : OutlinedButton.styleFrom(
            minimumSize: minimumSize,
            shape: shape,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 18, vertical: 14)
                : null,
          );
    final Widget child = Text(label);
    if (selected) {
      return FilledButton(
        key: key,
        onPressed: onPressed,
        style: style,
        child: child,
      );
    }
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }

  /// Purpose:
  /// Build one numeric stepper control with large increment/decrement buttons.
  ///
  /// Parameters:
  /// - `label`: user-facing field label.
  /// - `valueText`: formatted numeric value text.
  /// - `decrementKey`: stable key for the decrement button.
  /// - `incrementKey`: stable key for the increment button.
  /// - `onDecrement`: callback for the decrement button.
  /// - `onIncrement`: callback for the increment button.
  ///
  /// Return value:
  /// - Decorated stepper row.
  ///
  /// Requirements/Preconditions:
  /// - `valueText` should describe the current field value.
  ///
  /// Guarantees/Postconditions:
  /// - The control is touch-friendly and centered.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildSymbolButton({
    required Key key,
    required String symbol,
    required VoidCallback onPressed,
    Size minimumSize = const Size(48, 48),
    double fontSize = 24,
  }) {
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: minimumSize,
        shape: const StadiumBorder(),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        symbol,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Purpose:
  /// Build one numeric stepper control with large increment/decrement buttons.
  ///
  /// Parameters:
  /// - `label`: user-facing field label.
  /// - `valueText`: formatted numeric value text.
  /// - `decrementKey`: stable key for the decrement button.
  /// - `incrementKey`: stable key for the increment button.
  /// - `onDecrement`: callback for the decrement button.
  /// - `onIncrement`: callback for the increment button.
  ///
  /// Return value:
  /// - Decorated stepper row.
  ///
  /// Requirements/Preconditions:
  /// - `valueText` should describe the current field value.
  ///
  /// Guarantees/Postconditions:
  /// - The control is touch-friendly and centered.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildStepperControl({
    required String label,
    required String valueText,
    required Key decrementKey,
    required Key incrementKey,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5A5A5A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compactControls = constraints.maxWidth < 180;
            final Size buttonSize = compactControls
                ? const Size(32, 40)
                : const Size(48, 48);
            final double spacing = compactControls ? 4 : 10;
            final double valueWidth = compactControls ? 40 : 60;
            final double valueFontSize = compactControls ? 24 : 28;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _buildSymbolButton(
                      key: decrementKey,
                      symbol: '-',
                      onPressed: onDecrement,
                      minimumSize: buttonSize,
                      fontSize: compactControls ? 20 : 24,
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: valueWidth,
                      child: Center(
                        child: Text(
                          valueText,
                          style: TextStyle(
                            fontSize: valueFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: spacing),
                    _buildSymbolButton(
                      key: incrementKey,
                      symbol: '+',
                      onPressed: onIncrement,
                      minimumSize: buttonSize,
                      fontSize: compactControls ? 20 : 24,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Purpose:
  /// Build one interval control including the direction toggle.
  ///
  /// Parameters:
  /// - `label`: user-facing field label.
  /// - `valueText`: formatted interval text.
  /// - `decrementKey`: stable key for the decrement button.
  /// - `incrementKey`: stable key for the increment button.
  /// - `directionKey`: stable key for the direction toggle.
  /// - `directionLabel`: user-facing direction label.
  /// - `onDecrement`: callback for the decrement button.
  /// - `onIncrement`: callback for the increment button.
  /// - `onToggleDirection`: callback for the direction toggle.
  ///
  /// Return value:
  /// - Decorated interval control.
  ///
  /// Requirements/Preconditions:
  /// - `directionLabel` should be user-facing and concise.
  ///
  /// Guarantees/Postconditions:
  /// - The direction toggle sits alongside the numeric stepper.
  ///
  /// Invariants:
  /// - This helper is pure.
  Widget _buildIntervalControl({
    required String label,
    required String valueText,
    required Key decrementKey,
    required Key incrementKey,
    required Key directionKey,
    required String directionLabel,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
    required VoidCallback onToggleDirection,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5A5A5A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compactControls = constraints.maxWidth < 180;
            final Size buttonSize = compactControls
                ? const Size(32, 40)
                : const Size(48, 48);
            final double spacing = compactControls ? 4 : 10;
            final double valueWidth = compactControls ? 40 : 60;
            final double valueFontSize = compactControls ? 24 : 28;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _buildSymbolButton(
                      key: decrementKey,
                      symbol: '-',
                      onPressed: onDecrement,
                      minimumSize: buttonSize,
                      fontSize: compactControls ? 20 : 24,
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: valueWidth,
                      child: Center(
                        child: Text(
                          valueText,
                          style: TextStyle(
                            fontSize: valueFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: spacing),
                    _buildSymbolButton(
                      key: incrementKey,
                      symbol: '+',
                      onPressed: onIncrement,
                      minimumSize: buttonSize,
                      fontSize: compactControls ? 20 : 24,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Center(
                  child: FilledButton.tonal(
                    key: directionKey,
                    onPressed: onToggleDirection,
                    style: FilledButton.styleFrom(
                    minimumSize: Size(compactControls ? 84 : 96, 42),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(directionLabel),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Purpose:
  /// Build the target section according to the configured visibility mode.
  ///
  /// Parameters:
  /// - `context`: build context used for dialogs and theming.
  ///
  /// Return value:
  /// - Visible target section widget.
  ///
  /// Requirements/Preconditions:
  /// - `targetVisibility` must not be `hidden`.
  ///
  /// Guarantees/Postconditions:
  /// - Editable mode exposes the picker button.
  /// - Read-only mode shows the current target summary only.
  ///
  /// Invariants:
  /// - This helper does not fetch targets itself.
  Widget _buildTargetSection(BuildContext context) {
    final LayoutEditorTargetOption? selectedOption = _selectedTargetOption();
    final String targetLabel = value.scope.scope == 'shared'
        ? 'SHARED'
        : (selectedOption?.label ?? value.scope.targetKey ?? 'UNKNOWN TARGET');

    if (targetVisibility == LayoutEditorFieldVisibility.readOnly) {
      return _buildSectionCard(
        title: 'Target',
        child: Text(
          targetLabel,
          style: const TextStyle(fontSize: 18),
        ),
      );
    }

    return _buildSectionCard(
      title: 'Target',
      child: FilledButton.tonal(
        key: const Key('layout-target-button'),
        onPressed: () {
          _openTargetPicker(context);
        },
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
        ),
        child: Text(targetLabel),
      ),
    );
  }

  /// Purpose:
  /// Build the theme section according to the configured visibility mode.
  ///
  /// Parameters:
  /// - `context`: build context used for dialogs and theming.
  ///
  /// Return value:
  /// - Visible theme section widget.
  ///
  /// Requirements/Preconditions:
  /// - `themeVisibility` must not be `hidden`.
  ///
  /// Guarantees/Postconditions:
  /// - Editable mode can switch between current and inline theme choices.
  ///
  /// Invariants:
  /// - Theme storage remains outside the widget.
  Widget _buildThemeSection(BuildContext context) {
    final bool usesInlineTheme =
        value.themeChoice.activeSource == dp.LayoutChoiceActiveSource.overrideValue;
    final String summary = usesInlineTheme
        ? (value.themeChoice.overrideTheme?.displayName ?? 'Override Theme')
        : 'Shared Theme';

    if (themeVisibility == LayoutEditorFieldVisibility.readOnly) {
      return _buildSectionCard(
        title: 'Theme',
        child: Text(summary),
      );
    }

    return _buildSectionCard(
      title: 'Theme',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _buildChoiceButton(
                key: const Key('layout-theme-current'),
                label: 'SHARED',
                selected: !usesInlineTheme,
                onPressed: () {
                  _emitValue(
                    value.copyWith(
                      themeChoice: dp.LayoutThemeChoice.shared(
                        overrideTheme: value.themeChoice.overrideTheme,
                      ),
                    ),
                  );
                },
              ),
              _buildChoiceButton(
                key: const Key('layout-theme-inline'),
                label: 'OVERRIDE',
                selected: usesInlineTheme,
                onPressed: () {
                  _emitValue(
                    value.copyWith(
                      themeChoice: usesInlineTheme
                          ? value.themeChoice
                          : dp.LayoutThemeChoice.overrideValue(
                              value.themeChoice.overrideTheme ??
                                  const dp.ThemeData(
                                displayName: 'Inline Theme',
                                primaryColor: '#ff6f61',
                                secondaryColor: '#4fc3f7',
                                accentColor: '#ffd54f',
                                backgroundColor: '#1b1c1d',
                              ),
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(summary),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('layout-theme-edit-inline'),
            onPressed: () {
              _openThemeEditor(context);
            },
            child: const Text('Edit Theme'),
          ),
        ],
      ),
    );
  }

  /// Purpose:
  /// Build the scale section according to the configured visibility mode.
  ///
  /// Parameters:
  /// - `context`: build context used for dialogs and theming.
  ///
  /// Return value:
  /// - Visible scale section widget.
  ///
  /// Requirements/Preconditions:
  /// - `scaleVisibility` must not be `hidden`.
  ///
  /// Guarantees/Postconditions:
  /// - Editable mode can switch between current and inline scale choices.
  ///
  /// Invariants:
  /// - Scale storage remains outside the widget.
  Widget _buildScaleSection(BuildContext context) {
    final bool usesInlineScale =
        value.scaleChoice.activeSource == dp.LayoutChoiceActiveSource.overrideValue;
    final String summary = usesInlineScale
        ? (value.scaleChoice.overrideScale?.displayName ?? 'Override Scale')
        : 'Shared Scale';

    if (scaleVisibility == LayoutEditorFieldVisibility.readOnly) {
      return _buildSectionCard(
        title: 'Scale',
        child: Text(summary),
      );
    }

    return _buildSectionCard(
      title: 'Scale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _buildChoiceButton(
                key: const Key('layout-scale-current'),
                label: 'SHARED',
                selected: !usesInlineScale,
                onPressed: () {
                  _emitValue(
                    value.copyWith(
                      scaleChoice: dp.LayoutScaleChoice.shared(
                        overrideScale: value.scaleChoice.overrideScale,
                      ),
                    ),
                  );
                },
              ),
              _buildChoiceButton(
                key: const Key('layout-scale-inline'),
                label: 'OVERRIDE',
                selected: usesInlineScale,
                onPressed: () {
                  _emitValue(
                    value.copyWith(
                      scaleChoice: usesInlineScale
                          ? value.scaleChoice
                          : dp.LayoutScaleChoice.overrideValue(
                              value.scaleChoice.overrideScale ??
                                  dp.ScaleCatalog.scaleDataForName(
                                scaleName: 'Major',
                                rootNote: 0,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(summary),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('layout-scale-edit-inline'),
            onPressed: () {
              _openScaleEditor(context);
            },
            child: const Text('Edit Scale'),
          ),
        ],
      ),
    );
  }
}

/// Adapter that wraps layout preview ownership for shared/override theme flows.
class _LayoutThemePreviewController
    implements EditorPreviewController<SharedOverrideEditorValue<dp.ThemeData>> {
  final dp.LayoutDraft baseDraft;
  final ValueChanged<dp.ThemeData> onSharedThemeChanged;
  final EditorPreviewController<dp.LayoutDraft> layoutPreviewController;

  /// Purpose:
  ///   Bridge theme editor previews into layout-draft previews while preserving
  ///   shared-versus-override isolation.
  ///
  /// Parameters:
  ///   - `baseDraft`: Layout draft that should wrap each previewed theme choice.
  ///   - `onSharedThemeChanged`: Host callback for System shared theme writes.
  ///   - `layoutPreviewController`: Host-owned layout preview controller.
  ///
  /// Return value:
  ///   - A new `_LayoutThemePreviewController`.
  ///
  /// Requirements/Preconditions:
  ///   - `baseDraft` should already represent the non-theme parts of the layout
  ///     being edited.
  ///
  /// Guarantees/Postconditions:
  ///   - Preview and clear requests forward into `layoutPreviewController`.
  ///
  /// Invariants:
  ///   - This adapter never persists edits on its own.
  const _LayoutThemePreviewController({
    required this.baseDraft,
    required this.onSharedThemeChanged,
    required this.layoutPreviewController,
  });

  /// Purpose:
  ///   Preview one theme editor value as a full layout draft update.
  ///
  /// Parameters:
  ///   - `value`: Shared/override theme editor candidate being previewed.
  ///
  /// Return value:
  ///   - A future that completes when the host preview controller finishes.
  ///
  /// Requirements/Preconditions:
  ///   - `value` should describe a valid theme editor state.
  ///
  /// Guarantees/Postconditions:
  ///   - Shared-mode previews keep `themeChoice.activeSource` as shared and
  ///     forward `sharedValue` through `onSharedThemeChanged`.
  ///   - Override-mode previews update only the layout override payload.
  ///
  /// Invariants:
  ///   - The wrapped layout draft keeps its existing scale, scope, and settings.
  @override
  Future<void> preview(SharedOverrideEditorValue<dp.ThemeData> value) async {
    if (value.activeSource == dp.LayoutChoiceActiveSource.shared) {
      onSharedThemeChanged(value.sharedValue);
    }
    final dp.LayoutThemeChoice themeChoice =
        value.activeSource == dp.LayoutChoiceActiveSource.overrideValue
            ? dp.LayoutThemeChoice.overrideValue(
                value.overrideValue ?? value.sharedValue,
              )
            : dp.LayoutThemeChoice.shared(
                overrideTheme: value.overrideValue,
              );
    await layoutPreviewController.preview(
      baseDraft.copyWith(themeChoice: themeChoice),
    );
  }

  /// Purpose:
  ///   Clear any active theme preview through the host layout preview controller.
  ///
  /// Parameters:
  ///   - None.
  ///
  /// Return value:
  ///   - A future that completes when the host preview controller finishes.
  ///
  /// Requirements/Preconditions:
  ///   - Safe to call even if no preview is currently active.
  ///
  /// Guarantees/Postconditions:
  ///   - The host preview controller receives the clear request.
  ///
  /// Invariants:
  ///   - Clearing preview does not mutate persisted editor state.
  @override
  Future<void> clear() {
    return layoutPreviewController.clear();
  }
}

/// Adapter that wraps layout preview ownership for shared/override scale flows.
class _LayoutScalePreviewController
    implements EditorPreviewController<SharedOverrideEditorValue<dp.ScaleData>> {
  final dp.LayoutDraft baseDraft;
  final ValueChanged<dp.ScaleData> onSharedScaleChanged;
  final EditorPreviewController<dp.LayoutDraft> layoutPreviewController;

  /// Purpose:
  ///   Bridge scale editor previews into layout-draft previews while preserving
  ///   shared-versus-override isolation.
  ///
  /// Parameters:
  ///   - `baseDraft`: Layout draft that should wrap each previewed scale choice.
  ///   - `onSharedScaleChanged`: Host callback for System shared scale writes.
  ///   - `layoutPreviewController`: Host-owned layout preview controller.
  ///
  /// Return value:
  ///   - A new `_LayoutScalePreviewController`.
  ///
  /// Requirements/Preconditions:
  ///   - `baseDraft` should already represent the non-scale parts of the layout
  ///     being edited.
  ///
  /// Guarantees/Postconditions:
  ///   - Preview and clear requests forward into `layoutPreviewController`.
  ///
  /// Invariants:
  ///   - This adapter never persists edits on its own.
  const _LayoutScalePreviewController({
    required this.baseDraft,
    required this.onSharedScaleChanged,
    required this.layoutPreviewController,
  });

  /// Purpose:
  ///   Preview one scale editor value as a full layout draft update.
  ///
  /// Parameters:
  ///   - `value`: Shared/override scale editor candidate being previewed.
  ///
  /// Return value:
  ///   - A future that completes when the host preview controller finishes.
  ///
  /// Requirements/Preconditions:
  ///   - `value` should describe a valid scale editor state.
  ///
  /// Guarantees/Postconditions:
  ///   - Shared-mode previews keep `scaleChoice.activeSource` as shared and
  ///     forward `sharedValue` through `onSharedScaleChanged`.
  ///   - Override-mode previews update only the layout override payload.
  ///
  /// Invariants:
  ///   - The wrapped layout draft keeps its existing theme, scope, and settings.
  @override
  Future<void> preview(SharedOverrideEditorValue<dp.ScaleData> value) async {
    if (value.activeSource == dp.LayoutChoiceActiveSource.shared) {
      onSharedScaleChanged(value.sharedValue);
    }
    final dp.LayoutScaleChoice scaleChoice =
        value.activeSource == dp.LayoutChoiceActiveSource.overrideValue
            ? dp.LayoutScaleChoice.overrideValue(
                value.overrideValue ?? value.sharedValue,
              )
            : dp.LayoutScaleChoice.shared(
                overrideScale: value.overrideValue,
              );
    await layoutPreviewController.preview(
      baseDraft.copyWith(scaleChoice: scaleChoice),
    );
  }

  /// Purpose:
  ///   Clear any active scale preview through the host layout preview controller.
  ///
  /// Parameters:
  ///   - None.
  ///
  /// Return value:
  ///   - A future that completes when the host preview controller finishes.
  ///
  /// Requirements/Preconditions:
  ///   - Safe to call even if no preview is currently active.
  ///
  /// Guarantees/Postconditions:
  ///   - The host preview controller receives the clear request.
  ///
  /// Invariants:
  ///   - Clearing preview does not mutate persisted editor state.
  @override
  Future<void> clear() {
    return layoutPreviewController.clear();
  }
}
