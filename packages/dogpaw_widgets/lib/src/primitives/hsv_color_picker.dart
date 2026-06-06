import 'dart:async';

import 'package:flutter/material.dart';

/// Parse one stored `#rrggbb` value into a safe Flutter color.
///
/// Parameters:
/// - `hexColor`: Stored six-digit RGB color string.
///
/// Return value:
/// - Parsed `Color`, or grey when parsing fails.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Malformed input never throws and instead returns a safe fallback color.
///
/// Invariants:
/// - Pure parsing helper with no side effects.
Color parseHexColor(String hexColor) {
  String normalizedHex = hexColor.trim().replaceAll('#', '');
  if (normalizedHex.length != 6) {
    return Colors.grey;
  }
  normalizedHex = 'ff$normalizedHex';
  try {
    return Color(int.parse(normalizedHex, radix: 16));
  } catch (_) {
    return Colors.grey;
  }
}

/// Reusable touch-friendly HSV color picker with preset swatches.
///
/// Purpose:
/// Provides a musician-facing color picking surface that combines quick preset
/// access with direct HSV editing, so apps can compose the picker without
/// reimplementing swatches, saturation/value selection, or throttled updates.
class HsvColorPicker extends StatefulWidget {
  /// Current color shown by the picker in `#rrggbb` form.
  final String initialHexColor;

  /// Preset swatches offered for quick selection.
  final List<String> presetHexColors;

  /// Callback invoked when the picker commits a new color.
  final ValueChanged<String> onChanged;

  /// Height of the picker body.
  final double height;

  /// Whether to show the preview bar above the HSV editing region.
  final bool showPreviewBar;

  /// Delay used to throttle drag-driven update callbacks.
  final Duration previewThrottleDelay;

  /// Create one reusable HSV color picker panel.
  ///
  /// Parameters:
  /// - `initialHexColor`: Current color in `#rrggbb` form.
  /// - `presetHexColors`: Preset swatches offered for quick selection.
  /// - `onChanged`: Callback receiving throttled or immediate color updates.
  /// - `height`: Picker body height in logical pixels.
  /// - `showPreviewBar`: Whether to show the preview bar above the editor.
  /// - `previewThrottleDelay`: Delay used for drag-driven updates.
  ///
  /// Return value:
  /// - A new `HsvColorPicker`.
  ///
  /// Requirements/Preconditions:
  /// - `initialHexColor` should be a valid six-digit RGB hex string when possible.
  /// - `height` should be positive.
  ///
  /// Guarantees/Postconditions:
  /// - Preset taps emit immediately.
  /// - Drag interactions update the UI immediately and notify the host through a
  ///   throttled callback.
  ///
  /// Invariants:
  /// - The widget owns only temporary picker state.
  const HsvColorPicker({
    super.key,
    required this.initialHexColor,
    required this.presetHexColors,
    required this.onChanged,
    this.height = 320,
    this.showPreviewBar = true,
    this.previewThrottleDelay = const Duration(milliseconds: 80),
  });

  @override
  State<HsvColorPicker> createState() => _HsvColorPickerState();
}

/// Local state for the reusable HSV color picker.
class _HsvColorPickerState extends State<HsvColorPicker> {
  late HSVColor _currentHsvColor;
  Timer? _previewThrottleTimer;
  bool _throttleWindowIsActive = false;
  String? _pendingThrottledHexColor;
  String? _lastForwardedHexColor;

  @override
  void initState() {
    super.initState();
    _currentHsvColor = HSVColor.fromColor(parseHexColor(widget.initialHexColor));
  }

  /// Sync the internal picker state when the externally supplied color changes.
  ///
  /// Parameters:
  /// - `oldWidget`: Previous widget configuration.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Internal HSV state matches externally driven color changes after rebuilds.
  /// - Self-echoed rebuilds from this picker's own throttled callback do not
  ///   snap the drag interaction backward.
  ///
  /// Invariants:
  /// - Sync does not emit a new host callback on its own.
  @override
  void didUpdateWidget(covariant HsvColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialHexColor != widget.initialHexColor &&
        widget.initialHexColor != _lastForwardedHexColor) {
      _currentHsvColor =
          HSVColor.fromColor(parseHexColor(widget.initialHexColor));
    }
  }

  /// Release throttled preview resources.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Any pending drag-driven update callback is cancelled.
  ///
  /// Invariants:
  /// - No further throttled updates fire after disposal.
  @override
  void dispose() {
    _previewThrottleTimer?.cancel();
    super.dispose();
  }

  /// Convert the current picker color into stored `#rrggbb` form.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Lowercase six-digit RGB hex string with leading `#`.
  ///
  /// Requirements/Preconditions:
  /// - `_currentHsvColor` must be initialized.
  ///
  /// Guarantees/Postconditions:
  /// - Alpha is omitted from the returned string.
  ///
  /// Invariants:
  /// - The picker state remains unchanged.
  String _currentHexColor() {
    final Color color = _currentHsvColor.toColor();
    return '#'
        '${color.red.toRadixString(16).padLeft(2, '0')}'
        '${color.green.toRadixString(16).padLeft(2, '0')}'
        '${color.blue.toRadixString(16).padLeft(2, '0')}';
  }

  /// Start one throttle window for drag-driven updates.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The throttle window remains active until there are no pending updates.
  ///
  /// Invariants:
  /// - At most one throttle timer is pending at a time.
  void _startThrottleWindow() {
    _previewThrottleTimer?.cancel();
    _previewThrottleTimer = Timer(widget.previewThrottleDelay, () {
      if (_pendingThrottledHexColor != null) {
        final String nextHexColor = _pendingThrottledHexColor!;
        _pendingThrottledHexColor = null;
        _lastForwardedHexColor = nextHexColor;
        widget.onChanged(nextHexColor);
        _startThrottleWindow();
        return;
      }
      _throttleWindowIsActive = false;
    });
  }

  /// Emit one drag-driven update using a real throttle window.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `_currentHsvColor` must be initialized.
  ///
  /// Guarantees/Postconditions:
  /// - The first update in a throttle window is emitted immediately.
  /// - Later updates inside the same window are queued and emitted at most once
  ///   per throttle interval while dragging continues.
  ///
  /// Invariants:
  /// - The host callback is never invoked more frequently than the configured
  ///   throttle delay.
  void _emitThrottledUpdate() {
    final String currentHexColor = _currentHexColor();
    if (!_throttleWindowIsActive) {
      _throttleWindowIsActive = true;
      _lastForwardedHexColor = currentHexColor;
      widget.onChanged(currentHexColor);
      _startThrottleWindow();
      return;
    }
    _pendingThrottledHexColor = currentHexColor;
  }

  /// Apply one next HSV value to the picker and queue a throttled update.
  ///
  /// Parameters:
  /// - `nextHsvColor`: Full next picker color in HSV space.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `nextHsvColor` should represent a valid visible color.
  ///
  /// Guarantees/Postconditions:
  /// - The picker UI updates immediately.
  /// - The host callback is throttled while drag updates continue.
  ///
  /// Invariants:
  /// - Temporary picker state remains local between callback emissions.
  void _setCurrentHsvColor(HSVColor nextHsvColor) {
    setState(() {
      _currentHsvColor = nextHsvColor;
    });
    _emitThrottledUpdate();
  }

  /// Apply one preset swatch color immediately.
  ///
  /// Parameters:
  /// - `hexColor`: Chosen preset color in `#rrggbb` form.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `hexColor` should be a valid six-digit RGB hex string when possible.
  ///
  /// Guarantees/Postconditions:
  /// - The picker UI updates immediately.
  /// - The host callback fires immediately.
  ///
  /// Invariants:
  /// - Any pending throttled drag update is cancelled.
  void _applyPresetColor(String hexColor) {
    _previewThrottleTimer?.cancel();
    _throttleWindowIsActive = false;
    _pendingThrottledHexColor = null;
    setState(() {
      _currentHsvColor = HSVColor.fromColor(parseHexColor(hexColor));
    });
    _lastForwardedHexColor = hexColor;
    widget.onChanged(hexColor);
  }

  /// Build one visible border color for a preset swatch.
  ///
  /// Parameters:
  /// - `swatchColor`: Fill color displayed for the preset.
  ///
  /// Return value:
  /// - Border color that keeps the swatch visible against the picker surface.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Very dark swatches receive a lighter outline.
  ///
  /// Invariants:
  /// - Border selection depends only on the supplied swatch color.
  Color _swatchBorderColor(Color swatchColor) {
    if (swatchColor.computeLuminance() < 0.06) {
      return Colors.grey.shade500;
    }
    return Colors.black12;
  }

  /// Update the picker from a saturation/value gesture position.
  ///
  /// Parameters:
  /// - `position`: Local pointer position inside the saturation/value plane.
  /// - `width`: Plane width in logical pixels.
  /// - `height`: Plane height in logical pixels.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `width` and `height` should be positive.
  ///
  /// Guarantees/Postconditions:
  /// - Saturation and value are clamped into valid ranges.
  /// - The picker preview updates to the touched color.
  ///
  /// Invariants:
  /// - Hue is preserved.
  void _handleSVPan(Offset position, double width, double height) {
    final double saturation = (position.dx / width).clamp(0.0, 1.0);
    final double value = (1 - position.dy / height).clamp(0.0, 1.0);
    _setCurrentHsvColor(
      HSVColor.fromAHSV(1.0, _currentHsvColor.hue, saturation, value),
    );
  }

  /// Update the picker from one hue-strip gesture position.
  ///
  /// Parameters:
  /// - `dy`: Local vertical pointer position inside the hue strip.
  /// - `height`: Hue strip height in logical pixels.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `height` should be positive.
  ///
  /// Guarantees/Postconditions:
  /// - Hue is clamped into the valid `0..360` range.
  /// - The picker preview updates to the touched hue.
  ///
  /// Invariants:
  /// - Saturation and value are preserved.
  void _handleHuePan(double dy, double height) {
    final double hue = (dy / height * 360).clamp(0.0, 360.0);
    _setCurrentHsvColor(
      HSVColor.fromAHSV(
        1.0,
        hue,
        _currentHsvColor.saturation,
        _currentHsvColor.value,
      ),
    );
  }

  /// Build the full reusable color picker panel.
  ///
  /// Parameters:
  /// - `context`: Build context used for theming.
  ///
  /// Return value:
  /// - Panel containing preset swatches and an HSV editing area.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Presets appear in a two-column grid.
  /// - The HSV controls match the easy-layout interaction model.
  ///
  /// Invariants:
  /// - The widget never exposes raw hex strings in the visible UI.
  @override
  Widget build(BuildContext context) {
    final Color previewColor = _currentHsvColor.toColor();
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double previewBarHeight = widget.showPreviewBar ? 64 : 0;
    final double previewGapHeight = widget.showPreviewBar ? 16 : 0;
    final int swatchRows = (widget.presetHexColors.length / 2).ceil();

    return SizedBox(
      key: const Key('theme-color-picker-panel'),
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.showPreviewBar) ...<Widget>[
            Container(
              key: const Key('hsv-color-picker-preview-bar'),
              height: previewBarHeight,
              decoration: BoxDecoration(
                color: previewColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
            ),
            SizedBox(height: previewGapHeight),
          ],
          Expanded(
            child: Row(
              children: <Widget>[
                SizedBox(
                  key: const Key('theme-color-picker-swatches'),
                  width: 168,
                  child: LayoutBuilder(
                    builder: (
                      BuildContext context,
                      BoxConstraints constraints,
                    ) {
                      const double swatchSpacing = 10;
                      final double swatchHeight =
                          (constraints.maxHeight -
                                  (swatchRows - 1) * swatchSpacing) /
                              swatchRows;

                      return GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: swatchSpacing,
                          crossAxisSpacing: swatchSpacing,
                          mainAxisExtent: swatchHeight,
                        ),
                        itemCount: widget.presetHexColors.length,
                        itemBuilder: (BuildContext context, int index) {
                          final String hexColor = widget.presetHexColors[index];
                          final Color swatchColor = parseHexColor(hexColor);
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: Key('theme-swatch-$hexColor'),
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                _applyPresetColor(hexColor);
                              },
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: swatchColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _swatchBorderColor(swatchColor),
                                    width: 2,
                                  ),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final double svWidth = constraints.maxWidth - 56;
                      final double svHeight = constraints.maxHeight;

                      return Row(
                        children: <Widget>[
                          SizedBox(
                            key: const Key('theme-picker-sv-area'),
                            width: svWidth,
                            height: svHeight,
                            child: GestureDetector(
                              onPanDown: (DragDownDetails details) {
                                _handleSVPan(
                                  details.localPosition,
                                  svWidth,
                                  svHeight,
                                );
                              },
                              onPanUpdate: (DragUpdateDetails details) {
                                _handleSVPan(
                                  details.localPosition,
                                  svWidth,
                                  svHeight,
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CustomPaint(
                                    painter: _SaturationValuePainter(
                                      _currentHsvColor.hue,
                                    ),
                                    child: Stack(
                                      children: <Widget>[
                                        Positioned(
                                          left: _currentHsvColor.saturation *
                                                  svWidth -
                                              7,
                                          top: (1 - _currentHsvColor.value) *
                                                  svHeight -
                                              7,
                                          child: Container(
                                            width: 14,
                                            height: 14,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                              boxShadow: const <BoxShadow>[
                                                BoxShadow(
                                                  color: Colors.black26,
                                                  blurRadius: 3,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            key: const Key('theme-picker-hue-strip'),
                            width: 40,
                            height: svHeight,
                            child: GestureDetector(
                              onPanDown: (DragDownDetails details) {
                                _handleHuePan(
                                  details.localPosition.dy,
                                  svHeight,
                                );
                              },
                              onPanUpdate: (DragUpdateDetails details) {
                                _handleHuePan(
                                  details.localPosition.dy,
                                  svHeight,
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CustomPaint(
                                    painter: const _HuePainter(),
                                    child: Stack(
                                      children: <Widget>[
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: (_currentHsvColor.hue / 360) *
                                                  svHeight -
                                              3,
                                          child: Container(
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              border: Border.all(
                                                color: Colors.black,
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Paint the current hue's saturation/value plane.
class _SaturationValuePainter extends CustomPainter {
  /// Hue used to generate the plane's pure-color edge.
  final double hue;

  /// Create one saturation/value painter for the supplied hue.
  ///
  /// Parameters:
  /// - `hue`: Current hue in the `0..360` range.
  ///
  /// Return value:
  /// - A new `_SaturationValuePainter`.
  ///
  /// Requirements/Preconditions:
  /// - `hue` should be within the valid HSV hue range.
  ///
  /// Guarantees/Postconditions:
  /// - The painted plane transitions from white to the pure hue horizontally
  ///   and from transparent to black vertically.
  ///
  /// Invariants:
  /// - Painting depends only on `hue`.
  const _SaturationValuePainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final LinearGradient saturationGradient = LinearGradient(
      colors: <Color>[
        Colors.white,
        HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor(),
      ],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = saturationGradient.createShader(rect),
    );

    final LinearGradient valueGradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Colors.transparent,
        Colors.black,
      ],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = valueGradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}

/// Paint the vertical hue strip used by the reusable color picker.
class _HuePainter extends CustomPainter {
  /// Create one hue-strip painter.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - A new `_HuePainter`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The painted strip covers the full HSV hue cycle.
  ///
  /// Invariants:
  /// - Painting is stateless.
  const _HuePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final LinearGradient gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        const HSVColor.fromAHSV(1.0, 0, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 60, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 120, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 180, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 240, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 300, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 360, 1.0, 1.0).toColor(),
      ],
    );

    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
