import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionRule model alias', () {
    test('ConnectionRule round-trips through JSON', () {
      final ConnectionRule original = ConnectionRule(
        name: 'persistent_rule',
        spec: ConnectionRuleData(
          sourceRef: DataItemRef.byName(
            name: 'source_out',
            namespaceSelector:
                const NamespaceSelector.specificEntity('SourceEntity'),
          ),
          destinationRef: DataItemRef.byName(
            name: 'dest_in',
            namespaceSelector:
                const NamespaceSelector.specificEntity('DestEntity'),
          ),
        ),
      );

      final Map<String, dynamic> wire = original.toJson();
      final ConnectionRule parsed = ConnectionRule.fromJson(wire);
      expect(parsed.spec, isNotNull);
      expect(parsed.spec!.sourceRef.name, equals('source_out'));
      expect(parsed.spec!.destinationRef.name, equals('dest_in'));
    });

    test(
        'ConnectionRule serializes nested selectors for criteria and endpointRef',
        () {
      final ConnectionRule rule = ConnectionRule(
        name: 'selector_rule',
        spec: ConnectionRuleData(
          sourceSelector: ConnectionRuleSelector.matchCriteria(
            SearchCriteria.andCombination(<SearchCriteria>[
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals('source_out'),
            ]),
          ),
          destinationSelector: ConnectionRuleSelector.endpointRef(
            DataItemRef.byName(
              name: 'dest_in',
              namespaceSelector:
                  const NamespaceSelector.specificEntity('DestEntity'),
            ),
          ),
        ),
      );

      final Map<String, dynamic> wire = rule.toJson();
      final Map<String, dynamic> spec =
          Map<String, dynamic>.from(wire['spec'] as Map<String, dynamic>);
      expect(spec.containsKey('sourceSelector'), isTrue);
      expect(spec.containsKey('destinationSelector'), isTrue);
      expect(
        Map<String, dynamic>.from(
                spec['sourceSelector'] as Map<String, dynamic>)
            .containsKey('matchCriteria'),
        isTrue,
      );
      expect(
        Map<String, dynamic>.from(
                spec['destinationSelector'] as Map<String, dynamic>)
            .containsKey('endpointRef'),
        isTrue,
      );
      expect(spec.containsKey('sourceRef'), isFalse);
      expect(spec.containsKey('destinationRef'), isFalse);
    });

    test('sparse metadata does not default-fill omitted fields on send', () {
      final ConnectionRule rule = ConnectionRule(
        name: 'sparse_rule',
        spec: ConnectionRuleData(
          sourceRef: DataItemRef.byName(
            name: 'source',
            namespaceSelector: const NamespaceSelector.specificEntity('Source'),
          ),
          destinationRef: DataItemRef.byName(
            name: 'destination',
            namespaceSelector:
                const NamespaceSelector.specificEntity('Destination'),
          ),
          mapping: const MappingConfig(
            type: MappingType.logarithmic,
            curve: 0.75,
          ),
        ),
      );

      final Map<String, dynamic> spec =
          Map<String, dynamic>.from(rule.toJson()[JsonFields.SPEC]);
      expect(spec, contains(JsonFields.MAPPING));
      expect(spec, isNot(contains(JsonFields.INDEX_CONVERSION)));
      expect(spec, isNot(contains(JsonFields.ENABLED)));
    });

    test('null clear is distinct from omission', () {
      final ConnectionRule clearRule = ConnectionRule(
        name: 'clear_rule',
        spec: ConnectionRuleData(
          sourceRef: DataItemRef.byName(
            name: 'source',
            namespaceSelector: const NamespaceSelector.specificEntity('Source'),
          ),
          destinationRef: DataItemRef.byName(
            name: 'destination',
            namespaceSelector:
                const NamespaceSelector.specificEntity('Destination'),
          ),
          clearEnabled: true,
        ),
      );
      final Map<String, dynamic> clearSpec =
          Map<String, dynamic>.from(clearRule.toJson()[JsonFields.SPEC]);
      expect(clearSpec, containsPair(JsonFields.ENABLED, null));
    });

    test('MappingType serializes under the shared wire key and vocabulary', () {
      const List<String> sharedVocabulary = <String>[
        JsonFields.MAPPING_TYPE_LINEAR,
        JsonFields.MAPPING_TYPE_LOGARITHMIC,
        JsonFields.MAPPING_TYPE_EXPRESSION,
        JsonFields.MAPPING_TYPE_CUSTOM,
      ];

      final List<String> serialized = MappingType.values
          .map((MappingType type) => MappingConfig(type: type)
              .toJson()[JsonFields.MAPPING_TYPE] as String)
          .toList();
      expect(
        serialized,
        sharedVocabulary,
        reason: 'Dart must emit exactly the vocabulary Epiphany accepts, under '
            'the shared mappingType key.',
      );

      for (final String wireValue in sharedVocabulary) {
        final MappingConfig parsed = MappingConfig.fromJson(
            <String, dynamic>{JsonFields.MAPPING_TYPE: wireValue});
        expect(
          parsed.toJson()[JsonFields.MAPPING_TYPE],
          wireValue,
          reason: 'Parsing $wireValue must not collapse into another type.',
        );
      }
    });

    test('unknown mapping type fails loudly and absent one defaults', () {
      expect(
        () => MappingConfig.fromJson(
            <String, dynamic>{JsonFields.MAPPING_TYPE: 'bezierCurve'}),
        throwsArgumentError,
        reason: 'Vocabulary drift must surface instead of degrading to linear.',
      );
      expect(
        MappingConfig.fromJson(<String, dynamic>{
          JsonFields.TYPE: JsonFields.MAPPING_TYPE_LOGARITHMIC,
        }).type,
        MappingType.linear,
        reason: 'Only the shared mappingType key may carry the vocabulary.',
      );
      expect(
        MappingConfig.fromJson(<String, dynamic>{JsonFields.CURVE: 0.25}).type,
        MappingType.linear,
      );
    });

    test('Phase 3a conversion strategy vocabulary is shared', () {
      const List<String> supported = <String>[
        JsonFields.CONVERSION_NONE,
        JsonFields.CONVERSION_UNIFORM,
        JsonFields.CONVERSION_MAX_VALUE,
        JsonFields.CONVERSION_MIN_VALUE,
        JsonFields.CONVERSION_MAX_ABS,
        JsonFields.CONVERSION_AVERAGE_VALUE,
        JsonFields.CONVERSION_LAST_ACTIVE,
        JsonFields.CONVERSION_FIRST_ACTIVE,
      ];

      for (final String strategy in supported) {
        final IndexConversionConfig conversion =
            IndexConversionConfig(strategy: strategy);
        final Map<String, dynamic> wire = conversion.toJson();
        expect(wire[JsonFields.STRATEGY], strategy);
        expect(
          IndexConversionConfig.fromJson(wire).strategy,
          strategy,
          reason: 'Parsing $strategy must not collapse into another strategy.',
        );
      }
    });

    test('connection rule metadata updates round-trip projection strategies',
        () {
      const List<String> strategies = <String>[
        JsonFields.CONVERSION_LAST_ACTIVE,
        JsonFields.CONVERSION_FIRST_ACTIVE,
        JsonFields.CONVERSION_MAX_ABS,
        JsonFields.CONVERSION_MIN_VALUE,
      ];

      for (final String strategy in strategies) {
        final ConnectionRuleData data = ConnectionRuleData(
          sourceRef: const DataItemRef(name: 'source'),
          destinationRef: const DataItemRef(name: 'destination'),
          indexConversion: IndexConversionConfig(strategy: strategy),
        );
        final ConnectionRuleData parsed =
            ConnectionRuleData.fromJson(data.toJson());

        expect(parsed.indexConversion?.strategy, strategy);
      }
    });

    test('unknown conversion strategy fails loudly and absent one defaults',
        () {
      expect(
        () => IndexConversionConfig.fromJson(<String, dynamic>{
          JsonFields.STRATEGY: 'definitely_not_supported',
        }),
        throwsArgumentError,
      );
      expect(
        IndexConversionConfig.fromJson(<String, dynamic>{}).strategy,
        JsonFields.CONVERSION_NONE,
      );
    });

    test('endpoint-owned policy metadata is sparse and round-trips', () {
      const ConnectionPolicy policy = ConnectionPolicy(
        endpointConnectionRule: null,
        mapping: MappingConfig(type: MappingType.custom),
      );
      final Map<String, dynamic> wire = policy.toJson();
      expect(wire, contains(JsonFields.MAPPING));
      expect(wire, isNot(contains(JsonFields.INDEX_CONVERSION)));
      expect(wire, isNot(contains(JsonFields.ENABLED)));
      final ConnectionPolicy parsed = ConnectionPolicy.fromJson(wire);
      expect(parsed.mapping?.type, MappingType.custom);
      expect(parsed.enabled, isNull);
    });

    test('endpoint-owned policy null clear is explicit', () {
      const ConnectionPolicy policy = ConnectionPolicy(clearMapping: true);
      final Map<String, dynamic> wire = policy.toJson();
      expect(wire, containsPair(JsonFields.MAPPING, null));
      final ConnectionPolicy parsed = ConnectionPolicy.fromJson(wire);
      expect(parsed.clearMapping, isTrue);
      expect(parsed.mapping, isNull);
    });
  });
}
