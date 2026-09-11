import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingThemePreviewController
    implements
        EditorPreviewController<SharedOverrideEditorValue<dp.ThemeData>> {
  SharedOverrideEditorValue<dp.ThemeData>? lastPreviewValue;
  bool wasCleared = false;

  @override
  Future<void> preview(
    SharedOverrideEditorValue<dp.ThemeData> value,
  ) async {
    lastPreviewValue = value;
  }

  @override
  Future<void> clear() async {
    wasCleared = true;
  }
}

void main() {
  Future<void> pumpThemeEditor(
    WidgetTester tester, {
    required SharedOverrideEditorValue<dp.ThemeData> value,
    required ValueChanged<SharedOverrideEditorValue<dp.ThemeData>> onChanged,
    EditorPreviewController<SharedOverrideEditorValue<dp.ThemeData>>?
        previewController,
    bool showSourceSelector = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ThemeEditor(
            value: value,
            onChanged: onChanged,
            previewController: previewController,
            showSourceSelector: showSourceSelector,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders musician-facing role labels and hides hex values',
      (WidgetTester tester) async {
    await pumpThemeEditor(
      tester,
      value: const SharedOverrideEditorValue<dp.ThemeData>(
        activeSource: dp.LayoutChoiceActiveSource.shared,
        sharedValue: dp.ThemeData(
          displayName: 'Test Theme',
          primaryColor: '#ff0000',
          secondaryColor: '#00ff00',
          accentColor: '#0000ff',
          backgroundColor: '#101010',
        ),
      ),
      onChanged: (_) {},
    );

    expect(find.byKey(const Key('theme-source-shared')), findsOneWidget);
    expect(find.byKey(const Key('theme-source-override')), findsOneWidget);
    expect(find.byKey(const Key('theme-role-Root')), findsOneWidget);
    expect(find.byKey(const Key('theme-role-In Scale')), findsOneWidget);
    expect(find.byKey(const Key('theme-role-Background')), findsOneWidget);
    expect(find.byKey(const Key('theme-role-Highlight')), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsNothing);
    expect(find.byType(HsvColorPicker), findsOneWidget);
    expect(find.byKey(const Key('hsv-color-picker-preview-bar')), findsNothing);
    expect(find.textContaining('#'), findsNothing);
  });

  testWidgets('theme role buttons stay on one centered row and are wide enough',
      (WidgetTester tester) async {
    await pumpThemeEditor(
      tester,
      value: const SharedOverrideEditorValue<dp.ThemeData>(
        activeSource: dp.LayoutChoiceActiveSource.shared,
        sharedValue: dp.ThemeData(
          displayName: 'Test Theme',
          primaryColor: '#ff0000',
          secondaryColor: '#00ff00',
          accentColor: '#0000ff',
          backgroundColor: '#101010',
        ),
      ),
      onChanged: (_) {},
    );

    final Rect rootRect =
        tester.getRect(find.byKey(const Key('theme-role-Root')));
    final Rect highlightRect =
        tester.getRect(find.byKey(const Key('theme-role-Highlight')));
    final Rect scaleRect =
        tester.getRect(find.byKey(const Key('theme-role-In Scale')));

    expect(rootRect.top, equals(highlightRect.top));
    expect(rootRect.top, equals(scaleRect.top));
    expect(rootRect.width, greaterThanOrEqualTo(180));
  });

  testWidgets('theme picker swatches stretch to the picker area height',
      (WidgetTester tester) async {
    await pumpThemeEditor(
      tester,
      value: const SharedOverrideEditorValue<dp.ThemeData>(
        activeSource: dp.LayoutChoiceActiveSource.shared,
        sharedValue: dp.ThemeData(
          displayName: 'Test Theme',
          primaryColor: '#ff0000',
          secondaryColor: '#00ff00',
          accentColor: '#0000ff',
          backgroundColor: '#101010',
        ),
      ),
      onChanged: (_) {},
    );

    final Rect swatchPanelRect =
        tester.getRect(find.byKey(const Key('theme-color-picker-swatches')));
    final Rect pickerAreaRect =
        tester.getRect(find.byKey(const Key('theme-picker-sv-area')));

    expect(swatchPanelRect.top, equals(pickerAreaRect.top));
    expect(swatchPanelRect.bottom, equals(pickerAreaRect.bottom));
  });

  testWidgets('editing a role updates the embedded picker and preview controller',
      (WidgetTester tester) async {
    final _RecordingThemePreviewController previewController =
        _RecordingThemePreviewController();
    SharedOverrideEditorValue<dp.ThemeData>? latestValue;

    await pumpThemeEditor(
      tester,
      value: const SharedOverrideEditorValue<dp.ThemeData>(
        activeSource: dp.LayoutChoiceActiveSource.shared,
        sharedValue: dp.ThemeData(
          displayName: 'Test Theme',
          primaryColor: '#ff0000',
          secondaryColor: '#00ff00',
          accentColor: '#0000ff',
          backgroundColor: '#101010',
        ),
      ),
      onChanged: (SharedOverrideEditorValue<dp.ThemeData> nextValue) {
        latestValue = nextValue;
      },
      previewController: previewController,
    );

    expect(find.byKey(const Key('theme-color-picker-panel')), findsOneWidget);
    expect(find.byKey(const Key('theme-color-picker-swatches')), findsOneWidget);
    expect(find.byKey(const Key('theme-picker-sv-area')), findsOneWidget);
    expect(find.byKey(const Key('theme-picker-hue-strip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.pumpAndSettle();

    expect(latestValue, isNotNull);
    expect(latestValue!.sharedValue.primaryColor, equals('#2196f3'));
    expect(previewController.lastPreviewValue, isNotNull);
    expect(
      previewController.lastPreviewValue!.effectiveValue.primaryColor,
      equals('#2196f3'),
    );
  });

  testWidgets('selected theme role is visibly emphasized',
      (WidgetTester tester) async {
    await pumpThemeEditor(
      tester,
      value: const SharedOverrideEditorValue<dp.ThemeData>(
        activeSource: dp.LayoutChoiceActiveSource.shared,
        sharedValue: dp.ThemeData(
          displayName: 'Test Theme',
          primaryColor: '#ff0000',
          secondaryColor: '#00ff00',
          accentColor: '#0000ff',
          backgroundColor: '#101010',
        ),
      ),
      onChanged: (_) {},
    );

    final DecoratedBox rootCard = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const Key('theme-role-Root')),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final DecoratedBox backgroundCard = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const Key('theme-role-Background')),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final BoxDecoration rootDecoration =
        rootCard.decoration as BoxDecoration;
    final BoxDecoration backgroundDecoration =
        backgroundCard.decoration as BoxDecoration;

    expect((rootDecoration.border! as Border).top.width, greaterThan(2));
    expect(
      (backgroundDecoration.border! as Border).top.width,
      equals(2),
    );
  });

  testWidgets('dragging the embedded picker previews live before confirmation',
      (WidgetTester tester) async {
    final _RecordingThemePreviewController previewController =
        _RecordingThemePreviewController();

    await pumpThemeEditor(
      tester,
      value: const SharedOverrideEditorValue<dp.ThemeData>(
        activeSource: dp.LayoutChoiceActiveSource.shared,
        sharedValue: dp.ThemeData(
          displayName: 'Test Theme',
          primaryColor: '#ff0000',
          secondaryColor: '#00ff00',
          accentColor: '#0000ff',
          backgroundColor: '#101010',
        ),
      ),
      onChanged: (_) {},
      previewController: previewController,
    );

    await tester.drag(
      find.byKey(const Key('theme-picker-hue-strip')),
      const Offset(0, 60),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(previewController.lastPreviewValue, isNotNull);
    expect(
      previewController.lastPreviewValue!.effectiveValue.primaryColor,
      isNot('#ff0000'),
    );
  });

  testWidgets('switching to override clones shared theme when no override exists',
      (WidgetTester tester) async {
    SharedOverrideEditorValue<dp.ThemeData>? latestValue;

    await pumpThemeEditor(
      tester,
      value: const SharedOverrideEditorValue<dp.ThemeData>(
        activeSource: dp.LayoutChoiceActiveSource.shared,
        sharedValue: dp.ThemeData(
          displayName: 'Shared Theme',
          primaryColor: '#112233',
          secondaryColor: '#223344',
          accentColor: '#334455',
          backgroundColor: '#000000',
        ),
      ),
      onChanged: (SharedOverrideEditorValue<dp.ThemeData> nextValue) {
        latestValue = nextValue;
      },
    );

    await tester.tap(find.byKey(const Key('theme-source-override')));
    await tester.pumpAndSettle();

    expect(latestValue, isNotNull);
    expect(
      latestValue!.activeSource,
      equals(dp.LayoutChoiceActiveSource.overrideValue),
    );
    expect(latestValue!.overrideValue, isNotNull);
    expect(latestValue!.overrideValue!.primaryColor, equals('#112233'));
  });

  testWidgets('reset clears the saved override and returns to shared mode',
      (WidgetTester tester) async {
    SharedOverrideEditorValue<dp.ThemeData>? latestValue;

    await pumpThemeEditor(
      tester,
      value: const SharedOverrideEditorValue<dp.ThemeData>(
        activeSource: dp.LayoutChoiceActiveSource.overrideValue,
        sharedValue: dp.ThemeData(
          displayName: 'Shared Theme',
          primaryColor: '#112233',
          secondaryColor: '#223344',
          accentColor: '#334455',
          backgroundColor: '#000000',
        ),
        overrideValue: dp.ThemeData(
          displayName: 'Override Theme',
          primaryColor: '#abcdef',
          secondaryColor: '#bcdef0',
          accentColor: '#cdef01',
          backgroundColor: '#101010',
        ),
      ),
      onChanged: (SharedOverrideEditorValue<dp.ThemeData> nextValue) {
        latestValue = nextValue;
      },
    );

    expect(find.byKey(const Key('theme-reset-override')), findsOneWidget);
    await tester.tap(find.byKey(const Key('theme-reset-override')));
    await tester.pumpAndSettle();

    expect(latestValue, isNotNull);
    expect(
      latestValue!.activeSource,
      equals(dp.LayoutChoiceActiveSource.shared),
    );
    expect(latestValue!.overrideValue, isNull);
  });

  testWidgets('standalone picker reports throttled updates during drag',
      (WidgetTester tester) async {
    final List<String> updates = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 520,
            child: HsvColorPicker(
              initialHexColor: '#ff0000',
              presetHexColors: const <String>['#ff0000', '#00ff00'],
              onChanged: (String nextHexColor) {
                updates.add(nextHexColor);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('theme-picker-hue-strip'))),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(updates, isNotEmpty);

    final int updateCountDuringDrag = updates.length;
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(updates.length, greaterThan(updateCountDuringDrag));

    await gesture.up();
  });

  testWidgets('theme dialog opens and clears preview on cancel',
      (WidgetTester tester) async {
    final _RecordingThemePreviewController previewController =
        _RecordingThemePreviewController();
    const SharedOverrideEditorValue<dp.ThemeData> initialTheme =
        SharedOverrideEditorValue<dp.ThemeData>(
      activeSource: dp.LayoutChoiceActiveSource.shared,
      sharedValue: dp.ThemeData(
        displayName: 'Test Theme',
        primaryColor: '#ff0000',
        secondaryColor: '#00ff00',
        accentColor: '#0000ff',
        backgroundColor: '#101010',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Material(
              child: FilledButton(
                onPressed: () {
                  showThemeEditorDialog(
                    context: context,
                    initialValue: initialTheme,
                    previewController: previewController,
                    showSourceSelector: true,
                  );
                },
                child: const Text('Open Theme Dialog'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Theme Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byKey(const Key('theme-source-shared')), findsOneWidget);
    expect(find.byKey(const Key('theme-source-override')), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(previewController.lastPreviewValue, isNotNull);
    expect(
      previewController.lastPreviewValue!.effectiveValue.primaryColor,
      equals(initialTheme.sharedValue.primaryColor),
    );
    expect(
      previewController.lastPreviewValue!.effectiveValue.secondaryColor,
      equals(initialTheme.sharedValue.secondaryColor),
    );
    expect(
      previewController.lastPreviewValue!.effectiveValue.accentColor,
      equals(initialTheme.sharedValue.accentColor),
    );
    expect(
      previewController.lastPreviewValue!.effectiveValue.backgroundColor,
      equals(initialTheme.sharedValue.backgroundColor),
    );
    expect(previewController.wasCleared, isTrue);
  });
}
