import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayoutDraft', () {
    test('defaults to shared layout with current theme and scale', () {
      const LayoutDraft draft = LayoutDraft();

      expect(draft.scope, const LayoutScopeSettings.shared());
      expect(draft.themeChoice, const LayoutThemeChoice.current());
      expect(draft.scaleChoice, const LayoutScaleChoice.current());
      expect(draft.settings, const LayoutSettings());
      expect(draft.colorStrategy, const LayoutColorStrategy.scaleCategories());
    });

    test('serializes and restores editable draft state', () {
      final LayoutDraft draft = LayoutDraft(
        settings: const LayoutSettings(
          layoutMode: 'chromatic',
          rowInterval: 5,
          columnInterval: 2,
          rowIntervalUp: false,
          columnIntervalRight: false,
          octaveTranspose: 1,
          semitoneTranspose: -2,
        ),
        scope: const LayoutScopeSettings.targeted('Voice2LED_2'),
        themeChoice: LayoutThemeChoice.inline(
          const ThemeData(
            displayName: 'Inline Theme',
            primaryColor: '#ff0000',
            secondaryColor: '#00ff00',
            accentColor: '#0000ff',
            backgroundColor: '#101010',
          ),
        ),
        scaleChoice: LayoutScaleChoice.inline(
          const ScaleData(
            displayName: 'Inline Scale',
            rootNote: 2,
            noteCategories: <int>[1, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
          ),
        ),
        colorStrategy: LayoutColorStrategy.noteNumberMap(
          <int, LayoutColorValue>{
            0: const LayoutColorValue.themeRole('primary'),
            7: const LayoutColorValue.rgba('rgba(10,20,30,255)'),
          },
        ),
      );

      final LayoutDraft restored = LayoutDraft.fromJson(draft.toJson());

      expect(restored, equals(draft));
    });

    test('builds layout data from targeted inline draft values', () {
      final LayoutDraft draft = LayoutDraft(
        scope: const LayoutScopeSettings.targeted('Voice2LED_2'),
        themeChoice: LayoutThemeChoice.inline(
          const ThemeData(
            displayName: 'Inline Theme',
            primaryColor: '#ff0000',
            secondaryColor: '#00ff00',
            accentColor: '#0000ff',
            backgroundColor: '#101010',
          ),
        ),
        scaleChoice: LayoutScaleChoice.inline(
          const ScaleData(
            displayName: 'Inline Scale',
            rootNote: 0,
            noteCategories: <int>[3, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
          ),
        ),
      );

      final LayoutData layoutData = draft.toLayoutData(
        displayName: 'Draft Layout',
        bounds: const LayoutGridBounds(
          startColumn: 0,
          endColumn: 1,
          startRow: 0,
          endRow: 1,
        ),
      );

      expect(layoutData.displayName, equals('Draft Layout'));
      expect(layoutData.scope, equals('targeted'));
      expect(layoutData.targetKey, equals('Voice2LED_2'));
      expect(layoutData.keyIntents.length, equals(4));
      expect(layoutData.themeRef, isNotNull);
      expect(layoutData.scaleRef, isNotNull);
    });

    test('writes note-number color strategies into layout output', () {
      final LayoutDraft draft = LayoutDraft(
        colorStrategy: LayoutColorStrategy.noteNumberMap(
          <int, LayoutColorValue>{
            0: const LayoutColorValue.themeRole('accent'),
          },
        ),
      );

      final LayoutData layoutData = draft.toLayoutData(
        displayName: 'Color Layout',
      );

      expect(layoutData.keyColors.containsKey(JsonFields.NOTE_NUMBER_MAP), isTrue);
      expect(
        (layoutData.keyColors[JsonFields.NOTE_NUMBER_MAP] as Map<String, dynamic>)['0'],
        equals('accent'),
      );
    });
  });
}
