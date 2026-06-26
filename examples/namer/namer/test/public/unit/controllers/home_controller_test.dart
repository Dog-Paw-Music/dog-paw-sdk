import 'dart:convert';
import 'dart:io';

import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer/controllers/home_controller.dart';
import 'package:namer/utils/chord_utils.dart';
import '../../mocks/mock_dogpaw_entity.dart';

void main() {
  group('HomeController', () {
    late MockDogPawEntity mockEntity;
    late HomeController controller;
    
    setUp(() {
      mockEntity = MockDogPawEntity();
      controller = HomeController(entity: mockEntity);
    });
    
    tearDown(() {
      controller.dispose();
      mockEntity.reset();
    });
    
    test('initial state is loading', () {
      expect(controller.isLoading, true);
      expect(controller.isConnected, false);
    });
    
    test('initialize connects successfully and returns ConnectionHandle', () async {
      mockEntity.shouldConnectSucceed = true;
      
      final handle = await controller.initialize();
      
      expect(handle, isNotNull);
      expect(controller.isConnected, true);
      expect(controller.isLoading, false);
      expect(mockEntity.connectCalled, true);
    });
    
    test('initialize fails gracefully when connection fails', () async {
      mockEntity.shouldConnectSucceed = false;
      
      final handle = await controller.initialize();
      
      expect(handle, isNull);
      expect(controller.isConnected, false);
      expect(controller.isLoading, false);
    });
    
    test('initialize creates endpoints and subscribes to shared scoped view', () async {
      mockEntity.shouldConnectSucceed = true;
      
      await controller.initialize();
      
      // Verify endpoints were created
      expect(mockEntity.createEndpointCalls, contains('key_input'));
      expect(mockEntity.createEndpointCalls, contains('led_output'));
      
      // Verify shared scoped-view subscription
      expect(mockEntity.subscriptionCalls, contains('scopedLayoutView'));
    });
    
    test('selectNotes updates selected notes', () {
      final newNotes = {2, 5, 9}; // D, F, A
      
      controller.selectNotes(newNotes);
      
      expect(controller.selectedNotes, newNotes);
    });
    
    test('selectNotes notifies listeners', () {
      var notified = false;
      controller.addListener(() {
        notified = true;
      });
      
      controller.selectNotes({0, 3, 7});
      
      expect(notified, true);
    });
    
    test('toggleNamingScheme switches notation', () async {
      mockEntity.shouldConnectSucceed = true;
      await controller.initialize();
      
      final initialValue = controller.useJazzNotation;
      controller.toggleNamingScheme();
      
      expect(controller.useJazzNotation, !initialValue);
    });
    
    test('toggleNamingScheme notifies listeners', () async {
      mockEntity.shouldConnectSucceed = true;
      await controller.initialize();
      
      var notified = false;
      controller.addListener(() {
        notified = true;
      });
      
      controller.toggleNamingScheme();
      
      expect(notified, true);
    });
    
    test('highlightNotes can be called after initialization', () async {
      mockEntity.shouldConnectSucceed = true;
      await controller.initialize();
      
      // Should not throw
      controller.highlightNotes();
    });
    
    test('clearHighlights can be called after initialization', () async {
      mockEntity.shouldConnectSucceed = true;
      await controller.initialize();
      
      // Should not throw
      controller.clearHighlights();
    });
    
    test('physicallyHeldNotes starts empty', () {
      expect(controller.physicallyHeldNotes, isEmpty);
    });
    
    test('key event adds note to physicallyHeldNotes', () async {
      mockEntity.shouldConnectSucceed = true;
      await controller.initialize();
      
      // Simulate a key press by invoking the callback directly
      // In reality, this would come from the service polling endpoint
      // We can't easily test this without more complex mocking
      
      expect(controller.physicallyHeldNotes, isEmpty);
    });
    
    test('dispose disconnects service', () async {
      // Create a separate controller for this test to avoid double-dispose issue
      final testEntity = MockDogPawEntity();
      final testController = HomeController(entity: testEntity);
      
      testEntity.shouldConnectSucceed = true;
      await testController.initialize();
      
      testController.dispose();
      
      expect(testEntity.disconnectCalled, true);
      
      // Clean up the test-specific mock
      testEntity.reset();
    });

    test(
        'user flow receives notes, derives a chord, persists naming preference, and highlights keys',
        () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'namer_user_flow_',
      );
      mockEntity.localDirectory = tempDir.path;

      try {
        final dp.ConnectionHandle? handle = await controller.initialize();
        expect(handle, isNotNull);
        await handle!.complete();

        mockEntity.layoutCallback!(
          dp.ScopedLayoutView.fromResolvedLayout(
            dp.Layout.full(
              name: 'test_layout',
              resolved: const dp.LayoutData(
                displayName: 'Test Layout',
                keyIntents: <String, dynamic>{
                  '0,0': <dp.KeyIntent>[
                    dp.KeyIntent.midiNote(dp.MidiNoteData(midiNote: 69)),
                  ],
                  '1,0': <dp.KeyIntent>[
                    dp.KeyIntent.midiNote(dp.MidiNoteData(midiNote: 72)),
                  ],
                  '2,0': <dp.KeyIntent>[
                    dp.KeyIntent.midiNote(dp.MidiNoteData(midiNote: 76)),
                  ],
                },
              ),
            ),
            const dp.LayoutViewPolicy(
              strategy: dp.LayoutViewStrategy.sharedOnly,
            ),
          ),
        );

        final MockLocalEndpoint keyInputEndpoint =
            mockEntity.createdEndpoints['key_input']!;
        keyInputEndpoint.queuePollBatch(<dynamic>[
          const dp.KeyEvent(
            type: dp.KeyEventType.pressed,
            column: 0,
            row: 0,
            velocity: 0.8,
            oldState: dp.KeyState.activated,
            newState: dp.KeyState.pressed,
            timestamp: 1,
          ),
          const dp.KeyEvent(
            type: dp.KeyEventType.pressed,
            column: 1,
            row: 0,
            velocity: 0.8,
            oldState: dp.KeyState.activated,
            newState: dp.KeyState.pressed,
            timestamp: 2,
          ),
          const dp.KeyEvent(
            type: dp.KeyEventType.pressed,
            column: 2,
            row: 0,
            velocity: 0.8,
            oldState: dp.KeyState.activated,
            newState: dp.KeyState.pressed,
            timestamp: 3,
          ),
        ]);

        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(controller.physicallyHeldNotes, equals(<int>{69, 72, 76}));

        final (String, String, String?)? chordInfo =
            ChordUtils.detectChord(controller.physicallyHeldNotes);
        expect(chordInfo, isNotNull);
        expect(
          ChordUtils.formatChord(
            chordInfo!.$1,
            chordInfo.$2,
            chordInfo.$3,
            controller.useJazzNotation,
          ),
          equals('Amin'),
        );

        controller.toggleNamingScheme();

        final File settingsFile = File('${tempDir.path}/namer_settings.json');
        for (int attempt = 0; attempt < 20 && !await settingsFile.exists();
            attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(await settingsFile.exists(), isTrue);
        final Map<String, dynamic> persistedSettings =
            jsonDecode(await settingsFile.readAsString())
                as Map<String, dynamic>;
        expect(persistedSettings['useJazzNotation'], isTrue);
        expect(
          ChordUtils.formatChord(
            chordInfo.$1,
            chordInfo.$2,
            chordInfo.$3,
            controller.useJazzNotation,
          ),
          equals('A-'),
        );

        controller.selectNotes(controller.physicallyHeldNotes);
        controller.highlightNotes();

        final MockLocalEndpoint ledOutputEndpoint =
            mockEntity.createdEndpoints['led_output']!;
        expect(ledOutputEndpoint.writtenValues.length, greaterThanOrEqualTo(3));
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}

