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

const dp.ThemeData _sharedTheme = dp.ThemeData(
  displayName: 'Shared Theme',
  primaryColor: '#ff0000',
  secondaryColor: '#00ff00',
  accentColor: '#0000ff',
  backgroundColor: '#101010',
);

const dp.ScaleData _sharedScale = dp.ScaleData(
  displayName: 'Shared Scale',
  rootNote: 0,
  noteCategories: <int>[1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
);

void main() {
  Future<void> pumpLayoutEditor(
    WidgetTester tester, {
    required dp.LayoutDraft value,
    required ValueChanged<dp.LayoutDraft> onChanged,
    EditorPreviewController<dp.LayoutDraft>? previewController,
    dp.ThemeData sharedTheme = const dp.ThemeData(
      displayName: 'Shared Theme',
      primaryColor: '#ff0000',
      secondaryColor: '#00ff00',
      accentColor: '#0000ff',
      backgroundColor: '#101010',
    ),
    dp.ScaleData sharedScale = const dp.ScaleData(
      displayName: 'Shared Scale',
      rootNote: 0,
      noteCategories: <int>[1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
    ),
    ValueChanged<dp.ThemeData>? onSharedThemeChanged,
    ValueChanged<dp.ScaleData>? onSharedScaleChanged,
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
              sharedTheme: sharedTheme,
              sharedScale: sharedScale,
              onSharedThemeChanged: onSharedThemeChanged ?? (_) {},
              onSharedScaleChanged: onSharedScaleChanged ?? (_) {},
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

  testWidgets('theme and scale cards show status plus summaries',
      (WidgetTester tester) async {
    await pumpLayoutEditor(
      tester,
      value: const dp.LayoutDraft(
        themeChoice: dp.LayoutThemeChoice.overrideValue(
          dp.ThemeData(
            displayName: 'Override Theme',
            primaryColor: '#112233',
            secondaryColor: '#223344',
            accentColor: '#334455',
            backgroundColor: '#445566',
          ),
        ),
        scaleChoice: dp.LayoutScaleChoice.shared(
          overrideScale: dp.ScaleData(
            displayName: 'Dormant Override Scale',
            rootNote: 2,
            noteCategories: <int>[1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
          ),
        ),
      ),
      onChanged: (_) {},
      sharedScale: const dp.ScaleData(
        displayName: 'Shared Major',
        rootNote: 0,
        noteCategories: <int>[1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('layout-theme-card')),
        matching: find.text('OVERRIDE'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('layout-theme-preview-swatches')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('layout-theme-swatch-0')), findsOneWidget);
    expect(find.byKey(const Key('layout-theme-swatch-1')), findsOneWidget);
    expect(find.byKey(const Key('layout-theme-swatch-2')), findsOneWidget);
    expect(find.byKey(const Key('layout-theme-swatch-3')), findsOneWidget);

    expect(
      find.descendant(
        of: find.byKey(const Key('layout-scale-card')),
        matching: find.text('SHARED'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('layout-scale-summary')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('layout-scale-card')),
        matching: find.text('Shared Major'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('top row summaries fit without overflow in a tighter layout',
      (WidgetTester tester) async {
    await pumpLayoutEditor(
      tester,
      width: 980,
      height: 760,
      value: const dp.LayoutDraft(
        themeChoice: dp.LayoutThemeChoice.overrideValue(
          dp.ThemeData(
            displayName: 'Override Theme',
            primaryColor: '#112233',
            secondaryColor: '#223344',
            accentColor: '#334455',
            backgroundColor: '#445566',
          ),
        ),
        scaleChoice: dp.LayoutScaleChoice.overrideValue(
          dp.ScaleData(
            displayName: 'Db Diminished (Half-Whole)',
            rootNote: 1,
            noteCategories: <int>[1, -1, 1, 1, -1, 1, -1, 1, 1, -1, 1, -1],
          ),
        ),
      ),
      onChanged: (_) {},
    );

    final Object? layoutException = tester.takeException();
    expect(layoutException, isNull);

    final Rect topRowRect =
        tester.getRect(find.byKey(const Key('layout-editor-top-row')));
    final Rect themeRect =
        tester.getRect(find.byKey(const Key('layout-theme-card')));
    final Rect scaleRect =
        tester.getRect(find.byKey(const Key('layout-scale-card')));
    final Rect targetRect =
        tester.getRect(find.byKey(const Key('layout-target-card')));

    expect(themeRect.bottom, lessThanOrEqualTo(topRowRect.bottom));
    expect(scaleRect.bottom, lessThanOrEqualTo(topRowRect.bottom));
    expect(targetRect.bottom, lessThanOrEqualTo(topRowRect.bottom));
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
                  sharedTheme: _sharedTheme,
                  sharedScale: _sharedScale,
                  onSharedThemeChanged: (_) {},
                  onSharedScaleChanged: (_) {},
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
    expect(
      previewController.lastPreviewValue!
          .toLayoutData(displayName: 'Preview Layout')
          .bendMode,
      equals('fixed'),
    );
  });

  testWidgets('scale mode produces next-in-scale bend policy in shared draft output',
      (WidgetTester tester) async {
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      settings: dp.LayoutSettings(layoutMode: 'chromatic'),
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
                  sharedTheme: _sharedTheme,
                  sharedScale: _sharedScale,
                  onSharedThemeChanged: (_) {},
                  onSharedScaleChanged: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('layout-mode-scale')));
    await tester.pumpAndSettle();

    expect(currentDraft.settings.layoutMode, equals('scale'));
    expect(
      currentDraft.toLayoutData(displayName: 'Scale Layout').bendMode,
      equals('nextInScale'),
    );
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
                  sharedTheme: _sharedTheme,
                  sharedScale: _sharedScale,
                  onSharedThemeChanged: (_) {},
                  onSharedScaleChanged: (_) {},
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

    expect(
      find.descendant(
        of: find.byKey(const Key('layout-target-card')),
        matching: find.text('SHARED'),
      ),
      findsOneWidget,
    );

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

  testWidgets('theme and scale editors open directly from the layout editor',
      (WidgetTester tester) async {
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      themeChoice: dp.LayoutThemeChoice.overrideValue(
        dp.ThemeData(
          displayName: 'Inline Theme',
          primaryColor: '#ff0000',
          secondaryColor: '#00ff00',
          accentColor: '#0000ff',
          backgroundColor: '#101010',
        ),
      ),
      scaleChoice: dp.LayoutScaleChoice.overrideValue(
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
                  sharedTheme: _sharedTheme,
                  sharedScale: _sharedScale,
                  onSharedThemeChanged: (_) {},
                  onSharedScaleChanged: (_) {},
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
    expect(find.byKey(const Key('theme-role-Root')), findsOneWidget);
    expect(find.byKey(const Key('theme-source-shared')), findsOneWidget);
    expect(find.byKey(const Key('theme-source-override')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('layout-scale-button')));
    await tester.tap(find.byKey(const Key('layout-scale-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scale-root-note-C')), findsOneWidget);
    expect(find.byKey(const Key('scale-source-shared')), findsOneWidget);
    expect(find.byKey(const Key('scale-source-override')), findsOneWidget);
  });

  testWidgets('theme editor forwards live preview updates through the layout preview controller',
      (WidgetTester tester) async {
    final _RecordingLayoutPreviewController previewController =
        _RecordingLayoutPreviewController();
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      themeChoice: dp.LayoutThemeChoice.overrideValue(
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
                  sharedTheme: _sharedTheme,
                  sharedScale: _sharedScale,
                  onSharedThemeChanged: (_) {},
                  onSharedScaleChanged: (_) {},
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

    await tester.ensureVisible(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.tap(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.pumpAndSettle();

    expect(previewController.lastPreviewValue, isNotNull);
    expect(
      previewController.lastPreviewValue!.themeChoice.overrideTheme?.primaryColor,
      equals('#2196f3'),
    );
  });

  testWidgets('scale editor forwards live preview updates through the layout preview controller',
      (WidgetTester tester) async {
    final _RecordingLayoutPreviewController previewController =
        _RecordingLayoutPreviewController();
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      scaleChoice: dp.LayoutScaleChoice.overrideValue(
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
                  sharedTheme: _sharedTheme,
                  sharedScale: _sharedScale,
                  onSharedThemeChanged: (_) {},
                  onSharedScaleChanged: (_) {},
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

    await tester.tap(find.byKey(const Key('scale-root-note-D')));
    await tester.pumpAndSettle();

    expect(previewController.lastPreviewValue, isNotNull);
    expect(
      previewController.lastPreviewValue!.scaleChoice.overrideScale?.rootNote,
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
                    sharedTheme: _sharedTheme,
                    sharedScale: _sharedScale,
                    onSharedThemeChanged: (_) {},
                    onSharedScaleChanged: (_) {},
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

  testWidgets(
      'shared-mode theme preview keeps layout choice on shared and writes shared theme',
      (WidgetTester tester) async {
    final _RecordingLayoutPreviewController previewController =
        _RecordingLayoutPreviewController();
    final List<dp.ThemeData> sharedThemeWrites = <dp.ThemeData>[];
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      themeChoice: dp.LayoutThemeChoice.shared(),
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
                  sharedTheme: _sharedTheme,
                  sharedScale: _sharedScale,
                  onSharedThemeChanged: sharedThemeWrites.add,
                  onSharedScaleChanged: (_) {},
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

    await tester.ensureVisible(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.tap(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.pumpAndSettle();

    expect(previewController.lastPreviewValue, isNotNull);
    expect(
      previewController.lastPreviewValue!.themeChoice.activeSource,
      dp.LayoutChoiceActiveSource.shared,
    );
    expect(sharedThemeWrites, isNotEmpty);
    expect(sharedThemeWrites.last.primaryColor, '#2196f3');
    expect(
      currentDraft.themeChoice.activeSource,
      dp.LayoutChoiceActiveSource.shared,
    );
  });

  testWidgets(
      'override-mode theme preview updates override choice without writing shared',
      (WidgetTester tester) async {
    final _RecordingLayoutPreviewController previewController =
        _RecordingLayoutPreviewController();
    final List<dp.ThemeData> sharedThemeWrites = <dp.ThemeData>[];
    dp.LayoutDraft currentDraft = const dp.LayoutDraft(
      themeChoice: dp.LayoutThemeChoice.overrideValue(
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
                  sharedTheme: _sharedTheme,
                  sharedScale: _sharedScale,
                  onSharedThemeChanged: sharedThemeWrites.add,
                  onSharedScaleChanged: (_) {},
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

    await tester.ensureVisible(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.tap(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.pumpAndSettle();

    expect(previewController.lastPreviewValue, isNotNull);
    expect(
      previewController.lastPreviewValue!.themeChoice.activeSource,
      dp.LayoutChoiceActiveSource.overrideValue,
    );
    expect(
      previewController.lastPreviewValue!.themeChoice.overrideTheme?.primaryColor,
      '#2196f3',
    );
    expect(sharedThemeWrites, isEmpty);
  });

  testWidgets(
      'theme dialog cancel restores original shared theme and layout choice',
      (WidgetTester tester) async {
    final _RecordingLayoutPreviewController previewController =
        _RecordingLayoutPreviewController();
    final List<dp.ThemeData> sharedThemeWrites = <dp.ThemeData>[];
    const dp.LayoutDraft initialDraft = dp.LayoutDraft(
      themeChoice: dp.LayoutThemeChoice.shared(),
    );
    dp.LayoutDraft currentDraft = initialDraft;

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
                  sharedTheme: _sharedTheme,
                  sharedScale: _sharedScale,
                  onSharedThemeChanged: sharedThemeWrites.add,
                  onSharedScaleChanged: (_) {},
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

    await tester.ensureVisible(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.tap(find.byKey(const Key('theme-swatch-#2196f3')));
    await tester.pumpAndSettle();
    expect(sharedThemeWrites, isNotEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(previewController.wasCleared, isTrue);
    expect(
      previewController.lastPreviewValue!.themeChoice.activeSource,
      dp.LayoutChoiceActiveSource.shared,
    );
    expect(sharedThemeWrites.last, _sharedTheme);
    expect(
      currentDraft.themeChoice.activeSource,
      dp.LayoutChoiceActiveSource.shared,
    );
  });
}
