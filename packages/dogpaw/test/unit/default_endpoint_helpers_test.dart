import 'package:dogpaw/dogpaw.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EndpointInfo.defaultKeyPressOutputCriteria', () {
    test('matches BladeHW key_press output shape', () {
      final Map<String, dynamic> json =
          EndpointInfo.defaultKeyPressOutputCriteria().toJson();
      final List<dynamic> andList = json['and'] as List<dynamic>;
      expect(andList, hasLength(4));
      expect(
        andList,
        containsAll(<Matcher>[
          equals(<String, dynamic>{
            'field': 'direction',
            'operator': 'equals',
            'value': 'output',
          }),
          equals(<String, dynamic>{
            'field': 'name',
            'operator': 'equals',
            'value': DefaultDogPawEndpoints.keyPressEndpointName,
          }),
          equals(<String, dynamic>{
            'field': 'sourceEntity',
            'operator': 'equals',
            'value': DefaultDogPawEndpoints.keyPressSourceEntity,
          }),
          equals(<String, dynamic>{
            'field': 'baseType',
            'operator': 'equals',
            'value': 'key_press',
          }),
        ]),
      );
    });
  });

  group('EndpointInfo.forKeyPressInput', () {
    test('auto-connects by default', () {
      final EndpointInfo info = EndpointInfo.forKeyPressInput(
        name: 'key_input',
        displayName: 'Hello Key Input',
      );
      expect(info.name, 'key_input');
      expect(info.spec!.direction, EndpointDirection.input);
      expect(info.spec!.dataType.baseType, DataType.keyPress);
      expect(info.spec!.connectionPolicy.endpointConnectionRule, isNotNull);
    });

    test('can omit auto-connect', () {
      final EndpointInfo info = EndpointInfo.forKeyPressInput(
        name: 'key_input',
        autoConnectToDefault: false,
      );
      expect(info.spec!.connectionPolicy.endpointConnectionRule, isNull);
    });
  });

  group('EndpointInfo.defaultKeyPositionOutputCriteria', () {
    test('matches BladeHW key_position output shape', () {
      final Map<String, dynamic> json =
          EndpointInfo.defaultKeyPositionOutputCriteria().toJson();
      final List<dynamic> andList = json['and'] as List<dynamic>;
      expect(andList, hasLength(4));
      expect(
        andList,
        containsAll(<Matcher>[
          equals(<String, dynamic>{
            'field': 'direction',
            'operator': 'equals',
            'value': 'output',
          }),
          equals(<String, dynamic>{
            'field': 'name',
            'operator': 'equals',
            'value': DefaultDogPawEndpoints.keyPositionEndpointName,
          }),
          equals(<String, dynamic>{
            'field': 'sourceEntity',
            'operator': 'equals',
            'value': DefaultDogPawEndpoints.keyPressSourceEntity,
          }),
          equals(<String, dynamic>{
            'field': 'baseType',
            'operator': 'equals',
            'value': 'key_position',
          }),
        ]),
      );
    });
  });

  group('EndpointInfo.forKeyPositionInput', () {
    test('declares continuous key_position with 8x8 index by default', () {
      final EndpointInfo info = EndpointInfo.forKeyPositionInput(
        name: 'rain_pond_key_position_input',
        displayName: 'Rain Pond Key Position Input',
      );
      expect(info.name, 'rain_pond_key_position_input');
      expect(info.spec!.direction, EndpointDirection.input);
      expect(info.spec!.category, EndpointCategory.continuous);
      expect(info.spec!.dataType.baseType, DataType.keyPosition);
      expect(info.spec!.dataType.indexSpec, const IndexSpecKey(8, 8));
      expect(info.spec!.connectionPolicy.endpointConnectionRule, isNotNull);
    });

    test('can omit auto-connect', () {
      final EndpointInfo info = EndpointInfo.forKeyPositionInput(
        name: 'key_position_input',
        autoConnectToDefault: false,
      );
      expect(info.spec!.connectionPolicy.endpointConnectionRule, isNull);
    });
  });

  group('EndpointInfo.forLedOverlayOutput', () {
    test('targets led_overlay_input by default', () {
      final EndpointInfo info =
          EndpointInfo.forLedOverlayOutput(name: 'led_output');
      expect(info.spec!.direction, EndpointDirection.output);
      expect(info.spec!.dataType.baseType, DataType.ledMessage);
      final Map<String, dynamic> ruleJson =
          info.spec!.connectionPolicy.endpointConnectionRule!.toJson();
      final List<dynamic> andList = ruleJson['and'] as List<dynamic>;
      expect(
        andList,
        contains(
          equals(<String, dynamic>{
            'field': 'name',
            'operator': 'equals',
            'value': DefaultDogPawEndpoints.ledOverlayInputName,
          }),
        ),
      );
    });
  });

  group('EndpointInfo.forLedPrimaryOutput', () {
    test('targets led_primary_input by default', () {
      final EndpointInfo info =
          EndpointInfo.forLedPrimaryOutput(name: 'led_primary');
      final Map<String, dynamic> ruleJson =
          info.spec!.connectionPolicy.endpointConnectionRule!.toJson();
      final List<dynamic> andList = ruleJson['and'] as List<dynamic>;
      expect(
        andList,
        contains(
          equals(<String, dynamic>{
            'field': 'name',
            'operator': 'equals',
            'value': DefaultDogPawEndpoints.ledPrimaryInputName,
          }),
        ),
      );
    });
  });
}
