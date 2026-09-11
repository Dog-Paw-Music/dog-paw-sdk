import 'dart:typed_data';

import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

void main() {
  group('PosData field contract', () {
    test('JSON round-trips vertical / bend / rawHorizontal', () {
      const PosData original = PosData(
        vertical: -0.25,
        bend: 0.5,
        rawHorizontal: -0.75,
      );

      final PosData decoded = PosData.fromJson(original.toJson());

      expect(decoded.vertical, closeTo(-0.25, 1e-9));
      expect(decoded.bend, closeTo(0.5, 1e-9));
      expect(decoded.rawHorizontal, closeTo(-0.75, 1e-9));
      expect(decoded.toJson().containsKey('horizontal'), isFalse);
      expect(decoded.toJson().containsKey('horizBlendAmt'), isFalse);
    });

    test('equality uses the three wire fields', () {
      const PosData a = PosData(
        vertical: 0.1,
        bend: 0.2,
        rawHorizontal: 0.3,
      );
      const PosData b = PosData(
        vertical: 0.1,
        bend: 0.2,
        rawHorizontal: 0.3,
      );
      const PosData c = PosData(
        vertical: 0.1,
        bend: 0.2,
        rawHorizontal: 0.4,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('KeyPositionBuffer float layout', () {
    /// Mirrors `DPCommon::getKeyedBufferOffset` / Dart `_getKeyedBufferOffset`.
    int keyedOffset(int col, int row) {
      final int bladeIdx = 7 - col;
      final int keyIdx = 7 - row;
      return keyIdx + 8 * bladeIdx;
    }

    test('reads vertical / bend / rawHorizontal at float offsets 0 / 4 / 8', () {
      final ByteData bytes = ByteData(64 * 12);
      const int col = 2;
      const int row = 3;
      final int byteOffset = keyedOffset(col, row) * 12;

      bytes.setFloat32(byteOffset, -0.5, Endian.little);
      bytes.setFloat32(byteOffset + 4, 0.25, Endian.little);
      bytes.setFloat32(byteOffset + 8, -0.9, Endian.little);

      final KeyPositionBuffer buffer =
          KeyPositionBuffer(bytes.buffer.asUint8List());
      final PosData pos = buffer.getPos(col, row);

      expect(pos.vertical, closeTo(-0.5, 1e-6));
      expect(pos.bend, closeTo(0.25, 1e-6));
      expect(pos.rawHorizontal, closeTo(-0.9, 1e-6));
    });
  });
}
