import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records preview requests for package-surface tests.
class _RecordingPreviewController<T> implements EditorPreviewController<T> {
  /// Last preview value observed by the controller.
  T? lastPreviewedValue;

  /// Whether `clear()` has been requested.
  bool wasCleared = false;

  /// Store the latest preview value for assertions.
  ///
  /// Parameters:
  /// - `value`: Value emitted by the editor preview hook.
  ///
  /// Return value:
  /// - A completed future after recording the value.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - `lastPreviewedValue` equals `value` after the future completes.
  ///
  /// Invariants:
  /// - Does not mutate any editor-owned state.
  @override
  Future<void> preview(T value) async {
    lastPreviewedValue = value;
  }

  /// Record that preview state was cleared.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - A completed future after recording the clear request.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - `wasCleared` is `true` after the future completes.
  ///
  /// Invariants:
  /// - Does not mutate any editor-owned state.
  @override
  Future<void> clear() async {
    wasCleared = true;
  }
}

/// Build one minimal endpoint for connection-picker API tests.
///
/// Parameters:
/// - None.
///
/// Return value:
/// - A basic input endpoint that can be passed to `ConnectionPicker`.
///
/// Requirements/Preconditions:
/// - None.
///
/// Guarantees/Postconditions:
/// - Returns an `EndpointInfo` with a valid float input spec.
///
/// Invariants:
/// - Does not contact Epiphany or allocate runtime endpoint resources.
dp.EndpointInfo _buildFocusedEndpoint() {
  return dp.EndpointInfo(
    name: 'focused_endpoint',
    spec: const dp.EndpointSpec(
      direction: dp.EndpointDirection.input,
      dataType: dp.DataTypeSpec(dp.DataType.float),
    ),
  );
}

void main() {
  test('package exports shared editor surface', () async {
    final _RecordingPreviewController<dp.ScaleData> scalePreviewController =
        _RecordingPreviewController<dp.ScaleData>();
    final _RecordingPreviewController<dp.ThemeData> themePreviewController =
        _RecordingPreviewController<dp.ThemeData>();
    final _RecordingPreviewController<dp.LayoutDraft> layoutPreviewController =
        _RecordingPreviewController<dp.LayoutDraft>();

    final Widget scaleEditor = ScaleEditor(
      value: const dp.ScaleData(
        rootNote: 0,
        noteCategories: <int>[1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
      ),
      onChanged: (_) {},
      previewController: scalePreviewController,
    );

    final Widget themeEditor = ThemeEditor(
      value: const dp.ThemeData(
        displayName: 'Test Theme',
        primaryColor: '#ff0000',
        secondaryColor: '#00ff00',
        accentColor: '#0000ff',
        backgroundColor: '#101010',
      ),
      onChanged: (_) {},
      previewController: themePreviewController,
    );

    final Widget layoutEditor = LayoutEditor(
      value: const dp.LayoutDraft(),
      onChanged: (_) {},
      previewController: layoutPreviewController,
    );

    final Widget hsvColorPicker = HsvColorPicker(
      initialHexColor: '#ff0000',
      presetHexColors: const <String>['#ff0000', '#00ff00'],
      onChanged: (_) {},
    );

    final Widget connectionPicker = ConnectionPicker(
      entity: dp.DogPawEntity('test_entity'),
      focusedEndpoint: _buildFocusedEndpoint(),
    );

    expect(scaleEditor, isA<Widget>());
    expect(themeEditor, isA<Widget>());
    expect(layoutEditor, isA<Widget>());
    expect(hsvColorPicker, isA<Widget>());
    expect(connectionPicker, isA<Widget>());

    await scalePreviewController.preview(
      const dp.ScaleData(
        rootNote: 7,
        noteCategories: <int>[1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
      ),
    );
    await themePreviewController.clear();
    await layoutPreviewController.preview(const dp.LayoutDraft());

    expect(scalePreviewController.lastPreviewedValue, isNotNull);
    expect(themePreviewController.wasCleared, isTrue);
    expect(layoutPreviewController.lastPreviewedValue, isNotNull);
  });
}
