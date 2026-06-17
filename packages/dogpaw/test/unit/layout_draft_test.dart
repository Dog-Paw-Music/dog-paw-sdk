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

    test('parses bare resolved theme and scale data in layout refs', () {
      final LayoutData layoutData = LayoutData.fromJson(
        <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Resolved Layout',
          JsonFields.KEY_INTENTS: <String, dynamic>{},
          JsonFields.KEY_COLORS: <String, dynamic>{},
          JsonFields.THEME_REF: <String, dynamic>{
            JsonFields.DISPLAY_NAME: 'Resolved Theme',
            JsonFields.PRIMARY_COLOR: 'rgba(17,17,17,255)',
            JsonFields.SECONDARY_COLOR: 'rgba(34,34,34,255)',
            JsonFields.ACCENT_COLOR: 'rgba(51,51,51,255)',
            JsonFields.BACKGROUND_COLOR: 'rgba(68,68,68,255)',
          },
          JsonFields.SCALE_REF: <String, dynamic>{
            JsonFields.DISPLAY_NAME: 'Resolved Scale',
            JsonFields.ROOT_NOTE: 0,
            JsonFields.NOTE_CATEGORIES: <int>[
              3,
              -1,
              1,
              -1,
              1,
              1,
              -1,
              1,
              -1,
              1,
              -1,
              1,
            ],
          },
        },
      );

      expect(layoutData.themeRef, isNotNull);
      expect(layoutData.themeRef!.type, equals(ReferenceType.inline));
      expect(layoutData.themeRef!.inlineData, isNotNull);
      expect(
        layoutData.themeRef!.inlineData!.spec!.primaryColor,
        equals('rgba(17,17,17,255)'),
      );

      expect(layoutData.scaleRef, isNotNull);
      expect(layoutData.scaleRef!.type, equals(ReferenceType.inline));
      expect(layoutData.scaleRef!.inlineData, isNotNull);
      expect(layoutData.scaleRef!.inlineData!.spec!.rootNote, equals(0));
      expect(
        layoutData.scaleRef!.inlineData!.spec!.noteCategories.first,
        equals(3),
      );
    });
  });
}
