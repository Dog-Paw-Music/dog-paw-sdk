import 'dart:io';

import 'package:flutter/material.dart';

import 'compositor_keyboard_control.dart';

/// Text field that relies on the compositor on-screen keyboard for input.
///
/// Purpose:
/// Provide touchscreen text entry on Dog Paw Pi targets where a Wayland OSK
/// such as wvkbd is running in the Sway session. This widget does not embed a
/// virtual keyboard; it signals the compositor OSK on focus.
///
/// Architecture:
/// Shared input primitive for Dog Paw UI apps on Pi targets. Callers should
/// leave room below the field when the OSK overlays the bottom of the display.
class SystemKeyboardTextField extends StatefulWidget {
  /// Text editing controller bound to the field.
  final TextEditingController textController;

  /// Hint text shown when the field is empty.
  final String? hintText;

  /// Called when the user submits via the platform keyboard action.
  final VoidCallback? onSubmitted;

  /// Whether the field accepts input.
  final bool enabled;

  /// Maximum number of lines for the text field.
  final int? maxLines;

  /// Optional text style for the field contents.
  final TextStyle? style;

  /// Optional hint text style.
  final TextStyle? hintStyle;

  /// Optional full input decoration override.
  final InputDecoration? decoration;

  /// When true, request focus when the field is first built.
  final bool autofocus;

  /// When true, start with obscured characters and show a visibility toggle.
  final bool obscureText;

  /// Optional empty space below the field for a bottom-docked OSK overlay.
  final double keyboardBottomInset;

  /// Optional compositor keyboard visibility backend for tests.
  final CompositorKeyboardControl? compositorKeyboardControl;

  /// Optional external focus node for programmatic focus control.
  final FocusNode? focusNode;

  /// Purpose:
  /// Construct a compositor-keyboard text field for Pi touchscreen entry.
  ///
  /// Parameters:
  /// - `textController`: Owns the editable text value.
  /// - `hintText`: Placeholder when empty.
  /// - `onSubmitted`: Invoked after the platform keyboard submits the field.
  /// - `enabled`: When false, the field is disabled.
  /// - `maxLines`: Text field line count; defaults to 1.
  /// - `style`: Field text style.
  /// - `hintStyle`: Hint text style.
  /// - `decoration`: Full decoration override.
  /// - `autofocus`: When true, focus the field on first build.
  /// - `obscureText`: When true, start obscured and show a visibility toggle.
  /// - `keyboardBottomInset`: Optional spacer height below the field.
  /// - `compositorKeyboardControl`: Optional show/hide backend override.
  /// - `focusNode`: Optional external focus node owned by the caller.
  ///
  /// Return value:
  /// - A configured [SystemKeyboardTextField] widget.
  ///
  /// Requirements/Preconditions:
  /// - `textController` must outlive this widget unless the parent disposes it
  ///   after this widget is removed.
  /// - A compatible Wayland on-screen keyboard must be available on device.
  ///
  /// Guarantees/Postconditions:
  /// - The field is editable and does not render an embedded keyboard.
  /// - When `obscureText` is true, a suffix visibility toggle is shown.
  ///
  /// Invariants:
  /// - Does not own [textController].
  const SystemKeyboardTextField({
    super.key,
    required this.textController,
    this.hintText,
    this.onSubmitted,
    this.enabled = true,
    this.maxLines = 1,
    this.style,
    this.hintStyle,
    this.decoration,
    this.autofocus = false,
    this.obscureText = false,
    this.keyboardBottomInset = 0,
    this.compositorKeyboardControl,
    this.focusNode,
  });

  @override
  State<SystemKeyboardTextField> createState() =>
      _SystemKeyboardTextFieldState();
}

class _SystemKeyboardTextFieldState extends State<SystemKeyboardTextField> {
  FocusNode? _ownedFocusNode;
  late FocusNode _focusNode;
  late bool _textObscured;
  late CompositorKeyboardControl _keyboardControl;

  /// Purpose:
  /// Attach the active focus node, creating an owned one when needed.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Must run before listeners are attached.
  ///
  /// Guarantees/Postconditions:
  /// - [_focusNode] references either [widget.focusNode] or an owned node.
  ///
  /// Invariants:
  /// - At most one owned focus node exists at a time.
  void _attachFocusNode() {
    final FocusNode? provided = widget.focusNode;
    if (provided != null) {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
      _focusNode = provided;
      return;
    }
    _ownedFocusNode ??= FocusNode();
    _focusNode = _ownedFocusNode!;
  }

  @override
  void initState() {
    super.initState();
    _textObscured = widget.obscureText;
    _attachFocusNode();
    _keyboardControl = resolveCompositorKeyboardControl(
      widget.compositorKeyboardControl,
    );
    _focusNode.addListener(_handleFocusChange);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCompositorKeyboard();
      });
    }
  }

  @override
  void didUpdateWidget(SystemKeyboardTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);
      _attachFocusNode();
      _focusNode.addListener(_handleFocusChange);
    }
    if (oldWidget.compositorKeyboardControl !=
        widget.compositorKeyboardControl) {
      _keyboardControl = resolveCompositorKeyboardControl(
        widget.compositorKeyboardControl,
      );
    }
    if (oldWidget.obscureText != widget.obscureText && widget.obscureText) {
      _textObscured = true;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  /// Purpose:
  /// Show the compositor keyboard when this field gains focus or is tapped.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [widget.enabled] should be true for user-driven entry.
  ///
  /// Guarantees/Postconditions:
  /// - Requests show from [_keyboardControl].
  ///
  /// Invariants:
  /// - Does not mutate the text value.
  void _showCompositorKeyboard() {
    if (!widget.enabled) {
      return;
    }
    _keyboardControl.show();
  }

  /// Purpose:
  /// Hide the compositor keyboard when this field loses focus.
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
  /// - Requests hide from [_keyboardControl] when focus is lost.
  ///
  /// Invariants:
  /// - Does not mutate the text value.
  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _showCompositorKeyboard();
      return;
    }
    _keyboardControl.hide();
  }

  /// Purpose:
  /// Toggle whether the field currently renders obscured characters.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [widget.obscureText] must be true so the toggle is shown.
  ///
  /// Guarantees/Postconditions:
  /// - `_textObscured` flips and the field rebuilds.
  ///
  /// Invariants:
  /// - Does not change the underlying text value.
  void _toggleTextObscured() {
    setState(() {
      _textObscured = !_textObscured;
    });
  }

  /// Purpose:
  /// Build the input decoration, adding a visibility toggle for obscure fields.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Decoration shown on the [TextField].
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - When [widget.obscureText] is true, a suffix toggle icon is present.
  ///
  /// Invariants:
  /// - Caller-supplied [widget.decoration] values are preserved except for the
  ///   obscure toggle suffix when applicable.
  InputDecoration _buildDecoration() {
    final InputDecoration baseDecoration = widget.decoration ??
        InputDecoration(
          hintText: widget.hintText,
          hintStyle: widget.hintStyle,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
        );
    if (!widget.obscureText) {
      return baseDecoration;
    }
    return baseDecoration.copyWith(
      suffixIcon: IconButton(
        key: const Key('system-keyboard-text-obscure-toggle'),
        icon: Icon(
          _textObscured ? Icons.visibility : Icons.visibility_off,
        ),
        tooltip: _textObscured ? 'Show text' : 'Hide text',
        onPressed: widget.enabled ? _toggleTextObscured : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: widget.textController,
          focusNode: _focusNode,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          readOnly: false,
          obscureText: widget.obscureText && _textObscured,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          style: widget.style ?? const TextStyle(fontSize: 27),
          decoration: _buildDecoration(),
          textInputAction: TextInputAction.done,
          onTap: _showCompositorKeyboard,
          onSubmitted: widget.onSubmitted == null
              ? null
              : (_) {
                  widget.onSubmitted?.call();
                },
        ),
        if (widget.keyboardBottomInset > 0)
          SizedBox(
            key: const Key('system-keyboard-bottom-inset'),
            height: widget.keyboardBottomInset,
          ),
      ],
    );
  }
}
