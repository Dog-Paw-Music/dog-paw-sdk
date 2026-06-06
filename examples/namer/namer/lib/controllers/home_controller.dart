import 'package:flutter/foundation.dart';
import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw/dogpaw.dart';
import '../services/namer_service.dart';
import '../services/naming_scheme_service.dart';

/// Controller for the home screen that manages app state and business logic.
/// 
/// Encapsulates:
/// - Connection lifecycle with Epiphany
/// - Physical key tracking
/// - Chord selection state
/// - Naming scheme preference
/// 
/// Uses ChangeNotifier to notify UI of state changes.
/// DogPawEntity is injected via constructor for testability.
class HomeController extends ChangeNotifier {
  final dp.DogPawEntity _entity;
  
  late final NamerService _namerService;
  late final NamingSchemeService _namingSchemeService;
  
  // State
  bool _isLoading = true;
  bool _isConnected = false;
  final Set<int> _physicallyHeldNotes = {};
  Set<int> _selectedNotes = {0, 4, 7}; // Default: C Major
  
  HomeController({
    required dp.DogPawEntity entity,
  }) : _entity = entity;
  
  // Getters for UI to observe state
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  Set<int> get physicallyHeldNotes => _physicallyHeldNotes;
  Set<int> get selectedNotes => _selectedNotes;
  bool get useJazzNotation => _namingSchemeService.useJazzNotation;
  
  /// Get the NamerService for LED operations
  NamerService get namerService => _namerService;
  
  /// Initialize the controller: connect to system and load services.
  /// 
  /// Call this once after construction. Returns the ConnectionHandle
  /// that should have complete() called after UI is ready.
  /// 
  /// @return ConnectionHandle if successful, null if connection failed
  Future<dp.ConnectionHandle?> initialize() async {
    _isLoading = true;
    notifyListeners();
    
    // Create NamerService with callbacks that update our state
    _namerService = NamerService(
      entity: _entity,
      onKeyEvent: _handleKeyEvent,
      onLayoutUpdate: _handleLayoutUpdate,
    );
    
    // Connect to system
    final connectionHandle = await _namerService.connect();
    
    if (connectionHandle == null) {
      AppLogger.error('HomeController: Failed to connect to system');
      _isLoading = false;
      _isConnected = false;
      notifyListeners();
      return null;
    }
    
    _isConnected = true;
    
    // Get local directory and create naming scheme service
    final localDir = _namerService.getLocalDirectory();
    _namingSchemeService = NamingSchemeService(localDir);
    await _namingSchemeService.load();
    
    _isLoading = false;
    notifyListeners();
    
    return connectionHandle;
  }
  
  /// Handle key event from NamerService
  void _handleKeyEvent(int col, int row, int noteVal, dp.KeyState state) {
    AppLogger.info('HomeController: Key event: $col,$row,$noteVal,$state (${state.name})');
    
    if (state == dp.KeyState.rest) {
      _physicallyHeldNotes.remove(noteVal);
    } else if (state == dp.KeyState.pressed) {
      _physicallyHeldNotes.add(noteVal);
    }
    
    notifyListeners();
  }
  
  /// Handle layout update from NamerService
  void _handleLayoutUpdate() {
    // Layout updated, notify listeners to rebuild UI
    notifyListeners();
  }
  
  /// Update selected notes (from chord builder)
  void selectNotes(Set<int> notes) {
    _selectedNotes = notes;
    notifyListeners();
  }
  
  /// Toggle naming scheme between standard and jazz notation
  void toggleNamingScheme() {
    _namingSchemeService.toggle();
    notifyListeners();
  }
  
  /// Highlight the currently selected notes on the keyboard
  void highlightNotes() {
    AppLogger.info('HomeController: Highlighting notes');
    _namerService.highlightNotes(_selectedNotes);
  }
  
  /// Clear all note highlights on the keyboard
  void clearHighlights() {
    AppLogger.info('HomeController: Clearing highlights');
    _namerService.clearHighlights();
  }
  
  /// Clean up resources
  @override
  void dispose() {
    // Only disconnect if initialize() was called and _namerService was created
    if (_isConnected) {
      _namerService.disconnect();
    }
    super.dispose();
  }
}
