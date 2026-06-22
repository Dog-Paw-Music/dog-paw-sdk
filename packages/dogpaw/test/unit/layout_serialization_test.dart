import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:test/test.dart';

const String _legacyBaseLayoutsField = 'baseLayouts';

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

    test('enum committed state round-trips through JSON', () {
      const StatefulEnumCommittedState original =
          StatefulEnumCommittedState(id: 7);

      final StatefulEnumCommittedState parsed =
          StatefulEnumCommittedState.fromJson(original.toJson());
      expect(parsed.id, equals(7));
    });
  });
}
