import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter_test/flutter_test.dart';
import 'package:rain_pond/services/pond_key_input_service.dart';

void main() {
  group('endpoint contracts', () {
    test('key position endpoint declares 8x8 key index spec', () {
      final dp.EndpointInfo endpoint = buildRainPondKeyPositionEndpointInfo();
      final dp.EndpointSpec spec = endpoint.spec!;

      expect(endpoint.name, 'rain_pond_key_position_input');
      expect(spec.direction, dp.EndpointDirection.input);
      expect(spec.category, dp.EndpointCategory.continuous);
      expect(spec.dataType.baseType, dp.DataType.keyPosition);
      expect(spec.dataType.indexSpec, const dp.IndexSpecKey(8, 8));
    });
  });

  group('poll helpers', () {
    test('collectQueuedPollResults drains until poll returns empty', () {
      int pollCount = 0;

      final List<dynamic> results = collectQueuedPollResults(() {
        pollCount += 1;
        if (pollCount == 1) {
          return <dynamic>['a'];
        }
        if (pollCount == 2) {
          return <dynamic>['b', 'c'];
        }
        return <dynamic>[];
      });

      expect(results, <dynamic>['a', 'b', 'c']);
      expect(pollCount, 3);
    });

    test(
      'collectContinuousPollSnapshot reads one batch even when data remains available',
      () {
        int pollCount = 0;

        final List<dynamic> snapshot = collectContinuousPollSnapshot(() {
          pollCount += 1;
          return <dynamic>['shared-state'];
        });

        expect(snapshot, <dynamic>['shared-state']);
        expect(pollCount, 1);
      },
    );
  });

  group('key position packet decoding', () {
    test('extracts one key position from continuous PosData list payload', () {
      final List<dynamic> packet = List<dynamic>.filled(
        64,
        const dp.PosData(vertical: 1.0, horizontal: 0.0, horizBlendAmt: 0.0),
      );
      packet[keyPositionPacketIndex(col: 2, row: 3)] = const dp.PosData(
        vertical: -0.75,
        horizontal: 0.5,
        horizBlendAmt: 1.0,
      );

      final dp.PosData? pos = extractKeyPositionSample(packet, col: 2, row: 3);

      expect(
        pos,
        const dp.PosData(vertical: -0.75, horizontal: 0.5, horizBlendAmt: 1.0),
      );
    });
  });
}
