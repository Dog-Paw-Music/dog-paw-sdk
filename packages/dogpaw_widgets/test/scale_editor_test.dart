import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingScalePreviewController
    implements EditorPreviewController<dp.ScaleData> {
  bool wasCleared = false;

  @override
  Future<void> preview(dp.ScaleData value) async {}

  @override
  Future<void> clear() async {
    wasCleared = true;
  }
}

void main() {
  /// Return the rendered paragraph for one scale-option label.
  ///
  /// Parameters:
  /// - `tester`: Widget tester owning the current render tree.
  /// - `scaleName`: Scale-option label to inspect.
  ///
  /// Return value:
  /// - The `RenderParagraph` for the requested scale label.
  ///
  /// Requirements/Preconditions:
  /// - The current widget tree must include a scale option with the matching key.
  ///
  /// Guarantees/Postconditions:
  /// - Returns the paragraph actually used for painting the visible label.
  ///
  /// Invariants:
  /// - Does not mutate the widget tree or test state.
  RenderParagraph renderScaleLabel(
    WidgetTester tester,
    String scaleName,
  ) {
    return tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(Key('scale-option-$scaleName')),
        matching: find.byType(RichText),
      ),
    );
  }

  /// Return the configured text widget for one scale-option label.
  ///
  /// Parameters:
  /// - `tester`: Widget tester owning the current widget tree.
  /// - `scaleName`: Scale-option label to inspect.
  ///
  /// Return value:
  /// - The `Text` widget inside the requested scale card.
  ///
  /// Requirements/Preconditions:
  /// - The current widget tree must include a scale option with the matching key.
  ///
  /// Guarantees/Postconditions:
  /// - Returns the widget configuration used for text overflow behavior.
  ///
  /// Invariants:
  /// - Does not mutate the widget tree or test state.
  Text widgetScaleLabel(
    WidgetTester tester,
    String scaleName,
  ) {
    return tester.widget<Text>(
      find.descendant(
        of: find.byKey(Key('scale-option-$scaleName')),
        matching: find.byType(Text),
      ),
    );
  }

  Future<void> pumpScaleEditor(
    WidgetTester tester, {
    required dp.ScaleData value,
    required ValueChanged<dp.ScaleData> onChanged,
    double width = 1200,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: width,
            child: ScaleEditor(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders root controls, named scales, and piano keyboard',
      (WidgetTester tester) async {
    await pumpScaleEditor(
      tester,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (_) {},
    );

    expect(find.byKey(const Key('scale-root-note-C')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-Db')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-D')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-Eb')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-E')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-F')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-Gb')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-G')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-Ab')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-A')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-Bb')), findsOneWidget);
    expect(find.byKey(const Key('scale-root-note-B')), findsOneWidget);
    expect(find.byKey(const Key('scale-option-Major')), findsOneWidget);
    expect(find.byKey(const Key('scale-option-Minor')), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);
    expect(find.byKey(const Key('scale-root-row')), findsOneWidget);
    expect(find.byKey(const Key('scale-selection-grid')), findsOneWidget);
    expect(find.byType(AnimatedScale), findsWidgets);
    expect(find.byType(AnimatedDefaultTextStyle), findsWidgets);
  });

  testWidgets('root note selection transposes the current scale',
      (WidgetTester tester) async {
    dp.ScaleData? latestValue;

    await pumpScaleEditor(
      tester,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (dp.ScaleData nextValue) {
        latestValue = nextValue;
      },
    );

    await tester.ensureVisible(find.byKey(const Key('scale-root-note-Db')));
    await tester.tap(find.byKey(const Key('scale-root-note-Db')));
    await tester.pumpAndSettle();

    expect(latestValue, isNotNull);
    expect(latestValue!.rootNote, equals(1));
    expect(dp.ScaleCatalog.detectScaleName(latestValue!), equals('Major'));
  });

  testWidgets('named scale selection applies a new scale pattern',
      (WidgetTester tester) async {
    dp.ScaleData? latestValue;

    await pumpScaleEditor(
      tester,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (dp.ScaleData nextValue) {
        latestValue = nextValue;
      },
    );

    await tester.tap(find.byKey(const Key('scale-option-Minor')));
    await tester.pumpAndSettle();

    expect(latestValue, isNotNull);
    expect(dp.ScaleCatalog.detectScaleName(latestValue!), equals('Minor'));
  });

  testWidgets('root row uses square selected note and wider unselected notes',
      (WidgetTester tester) async {
    await pumpScaleEditor(
      tester,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (_) {},
    );

    final Finder selectedRootCard = find.descendant(
      of: find.byKey(const Key('scale-root-note-C')),
      matching: find.byType(AnimatedContainer),
    );
    final Finder unselectedRootCard = find.descendant(
      of: find.byKey(const Key('scale-root-note-Db')),
      matching: find.byType(AnimatedContainer),
    );

    final Size selectedSize = tester.getSize(selectedRootCard);
    final Size unselectedSize = tester.getSize(unselectedRootCard);

    expect(selectedSize.width, equals(selectedSize.height));
    expect(selectedSize.width, greaterThan(56));
    expect(unselectedSize.width, greaterThan(unselectedSize.height));
  });

  testWidgets('root row animates horizontal note movement during selection',
      (WidgetTester tester) async {
    dp.ScaleData currentValue = dp.ScaleCatalog.scaleDataForName(
      scaleName: 'Major',
      rootNote: 0,
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
                child: ScaleEditor(
                  value: currentValue,
                  onChanged: (dp.ScaleData nextValue) {
                    setState(() {
                      currentValue = nextValue;
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

    final Finder movedNote = find.byKey(const Key('scale-root-note-E'));
    final double initialLeft = tester.getTopLeft(movedNote).dx;

    await tester.tap(find.byKey(const Key('scale-root-note-E')));
    await tester.pump();
    final double midAnimationLeft = tester.getTopLeft(movedNote).dx;

    await tester.pump(const Duration(milliseconds: 240));
    final double finalLeft = tester.getTopLeft(movedNote).dx;

    expect(finalLeft, isNot(initialLeft));
    expect(midAnimationLeft, isNot(finalLeft));
  });

  testWidgets('only the selected scale card grows to fit longer text',
      (WidgetTester tester) async {
    await pumpScaleEditor(
      tester,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (_) {},
    );

    final Finder selectedCard = find.descendant(
      of: find.byKey(const Key('scale-option-Major')),
      matching: find.byType(AnimatedContainer),
    );
    final Finder unselectedCard = find.descendant(
      of: find.byKey(const Key('scale-option-Mixolydian')),
      matching: find.byType(AnimatedContainer),
    );
    final Finder secondUnselectedCard = find.descendant(
      of: find.byKey(const Key('scale-option-Lydian')),
      matching: find.byType(AnimatedContainer),
    );

    final Size selectedCardSize = tester.getSize(selectedCard);
    final Size unselectedCardSize = tester.getSize(unselectedCard);
    final Size secondUnselectedCardSize = tester.getSize(secondUnselectedCard);

    expect(selectedCardSize.width, greaterThan(unselectedCardSize.width));
    expect(selectedCardSize.height, greaterThan(unselectedCardSize.height));
    expect(secondUnselectedCardSize, equals(unselectedCardSize));
  });

  testWidgets('embedded editor keeps six scale columns before wrapping',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await pumpScaleEditor(
      tester,
      width: 1120,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (_) {},
    );

    final double majorTop =
        tester.getTopLeft(find.byKey(const Key('scale-option-Major'))).dy;
    final double phrygianTop =
        tester.getTopLeft(find.byKey(const Key('scale-option-Phrygian'))).dy;
    final double lydianTop =
        tester.getTopLeft(find.byKey(const Key('scale-option-Lydian'))).dy;

    expect(
      phrygianTop,
      equals(majorTop),
    );
    expect(lydianTop, greaterThan(majorTop));
  });

  testWidgets('scale selection grid spans the full width and stays centered',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await pumpScaleEditor(
      tester,
      width: 1120,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (_) {},
    );

    final Rect gridRect =
        tester.getRect(find.byKey(const Key('scale-selection-grid')));
    final Rect majorRect =
        tester.getRect(find.byKey(const Key('scale-option-Major')));
    final Rect phrygianRect =
        tester.getRect(find.byKey(const Key('scale-option-Phrygian')));

    expect(majorRect.left, equals(gridRect.left));
    expect(phrygianRect.right, equals(gridRect.right));
  });

  testWidgets('scale labels stay within their limits without overflowing',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await pumpScaleEditor(
      tester,
      width: 1120,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Diminished (Half-Whole)',
        rootNote: 0,
      ),
      onChanged: (_) {},
    );

    for (final String scaleName in <String>[
      'Mixolydian',
      'Barry Harris',
      'Diminished (Half-Whole)',
      'Diminished (Whole-Half)',
    ]) {
      final Text label = widgetScaleLabel(tester, scaleName);
      final RenderParagraph paragraph = renderScaleLabel(tester, scaleName);

      expect(label.maxLines, equals(3), reason: scaleName);
      expect(label.overflow, equals(TextOverflow.ellipsis), reason: scaleName);
      expect(paragraph.didExceedMaxLines, isFalse, reason: scaleName);
    }
  });

  testWidgets('scale labels wrap at spaces without breaking single words',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await pumpScaleEditor(
      tester,
      width: 1120,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (_) {},
    );

    final Text minorPentatonicLabel =
        widgetScaleLabel(tester, 'Minor Pentatonic');
    final Text mixolydianLabel = widgetScaleLabel(tester, 'Mixolydian');
    final RenderParagraph minorPentatonicParagraph =
        renderScaleLabel(tester, 'Minor Pentatonic');
    final RenderParagraph mixolydianParagraph =
        renderScaleLabel(tester, 'Mixolydian');
    final List<TextBox> minorPentatonicBoxes =
        minorPentatonicParagraph.getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: minorPentatonicLabel.data!.length,
      ),
    );
    final List<TextBox> mixolydianBoxes = mixolydianParagraph.getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: mixolydianLabel.data!.length,
      ),
    );

    expect(minorPentatonicLabel.maxLines, equals(3));
    expect(minorPentatonicLabel.softWrap, isTrue);
    expect(minorPentatonicParagraph.didExceedMaxLines, isFalse);

    expect(mixolydianLabel.maxLines, equals(3));
    expect(mixolydianLabel.softWrap, isTrue);
    expect(mixolydianParagraph.didExceedMaxLines, isFalse);
    expect(mixolydianBoxes.length, equals(1));

    expect(
      minorPentatonicBoxes.length,
      greaterThan(mixolydianBoxes.length),
    );
  });

  testWidgets('scale editor does not use a scroll container',
      (WidgetTester tester) async {
    await pumpScaleEditor(
      tester,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (_) {},
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('piano key tap toggles note membership',
      (WidgetTester tester) async {
    dp.ScaleData currentValue = dp.ScaleCatalog.scaleDataForName(
      scaleName: 'Major',
      rootNote: 0,
    );

    await pumpScaleEditor(
      tester,
      value: currentValue,
      onChanged: (dp.ScaleData nextValue) {
        currentValue = nextValue;
      },
    );

    final Finder keyboardDb = find
        .descendant(
          of: find.byType(PianoKeyboard),
          matching: find.text('Db'),
        )
        .first;

    await tester.ensureVisible(keyboardDb);
    await tester.tap(keyboardDb);
    await tester.pumpAndSettle();

    expect(dp.ScaleCatalog.isIncluded(currentValue, 1), isTrue);
    expect(dp.ScaleCatalog.detectScaleName(currentValue), equals('Custom'));
  });

  testWidgets('out of scale white and black keys share the same gray color',
      (WidgetTester tester) async {
    await pumpScaleEditor(
      tester,
      value: dp.ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      ),
      onChanged: (_) {},
    );

    final Finder ebKey = find.ancestor(
      of: find.text('Eb'),
      matching: find.byType(GestureDetector),
    );
    final Finder gbKey = find.ancestor(
      of: find.text('Gb'),
      matching: find.byType(GestureDetector),
    );

    final Container ebContainer = tester.widget<Container>(
      find.descendant(of: ebKey.first, matching: find.byType(Container)).first,
    );
    final Container gbContainer = tester.widget<Container>(
      find.descendant(of: gbKey.first, matching: find.byType(Container)).first,
    );

    final BoxDecoration ebDecoration =
        ebContainer.decoration! as BoxDecoration;
    final BoxDecoration gbDecoration =
        gbContainer.decoration! as BoxDecoration;

    expect(ebDecoration.color, equals(gbDecoration.color));
  });

  testWidgets('scale dialog opens and clears preview on cancel',
      (WidgetTester tester) async {
    final _RecordingScalePreviewController previewController =
        _RecordingScalePreviewController();

    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Material(
              child: FilledButton(
                onPressed: () {
                  showScaleEditorDialog(
                    context: context,
                    initialValue: dp.ScaleCatalog.scaleDataForName(
                      scaleName: 'Major',
                      rootNote: 0,
                    ),
                    previewController: previewController,
                  );
                },
                child: const Text('Open Scale Dialog'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Scale Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(previewController.wasCleared, isTrue);
  });

  testWidgets('scale dialog uses an almost full-width layout',
      (WidgetTester tester) async {
    final _RecordingScalePreviewController previewController =
        _RecordingScalePreviewController();

    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Material(
              child: FilledButton(
                onPressed: () {
                  showScaleEditorDialog(
                    context: context,
                    initialValue: dp.ScaleCatalog.scaleDataForName(
                      scaleName: 'Major',
                      rootNote: 0,
                    ),
                    previewController: previewController,
                  );
                },
                child: const Text('Open Scale Dialog'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Scale Dialog'));
    await tester.pumpAndSettle();

    final Size dialogSize =
        tester.getSize(find.byKey(const Key('scale-editor-dialog-shell')));
    final double screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    expect(dialogSize.width, greaterThanOrEqualTo(screenWidth - 40));
  });

  testWidgets('scale dialog reserves enough extra vertical headroom',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Material(
              child: FilledButton(
                onPressed: () {
                  showScaleEditorDialog(
                    context: context,
                    initialValue: dp.ScaleCatalog.scaleDataForName(
                      scaleName: 'Major',
                      rootNote: 0,
                    ),
                  );
                },
                child: const Text('Open Scale Dialog'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Scale Dialog'));
    await tester.pumpAndSettle();

    final Size dialogSize =
        tester.getSize(find.byKey(const Key('scale-editor-dialog-shell')));

    expect(dialogSize.height, greaterThanOrEqualTo(560));
  });

  testWidgets('scale dialog keeps six columns and no nested scroll view',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Material(
              child: FilledButton(
                onPressed: () {
                  showScaleEditorDialog(
                    context: context,
                    initialValue: dp.ScaleCatalog.scaleDataForName(
                      scaleName: 'Major',
                      rootNote: 0,
                    ),
                  );
                },
                child: const Text('Open Scale Dialog'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Scale Dialog'));
    await tester.pumpAndSettle();

    final double majorTop =
        tester.getTopLeft(find.byKey(const Key('scale-option-Major'))).dy;
    final double phrygianTop =
        tester.getTopLeft(find.byKey(const Key('scale-option-Phrygian'))).dy;
    final double lydianTop =
        tester.getTopLeft(find.byKey(const Key('scale-option-Lydian'))).dy;

    expect(phrygianTop, equals(majorTop));
    expect(lydianTop, greaterThan(majorTop));
    expect(
      find.descendant(
        of: find.byKey(const Key('scale-editor-dialog-shell')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets('scale editor trims the piano section to fit the live 556px editor budget',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: 1200,
              height: 572,
              child: ScaleEditor(
                value: dp.ScaleCatalog.scaleDataForName(
                  scaleName: 'Major',
                  rootNote: 0,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Object? layoutException = tester.takeException();
    final Size keyboardSize = tester.getSize(find.byType(PianoKeyboard));

    expect(layoutException, isNull);
    expect(keyboardSize.height, equals(134));
  });
}
