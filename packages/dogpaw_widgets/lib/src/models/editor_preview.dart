/// Contract for host-owned live preview integration.
///
/// Purpose:
/// Lets reusable editors ask the host app to preview the current value without
/// owning Epiphany connections or endpoint lifecycles themselves.
abstract interface class EditorPreviewController<T> {
  /// Request that the host preview the supplied editor value.
  ///
  /// Parameters:
  /// - `value`: Latest editor value that should be previewed.
  ///
  /// Return value:
  /// - A future that completes when the host has handled the preview request.
  ///
  /// Requirements/Preconditions:
  /// - `value` should describe a valid editor state for the corresponding editor.
  ///
  /// Guarantees/Postconditions:
  /// - The host receives one best-effort preview request for `value`.
  ///
  /// Invariants:
  /// - Implementations remain host-owned; editors never create runtime preview
  ///   resources on their own.
  Future<void> preview(T value);

  /// Request that the host clear any active preview owned by this editor flow.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - A future that completes when the host has handled the clear request.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Any best-effort preview owned by the host for this editor flow has been
  ///   cleared after the future completes.
  ///
  /// Invariants:
  /// - Editors do not assume how the host implements preview clearing.
  Future<void> clear();
}
