import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer/services/namer_service.dart';
import '../../mocks/mock_dogpaw_entity.dart';

void main() {
  group('NamerService', () {
    late MockDogPawEntity mockEntity;
    late NamerService service;
    bool layoutUpdateCalled = false;

    setUp(() {
      mockEntity = MockDogPawEntity();
      layoutUpdateCalled = false;

      service = NamerService(
        entity: mockEntity,
        onKeyEvent: (col, row, noteVal, state) {},
        onLayoutUpdate: () {
          layoutUpdateCalled = true;
        },
      );
    });

    tearDown(() {
      service.disconnect();
      mockEntity.reset();
    });

    /// Push a layout whose keys use full MIDI notes (as Epiphany does).
    ///
    /// Purpose:
    ///     Give highlight / reverse-lookup tests a realistic key→MIDI map.
    /// Parameters:
    ///     None (uses [mockEntity.layoutCallback] after connect).
    /// Return value:
    ///     None.
    /// Requirements:
    ///     [service.connect] must already have stored [mockEntity.layoutCallback].
    /// Guarantees:
    ///     Keys (0,0)/(1,0)/(2,0)/(3,0) map to MIDI 60/64/67/72 (C4/E4/G4/C5).
    /// Invariants:
    ///     Does not create endpoints or change connection state.
    void pushCMajorLayoutAcrossOctaves() {
      mockEntity.layoutCallback!(
        dp.ScopedLayoutView.fromResolvedLayout(
          dp.Layout.full(
            name: 'test_layout',
            resolved: const dp.LayoutData(
              displayName: 'Test Layout',
              keyIntents: <String, dynamic>{
                '0,0': <dp.KeyIntent>[
                  dp.KeyIntent.midiNote(dp.MidiNoteData(midiNote: 60)),
                ],
                '1,0': <dp.KeyIntent>[
                  dp.KeyIntent.midiNote(dp.MidiNoteData(midiNote: 64)),
                ],
                '2,0': <dp.KeyIntent>[
                  dp.KeyIntent.midiNote(dp.MidiNoteData(midiNote: 67)),
                ],
                '3,0': <dp.KeyIntent>[
                  dp.KeyIntent.midiNote(dp.MidiNoteData(midiNote: 72)),
                ],
              },
            ),
          ),
          const dp.LayoutViewPolicy(
            strategy: dp.LayoutViewStrategy.sharedOnly,
          ),
        ),
      );
    }

    test('connect succeeds and returns ConnectionHandle', () async {
      mockEntity.shouldConnectSucceed = true;

      final handle = await service.connect();

      expect(handle, isNotNull);
      expect(mockEntity.connectCalled, true);
    });

    test('connect fails and returns null when entity connection fails', () async {
      mockEntity.shouldConnectSucceed = false;

      final handle = await service.connect();

      expect(handle, isNull);
      expect(mockEntity.connectCalled, true);
    });

    test('connect creates key input endpoint', () async {
      mockEntity.shouldConnectSucceed = true;
      mockEntity.shouldCreateEndpointSucceed = true;

      await service.connect();

      expect(mockEntity.createEndpointCalls, contains('key_input'));
    });

    test('connect creates LED output endpoint', () async {
      mockEntity.shouldConnectSucceed = true;
      mockEntity.shouldCreateEndpointSucceed = true;

      await service.connect();

      expect(mockEntity.createEndpointCalls, contains('led_output'));
    });

    test('connect subscribes to shared scoped layout view', () async {
      mockEntity.shouldConnectSucceed = true;
      mockEntity.shouldSubscribeSucceed = true;

      await service.connect();

      expect(mockEntity.subscriptionCalls, contains('scopedLayoutView'));
    });

    test('layout update callback is invoked', () async {
      mockEntity.shouldConnectSucceed = true;
      mockEntity.shouldSubscribeSucceed = true;

      await service.connect();

      // The mock sends a layout immediately, which should trigger the callback
      expect(layoutUpdateCalled, true);
    });

    test('getLocalDirectory returns entity directory', () {
      mockEntity.localDirectory = '/test/path';

      final dir = service.getLocalDirectory();

      expect(dir, '/test/path');
    });

    test('disconnect calls entity disconnect', () {
      service.disconnect();

      expect(mockEntity.disconnectCalled, true);
    });

    test(
      'getKeysForNote matches pitch classes against layout MIDI notes',
      () async {
        mockEntity.shouldConnectSucceed = true;
        await service.connect();
        pushCMajorLayoutAcrossOctaves();

        // Chord-builder pitch classes for C and E (0 and 4).
        expect(
          service.getKeysForNote(0),
          equals(<(int, int)>[(0, 0), (3, 0)]),
        );
        expect(service.getKeysForNote(4), equals(<(int, int)>[(1, 0)]));
        expect(service.getKeysForNote(7), equals(<(int, int)>[(2, 0)]));
      },
    );

    test(
      'highlightNotes lights every key whose MIDI note matches selected pitch classes',
      () async {
        mockEntity.shouldConnectSucceed = true;
        await service.connect();
        pushCMajorLayoutAcrossOctaves();

        // Same values the chord builder / Show Me button use (0-11).
        service.highlightNotes({0, 4, 7});

        final MockLocalEndpoint ledOutputEndpoint =
            mockEntity.createdEndpoints['led_output']!;
        final List<dp.KeyHighlightLEDMessage> highlights = ledOutputEndpoint
            .writtenValues
            .whereType<dp.KeyHighlightLEDMessage>()
            .toList();

        expect(highlights.length, equals(4));
        expect(
          highlights.map((dp.KeyHighlightLEDMessage m) => (m.column, m.row)).toSet(),
          equals(<(int, int)>{(0, 0), (1, 0), (2, 0), (3, 0)}),
        );
      },
    );

    test('clearHighlights cancels previously sent highlights', () async {
      mockEntity.shouldConnectSucceed = true;
      await service.connect();
      pushCMajorLayoutAcrossOctaves();

      service.highlightNotes({0, 4, 7});
      final MockLocalEndpoint ledOutputEndpoint =
          mockEntity.createdEndpoints['led_output']!;
      ledOutputEndpoint.writtenValues.clear();

      service.clearHighlights();

      final List<dp.AnimationCancelLEDMessage> cancels = ledOutputEndpoint
          .writtenValues
          .whereType<dp.AnimationCancelLEDMessage>()
          .toList();
      expect(cancels.length, equals(4));
    });
  });
}

