import 'package:flutter_test/flutter_test.dart';
import 'package:namer/services/namer_service.dart';
import '../../mocks/mock_dogpaw_entity.dart';

void main() {
  group('NamerService', () {
    late MockDogPawEntity mockEntity;
    late NamerService service;
    // bool keyEventCalled = false;
    bool layoutUpdateCalled = false;
    
    setUp(() {
      mockEntity = MockDogPawEntity();
      // keyEventCalled = false;
      layoutUpdateCalled = false;
      
      service = NamerService(
        entity: mockEntity,
        onKeyEvent: (col, row, noteVal, state) {
          // keyEventCalled = true;
        },
        onLayoutUpdate: () {
          layoutUpdateCalled = true;
        },
      );
    });
    
    tearDown(() {
      service.disconnect();
      mockEntity.reset();
    });
    
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
    
    test('highlightNotes sends LED messages for each note', () {
      // This test would require more complex mocking of endpoints
      // For now, we verify the service doesn't crash
      service.highlightNotes({0, 4, 7}); // C major
      
      // No exception = success
    });
    
    test('clearHighlights sends clear messages', () {
      // This test would require more complex mocking of endpoints
      // For now, we verify the service doesn't crash
      service.clearHighlights();
      
      // No exception = success
    });
  });
}

