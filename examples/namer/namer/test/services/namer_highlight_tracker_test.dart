import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer/services/namer_highlight_tracker.dart';

void main() {
  group('NamerHighlightTracker', () {
    test('creates retained highlights for newly requested keys', () {
      final NamerHighlightTracker tracker = NamerHighlightTracker(
        allocator: dp.LedClientAnimIdAllocator(0x2200),
      );

      final List<dp.LEDMessage> messages = tracker.replaceHighlightsForKeys(
        keys: const <(int, int)>[(1, 2), (3, 4)],
        colorArgb: 0xff102030,
      );

      expect(messages, hasLength(2));

      final dp.KeyHighlightLEDMessage first =
          messages[0] as dp.KeyHighlightLEDMessage;
      final dp.KeyHighlightLEDMessage second =
          messages[1] as dp.KeyHighlightLEDMessage;

      expect((first.column, first.row), equals((1, 2)));
      expect(first.colorArgb, equals(0xff102030));
      expect(first.clientInstanceId, equals(0x2200));

      expect((second.column, second.row), equals((3, 4)));
      expect(second.colorArgb, equals(0xff102030));
      expect(second.clientInstanceId, equals(0x2201));
    });

    test('cancels removed keys and adds new keys on replacement', () {
      final NamerHighlightTracker tracker = NamerHighlightTracker(
        allocator: dp.LedClientAnimIdAllocator(0x2200),
      );

      tracker.replaceHighlightsForKeys(
        keys: const <(int, int)>[(1, 2), (3, 4)],
        colorArgb: 0xff506070,
      );

      final List<dp.LEDMessage> messages = tracker.replaceHighlightsForKeys(
        keys: const <(int, int)>[(3, 4), (5, 6)],
        colorArgb: 0xff506070,
      );

      expect(messages, hasLength(2));
      expect(messages[0], isA<dp.AnimationCancelLEDMessage>());
      expect(messages[1], isA<dp.KeyHighlightLEDMessage>());

      final dp.AnimationCancelLEDMessage cancel =
          messages[0] as dp.AnimationCancelLEDMessage;
      final dp.KeyHighlightLEDMessage create =
          messages[1] as dp.KeyHighlightLEDMessage;

      expect(cancel.clientInstanceId, equals(0x2200));
      expect((create.column, create.row), equals((5, 6)));
      expect(create.clientInstanceId, equals(0x2202));
    });

    test('clearHighlights cancels all active highlights and resets state', () {
      final NamerHighlightTracker tracker = NamerHighlightTracker(
        allocator: dp.LedClientAnimIdAllocator(0x2200),
      );

      tracker.replaceHighlightsForKeys(
        keys: const <(int, int)>[(1, 2), (3, 4)],
        colorArgb: 0xff8090a0,
      );

      final List<dp.LEDMessage> messages = tracker.clearHighlights();

      expect(messages, hasLength(2));
      expect(messages[0], isA<dp.AnimationCancelLEDMessage>());
      expect(messages[1], isA<dp.AnimationCancelLEDMessage>());

      final List<int> cancelledIds = messages
          .cast<dp.AnimationCancelLEDMessage>()
          .map((dp.AnimationCancelLEDMessage message) => message.clientInstanceId)
          .toList();
      expect(cancelledIds, equals(<int>[0x2200, 0x2201]));

      expect(
        tracker.replaceHighlightsForKeys(
          keys: const <(int, int)>[(7, 7)],
          colorArgb: 0xff010203,
        ),
        hasLength(1),
      );
    });
  });
}
