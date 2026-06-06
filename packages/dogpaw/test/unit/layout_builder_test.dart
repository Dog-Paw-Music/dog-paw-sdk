import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateIntervalGridKeyIntents', () {
    test('produces 64 keys for the default 8x8 grid', () {
      const LayoutSettings settings = LayoutSettings();

      final Map<String, List<Map<String, dynamic>>> intents =
          generateIntervalGridKeyIntents(settings);

      expect(intents.length, equals(64));
      for (int column = 0; column < 8; column += 1) {
        for (int row = 0; row < 8; row += 1) {
          expect(intents.containsKey('$column,$row'), isTrue);
          expect(intents['$column,$row'], hasLength(1));
        }
      }
    });

    test('uses scaleDegreesFromRoot in scale mode', () {
      const LayoutSettings settings = LayoutSettings(layoutMode: 'scale');

      final Map<String, List<Map<String, dynamic>>> intents =
          generateIntervalGridKeyIntents(settings);
      final Map<String, dynamic> firstIntent = intents['0,0']!.first;

      expect(firstIntent[JsonFields.INTENT], equals(JsonFields.MIDI_NOTE));
      expect(firstIntent.containsKey(JsonFields.SCALE_DEGREES_FROM_ROOT), isTrue);
      expect(firstIntent.containsKey(JsonFields.SEMITONES_FROM_ROOT), isFalse);
      expect(firstIntent.containsKey(JsonFields.OCTAVE), isTrue);
    });

    test('uses semitonesFromRoot in chromatic mode', () {
      const LayoutSettings settings = LayoutSettings(layoutMode: 'chromatic');

      final Map<String, List<Map<String, dynamic>>> intents =
          generateIntervalGridKeyIntents(settings);
      final Map<String, dynamic> firstIntent = intents['0,0']!.first;

      expect(firstIntent[JsonFields.INTENT], equals(JsonFields.MIDI_NOTE));
      expect(firstIntent.containsKey(JsonFields.SCALE_DEGREES_FROM_ROOT), isFalse);
      expect(firstIntent.containsKey(JsonFields.SEMITONES_FROM_ROOT), isTrue);
      expect(firstIntent.containsKey(JsonFields.OCTAVE), isTrue);
    });

    test('respects bounded grid generation for zone-style use cases', () {
      const LayoutSettings settings = LayoutSettings();
      const LayoutGridBounds bounds = LayoutGridBounds(
        startColumn: 2,
        endColumn: 4,
        startRow: 1,
        endRow: 3,
      );

      final Map<String, List<Map<String, dynamic>>> intents =
          generateIntervalGridKeyIntents(
        settings,
        bounds: bounds,
      );

      expect(intents.length, equals(9));
      expect(intents.containsKey('2,1'), isTrue);
      expect(intents.containsKey('4,3'), isTrue);
      expect(intents.containsKey('0,0'), isFalse);
      expect(intents.containsKey('7,7'), isFalse);
    });
  });

  group('LayoutColorStrategy', () {
    test('builds default scale-category key colors', () {
      const LayoutColorStrategy strategy = LayoutColorStrategy.scaleCategories();

      final Map<String, dynamic> keyColors = generateLayoutKeyColors(strategy);
      final Map<String, dynamic> noteCategoryMap =
          Map<String, dynamic>.from(keyColors[JsonFields.NOTE_CATEGORY_MAP] as Map);

      expect(noteCategoryMap['-1'], equals('background'));
      expect(noteCategoryMap['1'], equals('secondary'));
      expect(noteCategoryMap['3'], equals('primary'));
    });

    test('builds note-number colors with theme roles and rgba values', () {
      final LayoutColorStrategy strategy = LayoutColorStrategy.noteNumberMap(
        <int, LayoutColorValue>{
          0: const LayoutColorValue.themeRole('primary'),
          1: const LayoutColorValue.rgba('rgba(10,20,30,255)'),
        },
      );

      final Map<String, dynamic> keyColors = generateLayoutKeyColors(strategy);
      final Map<String, dynamic> noteNumberMap =
          Map<String, dynamic>.from(keyColors[JsonFields.NOTE_NUMBER_MAP] as Map);

      expect(noteNumberMap['0'], equals('primary'));
      expect(
        Map<String, dynamic>.from(noteNumberMap['1'] as Map),
        equals(<String, dynamic>{JsonFields.RGBA: 'rgba(10,20,30,255)'}),
      );
    });
  });

  group('buildIntervalGridLayoutData', () {
    test('builds shared layout data with current refs by default', () {
      const LayoutSettings settings = LayoutSettings();

      final LayoutData layoutData = buildIntervalGridLayoutData(
        displayName: 'Shared Layout',
        settings: settings,
      );

      expect(layoutData.displayName, equals('Shared Layout'));
      expect(layoutData.scope, equals('shared'));
      expect(layoutData.targetKey, isNull);
      expect(layoutData.keyIntents.length, equals(64));
      expect(layoutData.keyColors.containsKey(JsonFields.NOTE_CATEGORY_MAP), isTrue);
      expect(layoutData.themeRef, equals(DataReference<Theme>.current()));
      expect(layoutData.scaleRef, equals(DataReference<Scale>.current()));
    });

    test('builds targeted layout data with bounded grid and explicit refs', () {
      const LayoutSettings settings = LayoutSettings(layoutMode: 'chromatic');
      const LayoutGridBounds bounds = LayoutGridBounds(
        startColumn: 0,
        endColumn: 1,
        startRow: 0,
        endRow: 1,
      );
      final LayoutColorStrategy strategy = LayoutColorStrategy.noteNumberMap(
        <int, LayoutColorValue>{
          0: const LayoutColorValue.themeRole('accent'),
        },
      );

      final LayoutData layoutData = buildIntervalGridLayoutData(
        displayName: 'Targeted Layout',
        settings: settings,
        scope: const LayoutScopeSettings.targeted('Voice2LED_2'),
        bounds: bounds,
        colorStrategy: strategy,
        themeRef: DataReference<Theme>.byName(
          'Theme A',
          namespaceSelector: const NamespaceSelector.global(),
        ),
        scaleRef: DataReference<Scale>.inline(
          Scale(
            name: 'inline_scale',
            spec: const ScaleData(
              displayName: 'Inline Scale',
              rootNote: 0,
              noteCategories: <int>[3, -1, 1, -1, 1, 1, -1, 1, -1, 1, -1, 1],
            ),
          ),
        ),
      );

      expect(layoutData.scope, equals('targeted'));
      expect(layoutData.targetKey, equals('Voice2LED_2'));
      expect(layoutData.keyIntents.length, equals(4));
      expect(layoutData.keyColors.containsKey(JsonFields.NOTE_NUMBER_MAP), isTrue);
      expect(layoutData.themeRef, isNotNull);
      expect(layoutData.scaleRef, isNotNull);
    });
  });
}
