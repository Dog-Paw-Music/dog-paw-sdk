import 'dart:typed_data';

import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

void main() {
  group('LedClientAnimIdAllocator', () {
    test('wraps at 16 bits from the provided base', () {
      final LedClientAnimIdAllocator allocator =
          LedClientAnimIdAllocator(0xfffe);

      expect(allocator.next(), 0xfffe);
      expect(allocator.next(), 0xffff);
      expect(allocator.next(), 0x0000);
      expect(allocator.next(), 0x0001);
    });
  });

  group('LEDMessage solid key compatibility', () {
    test('legacy constructor still produces a solid-key record', () {
      final LEDMessage message = LEDMessage(
        column: 6,
        row: 2,
        red: 0x11,
        green: 0x22,
        blue: 0x33,
        alpha: 0x44,
        modifierLayer: 9,
      );

      final ByteData wire = message.toWireByteData();
      final LEDMessage decoded = LEDMessage.fromWireByteData(wire);

      expect(decoded, isA<SolidKeyLEDMessage>());
      final SolidKeyLEDMessage solid = decoded as SolidKeyLEDMessage;
      expect(solid.command, LedCommand.solidKey);
      expect(solid.column, 6);
      expect(solid.row, 2);
      expect(solid.red, 0x11);
      expect(solid.green, 0x22);
      expect(solid.blue, 0x33);
      expect(solid.alpha, 0x44);
      expect(solid.modifierLayer, 1);
      expect(solid.asOverride, isTrue);
    });

    test('supports explicit solid-key construction without override', () {
      final SolidKeyLEDMessage message = SolidKeyLEDMessage(
        column: 1,
        row: 7,
        colorArgb: 0x80abcdef,
        asOverride: false,
      );

      final SolidKeyLEDMessage decoded =
          LEDMessage.fromWireByteData(message.toWireByteData())
              as SolidKeyLEDMessage;

      expect(decoded.command, LedCommand.solidKey);
      expect(decoded.column, 1);
      expect(decoded.row, 7);
      expect(decoded.colorArgb, 0x80abcdef);
      expect(decoded.asOverride, isFalse);
      expect(decoded.modifierLayer, 0);
    });
  });

  group('LEDMessage retained animation commands', () {
    test('round trips highlight, cancel, and highlight mask commands', () {
      final KeyHighlightLEDMessage highlight = KeyHighlightLEDMessage(
        column: 3,
        row: 4,
        colorArgb: 0xff102030,
        clientInstanceId: 0x4567,
      );
      final AnimationCancelLEDMessage cancel =
          AnimationCancelLEDMessage(clientInstanceId: 0x4567);
      final KeyHighlightMaskLEDMessage mask = KeyHighlightMaskLEDMessage(
        colorArgb: 0xff998877,
        keyMask: 0x0001001000010010,
        clientInstanceId: 0x1234,
      );

      final KeyHighlightLEDMessage decodedHighlight =
          LEDMessage.fromWireByteData(highlight.toWireByteData())
              as KeyHighlightLEDMessage;
      final AnimationCancelLEDMessage decodedCancel =
          LEDMessage.fromWireByteData(cancel.toWireByteData())
              as AnimationCancelLEDMessage;
      final KeyHighlightMaskLEDMessage decodedMask =
          LEDMessage.fromWireByteData(mask.toWireByteData())
              as KeyHighlightMaskLEDMessage;

      expect(decodedHighlight.column, 3);
      expect(decodedHighlight.row, 4);
      expect(decodedHighlight.colorArgb, 0xff102030);
      expect(decodedHighlight.clientInstanceId, 0x4567);

      expect(decodedCancel.command, LedCommand.keyAnimCancel);
      expect(decodedCancel.clientInstanceId, 0x4567);

      expect(decodedMask.command, LedCommand.keyAnimHighlightMask);
      expect(decodedMask.colorArgb, 0xff998877);
      expect(decodedMask.keyMask, 0x0001001000010010);
      expect(decodedMask.clientInstanceId, 0x1234);
    });

    test('round trips spread and LR highlight commands', () {
      final SpreadHighlightLEDMessage spread = SpreadHighlightLEDMessage(
        column: 2,
        row: 5,
        colorArgb: 0xffabcdef,
        spread: 2.5,
        shape: -0.75,
        clientInstanceId: 0x2244,
      );
      final LrHighlightLEDMessage lr = LrHighlightLEDMessage(
        column: 7,
        row: 0,
        colorArgb: 0xff554433,
        lr: 0.375,
        clientInstanceId: 0x5533,
      );

      final SpreadHighlightLEDMessage decodedSpread =
          LEDMessage.fromWireByteData(spread.toWireByteData())
              as SpreadHighlightLEDMessage;
      final LrHighlightLEDMessage decodedLr =
          LEDMessage.fromWireByteData(lr.toWireByteData())
              as LrHighlightLEDMessage;

      expect(decodedSpread.column, 2);
      expect(decodedSpread.row, 5);
      expect(decodedSpread.colorArgb, 0xffabcdef);
      expect(decodedSpread.spread, closeTo(2.5, 1e-6));
      expect(decodedSpread.shape, closeTo(-0.75, 1e-6));
      expect(decodedSpread.clientInstanceId, 0x2244);

      expect(decodedLr.column, 7);
      expect(decodedLr.row, 0);
      expect(decodedLr.colorArgb, 0xff554433);
      expect(decodedLr.lr, closeTo(0.375, 1e-6));
      expect(decodedLr.clientInstanceId, 0x5533);
    });

    test('round trips pulse, rainbow-wave, and pulse-wave commands', () {
      final KeyPulseLEDMessage keyPulse = KeyPulseLEDMessage(
        colorArgb: 0xff010203,
        colorArgbB: 0xff040506,
        keyMask: 0x00ff0000ff00ff00,
        clientInstanceId: 0x1010,
      );
      final SidePulseLEDMessage sidePulse = SidePulseLEDMessage(
        colorArgb: 0xff0a0b0c,
        colorArgbB: 0xff0d0e0f,
        keyMask: 0x0f0f0f0f0f0f0f0f,
        clientInstanceId: 0x2020,
      );
      final RainbowWaveLEDMessage rainbow =
          RainbowWaveLEDMessage(clientInstanceId: 0x3030);
      final PulseWaveLEDMessage pulseWave = PulseWaveLEDMessage(
        basePulseHz: 1.25,
        deltaPulseHz: 0.5,
        clientInstanceId: 0x4040,
      );

      expect(
        LEDMessage.fromWireByteData(keyPulse.toWireByteData()),
        equals(keyPulse),
      );
      expect(
        LEDMessage.fromWireByteData(sidePulse.toWireByteData()),
        equals(sidePulse),
      );
      expect(
        LEDMessage.fromWireByteData(rainbow.toWireByteData()),
        equals(rainbow),
      );

      final PulseWaveLEDMessage decodedPulseWave =
          LEDMessage.fromWireByteData(pulseWave.toWireByteData())
              as PulseWaveLEDMessage;
      expect(decodedPulseWave.basePulseHz, closeTo(1.25, 1e-6));
      expect(decodedPulseWave.deltaPulseHz, closeTo(0.5, 1e-6));
      expect(decodedPulseWave.clientInstanceId, 0x4040);
    });

    test('round trips parameter and color update commands', () {
      final AnimationParamUpdateLEDMessage keyParam =
          AnimationParamUpdateLEDMessage(
        clientInstanceId: 0x1111,
        paramIndex: LedWire.animParamSpreadHighlightLr,
        value: -0.25,
      );
      final AnimationColorUpdateLEDMessage keyColor =
          AnimationColorUpdateLEDMessage(
        clientInstanceId: 0x1111,
        colorArgb: 0xff998800,
        colorArgbB: 0xff776600,
      );
      final SideAnimationParamUpdateLEDMessage sideParam =
          SideAnimationParamUpdateLEDMessage(
        clientInstanceId: 0x2222,
        paramIndex: LedWire.animParamLrHighlightLr,
        value: 0.875,
      );
      final SideAnimationColorUpdateLEDMessage sideColor =
          SideAnimationColorUpdateLEDMessage(
        clientInstanceId: 0x2222,
        colorArgb: 0xff112233,
        colorArgbB: 0xff445566,
      );

      expect(
        LEDMessage.fromWireByteData(keyParam.toWireByteData()),
        equals(keyParam),
      );
      expect(
        LEDMessage.fromWireByteData(keyColor.toWireByteData()),
        equals(keyColor),
      );
      expect(
        LEDMessage.fromWireByteData(sideParam.toWireByteData()),
        equals(sideParam),
      );
      expect(
        LEDMessage.fromWireByteData(sideColor.toWireByteData()),
        equals(sideColor),
      );
    });

    test('round trips lifecycle sync chunks', () {
      final LifecycleSyncLEDMessage sync = LifecycleSyncLEDMessage(
        syncSequence: 42,
        chunkIndex: 1,
        chunkCount: 3,
        isStart: false,
        isEnd: true,
        activeAnimationIds: <int>[0x1001, 0x1002, 0x1003],
      );

      final LifecycleSyncLEDMessage decoded =
          LEDMessage.fromWireByteData(sync.toWireByteData())
              as LifecycleSyncLEDMessage;

      expect(decoded.command, LedCommand.lifecycleSync);
      expect(decoded.syncSequence, 42);
      expect(decoded.chunkIndex, 1);
      expect(decoded.chunkCount, 3);
      expect(decoded.isStart, isFalse);
      expect(decoded.isEnd, isTrue);
      expect(decoded.activeAnimationIds, <int>[0x1001, 0x1002, 0x1003]);
    });
  });
}
