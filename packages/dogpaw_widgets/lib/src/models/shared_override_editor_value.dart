import 'package:dogpaw/dogpaw.dart' as dp;

/// Purpose:
/// Generic widget-owned editing value for controls that can either follow the
/// shared system value or use a saved per-layout override.
///
/// Parameters:
/// - `activeSource`: whether the editor is currently editing the shared value or
///   the saved override value.
/// - `sharedValue`: current shared/system value supplied by the host.
/// - `overrideValue`: optional saved override value retained even when the
///   shared source is active.
///
/// Return value:
/// - Immutable editor value that carries both the active source and both
///   backing payloads.
///
/// Requirements/Preconditions:
/// - `overrideValue` should be non-null when `activeSource` is
///   `overrideValue`.
///
/// Guarantees/Postconditions:
/// - The active editable value is always available through `effectiveValue`.
///
/// Invariants:
/// - Construction performs no I/O.
class SharedOverrideEditorValue<T> {
  final dp.LayoutChoiceActiveSource activeSource;
  final T sharedValue;
  final T? overrideValue;

  const SharedOverrideEditorValue({
    required this.activeSource,
    required this.sharedValue,
    this.overrideValue,
  });

  /// Purpose:
  /// Return the value currently being edited or previewed.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Saved override when override mode is active and present; otherwise the
  ///   shared value.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Never returns `null`.
  ///
  /// Invariants:
  /// - Reading this getter does not mutate state.
  T get effectiveValue {
    if (activeSource == dp.LayoutChoiceActiveSource.overrideValue &&
        overrideValue != null) {
      return overrideValue as T;
    }
    return sharedValue;
  }

  /// Purpose:
  /// Clone this editor value while overriding selected fields.
  ///
  /// Parameters:
  /// - `activeSource`: replacement active source.
  /// - `sharedValue`: replacement shared/system value.
  /// - `overrideValue`: replacement saved override value.
  /// - `clearOverrideValue`: when true, clears the saved override.
  ///
  /// Return value:
  /// - New immutable `SharedOverrideEditorValue<T>`.
  ///
  /// Requirements/Preconditions:
  /// - Replacement values should satisfy the same expectations as the
  ///   constructor.
  ///
  /// Guarantees/Postconditions:
  /// - Unspecified fields preserve their previous values.
  ///
  /// Invariants:
  /// - This instance remains unchanged.
  SharedOverrideEditorValue<T> copyWith({
    dp.LayoutChoiceActiveSource? activeSource,
    T? sharedValue,
    T? overrideValue,
    bool clearOverrideValue = false,
  }) {
    return SharedOverrideEditorValue<T>(
      activeSource: activeSource ?? this.activeSource,
      sharedValue: sharedValue ?? this.sharedValue,
      overrideValue: clearOverrideValue
          ? null
          : (overrideValue ?? this.overrideValue),
    );
  }

  /// Purpose:
  /// Return a copy that activates override mode and initializes the override
  /// from the shared value when needed.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - New editor value with `overrideValue` ready for editing.
  ///
  /// Requirements/Preconditions:
  /// - `T` should be treated as immutable so sharing `sharedValue` is safe.
  ///
  /// Guarantees/Postconditions:
  /// - The returned value uses `overrideValue` as its active source.
  ///
  /// Invariants:
  /// - This instance remains unchanged.
  SharedOverrideEditorValue<T> activateOverride() {
    return SharedOverrideEditorValue<T>(
      activeSource: dp.LayoutChoiceActiveSource.overrideValue,
      sharedValue: sharedValue,
      overrideValue: overrideValue ?? sharedValue,
    );
  }

  /// Purpose:
  /// Return a copy that clears any saved override and falls back to the shared
  /// source.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - New editor value using the shared source with no saved override.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - `overrideValue` is `null` in the returned value.
  ///
  /// Invariants:
  /// - This instance remains unchanged.
  SharedOverrideEditorValue<T> resetOverride() {
    return SharedOverrideEditorValue<T>(
      activeSource: dp.LayoutChoiceActiveSource.shared,
      sharedValue: sharedValue,
      overrideValue: null,
    );
  }

  /// Purpose:
  /// Return a copy with the active effective value replaced in whichever source
  /// is currently selected.
  ///
  /// Parameters:
  /// - `nextValue`: replacement value for the active source.
  ///
  /// Return value:
  /// - New editor value reflecting the updated active source payload.
  ///
  /// Requirements/Preconditions:
  /// - `nextValue` should satisfy the same constraints as the original value
  ///   type.
  ///
  /// Guarantees/Postconditions:
  /// - Shared mode updates `sharedValue`.
  /// - Override mode updates `overrideValue`.
  ///
  /// Invariants:
  /// - This instance remains unchanged.
  SharedOverrideEditorValue<T> withEffectiveValue(T nextValue) {
    if (activeSource == dp.LayoutChoiceActiveSource.overrideValue) {
      return copyWith(overrideValue: nextValue);
    }
    return copyWith(sharedValue: nextValue);
  }
}
