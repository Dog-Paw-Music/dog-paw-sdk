import 'package:flutter_test/flutter_test.dart';
import 'package:namer/services/naming_scheme_service.dart';

void main() {
  group('NamingSchemeService', () {
    test('withPreference constructor sets initial value to false', () {
      final service = NamingSchemeService.withPreference(false);
      expect(service.useJazzNotation, false);
    });
    
    test('withPreference constructor sets initial value to true', () {
      final service = NamingSchemeService.withPreference(true);
      expect(service.useJazzNotation, true);
    });
    
    test('toggle switches from standard to jazz', () {
      final service = NamingSchemeService.withPreference(false);
      expect(service.useJazzNotation, false);
      
      service.toggle();
      expect(service.useJazzNotation, true);
    });
    
    test('toggle switches from jazz to standard', () {
      final service = NamingSchemeService.withPreference(true);
      expect(service.useJazzNotation, true);
      
      service.toggle();
      expect(service.useJazzNotation, false);
    });
    
    test('toggle can be called multiple times', () {
      final service = NamingSchemeService.withPreference(false);
      
      service.toggle(); // false -> true
      expect(service.useJazzNotation, true);
      
      service.toggle(); // true -> false
      expect(service.useJazzNotation, false);
      
      service.toggle(); // false -> true
      expect(service.useJazzNotation, true);
    });
    
    test('useJazzNotation getter returns current value', () {
      final service1 = NamingSchemeService.withPreference(false);
      expect(service1.useJazzNotation, false);
      
      final service2 = NamingSchemeService.withPreference(true);
      expect(service2.useJazzNotation, true);
    });
  });
}

