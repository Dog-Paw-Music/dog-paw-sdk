import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:test/test.dart';

void main() {
  group('EndpointInfo ownerDisplayName', () {
    test('parses ownerDisplayName from endpoint search/list JSON', () {
      final EndpointInfo endpoint = EndpointInfo.fromJson(<String, dynamic>{
        JsonFields.NAME: 'out_endpoint',
        JsonFields.NAMESPACE_SELECTOR: <String, dynamic>{
          JsonFields.TYPE: 'SPECIFIC_ENTITY',
          JsonFields.SOURCE_ENTITY: 'OwnerEntity_1',
        },
        JsonFields.OWNER_DISPLAY_NAME: 'Demo Mode DPP Host',
        JsonFields.RESOLVED: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Out',
          JsonFields.DESCRIPTION: '',
          JsonFields.DIRECTION: 'output',
          JsonFields.DATA_TYPE: <String, dynamic>{
            JsonFields.BASE_TYPE: 'toggle',
            JsonFields.INDEX_SPEC: <String, dynamic>{
              JsonFields.TYPE: 'none',
            },
          },
          JsonFields.CATEGORY: JsonFields.CATEGORY_MESSAGE_QUEUE,
          JsonFields.CONNECTION_POLICY: <String, dynamic>{},
        },
      });

      expect(endpoint.ownerDisplayName, equals('Demo Mode DPP Host'));
      expect(endpoint.namespaceSelector.sourceEntity, equals('OwnerEntity_1'));
      expect(
        endpoint.toJson()[JsonFields.OWNER_DISPLAY_NAME],
        equals('Demo Mode DPP Host'),
      );
    });

    test('omits ownerDisplayName when absent', () {
      final EndpointInfo endpoint = EndpointInfo.fromJson(<String, dynamic>{
        JsonFields.NAME: 'out_endpoint',
        JsonFields.NAMESPACE_SELECTOR: <String, dynamic>{
          JsonFields.TYPE: 'SPECIFIC_ENTITY',
          JsonFields.SOURCE_ENTITY: 'OwnerEntity_1',
        },
        JsonFields.RESOLVED: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Out',
          JsonFields.DESCRIPTION: '',
          JsonFields.DIRECTION: 'output',
          JsonFields.DATA_TYPE: <String, dynamic>{
            JsonFields.BASE_TYPE: 'toggle',
            JsonFields.INDEX_SPEC: <String, dynamic>{
              JsonFields.TYPE: 'none',
            },
          },
          JsonFields.CATEGORY: JsonFields.CATEGORY_MESSAGE_QUEUE,
          JsonFields.CONNECTION_POLICY: <String, dynamic>{},
        },
      });

      expect(endpoint.ownerDisplayName, isNull);
      expect(endpoint.toJson().containsKey(JsonFields.OWNER_DISPLAY_NAME), isFalse);
    });
  });
}
