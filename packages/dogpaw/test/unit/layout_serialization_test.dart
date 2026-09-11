import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:test/test.dart';

const String _legacyBaseLayoutsField = 'baseLayouts';
const String _bendModeField = 'bendMode';
const String _bendRangeSemitonesField = 'bendRangeSemitones';

void main() {
  group('Layout serialization', () {
    test('legacy baseLayouts input is not preserved on round-trip', () {
      final Layout layout = Layout.fromJson(<String, dynamic>{
        JsonFields.NAME: 'layout_with_legacy_base',
        JsonFields.NAMESPACE_SELECTOR:
            const NamespaceSelector.global().toJson(),
        JsonFields.SPEC: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Legacy Base Layout Input',
          _legacyBaseLayoutsField: <Map<String, dynamic>>[
            <String, dynamic>{
              JsonFields.NAME: 'base_layout',
              JsonFields.NAMESPACE_SELECTOR:
                  const NamespaceSelector.global().toJson(),
            },
          ],
        },
      });

      final Map<String, dynamic> serialized = layout.toJson();
      expect(serialized.containsKey(JsonFields.SPEC), isTrue);

      final Map<String, dynamic> spec =
          serialized[JsonFields.SPEC] as Map<String, dynamic>;
      expect(spec.containsKey(_legacyBaseLayoutsField), isFalse);
    });

    test('shared layout scope round-trips through layout JSON', () {
      final Layout layout = Layout.fromJson(<String, dynamic>{
        JsonFields.NAME: 'shared_layout',
        JsonFields.NAMESPACE_SELECTOR:
            const NamespaceSelector.global().toJson(),
        JsonFields.SPEC: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Shared Layout',
          JsonFields.SCOPE: 'shared',
        },
      });

      final Map<String, dynamic> serialized = layout.toJson();
      final Map<String, dynamic> spec =
          serialized[JsonFields.SPEC] as Map<String, dynamic>;
      expect(spec[JsonFields.SCOPE], equals('shared'));
      expect(spec.containsKey(JsonFields.TARGET_KEY), isFalse);
    });

    test('targeted layout scope round-trips targetKey through layout JSON', () {
      final Layout layout = Layout.fromJson(<String, dynamic>{
        JsonFields.NAME: 'targeted_layout',
        JsonFields.NAMESPACE_SELECTOR:
            const NamespaceSelector.global().toJson(),
        JsonFields.SPEC: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Targeted Layout',
          JsonFields.SCOPE: 'targeted',
          JsonFields.TARGET_KEY: 'controller:left',
        },
      });

      final Map<String, dynamic> serialized = layout.toJson();
      final Map<String, dynamic> spec =
          serialized[JsonFields.SPEC] as Map<String, dynamic>;
      expect(spec[JsonFields.SCOPE], equals('targeted'));
      expect(spec[JsonFields.TARGET_KEY], equals('controller:left'));
    });

    test('bend policy round-trips through layout JSON', () {
      final Layout layout = Layout.fromJson(<String, dynamic>{
        JsonFields.NAME: 'bend_layout',
        JsonFields.NAMESPACE_SELECTOR:
            const NamespaceSelector.global().toJson(),
        JsonFields.SPEC: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Bend Layout',
          _bendModeField: 'nextInScale',
          _bendRangeSemitonesField: 1.5,
        },
      });

      final Map<String, dynamic> serialized = layout.toJson();
      final Map<String, dynamic> spec =
          serialized[JsonFields.SPEC] as Map<String, dynamic>;
      expect(spec[_bendModeField], equals('nextInScale'));
      expect(spec[_bendRangeSemitonesField], equals(1.5));
    });

    test('bend policy defaults round-trip through layout JSON', () {
      final Layout layout = Layout.fromJson(<String, dynamic>{
        JsonFields.NAME: 'default_bend_layout',
        JsonFields.NAMESPACE_SELECTOR:
            const NamespaceSelector.global().toJson(),
        JsonFields.SPEC: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Default Bend Layout',
        },
      });

      final Map<String, dynamic> serialized = layout.toJson();
      final Map<String, dynamic> spec =
          serialized[JsonFields.SPEC] as Map<String, dynamic>;
      expect(spec[_bendModeField], equals('fixed'));
      expect(spec[_bendRangeSemitonesField], equals(2.0));
    });
  });

  group('Endpoint serialization', () {
    test('stateful color input round-trips through endpoint JSON', () {
      final EndpointSpec original = EndpointSpec(
        displayName: 'Accent Color',
        description: 'Stateful accent color surface',
        direction: EndpointDirection.input,
        dataType: const DataTypeSpec(DataType.color),
        messageQueuePayloadContract:
            MessageQueuePayloadContract.statefulColorAction,
        statefulInput: EndpointStatefulInputSpec(
          behavior: StatefulInputBehavior.ownerManaged,
          consumptionMode:
              StatefulInputConsumptionMode.callbackAndRetainedState,
          initialValue: 0xff336699,
          matchedOutput: const MatchedStateOutputSpec(
            name: 'accent_color_state',
            displayName: 'Accent Color State',
            description: 'Published accepted accent color state',
            flags: <String>['public_state', 'accent'],
            groupKey: 'theme',
          ),
        ),
      );

      final EndpointSpec parsed = EndpointSpec.fromJson(original.toJson());
      expect(parsed.dataType.baseType, equals(DataType.color));
      expect(
        parsed.messageQueuePayloadContract,
        equals(MessageQueuePayloadContract.statefulColorAction),
      );
      expect(parsed.statefulInput, isNotNull);
      expect(
        parsed.statefulInput!.behavior,
        equals(StatefulInputBehavior.ownerManaged),
      );
      expect(
        parsed.statefulInput!.consumptionMode,
        equals(StatefulInputConsumptionMode.callbackAndRetainedState),
      );
      expect(parsed.statefulInput!.initialValue, equals(0xff336699));
      expect(
        parsed.statefulInput!.matchedOutput!.name,
        equals('accent_color_state'),
      );
      expect(
        parsed.statefulInput!.matchedOutput!.flags,
        equals(<String>['public_state', 'accent']),
      );
      expect(parsed.statefulInput!.matchedOutput!.groupKey, equals('theme'));
    });

    test('continuousFirstPeerPolicy defaults to invalidateUntilNextWrite',
        () {
      final EndpointSpec original = EndpointSpec(
        direction: EndpointDirection.output,
        dataType: const DataTypeSpec(DataType.float),
        category: EndpointCategory.continuous,
      );

      expect(
        original.continuousFirstPeerPolicy,
        equals(ContinuousFirstPeerPolicy.invalidateUntilNextWrite),
      );

      final Map<String, dynamic> wire = original.toJson();
      expect(
        wire[JsonFields.CONTINUOUS_FIRST_PEER_POLICY],
        equals(
          JsonFields
              .CONTINUOUS_FIRST_PEER_POLICY_INVALIDATE_UNTIL_NEXT_WRITE,
        ),
      );

      final EndpointSpec parsed = EndpointSpec.fromJson(wire);
      expect(
        parsed.continuousFirstPeerPolicy,
        equals(ContinuousFirstPeerPolicy.invalidateUntilNextWrite),
      );
    });

    test('continuousFirstPeerPolicy keepLastValid round-trips through JSON',
        () {
      final EndpointSpec original = EndpointSpec(
        direction: EndpointDirection.output,
        dataType: const DataTypeSpec(DataType.float),
        category: EndpointCategory.continuous,
        continuousFirstPeerPolicy: ContinuousFirstPeerPolicy.keepLastValid,
      );

      final Map<String, dynamic> wire = original.toJson();
      expect(
        wire[JsonFields.CONTINUOUS_FIRST_PEER_POLICY],
        equals(JsonFields.CONTINUOUS_FIRST_PEER_POLICY_KEEP_LAST_VALID),
      );

      final EndpointSpec parsed = EndpointSpec.fromJson(wire);
      expect(
        parsed.continuousFirstPeerPolicy,
        equals(ContinuousFirstPeerPolicy.keepLastValid),
      );
    });

    test('continuousFirstPeerPolicy wire helpers round-trip both values', () {
      for (final ContinuousFirstPeerPolicy policy
          in ContinuousFirstPeerPolicy.values) {
        final String wireValue = continuousFirstPeerPolicyToWireValue(policy);
        expect(
          continuousFirstPeerPolicyFromWireValue(wireValue),
          equals(policy),
        );
      }

      // Unrecognized/null values fall back to the native default.
      expect(
        continuousFirstPeerPolicyFromWireValue(null),
        equals(ContinuousFirstPeerPolicy.invalidateUntilNextWrite),
      );
      expect(
        continuousFirstPeerPolicyFromWireValue('bogus'),
        equals(ContinuousFirstPeerPolicy.invalidateUntilNextWrite),
      );
    });

    test('canonical display category constants match plan values', () {
      expect(kDisplayCategorySystem, equals('System'));
      expect(kDisplayCategoryKeys, equals('Keys'));
      expect(kDisplayCategoryKnobs, equals('Knobs'));
      expect(kDisplayCategoryAudioAndMidi, equals('Audio & MIDI'));
      expect(kDisplayCategoryIO, equals('I/O'));
      expect(kDisplayCategoryOther, equals('Other'));
    });

    test('absent display round-trips as unset', () {
      final EndpointSpec original = EndpointSpec(
        direction: EndpointDirection.output,
        dataType: const DataTypeSpec(DataType.float),
        displayName: 'No Display',
      );

      final Map<String, dynamic> wire = original.toJson();
      expect(wire.containsKey(JsonFields.DISPLAY), isFalse);

      final EndpointSpec parsed = EndpointSpec.fromJson(wire);
      expect(parsed.display, isNull);
    });

    test('top-level-only display round-trips', () {
      final EndpointSpec original = EndpointSpec(
        direction: EndpointDirection.output,
        dataType: const DataTypeSpec(DataType.float),
        display: const EndpointDisplaySpec(
          topLevelCategory: kDisplayCategorySystem,
        ),
      );

      final Map<String, dynamic> wire = original.toJson();
      expect(wire[JsonFields.DISPLAY], isA<Map<String, dynamic>>());
      final Map<String, dynamic> displayJson =
          wire[JsonFields.DISPLAY] as Map<String, dynamic>;
      expect(
        displayJson[JsonFields.TOP_LEVEL_CATEGORY],
        equals(kDisplayCategorySystem),
      );
      expect(displayJson.containsKey(JsonFields.CATEGORY_PATH), isFalse);

      final EndpointSpec parsed = EndpointSpec.fromJson(wire);
      expect(parsed.display, isNotNull);
      expect(parsed.display!.topLevelCategory, equals(kDisplayCategorySystem));
      expect(parsed.display!.categoryPath, isEmpty);
    });

    test('nested categoryPath display round-trips', () {
      final EndpointSpec original = EndpointSpec(
        direction: EndpointDirection.output,
        dataType: const DataTypeSpec(DataType.audioStream),
        groupKey: 'system_audio_out',
        display: const EndpointDisplaySpec(
          topLevelCategory: kDisplayCategorySystem,
          categoryPath: <String>[kDisplayCategoryAudioAndMidi, 'Filter 1'],
        ),
      );

      final EndpointSpec parsed = EndpointSpec.fromJson(original.toJson());
      expect(parsed.display, isNotNull);
      expect(parsed.display!.topLevelCategory, equals(kDisplayCategorySystem));
      expect(
        parsed.display!.categoryPath,
        equals(<String>[kDisplayCategoryAudioAndMidi, 'Filter 1']),
      );
      expect(parsed.groupKey, equals('system_audio_out'));
    });

    test('hideFromPicker true serializes; false omitted', () {
      final EndpointSpec hidden = EndpointSpec(
        direction: EndpointDirection.input,
        dataType: const DataTypeSpec(DataType.toggle),
        hideFromPicker: true,
      );
      final Map<String, dynamic> hiddenJson = hidden.toJson();
      expect(hiddenJson[JsonFields.HIDE_FROM_PICKER], isTrue);
      expect(EndpointSpec.fromJson(hiddenJson).hideFromPicker, isTrue);

      final EndpointSpec visible = EndpointSpec(
        direction: EndpointDirection.output,
        dataType: const DataTypeSpec(DataType.float),
      );
      final Map<String, dynamic> visibleJson = visible.toJson();
      expect(visibleJson.containsKey(JsonFields.HIDE_FROM_PICKER), isFalse);
      expect(EndpointSpec.fromJson(visibleJson).hideFromPicker, isFalse);
    });

    test('projectionHints full schema round-trips through endpoint JSON', () {
      const ProjectionHints hints = ProjectionHints(
        polarity: ProjectionPolarity.bipolar,
        activity: ProjectionActivityRule.absAboveThreshold,
        activeThreshold: 0.25,
        idleValue: -0.5,
        strategies: <ProjectionStrategyHint>[
          ProjectionStrategyHint(name: JsonFields.CONVERSION_MAX_ABS),
          ProjectionStrategyHint(
            name: JsonFields.CONVERSION_MIN_VALUE,
            params: <String, dynamic>{JsonFields.IDLE_VALUE: -0.5},
          ),
        ],
      );
      const EndpointSpec original = EndpointSpec(
        direction: EndpointDirection.output,
        dataType: DataTypeSpec(DataType.float, indexSpec: IndexSpecKey(8, 8)),
        projectionHints: hints,
      );

      final Map<String, dynamic> wire = original.toJson();
      expect(wire, contains(JsonFields.PROJECTION_HINTS));

      final EndpointSpec parsed = EndpointSpec.fromJson(wire);
      expect(parsed.projectionHints, isNotNull);
      expect(parsed.projectionHints!.polarity, ProjectionPolarity.bipolar);
      expect(parsed.projectionHints!.activity,
          ProjectionActivityRule.absAboveThreshold);
      expect(parsed.projectionHints!.activeThreshold, 0.25);
      expect(parsed.projectionHints!.idleValue, -0.5);
      expect(parsed.projectionHints!.strategies
          .map((ProjectionStrategyHint hint) => hint.name), <String>[
        JsonFields.CONVERSION_MAX_ABS,
        JsonFields.CONVERSION_MIN_VALUE,
      ]);
    });

    test('omitted projectionHints resolve to pressure-like defaults', () {
      const EndpointSpec endpoint = EndpointSpec(
        direction: EndpointDirection.output,
        dataType: DataTypeSpec(DataType.float),
      );

      expect(endpoint.toJson().containsKey(JsonFields.PROJECTION_HINTS), false);

      final ProjectionHints resolved =
          resolveProjectionHints(endpoint.projectionHints);
      expect(resolved.polarity, ProjectionPolarity.unipolar);
      expect(resolved.activity, ProjectionActivityRule.aboveThreshold);
      expect(resolved.activeThreshold, 0.0);
      expect(resolved.idleValue, 0.0);
      expect(
        resolved.strategies
            .map((ProjectionStrategyHint hint) => hint.name)
            .toList(),
        <String>[
          JsonFields.CONVERSION_MAX_VALUE,
          JsonFields.CONVERSION_AVERAGE_VALUE,
          JsonFields.CONVERSION_LAST_ACTIVE,
          JsonFields.CONVERSION_FIRST_ACTIVE,
        ],
      );
    });

    test('connection parameters override projection hint threshold and idle',
        () {
      const ProjectionHints hints = ProjectionHints(
        activeThreshold: 0.1,
        idleValue: 0.2,
      );
      const IndexConversionConfig conversion = IndexConversionConfig(
        parameters: <String, dynamic>{
          JsonFields.ACTIVE_THRESHOLD: 0.3,
          JsonFields.IDLE_VALUE: 0.4,
        },
      );

      final ProjectionHints resolved = resolveProjectionHints(
        hints,
        indexConversion: conversion,
      );
      expect(resolved.activeThreshold, 0.3);
      expect(resolved.idleValue, 0.4);
    });

    test('whitespace-only display segments are skipped on read and write', () {
      final EndpointSpec parsed = EndpointSpec.fromJson(<String, dynamic>{
        JsonFields.DIRECTION: JsonFields.DIRECTION_OUTPUT,
        JsonFields.DATA_TYPE: <String, dynamic>{
          JsonFields.BASE_TYPE: 'float',
          JsonFields.INDEX_SPEC: <String, dynamic>{JsonFields.TYPE: 'none'},
        },
        JsonFields.DISPLAY: <String, dynamic>{
          JsonFields.TOP_LEVEL_CATEGORY: '  ',
          JsonFields.CATEGORY_PATH: <dynamic>['Keys', '   ', 'I/O'],
        },
      });
      expect(parsed.display, isNotNull);
      expect(parsed.display!.topLevelCategory, isNull);
      expect(
        parsed.display!.categoryPath,
        equals(<String>[kDisplayCategoryKeys, kDisplayCategoryIO]),
      );

      final Map<String, dynamic> rewritten = EndpointSpec(
        direction: EndpointDirection.input,
        dataType: const DataTypeSpec(DataType.float),
        display: const EndpointDisplaySpec(
          topLevelCategory: '  System  ',
          categoryPath: <String>['  ', 'Audio & MIDI', '\t'],
        ),
      ).toJson();
      final Map<String, dynamic> displayJson =
          rewritten[JsonFields.DISPLAY] as Map<String, dynamic>;
      expect(displayJson[JsonFields.TOP_LEVEL_CATEGORY], equals('System'));
      expect(
        displayJson[JsonFields.CATEGORY_PATH],
        equals(<String>[kDisplayCategoryAudioAndMidi]),
      );
    });

    test('malformed display is ignored like other optional nested objects', () {
      final EndpointSpec nonObjectDisplay = EndpointSpec.fromJson(
        <String, dynamic>{
          JsonFields.DIRECTION: JsonFields.DIRECTION_OUTPUT,
          JsonFields.DATA_TYPE: <String, dynamic>{
            JsonFields.BASE_TYPE: 'float',
            JsonFields.INDEX_SPEC: <String, dynamic>{JsonFields.TYPE: 'none'},
          },
          JsonFields.DISPLAY: 'System',
        },
      );
      expect(nonObjectDisplay.display, isNull);

      expect(
        () => EndpointSpec.fromJson(<String, dynamic>{
          JsonFields.DIRECTION: JsonFields.DIRECTION_OUTPUT,
          JsonFields.DATA_TYPE: <String, dynamic>{
            JsonFields.BASE_TYPE: 'float',
            JsonFields.INDEX_SPEC: <String, dynamic>{JsonFields.TYPE: 'none'},
          },
          JsonFields.DISPLAY: <String, dynamic>{
            JsonFields.CATEGORY_PATH: 'Audio & MIDI',
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('matched output display round-trips through endpoint JSON', () {
      final EndpointSpec original = EndpointSpec(
        direction: EndpointDirection.input,
        dataType: const DataTypeSpec(DataType.float),
        statefulInput: const EndpointStatefulInputSpec(
          matchedOutput: MatchedStateOutputSpec(
            name: 'volume_state',
            displayName: 'Volume State',
            groupKey: 'volume',
            display: EndpointDisplaySpec(
              topLevelCategory: kDisplayCategorySystem,
              categoryPath: <String>[kDisplayCategoryIO],
            ),
          ),
        ),
      );

      final EndpointSpec parsed = EndpointSpec.fromJson(original.toJson());
      expect(parsed.statefulInput!.matchedOutput!.display, isNotNull);
      expect(
        parsed.statefulInput!.matchedOutput!.display!.topLevelCategory,
        equals(kDisplayCategorySystem),
      );
      expect(
        parsed.statefulInput!.matchedOutput!.display!.categoryPath,
        equals(<String>[kDisplayCategoryIO]),
      );
    });

    test('supported scalar queues default to action payload contracts in JSON',
        () {
      final List<MapEntry<DataType, MessageQueuePayloadContract>> testCases =
          <MapEntry<DataType, MessageQueuePayloadContract>>[
        const MapEntry<DataType, MessageQueuePayloadContract>(
          DataType.float,
          MessageQueuePayloadContract.statefulFloatAction,
        ),
        const MapEntry<DataType, MessageQueuePayloadContract>(
          DataType.int_,
          MessageQueuePayloadContract.statefulIntAction,
        ),
        const MapEntry<DataType, MessageQueuePayloadContract>(
          DataType.toggle,
          MessageQueuePayloadContract.statefulToggleAction,
        ),
        const MapEntry<DataType, MessageQueuePayloadContract>(
          DataType.enum_,
          MessageQueuePayloadContract.statefulEnumAction,
        ),
        const MapEntry<DataType, MessageQueuePayloadContract>(
          DataType.color,
          MessageQueuePayloadContract.statefulColorAction,
        ),
        const MapEntry<DataType, MessageQueuePayloadContract>(
          DataType.theme,
          MessageQueuePayloadContract.statefulThemeAction,
        ),
        const MapEntry<DataType, MessageQueuePayloadContract>(
          DataType.scale,
          MessageQueuePayloadContract.statefulScaleAction,
        ),
      ];

      for (final MapEntry<DataType, MessageQueuePayloadContract> testCase
          in testCases) {
        final EndpointSpec parsed = EndpointSpec.fromJson(
          EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec(testCase.key),
            category: EndpointCategory.messageQueue,
          ).toJson(),
        );

        expect(
          parsed.messageQueuePayloadContract,
          equals(testCase.value),
        );
      }
    });

    test('enum options round-trip through data type JSON', () {
      final DataTypeSpec original = DataTypeSpec(
        DataType.enum_,
        enumOptions: const <EnumOption>[
          EnumOption(id: 2, label: 'Clean'),
          EnumOption(id: 7, label: 'Crunch'),
        ],
      );

      final Map<String, dynamic> wire = original.toJson();
      expect(wire.containsKey(JsonFields.CONSTRAINTS), isTrue);

      final DataTypeSpec parsed = DataTypeSpec.fromJson(wire);
      expect(parsed.enumOptions.length, equals(2));
      expect(parsed.enumOptions.first.id, equals(2));
      expect(parsed.enumOptions.first.label, equals('Clean'));
      expect(parsed.enumOptions.last.id, equals(7));
      expect(parsed.enumOptions.last.label, equals('Crunch'));
    });

    test('float add action round-trips through JSON', () {
      final StatefulFloatAction original = StatefulFloatAction(
        action: StatefulFloatActionType.add,
        value: 0.25,
      );

      final StatefulFloatAction parsed = StatefulFloatAction.fromJson(
        original.toJson(),
      );
      expect(parsed.action, equals(StatefulFloatActionType.add));
      expect(parsed.value, equals(0.25));
    });

    test('enum step action round-trips through JSON', () {
      final StatefulEnumAction original = StatefulEnumAction(
        action: StatefulEnumActionType.step,
        value: -2,
      );

      final StatefulEnumAction parsed = StatefulEnumAction.fromJson(
        original.toJson(),
      );
      expect(parsed.action, equals(StatefulEnumActionType.step));
      expect(parsed.value, equals(-2));
    });

    test('color set action round-trips through JSON', () {
      final StatefulColorAction original = StatefulColorAction(
        action: StatefulColorActionType.setValue,
        value: 0xff336699,
      );

      final StatefulColorAction parsed = StatefulColorAction.fromJson(
        original.toJson(),
      );
      expect(parsed.action, equals(StatefulColorActionType.setValue));
      expect(parsed.value, equals(0xff336699));
    });

    test('theme set action round-trips through JSON', () {
      const ThemeData value = ThemeData(
        displayName: 'Midnight',
        primaryColor: '#101820',
        secondaryColor: '#263340',
        accentColor: '#00aaff',
        backgroundColor: '#05080c',
      );
      const StatefulThemeAction original = StatefulThemeAction(
        action: StatefulThemeActionType.setValue,
        value: value,
      );

      final StatefulThemeAction parsed =
          StatefulThemeAction.fromJson(original.toJson());
      expect(parsed.action, equals(StatefulThemeActionType.setValue));
      expect(parsed.value, equals(value));
    });

    test('scale set action round-trips through JSON', () {
      const ScaleData value = ScaleData(
        displayName: 'D Dorian',
        rootNote: 2,
        noteCategories: <int>[1, -1, 3, 1, -1, 1, -1, 3, 1, -1, 1, -1],
      );
      const StatefulScaleAction original = StatefulScaleAction(
        action: StatefulScaleActionType.setValue,
        value: value,
      );

      final StatefulScaleAction parsed =
          StatefulScaleAction.fromJson(original.toJson());
      expect(parsed.action, equals(StatefulScaleActionType.setValue));
      expect(parsed.value, equals(value));
    });

    test('enum committed state round-trips through JSON', () {
      const StatefulEnumCommittedState original =
          StatefulEnumCommittedState(id: 7);

      final StatefulEnumCommittedState parsed =
          StatefulEnumCommittedState.fromJson(original.toJson());
      expect(parsed.id, equals(7));
    });

    test('theme committed state round-trips through JSON', () {
      const ThemeData value = ThemeData(
        displayName: 'Daylight',
        primaryColor: '#ffffff',
        secondaryColor: '#dddddd',
        accentColor: '#0066ff',
        backgroundColor: '#f5f5f5',
      );
      const StatefulThemeCommittedState original =
          StatefulThemeCommittedState(value: value);

      final StatefulThemeCommittedState parsed =
          StatefulThemeCommittedState.fromJson(original.toJson());
      expect(parsed.value, equals(value));
    });

    test('scale committed state round-trips through JSON', () {
      const ScaleData value = ScaleData(
        displayName: 'C Major',
        rootNote: 0,
        noteCategories: <int>[3, -1, 1, -1, 1, 1, -1, 3, -1, 1, -1, 1],
      );
      const StatefulScaleCommittedState original =
          StatefulScaleCommittedState(value: value);

      final StatefulScaleCommittedState parsed =
          StatefulScaleCommittedState.fromJson(original.toJson());
      expect(parsed.value, equals(value));
    });
  });
}
