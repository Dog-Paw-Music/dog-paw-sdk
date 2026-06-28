import 'package:dogpaw/dogpaw.dart';
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

    test('ConnectionRule serializes nested selectors for criteria and endpointRef',
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
        Map<String, dynamic>.from(spec['sourceSelector'] as Map<String, dynamic>)
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
  });
}
