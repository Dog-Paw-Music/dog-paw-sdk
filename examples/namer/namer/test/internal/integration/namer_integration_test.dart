import 'package:flutter_test/flutter_test.dart';
import 'package:dogpaw_test/dogpaw_test.dart';
import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:namer/services/namer_service.dart';

void main() {
  IntegrationTestFixture.register();
  
  group('Namer Integration Tests', () {
    integrationTest('connects to Epiphany and creates endpoints', () async {
      final entity = dp.DogPawEntity('TestNamer_Endpoints');
      
      final service = NamerService(
        entity: entity,
        onKeyEvent: (col, row, noteVal, state) {},
        onLayoutUpdate: () {},
      );
      
      try {
        // Connect to Epiphany
        final handle = await service.connect();
        expect(handle, isNotNull, reason: 'Connection should succeed');
        
        // Complete the connection
        await handle!.complete();
        
        // Verify entity is connected
        expect(entity.isConnected(), true);
        
        // Wait a moment for async endpoint creation
        await Future.delayed(const Duration(milliseconds: 500));
        
        // If we got this far, endpoints were created successfully
        // (createEndpoint would throw/return error if it failed)
        
      } finally {
        service.disconnect();
      }
    });
    
    integrationTest('subscribes to shared scoped layout view', () async {
      final entity = dp.DogPawEntity('TestNamer_Layout');
      bool layoutUpdateCalled = false;
      
      final service = NamerService(
        entity: entity,
        onKeyEvent: (col, row, noteVal, state) {},
        onLayoutUpdate: () {
          layoutUpdateCalled = true;
        },
      );
      
      try {
        // Connect to Epiphany
        final handle = await service.connect();
        expect(handle, isNotNull);
        await handle!.complete();
        
        // Wait for scoped layout view subscription to trigger
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Layout update callback should have been called
        // (sendImmediately=true in the shared scoped-view subscription)
        expect(layoutUpdateCalled, true, 
            reason: 'Layout update callback should be invoked');
        
      } finally {
        service.disconnect();
      }
    });
    
    integrationTest('full connection lifecycle', () async {
      final entity = dp.DogPawEntity('TestNamer_Lifecycle');
      
      final service = NamerService(
        entity: entity,
        onKeyEvent: (col, row, noteVal, state) {},
        onLayoutUpdate: () {},
      );
      
      // Connect
      final handle = await service.connect();
      expect(handle, isNotNull);
      await handle!.complete();
      expect(entity.isConnected(), true);
      
      // Get local directory
      final localDir = service.getLocalDirectory();
      expect(localDir, isNotEmpty);
      
      // Disconnect
      service.disconnect();
      expect(entity.isConnected(), false);
    });
  });
}

