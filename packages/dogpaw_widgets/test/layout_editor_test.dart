import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingLayoutPreviewController
    implements EditorPreviewController<dp.LayoutDraft> {
  dp.LayoutDraft? lastPreviewValue;
  bool wasCleared = false;

  @override
  Future<void> preview(dp.LayoutDraft value) async {
    lastPreviewValue = value;
  }

  @override
  Future<void> clear() async {
    wasCleared = true;
  }
}

void main() {
  Future<void> pumpLayoutEditor(
    WidgetTester tester, {
    required dp.LayoutDraft value,
    required ValueChanged<dp.LayoutDraft> onChanged,
    EditorPreviewController<dp.LayoutDraft>? previewController,
    LayoutEditorFieldVisibility targetVisibility =
        LayoutEditorFieldVisibility.editable,
    LayoutEditorFieldVisibility themeVisibility =
        LayoutEditorFieldVisibility.editable,
    LayoutEditorFieldVisibility scaleVisibility =
        LayoutEditorFieldVisibility.editable,
    List<LayoutEditorTargetOption> availableTargets =
        const <LayoutEditorTargetOption>[],
    double width = 1200,
    double height = 900,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: width,
            height: height,
            child: LayoutEditor(
              value: value,
              onChanged: onChanged,
              previewController: previewController,
              targetVisibility: targetVisibility,
              themeVisibility: themeVisibility,
              scaleVisibility: scaleVisibility,
              availableTargets: availableTargets,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders layout controls without bend range', (WidgetTester tester) async {
    await pumpLayoutEditor(
      tester,
      value: const dp.LayoutDraft(),
      onChanged: (_) {},
      availableTargets: const <LayoutEditorTargetOption>[
        LayoutEditorTargetOption(
          targetKey: 'Voice2LED_1',
          appName: 'Voice2LED',
          entityName: 'Voice2LED_1',
        ),
      ],
    );

    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Intervals'), findsOneWidget);
    expect(find.text('Transpose'), findsOneWidget);
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Scale'), findsOneWidget);
    expect(find.textContaining('Bend'), findsNothing);
  });

  testWidgets('top row keeps mode on the left and option cards on the right',
      (WidgetTester tester) async {
    await pumpLayoutEditor(
      tester,
      value: const dp.LayoutDraft(),
      onChanged: (_) {},
      availableTargets: const <LayoutEditorTargetOption>[
        LayoutEditorTargetOption(
          targetKey: 'Voice2LED_1',
          appName: 'Voice2LED',
          entityName: 'Voice2LED_1',
        ),
      ],
    );

    final Rect modeRect =
        tester.getRect(find.byKey(const Key('layout-mode-card')));
    final Rect themeRect =
        tester.getRect(find.byKey(const Key('layout-theme-card')));
    final Rect scaleRect =
        tester.getRect(find.byKey(const Key('layout-scale-card')));
    final Rect targetRect =
        tester.getRect(find.byKey(const Key('layout-target-card')));

    expect(modeRect.top, equals(themeRect.top));
    expect(themeRect.top, equals(scaleRect.top));
    expect(scaleRect.top, equals(targetRect.top));
    expect(modeRect.left, lessThan(themeRect.left));
    expect(themeRect.left, lessThan(scaleRect.left));
    expect(scaleRect.left, lessThan(targetRect.left));
    expect(modeRect.width, greaterThan(themeRect.width * 2));
  });

  testWidgets('mode expands across the full top row when option cards are hidden',
      (WidgetTester tester) async {
    await pumpLayoutEditor(
      tester,
      value: const dp.LayoutDraft(),
      onChanged: (_) {},
      targetVisibility: LayoutEditorFieldVisibility.hidden,
      themeVisibility: LayoutEditorFieldVisibility.hidden,
      scaleVisibility: LayoutEditorFieldVisibility.hidden,
    );

    final Rect topRowRect =
        tester.getRect(find.byKey(const Key('layout-editor-top-row')));
    final Rect modeRect =
        tester.getRect(find.byKey(const Key('layout-mode-card')));

    expect(modeRect.width, greaterThan(topRowRect.width * 0.9));
    expect(find.byKey(const Key('layout-theme-card')), findsNothing);
    expect(find.byKey(const Key('layout-scale-card')), findsNothing);
    expect(find.byKey(const Key('layout-target-card')), findsNothing);
  });

  testWidgets('changing mode and transpose emits updated drafts and previews',
      (WidgetTester tester) async {
    final _RecordingLayoutPreviewController previewController =
        _RecordingLayoutPreviewController();
    dp.LayoutDraft currentDraft = const dp.LayoutDraft();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (
              BuildContext context,
              void Function(void Function()) setState,
            ) {
              return SizedBox(
                width: 1200,
                height: 900,
                child: LayoutEditor(
                  value: currentDraft,
                  onChanged: (dp.LayoutDraft nextDraft) {
                    setState(() {
                      currentDraft = nextDraft;
                    });
                  },
                  previewController: previewController,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('layout-mode-chromatic')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('layout-octave-increment')));
    await tester.tap(find.byKey(const Key('layout-octave-increment')));
    await tester.pumpAndSettle();

    expect(currentDraft.settings.layoutMode, equals('chromatic'));
    expect(currentDraft.settings.octaveTranspose, equals(1));
    expect(previewController.lastPreviewValue, isNotNull);
    expect(previewController.lastPreviewValue!.settings.layoutMode, equals('chromatic'));
  });

  testWidgets('flip negates interval values', (WidgetTester tester) async {
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      settings: dp.LayoutSettings(
        rowInterval: 3,
        rowIntervalUp: true,
        columnInterval: -1,
        columnIntervalRight: true,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (
              BuildContext context,
              void Function(void Function()) setState,
            ) {
              return SizedBox(
                width: 1200,
                height: 900,
                child: LayoutEditor(
                  value: currentDraft,
                  onChanged: (dp.LayoutDraft nextDraft) {
                    setState(() {
                      currentDraft = nextDraft;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('layout-row-direction-toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('layout-column-direction-toggle')));
    await tester.tap(find.byKey(const Key('layout-column-direction-toggle')));
    await tester.pumpAndSettle();

    expect(currentDraft.settings.rowInterval, equals(-3));
    expect(currentDraft.settings.columnInterval, equals(1));
  });

  testWidgets('editable target section can switch between shared and target',
      (WidgetTester tester) async {
    dp.LayoutDraft? latestDraft;

    await pumpLayoutEditor(
      tester,
      value: const dp.LayoutDraft(),
      onChanged: (dp.LayoutDraft nextDraft) {
        latestDraft = nextDraft;
      },
      availableTargets: const <LayoutEditorTargetOption>[
        LayoutEditorTargetOption(
          targetKey: 'Voice2LED_2',
          appName: 'Voice2LED',
          entityName: 'Voice2LED_2',
        ),
      ],
    );

    expect(find.text('SHARED'), findsOneWidget);

    await tester.tap(find.byKey(const Key('layout-target-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout-target-option-Voice2LED_2')));
    await tester.pumpAndSettle();

    expect(latestDraft, isNotNull);
    expect(latestDraft!.scope, const dp.LayoutScopeSettings.targeted('Voice2LED_2'));
  });

  testWidgets('hidden target section is omitted', (WidgetTester tester) async {
    await pumpLayoutEditor(
      tester,
      value: const dp.LayoutDraft(),
      onChanged: (_) {},
      targetVisibility: LayoutEditorFieldVisibility.hidden,
    );

    expect(find.text('Target'), findsNothing);
    expect(find.byKey(const Key('layout-target-button')), findsNothing);
  });

  testWidgets('custom theme and scale flows can be opened from the layout editor',
      (WidgetTester tester) async {
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      themeChoice: dp.LayoutThemeChoice.inline(
        dp.ThemeData(
          displayName: 'Inline Theme',
          primaryColor: '#ff0000',
          secondaryColor: '#00ff00',
          accentColor: '#0000ff',
          backgroundColor: '#101010',
        ),
      ),
      scaleChoice: dp.LayoutScaleChoice.inline(
        dp.ScaleData(
          displayName: 'Inline Scale',
          rootNote: 0,
          noteCategories: <int>[1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (
              BuildContext context,
              void Function(void Function()) setState,
            ) {
              return SizedBox(
                width: 1200,
                child: LayoutEditor(
                  value: currentDraft,
                  onChanged: (dp.LayoutDraft nextDraft) {
                    setState(() {
                      currentDraft = nextDraft;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('layout-theme-button')));
    await tester.tap(find.byKey(const Key('layout-theme-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layout-theme-choice-row')), findsOneWidget);
    expect(find.text('Edit Custom'), findsNothing);
    expect(find.byKey(const Key('layout-theme-option-current')), findsOneWidget);
    expect(find.byKey(const Key('layout-theme-option-custom')), findsOneWidget);
    await tester.tap(find.byKey(const Key('layout-theme-option-custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-role-Root')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('layout-scale-button')));
    await tester.tap(find.byKey(const Key('layout-scale-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layout-scale-choice-row')), findsOneWidget);
    expect(find.text('Edit Custom'), findsNothing);
    expect(find.byKey(const Key('layout-scale-option-current')), findsOneWidget);
    expect(find.byKey(const Key('layout-scale-option-custom')), findsOneWidget);
    await tester.tap(find.byKey(const Key('layout-scale-option-custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scale-root-note-C')), findsOneWidget);
  });

  testWidgets('inline theme editor forwards live preview updates through the layout preview controller',
      (WidgetTester tester) async {
    final _RecordingLayoutPreviewController previewController =
        _RecordingLayoutPreviewController();
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      themeChoice: dp.LayoutThemeChoice.inline(
        dp.ThemeData(
          displayName: 'Inline Theme',
          primaryColor: '#ff0000',
          secondaryColor: '#00ff00',
          accentColor: '#0000ff',
          backgroundColor: '#101010',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (
              BuildContext context,
              void Function(void Function()) setState,
            ) {
              return SizedBox(
                width: 1200,
                child: LayoutEditor(
                  value: currentDraft,
                  onChanged: (dp.LayoutDraft nextDraft) {
                    setState(() {
                      currentDraft = nextDraft;
                    });
                  },
                  previewController: previewController,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('layout-theme-button')));
    await tester.tap(find.byKey(const Key('layout-theme-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout-theme-option-custom')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.pumpAndSettle();

    expect(previewController.lastPreviewValue, isNotNull);
    expect(
      previewController.lastPreviewValue!.themeChoice.inlineTheme?.primaryColor,
      equals('#2196f3'),
    );
  });

  testWidgets('inline scale editor forwards live preview updates through the layout preview controller',
      (WidgetTester tester) async {
    final _RecordingLayoutPreviewController previewController =
        _RecordingLayoutPreviewController();
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      scaleChoice: dp.LayoutScaleChoice.inline(
        dp.ScaleData(
          displayName: 'Inline Scale',
          rootNote: 0,
          noteCategories: <int>[1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (
              BuildContext context,
              void Function(void Function()) setState,
            ) {
              return SizedBox(
                width: 1200,
                child: LayoutEditor(
                  value: currentDraft,
                  onChanged: (dp.LayoutDraft nextDraft) {
                    setState(() {
                      currentDraft = nextDraft;
                    });
                  },
                  previewController: previewController,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('layout-scale-button')));
    await tester.tap(find.byKey(const Key('layout-scale-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout-scale-option-custom')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scale-root-note-D')));
    await tester.pumpAndSettle();

    expect(previewController.lastPreviewValue, isNotNull);
    expect(
      previewController.lastPreviewValue!.scaleChoice.inlineScale?.rootNote,
      equals(2),
    );
  });

  testWidgets('layout dialog opens and clears preview on cancel',
      (WidgetTester tester) async {
    final _RecordingLayoutPreviewController previewController =
        _RecordingLayoutPreviewController();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Center(
              child: FilledButton(
                onPressed: () {
                  showLayoutEditorDialog(
                    context: context,
                    initialValue: const dp.LayoutDraft(),
                    previewController: previewController,
                    availableTargets: const <LayoutEditorTargetOption>[
                      LayoutEditorTargetOption(
                        targetKey: 'Voice2LED_1',
                        appName: 'Voice2LED',
                        entityName: 'Voice2LED_1',
                      ),
                    ],
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layout-editor-dialog-shell')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('layout-editor-dialog-shell')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(previewController.wasCleared, isTrue);
  });
}
