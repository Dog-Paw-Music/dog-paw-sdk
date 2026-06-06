import 'dart:async';

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../dialogs/show_scale_editor_dialog.dart';
import '../dialogs/show_theme_editor_dialog.dart';
import '../models/editor_preview.dart';

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
  /// Open the inline theme editor dialog when the draft uses an inline theme.
  ///
  /// Parameters:
  /// - `context`: build context used to present the dialog.
  ///
  /// Return value:
  /// - A future that completes once the dialog is dismissed.
  ///
  /// Requirements/Preconditions:
  /// - `context` must be able to present dialogs.
  /// - `value.themeChoice.inlineTheme` should be non-null.
  ///
  /// Guarantees/Postconditions:
  /// - Confirming the dialog replaces the inline theme inside the draft.
  ///
  /// Invariants:
  /// - Theme editing remains host-controlled through `LayoutDraft`.
  Future<void> _editInlineTheme(BuildContext context) async {
    final dp.ThemeData? inlineTheme = value.themeChoice.inlineTheme;
    if (inlineTheme == null) {
      return;
    }
    final dp.ThemeData? nextTheme = await showThemeEditorDialog(
      context: context,
      initialValue: inlineTheme,
    );
    if (nextTheme != null) {
      _emitValue(
        value.copyWith(
          themeChoice: dp.LayoutThemeChoice.inline(nextTheme),
        ),
      );
    }
  }

  /// Purpose:
  /// Open the inline scale editor dialog when the draft uses an inline scale.
  ///
  /// Parameters:
  /// - `context`: build context used to present the dialog.
  ///
  /// Return value:
  /// - A future that completes once the dialog is dismissed.
  ///
  /// Requirements/Preconditions:
  /// - `context` must be able to present dialogs.
  /// - `value.scaleChoice.inlineScale` should be non-null.
  ///
  /// Guarantees/Postconditions:
  /// - Confirming the dialog replaces the inline scale inside the draft.
  ///
  /// Invariants:
  /// - Scale editing remains host-controlled through `LayoutDraft`.
  Future<void> _editInlineScale(BuildContext context) async {
    final dp.ScaleData? inlineScale = value.scaleChoice.inlineScale;
    if (inlineScale == null) {
      return;
    }
    final dp.ScaleData? nextScale = await showScaleEditorDialog(
      context: context,
      initialValue: inlineScale,
    );
    if (nextScale != null) {
      _emitValue(
        value.copyWith(
          scaleChoice: dp.LayoutScaleChoice.inline(nextScale),
        ),
      );
    }
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
  ///
  /// Invariants:
  /// - Theme data remains host-controlled.
  Widget _buildThemeTopCard(BuildContext context) {
    final bool usesInlineTheme =
        value.themeChoice.mode == dp.LayoutDraftReferenceMode.inline;
    return _buildTopCard(
      key: const Key('layout-theme-card'),
      title: 'Theme',
      child: _buildChoiceButton(
        key: const Key('layout-theme-button'),
        label: usesInlineTheme ? 'CUSTOM' : 'CURRENT',
        selected: usesInlineTheme,
        onPressed: themeVisibility == LayoutEditorFieldVisibility.readOnly
            ? null
            : () {
                _openThemeChoicePicker(context);
              },
        compact: true,
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
  ///
  /// Invariants:
  /// - Scale data remains host-controlled.
  Widget _buildScaleTopCard(BuildContext context) {
    final bool usesInlineScale =
        value.scaleChoice.mode == dp.LayoutDraftReferenceMode.inline;
    return _buildTopCard(
      key: const Key('layout-scale-card'),
      title: 'Scale',
      child: _buildChoiceButton(
        key: const Key('layout-scale-button'),
        label: usesInlineScale ? 'CUSTOM' : 'CURRENT',
        selected: usesInlineScale,
        onPressed: scaleVisibility == LayoutEditorFieldVisibility.readOnly
            ? null
            : () {
                _openScaleChoicePicker(context);
              },
        compact: true,
      ),
    );
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
  /// Open the theme choice flow used by the compact top-row card.
  ///
  /// Parameters:
  /// - `context`: build context used to present dialogs.
  ///
  /// Return value:
  /// - A future that completes once the flow finishes.
  ///
  /// Requirements/Preconditions:
  /// - `context` must be able to present dialogs.
  ///
  /// Guarantees/Postconditions:
  /// - Choosing `CURRENT` switches to the current theme reference.
  /// - Choosing `CUSTOM` opens the inline theme editor.
  ///
  /// Invariants:
  /// - Theme storage remains host-controlled.
  Future<void> _openThemeChoicePicker(BuildContext context) async {
    final bool usesInlineTheme =
        value.themeChoice.mode == dp.LayoutDraftReferenceMode.inline;
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return SimpleDialog(
          title: const Text('Theme'),
          children: <Widget>[
            SimpleDialogOption(
              key: const Key('layout-theme-option-current'),
              onPressed: () {
                Navigator.of(dialogContext).pop('current');
              },
              child: const Text('Current'),
            ),
            SimpleDialogOption(
              key: const Key('layout-theme-option-custom'),
              onPressed: () {
                Navigator.of(dialogContext).pop('custom');
              },
              child: Text(usesInlineTheme ? 'Edit Custom' : 'Custom'),
            ),
          ],
        );
      },
    );

    if (result == 'current') {
      _emitValue(
        value.copyWith(
          themeChoice: const dp.LayoutThemeChoice.current(),
        ),
      );
      return;
    }
    if (result != 'custom') {
      return;
    }

    final dp.ThemeData initialTheme = value.themeChoice.inlineTheme ??
        const dp.ThemeData(
          displayName: 'Inline Theme',
          primaryColor: '#ff6f61',
          secondaryColor: '#4fc3f7',
          accentColor: '#ffd54f',
          backgroundColor: '#1b1c1d',
        );
    final dp.ThemeData? nextTheme = await showThemeEditorDialog(
      context: context,
      initialValue: initialTheme,
    );
    if (nextTheme != null) {
      _emitValue(
        value.copyWith(
          themeChoice: dp.LayoutThemeChoice.inline(nextTheme),
        ),
      );
    }
  }

  /// Purpose:
  /// Open the scale choice flow used by the compact top-row card.
  ///
  /// Parameters:
  /// - `context`: build context used to present dialogs.
  ///
  /// Return value:
  /// - A future that completes once the flow finishes.
  ///
  /// Requirements/Preconditions:
  /// - `context` must be able to present dialogs.
  ///
  /// Guarantees/Postconditions:
  /// - Choosing `CURRENT` switches to the current scale reference.
  /// - Choosing `CUSTOM` opens the inline scale editor.
  ///
  /// Invariants:
  /// - Scale storage remains host-controlled.
  Future<void> _openScaleChoicePicker(BuildContext context) async {
    final bool usesInlineScale =
        value.scaleChoice.mode == dp.LayoutDraftReferenceMode.inline;
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return SimpleDialog(
          title: const Text('Scale'),
          children: <Widget>[
            SimpleDialogOption(
              key: const Key('layout-scale-option-current'),
              onPressed: () {
                Navigator.of(dialogContext).pop('current');
              },
              child: const Text('Current'),
            ),
            SimpleDialogOption(
              key: const Key('layout-scale-option-custom'),
              onPressed: () {
                Navigator.of(dialogContext).pop('custom');
              },
              child: Text(usesInlineScale ? 'Edit Custom' : 'Custom'),
            ),
          ],
        );
      },
    );

    if (result == 'current') {
      _emitValue(
        value.copyWith(
          scaleChoice: const dp.LayoutScaleChoice.current(),
        ),
      );
      return;
    }
    if (result != 'custom') {
      return;
    }

    final dp.ScaleData initialScale = value.scaleChoice.inlineScale ??
        dp.ScaleCatalog.scaleDataForName(
          scaleName: 'Major',
          rootNote: 0,
        );
    final dp.ScaleData? nextScale = await showScaleEditorDialog(
      context: context,
      initialValue: initialScale,
    );
    if (nextScale != null) {
      _emitValue(
        value.copyWith(
          scaleChoice: dp.LayoutScaleChoice.inline(nextScale),
        ),
      );
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
        value.themeChoice.mode == dp.LayoutDraftReferenceMode.inline;
    final String summary = usesInlineTheme
        ? (value.themeChoice.inlineTheme?.displayName ?? 'Inline Theme')
        : 'Current Theme';

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
                label: 'CURRENT',
                selected: !usesInlineTheme,
                onPressed: () {
                  _emitValue(
                    value.copyWith(
                      themeChoice: const dp.LayoutThemeChoice.current(),
                    ),
                  );
                },
              ),
              _buildChoiceButton(
                key: const Key('layout-theme-inline'),
                label: 'INLINE',
                selected: usesInlineTheme,
                onPressed: () {
                  _emitValue(
                    value.copyWith(
                      themeChoice: usesInlineTheme
                          ? value.themeChoice
                          : const dp.LayoutThemeChoice.inline(
                              dp.ThemeData(
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
          if (usesInlineTheme) ...<Widget>[
            const SizedBox(height: 12),
            Text(summary),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('layout-theme-edit-inline'),
              onPressed: () {
                _editInlineTheme(context);
              },
              child: const Text('Edit Theme'),
            ),
          ],
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
        value.scaleChoice.mode == dp.LayoutDraftReferenceMode.inline;
    final String summary = usesInlineScale
        ? (value.scaleChoice.inlineScale?.displayName ?? 'Inline Scale')
        : 'Current Scale';

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
                label: 'CURRENT',
                selected: !usesInlineScale,
                onPressed: () {
                  _emitValue(
                    value.copyWith(
                      scaleChoice: const dp.LayoutScaleChoice.current(),
                    ),
                  );
                },
              ),
              _buildChoiceButton(
                key: const Key('layout-scale-inline'),
                label: 'INLINE',
                selected: usesInlineScale,
                onPressed: () {
                  _emitValue(
                    value.copyWith(
                      scaleChoice: usesInlineScale
                          ? value.scaleChoice
                          : dp.LayoutScaleChoice.inline(
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
          if (usesInlineScale) ...<Widget>[
            const SizedBox(height: 12),
            Text(summary),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('layout-scale-edit-inline'),
              onPressed: () {
                _editInlineScale(context);
              },
              child: const Text('Edit Scale'),
            ),
          ],
        ],
      ),
    );
  }
}
