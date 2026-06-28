import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionPolicy endpoint-owned rule alias', () {
    test('endpointConnectionRule serializes through autoConnectCriteria wire key',
        () {
      final ConnectionPolicy policy = ConnectionPolicy(
        maxConnections: 2,
        endpointConnectionRule: SearchCriteria.andCombination(<SearchCriteria>[
          SearchCriteria.directionEquals(EndpointDirection.input),
          SearchCriteria.nameEquals('target_input'),
        ]),
      );

      final Map<String, dynamic> wire = policy.toJson();
      expect(wire[JsonFields.MAX_CONNECTIONS], equals(2));
      expect(wire.containsKey(JsonFields.AUTO_CONNECT_CRITERIA), isTrue);

      final ConnectionPolicy parsed = ConnectionPolicy.fromJson(wire);
      expect(parsed.endpointConnectionRule, isNotNull);
      expect(parsed.autoConnectCriteria, isNotNull);
      expect(
        parsed.endpointConnectionRule!.toJson(),
        equals(wire[JsonFields.AUTO_CONNECT_CRITERIA]),
      );
    });
  });
}
