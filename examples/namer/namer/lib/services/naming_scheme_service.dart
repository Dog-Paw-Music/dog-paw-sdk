import 'dart:io';
import 'dart:convert';
import 'package:dogpaw/dogpaw.dart';

/// Service for managing the chord naming scheme preference (standard vs jazz).
/// Persists the choice to a JSON file in the app's local directory.
class NamingSchemeService {
  final String _localDirectory;
  bool _useJazzNotation = false;
  
  static const String _settingsFileName = 'namer_settings.json';
  
  /// Creates a NamingSchemeService that persists to the given directory.
  /// 
  /// @param localDirectory Path to directory for storing settings file
  NamingSchemeService(this._localDirectory);
  
  /// Creates a NamingSchemeService with a preset preference (for testing).
  /// 
  /// This constructor bypasses file persistence and sets the preference directly.
  /// Useful for unit tests that don't need file I/O.
  /// 
  /// @param useJazz Initial value for the jazz notation preference
  NamingSchemeService.withPreference(bool useJazz)
      : _localDirectory = '',
        _useJazzNotation = useJazz;
  
  /// Get the current naming scheme preference
  bool get useJazzNotation => _useJazzNotation;
  
  /// Toggle between standard and jazz notation
  void toggle() {
    _useJazzNotation = !_useJazzNotation;
    _save();
  }
  
  /// Load the naming scheme preference from file
  Future<void> load() async {
    try {
      final file = File('$_localDirectory/$_settingsFileName');
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents) as Map<String, dynamic>;
        _useJazzNotation = json['useJazzNotation'] as bool? ?? false;
        AppLogger.info('NamingScheme: Loaded preference: useJazzNotation=$_useJazzNotation');
      } else {
        AppLogger.info('NamingScheme: No settings file found, using default (standard notation)');
      }
    } catch (e) {
      AppLogger.error('NamingScheme: Error loading settings: $e');
      _useJazzNotation = false;
    }
  }
  
  /// Save the naming scheme preference to file
  Future<void> _save() async {
    // Skip saving if using test constructor
    if (_localDirectory.isEmpty) {
      return;
    }
    
    try {
      final file = File('$_localDirectory/$_settingsFileName');
      final json = {
        'useJazzNotation': _useJazzNotation,
      };
      await file.writeAsString(jsonEncode(json));
      AppLogger.info('NamingScheme: Saved preference: useJazzNotation=$_useJazzNotation');
    } catch (e) {
      AppLogger.error('NamingScheme: Error saving settings: $e');
    }
  }
}
