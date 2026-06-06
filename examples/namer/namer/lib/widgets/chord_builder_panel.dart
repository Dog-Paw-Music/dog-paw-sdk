import 'package:flutter/material.dart';
import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import '../utils/chord_utils.dart';

/// Right panel (75% of screen) for building and selecting chords.
/// 
/// Layout:
/// - Top: Root note and chord flavor selectors
/// - Middle: Piano keyboard with toggleable notes
/// - Right: "Highlight Chord" button
/// 
/// Features:
/// - Bidirectional sync between selected notes and chord/root
/// - Shows subtle shading on keys that are physically held
/// - Highlight button sends LED messages on modifier layer 11
class ChordBuilderPanel extends StatefulWidget {
  /// Currently selected notes (0-11 for C through B)
  final Set<int> selectedNotes;
  
  /// Physically held notes (MIDI note values 0-127)
  final Set<int> physicallyHeldNotes;
  
  /// Called when selected notes change
  final void Function(Set<int> notes) onNotesChanged;
  
  const ChordBuilderPanel({
    super.key,
    required this.selectedNotes,
    required this.physicallyHeldNotes,
    required this.onNotesChanged,
  });
  
  @override
  State<ChordBuilderPanel> createState() => _ChordBuilderPanelState();
}

class _ChordBuilderPanelState extends State<ChordBuilderPanel> {
  int? _rootNote; // null means no selection
  String? _chordFlavor; // null means no selection
  
  @override
  void initState() {
    super.initState();
    _updateRootAndFlavorFromNotes();
  }
  
  @override
  void didUpdateWidget(ChordBuilderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedNotes != oldWidget.selectedNotes) {
      _updateRootAndFlavorFromNotes();
    }
  }
  
  /// Update root note and flavor based on selected notes using chord detection
  void _updateRootAndFlavorFromNotes() {
    if (widget.selectedNotes.isEmpty) {
      setState(() {
        _rootNote = null;
        _chordFlavor = null;
      });
      return;
    }
    
    // Use chord detection to identify the chord
    final chordInfo = ChordUtils.detectChord(widget.selectedNotes);
    
    if (chordInfo != null) {
      final rootName = chordInfo.$1;
      final flavor = chordInfo.$2;
      
      // Convert root name to note class (0-11)
      final rootClass = ChordUtils.getNoteClass(rootName);
      
      setState(() {
        _rootNote = rootClass;
        _chordFlavor = flavor;
      });
    } else {
      // No recognized chord pattern
      setState(() {
        _rootNote = null;
        _chordFlavor = null;
      });
    }
  }
  
  /// Update selected notes based on root note and chord flavor
  void _updateNotesFromRootAndFlavor() {
    if (_rootNote == null || _chordFlavor == null) return;
    
    final newNotes = _getNotesForChord(_rootNote!, _chordFlavor!);
    widget.onNotesChanged(newNotes);
  }
  
  /// Get the set of notes for a given root and chord flavor
  Set<int> _getNotesForChord(int root, String flavor) {
    // Use the patterns from ChordUtils
    final pattern = ChordUtils.chordPatterns[flavor] ?? [0, 4, 7];
    return pattern.map((interval) => (root + interval) % 12).toSet();
  }
  
  /// Toggle a note in/out of the selection
  void _toggleNote(int noteIndex) {
    final newNotes = Set<int>.from(widget.selectedNotes);
    if (newNotes.contains(noteIndex)) {
      // Don't allow removing the last note
      if (newNotes.length > 1) {
        newNotes.remove(noteIndex);
      }
    } else {
      newNotes.add(noteIndex);
    }
    widget.onNotesChanged(newNotes);
  }
  
  /// Set root note and update chord
  void _setRootNote(int newRoot) {
    setState(() {
      _rootNote = newRoot;
      // If we have a flavor, update notes; otherwise just select the root
      if (_chordFlavor != null) {
        _updateNotesFromRootAndFlavor();
      } else {
        // Default to major if no flavor selected
        _chordFlavor = 'Major';
        _updateNotesFromRootAndFlavor();
      }
    });
  }
  
  /// Set chord flavor and update chord
  void _setChordFlavor(String newFlavor) {
    setState(() {
      _chordFlavor = newFlavor;
      // If we have a root, update notes; otherwise just select the flavor
      if (_rootNote != null) {
        _updateNotesFromRootAndFlavor();
      } else {
        // Default to C if no root selected
        _rootNote = 0;
        _updateNotesFromRootAndFlavor();
      }
    });
  }
  
  /// Get color for a piano key
  Color _getColorForNote(int noteIndex, BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = widget.selectedNotes.contains(noteIndex);
    final isPhysicallyHeld = widget.physicallyHeldNotes
        .any((midiNote) => (midiNote % 12) == noteIndex);
    
    if (isSelected && isPhysicallyHeld) {
      // Selected and physically held: bright cyan
      return theme.colorScheme.primary;
    } else if (isSelected) {
      // Selected only: secondary purple
      return theme.colorScheme.secondary;
    } else if (isPhysicallyHeld) {
      // Physically held only: subtle gray overlay
      return const Color(0xFF404040);
    } else {
      // Not selected: background color (dark for black keys, light for white)
      return NoteUtils.isBlackKey(noteIndex)
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.onSurface;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Root note selector
          _buildRootNoteSelector(context),
          
          const SizedBox(height: 16),
          
          // Row 2: Chord flavor selector
          _buildChordFlavorSelector(context),
          
          const SizedBox(height: 24),
          
          // Row 3: Piano keyboard
          Expanded(
            child: Center(
              child: PianoKeyboard(
                height: 140,
                colorForNote: (noteIndex) => _getColorForNote(noteIndex, context),
                onNoteTap: _toggleNote,
                showNoteLabels: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRootNoteSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROOT NOTE',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // First 6 notes
            ...List.generate(6, (index) {
              final isSelected = _rootNote == index;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ElevatedButton(
                    onPressed: () => _setRootNote(index),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHigh,
                      foregroundColor: isSelected ? Colors.black : theme.colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    child: Text(
                      NoteUtils.dualNoteNames[index],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            // Last 6 notes
            ...List.generate(6, (index) {
              final noteIndex = index + 6;
              final isSelected = _rootNote == noteIndex;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ElevatedButton(
                    onPressed: () => _setRootNote(noteIndex),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHigh,
                      foregroundColor: isSelected ? Colors.black : theme.colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    child: Text(
                      NoteUtils.dualNoteNames[noteIndex],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
  
  Widget _buildChordFlavorSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHORD FLAVOR',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ChordUtils.chordFlavors.map((flavor) {
            final isSelected = _chordFlavor == flavor;
            return ElevatedButton(
              onPressed: () => _setChordFlavor(flavor),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.surfaceContainerHigh,
                foregroundColor: theme.colorScheme.onSurface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
              child: Text(
                flavor,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
