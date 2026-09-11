// Integration tests for the Connections app Phase 5 "Detail editor + rebind
// + remove" server contracts: sparse delta preservation, JSON `null` clears,
// create-on-edit for an externally-owned pair, and effective-value fallback
// after an override rule is deleted.
//
// RUN WITH: flutter test test/integration/connection_rule_detail_test.dart --concurrency=1

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:test/test.dart';

void main() {
  IntegrationTestFixture.register();

  group('Connection detail delta writes', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('DetailProducer_$suffix');
      expect((await producer.connect()).success, isTrue);

      consumer = DogPawEntity('DetailConsumer_$suffix');
      expect((await consumer.connect()).success, isTrue);
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('delta update preserves omitted fields server-side', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String outputName = 'delta_output_$suffix';
      final String inputName = 'delta_input_$suffix';
      final String ruleName = 'opaque-delta-$suffix';

      expect(
          (await producer.createEndpoint(EndpointInfo(
            name: outputName,
            spec: const EndpointSpec(
              direction: EndpointDirection.output,
              dataType: DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
            ),
          )))
              .success,
          isTrue);
      expect(
          (await consumer.createEndpoint(EndpointInfo(
            name: inputName,
            spec: const EndpointSpec(
              direction: EndpointDirection.input,
              dataType: DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
            ),
          )))
              .success,
          isTrue);

      final DataItemRef sourceRef = DataItemRef.byName(
        name: outputName,
        namespaceSelector: NamespaceSelector.specificEntity(
          producer.entityName,
        ),
      );
      final DataItemRef destinationRef = DataItemRef.byName(
        name: inputName,
        namespaceSelector: NamespaceSelector.specificEntity(
          consumer.entityName,
        ),
      );

      // Our rule asserts both mapping and enabled up front.
      expect(
          (await producer.createConnectionRule(ConnectionRule(
            name: ruleName,
            spec: ConnectionRuleData(
              sourceRef: sourceRef,
              destinationRef: destinationRef,
              mapping: const MappingConfig(type: MappingType.logarithmic),
              enabled: false,
            ),
          )))
              .success,
          isTrue);

      // Detail-screen delta edit: change only `enabled`, omitting `mapping`
      // entirely (mirrors ConnectionsController.updateOurMetadata, which
      // never round-trips fields the user did not touch).
      expect(
          (await producer.updateConnectionRule(ConnectionRule(
            name: ruleName,
            spec: ConnectionRuleData(
              sourceRef: sourceRef,
              destinationRef: destinationRef,
              enabled: true,
            ),
          )))
              .success,
          isTrue);

      final Result<ConnectionRule?> stored = await producer.readConnectionRule(
        ruleName,
        includeSpec: true,
      );
      expect(stored.success, isTrue);
      // The omitted `mapping` field must still be present on the wire;
      // a delta-only update must not have wiped it.
      expect(stored.value!.spec!.mapping?.type, MappingType.logarithmic);
      expect(stored.value!.spec!.enabled, isTrue);
    });

    test('JSON null clear unsets the field instead of reviving a default',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String outputName = 'clear_output_$suffix';
      final String inputName = 'clear_input_$suffix';
      final String ruleName = 'opaque-clear-$suffix';

      expect(
          (await producer.createEndpoint(EndpointInfo(
            name: outputName,
            spec: const EndpointSpec(
              direction: EndpointDirection.output,
              dataType: DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
            ),
          )))
              .success,
          isTrue);
      expect(
          (await consumer.createEndpoint(EndpointInfo(
            name: inputName,
            spec: const EndpointSpec(
              direction: EndpointDirection.input,
              dataType: DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
            ),
          )))
              .success,
          isTrue);

      final DataItemRef sourceRef = DataItemRef.byName(
        name: outputName,
        namespaceSelector: NamespaceSelector.specificEntity(
          producer.entityName,
        ),
      );
      final DataItemRef destinationRef = DataItemRef.byName(
        name: inputName,
        namespaceSelector: NamespaceSelector.specificEntity(
          consumer.entityName,
        ),
      );

      expect(
          (await producer.createConnectionRule(ConnectionRule(
            name: ruleName,
            spec: ConnectionRuleData(
              sourceRef: sourceRef,
              destinationRef: destinationRef,
              enabled: false,
            ),
          )))
              .success,
          isTrue);

      // Sanity: our assertion is present before the clear.
      final Result<ConnectionRule?> beforeClear =
          await producer.readConnectionRule(ruleName, includeSpec: true);
      expect(beforeClear.value!.spec!.enabled, isFalse);
      expect(
        beforeClear.value!.toJson()[JsonFields.SPEC][JsonFields.ENABLED],
        isFalse,
      );

      // Detail-screen clear: send JSON `null` for `enabled` via clearEnabled,
      // matching ConnectionsController.updateOurMetadata's clear* contract.
      expect(
          (await producer.updateConnectionRule(ConnectionRule(
            name: ruleName,
            spec: ConnectionRuleData(
              sourceRef: sourceRef,
              destinationRef: destinationRef,
              clearEnabled: true,
            ),
          )))
              .success,
          isTrue);

      final Result<ConnectionRule?> afterClear =
          await producer.readConnectionRule(ruleName, includeSpec: true);
      expect(afterClear.success, isTrue);
      // The bag must no longer assert `enabled` at all (not merely reset to
      // a default `true`); the server must not silently revive a default on
      // our rule's own bag.
      expect(afterClear.value!.spec!.enabled, isNull);
      expect(
        afterClear.value!.toJson()[JsonFields.SPEC][JsonFields.ENABLED],
        isNull,
      );

      // The pair's resolved effective value is now free to fall back to the
      // endpoint-owned default rather than our (now-cleared) assertion.
      // Coalesced reconcile can leave stale resolved bags briefly after clear.
      final Connection projected = await waitForProjectedConnection(
        producer,
        sourceName: outputName,
        destinationName: inputName,
        matches: (Connection connection) =>
            connection.resolved?.enabled == true &&
            connection.resolved?.fieldAttribution[JsonFields.ENABLED]
                    [JsonFields.RATIONALE_TYPE] ==
                'default',
      );
      expect(projected.resolved!.enabled, isTrue);
      expect(
        projected.resolved!.fieldAttribution[JsonFields.ENABLED]
            [JsonFields.RATIONALE_TYPE],
        'default',
      );
    });

    test(
        'create-on-edit for an externally-owned pair yields our own override rule',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String outputName = 'external_output_$suffix';
      final String inputName = 'external_input_$suffix';
      final String foreignRuleName = 'opaque-foreign-$suffix';
      final String ourRuleName = 'opaque-ours-$suffix';

      expect(
          (await producer.createEndpoint(EndpointInfo(
            name: outputName,
            spec: const EndpointSpec(
              direction: EndpointDirection.output,
              dataType: DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
            ),
          )))
              .success,
          isTrue);
      expect(
          (await consumer.createEndpoint(EndpointInfo(
            name: inputName,
            spec: const EndpointSpec(
              direction: EndpointDirection.input,
              dataType: DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
            ),
          )))
              .success,
          isTrue);

      final DataItemRef sourceRef = DataItemRef.byName(
        name: outputName,
        namespaceSelector: NamespaceSelector.specificEntity(
          producer.entityName,
        ),
      );
      final DataItemRef destinationRef = DataItemRef.byName(
        name: inputName,
        namespaceSelector: NamespaceSelector.specificEntity(
          consumer.entityName,
        ),
      );

      // Pair exists purely via a foreign (`consumer`-owned) rule; the
      // Connections app (`producer` here, standing in for our entity) has
      // never asserted anything on it.
      expect(
          (await consumer.createConnectionRule(ConnectionRule(
            name: foreignRuleName,
            spec: ConnectionRuleData(
              sourceRef: sourceRef,
              destinationRef: destinationRef,
              mapping: const MappingConfig(type: MappingType.logarithmic),
            ),
          )))
              .success,
          isTrue);

      Connection projected = await waitForProjectedConnection(
        producer,
        sourceName: outputName,
        destinationName: inputName,
        matches: (Connection connection) =>
            connection.spec?.contributingRationales.isNotEmpty == true,
      );
      expect(
        projected.spec!.contributingRationales
            .every((Map<String, dynamic> r) =>
                r[JsonFields.OWNING_ENTITY] != producer.entityName),
        isTrue,
      );

      // Editing "inherited" metadata from the detail screen with no rule of
      // our own yet must create one (ConnectionsController.updateOurMetadata
      // create-if-needed path), not edit the foreign rule's bag in place.
      expect(
          (await producer.createConnectionRule(ConnectionRule(
            name: ourRuleName,
            spec: ConnectionRuleData(
              sourceRef: sourceRef,
              destinationRef: destinationRef,
              enabled: false,
            ),
          )))
              .success,
          isTrue);

      projected = await waitForProjectedConnection(
        producer,
        sourceName: outputName,
        destinationName: inputName,
        matches: (Connection connection) {
          final bool weContribute =
              connection.spec?.contributingRationales.any(
                    (Map<String, dynamic> r) =>
                        r[JsonFields.OWNING_ENTITY] == producer.entityName &&
                        r[JsonFields.RATIONALE_KEY] == ourRuleName,
                  ) ??
                  false;
          return weContribute &&
              connection.resolved?.mapping.type == MappingType.logarithmic &&
              connection.resolved?.enabled == false;
        },
      );
      final bool weNowContribute = projected.spec!.contributingRationales.any(
        (Map<String, dynamic> r) =>
            r[JsonFields.OWNING_ENTITY] == producer.entityName &&
            r[JsonFields.RATIONALE_KEY] == ourRuleName,
      );
      expect(weNowContribute, isTrue);
      // The foreign rule's mapping assertion is untouched by our create.
      expect(projected.resolved!.mapping.type, MappingType.logarithmic);
      expect(projected.resolved!.enabled, isFalse);
    });

    test(
        'effective falls back to endpoint-owned defaults after our override is deleted',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String outputName = 'fallback_output_$suffix';
      final String inputName = 'fallback_input_$suffix';
      final String ruleName = 'opaque-fallback-$suffix';

      expect(
          (await producer.createEndpoint(EndpointInfo(
            name: outputName,
            spec: EndpointSpec(
              direction: EndpointDirection.output,
              dataType: const DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
              // Endpoint-owned automatic pairing keeps this pair "existing"
              // (via the `endpointOwned` rationale) once our override rule
              // is deleted below, matching how a real Connections app pair
              // would remain visible.
              connectionPolicy: ConnectionPolicy(
                endpointConnectionRule: SearchCriteria.nameEquals(inputName),
              ),
            ),
          )))
              .success,
          isTrue);
      expect(
          (await consumer.createEndpoint(EndpointInfo(
            name: inputName,
            spec: const EndpointSpec(
              direction: EndpointDirection.input,
              dataType: DataTypeSpec(DataType.int_),
              category: EndpointCategory.messageQueue,
            ),
          )))
              .success,
          isTrue);

      final DataItemRef sourceRef = DataItemRef.byName(
        name: outputName,
        namespaceSelector: NamespaceSelector.specificEntity(
          producer.entityName,
        ),
      );
      final DataItemRef destinationRef = DataItemRef.byName(
        name: inputName,
        namespaceSelector: NamespaceSelector.specificEntity(
          consumer.entityName,
        ),
      );

      expect(
          (await producer.createConnectionRule(ConnectionRule(
            name: ruleName,
            spec: ConnectionRuleData(
              sourceRef: sourceRef,
              destinationRef: destinationRef,
              mapping: const MappingConfig(type: MappingType.logarithmic),
              enabled: false,
            ),
          )))
              .success,
          isTrue);

      Connection projected = await waitForProjectedConnection(
        producer,
        sourceName: outputName,
        destinationName: inputName,
        matches: (Connection connection) =>
            connection.resolved?.mapping.type == MappingType.logarithmic &&
            connection.resolved?.enabled == false,
      );
      expect(projected.resolved!.mapping.type, MappingType.logarithmic);
      expect(projected.resolved!.enabled, isFalse);

      // Detail-screen "Remove": delete our only override rule for the pair.
      expect((await producer.deleteConnectionRule(ruleName)).success, isTrue);

      projected = await waitForProjectedConnection(
        producer,
        sourceName: outputName,
        destinationName: inputName,
        matches: (Connection connection) {
          if (connection.spec?.contributingRationales.length != 1) {
            return false;
          }
          if (connection.spec!.contributingRationales
                  .single[JsonFields.RATIONALE_TYPE] !=
              'endpointOwned') {
            return false;
          }
          if (connection.resolved?.mapping.type != MappingType.linear ||
              connection.resolved?.enabled != true) {
            return false;
          }
          for (final String field in <String>[
            JsonFields.MAPPING,
            JsonFields.ENABLED,
          ]) {
            if (connection.resolved!.fieldAttribution[field]
                    [JsonFields.RATIONALE_TYPE] !=
                'default') {
              return false;
            }
          }
          return true;
        },
      );
      expect(projected.spec!.contributingRationales, hasLength(1));
      expect(
        projected
            .spec!.contributingRationales.single[JsonFields.RATIONALE_TYPE],
        'endpointOwned',
      );
      expect(projected.resolved!.mapping.type, MappingType.linear);
      expect(projected.resolved!.enabled, isTrue);
      for (final String field in <String>[
        JsonFields.MAPPING,
        JsonFields.ENABLED,
      ]) {
        expect(
          projected.resolved!.fieldAttribution[field][JsonFields.RATIONALE_TYPE],
          'default',
        );
      }
    });
  });
}
