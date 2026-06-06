import 'dart:async';
import 'dart:math' as math;

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';

import '../models/editor_preview.dart';
import '../primitives/piano_keyboard.dart';

/// Reusable musician-facing editor for one Dog Paw scale value.
///
/// Purpose:
/// Defines the shared package contract for scale editing while keeping the host
/// app in control of persistence and optional live preview side effects.
class ScaleEditor extends StatelessWidget {
  /// Current scale value being edited.
  final dp.ScaleData value;

  /// Callback that receives the next full scale value after user edits.
  final ValueChanged<dp.ScaleData> onChanged;

  /// Optional host-owned live preview integration.
  final EditorPreviewController<dp.ScaleData>? previewController;

  /// Whether the editor should render its keyboard preview region.
  final bool enableKeyboardPreview;

  /// Create one reusable scale editor shell.
  ///
  /// Parameters:
  /// - `value`: Current scale value to present.
  /// - `onChanged`: Callback receiving the next full scale value.
  /// - `previewController`: Optional host-owned preview integration.
  /// - `enableKeyboardPreview`: Whether the keyboard preview region is enabled.
  ///
  /// Return value:
  /// - A new `ScaleEditor`.
  ///
  /// Requirements/Preconditions:
  /// - `value` should describe a valid scale.
  ///
  /// Guarantees/Postconditions:
  /// - The editor remains purely presentational and does not persist changes on
  ///   its own.
  ///
  /// Invariants:
  /// - Persistence and preview ownership remain outside the widget.
  const ScaleEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.previewController,
    this.enableKeyboardPreview = true,
  });

  /// Emit one next scale value through the public callback and optional preview.
  ///
  /// Parameters:
  /// - `nextValue`: Full next scale value after one user interaction.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `nextValue` should describe a valid scale state.
  ///
  /// Guarantees/Postconditions:
  /// - `onChanged` is invoked synchronously with `nextValue`.
  /// - The preview controller receives a best-effort preview request when present.
  ///
  /// Invariants:
  /// - The widget does not persist scale changes on its own.
  void _emitValue(dp.ScaleData nextValue) {
    onChanged(nextValue);
    final EditorPreviewController<dp.ScaleData>? controller = previewController;
    if (controller != null) {
      unawaited(controller.preview(nextValue));
    }
  }

  /// Build the current scale editor UI.
  ///
  /// Parameters:
  /// - `context`: Build context for inherited widget lookup.
  ///
  /// Return value:
  /// - Musician-facing scale editor content that can be embedded or shown in a dialog.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The returned tree includes root controls, named-scale selection, and a
  ///   piano-keyboard editing region.
  ///
  /// Invariants:
  /// - The widget remains presentational and host-controlled.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final String detectedScaleName = dp.ScaleCatalog.detectScaleName(value);
        final _ScaleEditorLayoutMetrics metrics =
            _resolveLayoutMetrics(constraints);

        return Padding(
          padding: EdgeInsets.all(metrics.outerPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildRootControls(
                context,
                selectedWidth: metrics.rootSelectedWidth,
                selectedHeight: metrics.rootSelectedHeight,
                unselectedHeight: metrics.rootUnselectedHeight,
              ),
              SizedBox(height: metrics.sectionSpacing),
              _buildNamedScaleSection(
                context,
                detectedScaleName,
                baseHeight: metrics.scaleCardHeight,
                selectedHeight: metrics.selectedScaleCardHeight,
                selectedFontSize: metrics.scaleCardFontSize,
              ),
              if (enableKeyboardPreview) ...<Widget>[
                SizedBox(height: metrics.sectionSpacing),
                _buildKeyboardSection(
                  context,
                  keyboardHeight: metrics.keyboardHeight,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Resolve one set of editor layout metrics from the current constraints.
  ///
  /// Parameters:
  /// - `constraints`: Incoming layout constraints for this scale editor.
  ///
  /// Return value:
  /// - Compact metrics for tighter bounded-height layouts, otherwise the default
  ///   roomy desktop metrics.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The dialog-hosted editor uses a shorter vertical layout that fits without
  ///   an internal scroll view.
  /// - The embedded editor keeps the larger presentation when space allows.
  ///
  /// Invariants:
  /// - Selection cards still grow in both compact and roomy layouts.
  _ScaleEditorLayoutMetrics _resolveLayoutMetrics(BoxConstraints constraints) {
    final bool useCompactLayout =
        constraints.hasBoundedHeight && constraints.maxHeight <= 500;
    if (useCompactLayout) {
      return const _ScaleEditorLayoutMetrics(
        outerPadding: 4,
        sectionSpacing: 10,
        rootSelectedWidth: 52,
        rootSelectedHeight: 52,
        rootUnselectedHeight: 44,
        scaleCardHeight: 64,
        selectedScaleCardHeight: 72,
        scaleCardFontSize: 16,
        keyboardHeight: 76,
      );
    }
    return const _ScaleEditorLayoutMetrics(
      outerPadding: 8,
      sectionSpacing: 20,
      rootSelectedWidth: 64,
      rootSelectedHeight: 64,
      rootUnselectedHeight: 56,
      scaleCardHeight: 96,
      selectedScaleCardHeight: 102,
      scaleCardFontSize: 20,
      keyboardHeight: 134,
    );
  }

  /// Build the top root-control section.
  ///
  /// Parameters:
  /// - `context`: Build context used for theming.
  ///
  /// Return value:
  /// - One horizontally arranged absolute root-note selector row.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The current root note is clearly emphasized.
  /// - All twelve root choices remain available in one non-scrolling scan line.
  ///
  /// Invariants:
  /// - The root row fills the available width without scrolling.
  Widget _buildRootControls(
    BuildContext context, {
    required double selectedWidth,
    required double selectedHeight,
    required double unselectedHeight,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = 4;
        const Duration selectionAnimationDuration = Duration(milliseconds: 240);
        final double totalSpacing =
            spacing * (dp.ScaleCatalog.noteNames.length - 1);
        final double unselectedWidth = (constraints.maxWidth -
                totalSpacing -
                selectedWidth)
            / (dp.ScaleCatalog.noteNames.length - 1);
        final double rowHeight = math.max(selectedHeight, unselectedHeight);
        double currentLeft = 0;

        return SizedBox(
          key: const Key('scale-root-row'),
          height: rowHeight,
          child: Stack(
            children: List<Widget>.generate(dp.ScaleCatalog.noteNames.length, (
              int noteIndex,
            ) {
              final String noteName = dp.ScaleCatalog.rootNoteName(noteIndex);
              final bool isSelected = value.rootNote % 12 == noteIndex;
              final double noteWidth = isSelected ? selectedWidth : unselectedWidth;
              final double noteHeight =
                  isSelected ? selectedHeight : unselectedHeight;
              final double noteLeft = currentLeft;
              currentLeft += noteWidth + (noteIndex == dp.ScaleCatalog.noteNames.length - 1 ? 0 : spacing);

              return AnimatedPositioned(
                duration: selectionAnimationDuration,
                curve: Curves.easeInOutCubic,
                left: noteLeft,
                top: (rowHeight - noteHeight) / 2,
                width: noteWidth,
                height: noteHeight,
                child: _BeveledSelectionCard(
                  key: Key('scale-root-note-$noteName'),
                  label: noteName,
                  isSelected: isSelected,
                  width: noteWidth,
                  height: noteHeight,
                  fontSize: 19,
                  onTap: () {
                    _emitValue(dp.ScaleCatalog.setRootNote(value, noteIndex));
                  },
                ),
              );
            }),
          ),
        );
      },
    );
  }

  /// Build one note color for the keyboard preview.
  ///
  /// Parameters:
  /// - `colorScheme`: Active material color scheme used for the editor.
  /// - `noteIndex`: Chromatic note index within the octave.
  ///
  /// Return value:
  /// - Musician-facing key color for the requested note category.
  ///
  /// Requirements/Preconditions:
  /// - `noteIndex` should be within the scale editor's octave display range.
  ///
  /// Guarantees/Postconditions:
  /// - Root, in-scale, and out-of-scale notes receive clearly distinct colors.
  /// - Out-of-scale white and black keys share the same grey treatment.
  ///
  /// Invariants:
  /// - Color selection depends only on the current scale state.
  Color _keyboardColorForNote(ColorScheme colorScheme, int noteIndex) {
    if (dp.ScaleCatalog.isRoot(value, noteIndex)) {
      return colorScheme.primary;
    }
    if (dp.ScaleCatalog.isIncluded(value, noteIndex)) {
      return colorScheme.tertiaryContainer;
    }
    return colorScheme.surfaceContainerHighest;
  }

  /// Build one keyboard label style for the current scale preview.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Shared text style used for note labels on the preview keyboard.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Label text remains readable at the shorter preview height.
  ///
  /// Invariants:
  /// - Style selection does not mutate editor state.
  TextStyle _keyboardLabelStyle() {
    return const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
    );
  }

  /// Build the named-scale selection section.
  ///
  /// Parameters:
  /// - `context`: Build context used for theming.
  /// - `detectedScaleName`: Current named-scale identity or `Custom`.
  ///
  /// Return value:
  /// - Grid-like wrap of fixed-size named-scale selection cards.
  ///
  /// Requirements/Preconditions:
  /// - `detectedScaleName` should come from the shared scale catalog.
  ///
  /// Guarantees/Postconditions:
  /// - The scale chooser always renders as a six-column grid that fills the
  ///   available width.
  /// - The current scale choice is visually emphasized with extra room while the
  ///   grid layout itself remains stable.
  ///
  /// Invariants:
  /// - Every visible row uses six equal-width slots.
  Widget _buildNamedScaleSection(
    BuildContext context,
    String detectedScaleName, {
    required double baseHeight,
    required double selectedHeight,
    required double selectedFontSize,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const int columnCount = 6;
        const double columnSpacing = 6;
        const double rowSpacing = 6;
        const double cardHorizontalInset = 4;
        const double selectedCardGrowth = 12;
        final List<String> scaleNames = dp.ScaleCatalog.scaleNames;
        final int rowCount = (scaleNames.length / columnCount).ceil();
        final double slotWidth =
            (constraints.maxWidth - columnSpacing * (columnCount - 1)) /
                columnCount;
        final double unselectedCardWidth = math.max(
          0,
          slotWidth - cardHorizontalInset,
        );
        final double selectedCardWidth = math.min(
          slotWidth,
          unselectedCardWidth + selectedCardGrowth,
        );

        return SizedBox(
          key: const Key('scale-selection-grid'),
          width: constraints.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(rowCount, (int rowIndex) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: rowIndex == rowCount - 1 ? 0 : rowSpacing,
                ),
                child: Row(
                  children: List<Widget>.generate(columnCount, (int columnIndex) {
                    final int itemIndex = rowIndex * columnCount + columnIndex;
                    final Widget slotChild = itemIndex < scaleNames.length
                        ? _BeveledSelectionCard(
                            key: Key('scale-option-${scaleNames[itemIndex]}'),
                            label: scaleNames[itemIndex],
                            isSelected:
                                scaleNames[itemIndex] == detectedScaleName,
                            width: unselectedCardWidth,
                            height: baseHeight,
                            fontSize: selectedFontSize,
                            selectedWidth: selectedCardWidth,
                            selectedHeight: selectedHeight,
                            selectedScale: 1.0,
                            unselectedScale: 1.0,
                            onTap: scaleNames[itemIndex] == 'Custom'
                                ? null
                                : () {
                                    _emitValue(
                                      dp.ScaleCatalog.scaleDataForName(
                                        scaleName: scaleNames[itemIndex],
                                        rootNote: value.rootNote,
                                      ),
                                    );
                                  },
                          )
                        : SizedBox(
                            width: slotWidth,
                            height: selectedHeight,
                          );

                    return Padding(
                      padding: EdgeInsets.only(
                        right: columnIndex == columnCount - 1
                            ? 0
                            : columnSpacing,
                      ),
                      child: SizedBox(
                        width: slotWidth,
                        height: selectedHeight,
                        child: slotChild,
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  /// Build the keyboard-based manual scale editing section.
  ///
  /// Parameters:
  /// - `context`: Build context used for theming.
  ///
  /// Return value:
  /// - One `PianoKeyboard` configured for root and note-membership editing.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Tap toggles non-root note membership.
  /// - Long press reassigns the root while preserving interval structure.
  ///
  /// Invariants:
  /// - Visual state derives only from the current `ScaleData`.
  Widget _buildKeyboardSection(
    BuildContext context, {
    required double keyboardHeight,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return PianoKeyboard(
      height: keyboardHeight,
      colorForNote: (int noteIndex) => _keyboardColorForNote(colorScheme, noteIndex),
      onNoteTap: (int noteIndex) {
        _emitValue(dp.ScaleCatalog.toggleIncludedNote(value, noteIndex));
      },
      onNoteLongPress: (int noteIndex) {
        _emitValue(dp.ScaleCatalog.setRootNote(value, noteIndex));
      },
      showNoteLabels: true,
      labelStyle: _keyboardLabelStyle(),
      whiteKeyBorderColor: colorScheme.outlineVariant,
      blackKeyBorderColor: colorScheme.outline,
    );
  }
}

/// Layout metrics for one constraint-driven `ScaleEditor` pass.
class _ScaleEditorLayoutMetrics {
  /// Outer padding around the full editor content.
  final double outerPadding;

  /// Vertical gap between major editor sections.
  final double sectionSpacing;

  /// Width of the selected root-note card.
  final double rootSelectedWidth;

  /// Height of the selected root-note card.
  final double rootSelectedHeight;

  /// Height of unselected root-note cards.
  final double rootUnselectedHeight;

  /// Height of unselected scale-selection cards.
  final double scaleCardHeight;

  /// Height of the selected scale-selection card.
  final double selectedScaleCardHeight;

  /// Base selected font size used for scale-selection labels.
  final double scaleCardFontSize;

  /// Height of the keyboard preview region.
  final double keyboardHeight;

  /// Create one immutable set of scale-editor layout metrics.
  ///
  /// Parameters:
  /// - `outerPadding`: Outer padding around the editor content.
  /// - `sectionSpacing`: Vertical gap between major sections.
  /// - `rootSelectedWidth`: Width of the selected root note card.
  /// - `rootSelectedHeight`: Height of the selected root note card.
  /// - `rootUnselectedHeight`: Height of unselected root note cards.
  /// - `scaleCardHeight`: Height of unselected scale cards.
  /// - `selectedScaleCardHeight`: Height of the selected scale card.
  /// - `scaleCardFontSize`: Selected-state font size for scale labels.
  /// - `keyboardHeight`: Height of the keyboard preview.
  ///
  /// Return value:
  /// - A new `_ScaleEditorLayoutMetrics` instance.
  ///
  /// Requirements/Preconditions:
  /// - All metric values should be positive.
  ///
  /// Guarantees/Postconditions:
  /// - Stores the exact values supplied by the caller.
  ///
  /// Invariants:
  /// - Instances are immutable after construction.
  const _ScaleEditorLayoutMetrics({
    required this.outerPadding,
    required this.sectionSpacing,
    required this.rootSelectedWidth,
    required this.rootSelectedHeight,
    required this.rootUnselectedHeight,
    required this.scaleCardHeight,
    required this.selectedScaleCardHeight,
    required this.scaleCardFontSize,
    required this.keyboardHeight,
  });
}

/// Beveled selection surface used by the scale editor.
class _BeveledSelectionCard extends StatelessWidget {
  static const Duration _selectionAnimationDuration = Duration(milliseconds: 240);

  /// User-facing label shown inside the card.
  final String label;

  /// Whether the current card is visually selected.
  final bool isSelected;

  /// Base card width used for the unselected presentation.
  final double width;

  /// Base card height used for the unselected presentation.
  final double height;

  /// Optional tap handler for interactive cards.
  final VoidCallback? onTap;

  /// Font size for the current label.
  final double fontSize;

  /// Optional selected width used when the chosen state needs more space.
  final double? selectedWidth;

  /// Optional selected height used when the chosen state needs more space.
  final double? selectedHeight;

  /// Scale used for the selected presentation.
  final double selectedScale;

  /// Scale used for the unselected presentation.
  final double unselectedScale;

  /// Create one beveled selection card.
  ///
  /// Parameters:
  /// - `label`: User-facing text inside the card.
  /// - `isSelected`: Whether the card uses the selected treatment.
  /// - `width`: Base width for the unselected card.
  /// - `height`: Base height for the unselected card.
  /// - `onTap`: Optional tap handler.
  /// - `fontSize`: Base font size for the label.
  /// - `selectedWidth`: Optional width used when the card is selected.
  /// - `selectedHeight`: Optional height used when the card is selected.
  /// - `selectedScale`: Scale applied to the selected card treatment.
  /// - `unselectedScale`: Scale applied to the unselected card treatment.
  ///
  /// Return value:
  /// - A new `_BeveledSelectionCard`.
  ///
  /// Requirements/Preconditions:
  /// - `width` and `height` should be positive.
  ///
  /// Guarantees/Postconditions:
  /// - The card keeps a stable outer slot even if the selected state grows.
  ///
  /// Invariants:
  /// - Visual styling depends only on the supplied properties.
  const _BeveledSelectionCard({
    super.key,
    required this.label,
    required this.isSelected,
    required this.width,
    required this.height,
    this.onTap,
    this.fontSize = 22,
    this.selectedWidth,
    this.selectedHeight,
    this.selectedScale = 1.04,
    this.unselectedScale = 0.88,
  });

  /// Build the beveled selection surface.
  ///
  /// Parameters:
  /// - `context`: Build context used for theming.
  ///
  /// Return value:
  /// - A fixed-size card with selection-aware styling.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Selected cards use a filled highlighted treatment.
  /// - Unselected cards keep a transparent background with a visible border.
  ///
  /// Invariants:
  /// - Layout size is independent of selection state.
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final BorderRadius borderRadius = BorderRadius.circular(14);
    final double effectiveSelectedWidth = selectedWidth ?? width;
    final double effectiveSelectedHeight = selectedHeight ?? height;
    final double slotWidth = math.max(width, effectiveSelectedWidth);
    final double slotHeight = math.max(height, effectiveSelectedHeight);
    final double animatedWidth = isSelected ? effectiveSelectedWidth : width;
    final double animatedHeight = isSelected ? effectiveSelectedHeight : height;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: slotWidth,
        height: slotHeight,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Center(
            child: AnimatedScale(
              duration: _selectionAnimationDuration,
              curve: Curves.easeInOutCubic,
              scale: isSelected ? selectedScale : unselectedScale,
              child: AnimatedContainer(
                duration: _selectionAnimationDuration,
                curve: Curves.easeInOutCubic,
                width: animatedWidth,
                height: animatedHeight,
                decoration: BoxDecoration(
                  color:
                      isSelected ? colorScheme.primaryContainer : Colors.transparent,
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                    width: 2,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(isSelected ? 0.18 : 0.08),
                      blurRadius: isSelected ? 10 : 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedDefaultTextStyle(
                      duration: _selectionAnimationDuration,
                      curve: Curves.easeInOutCubic,
                      style: TextStyle(
                        fontSize: isSelected ? fontSize : fontSize - 2,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
