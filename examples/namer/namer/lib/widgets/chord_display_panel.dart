import 'package:flutter/material.dart';
import '../utils/chord_utils.dart';

/// Left panel (25% of screen) that displays the current chord and held notes.
/// 
/// Shows:
/// - Chord root (very large)
/// - Chord name (smaller, beneath root) - tappable to toggle naming scheme
/// - List of currently held note names
/// 
/// This panel only responds to physical key presses, not UI interactions.
class ChordDisplayPanel extends StatelessWidget {
  /// Set of currently held MIDI note values
  final Set<int> heldNotes;
  
  /// Whether to use jazz notation
  final bool useJazzNotation;
  
  /// Callback when the naming scheme should toggle
  final VoidCallback onToggleNamingScheme;
  
  const ChordDisplayPanel({
    super.key,
    required this.heldNotes,
    required this.useJazzNotation,
    required this.onToggleNamingScheme,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Detect chord from held notes
    final chordInfo = ChordUtils.detectChord(heldNotes);
    final rootNote = chordInfo?.$1 ?? '-';
    
    // Format chord name
    String chordName = '';
    if (chordInfo != null) {
      chordName = ChordUtils.formatChord(
        chordInfo.$1,
        chordInfo.$2,
        chordInfo.$3,
        useJazzNotation,
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.3),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Chord root (very large)
          Text(
            rootNote,
            style: TextStyle(
              fontSize: 120,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Chord name (smaller, tappable)
          if (chordName.isNotEmpty)
            GestureDetector(
              onTap: onToggleNamingScheme,
              child: Text(
                chordName,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
