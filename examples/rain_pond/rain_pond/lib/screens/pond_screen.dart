import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/pond_controller.dart';
import '../models/ripple_key_source.dart';
import '../models/ripple_note_event.dart';
import '../utils/pond_keyboard_notes.dart';
import '../widgets/pond_canvas.dart';
import '../widgets/settings_drawer.dart';

// =============================================================================
// Rain Pond — screen
//
// After the first frame: initialize Dog Paw (prefs + connect), then
// complete() the ConnectionHandle when connect succeeded. QWERTY keys feed the
// same ripple path as hardware via submitKeyboardNote.
// =============================================================================

/// Full-screen pond with drawer and keyboard focus for local testing.
class PondScreen extends StatefulWidget {
  const PondScreen({super.key});

  @override
  State<PondScreen> createState() => _PondScreenState();
}

class _PondScreenState extends State<PondScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  /// Boot Dog Paw after Provider is available; complete the connection handle.
  Future<void> _boot() async {
    if (!mounted) {
      return;
    }
    final PondController pond = context.read<PondController>();
    final dp.ConnectionHandle? handle = await pond.initialize();
    if (!mounted) {
      return;
    }
    if (handle != null) {
      await handle.complete();
    }
  }

  /// Map a small QWERTY set into [PondController.submitKeyboardNote].
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final PondController pond = context.read<PondController>();
    if (event is KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (supportsQwertyRippleKey(event.logicalKey)) {
        pond.submitKeyboardNote(RippleNoteEvent(
          source:
              RippleKeySource.keyboard(keyboardKeyId: event.logicalKey.keyId),
          velocity: 0.88,
          isDown: true,
        ));
        return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent) {
      if (supportsQwertyRippleKey(event.logicalKey)) {
        pond.submitKeyboardNote(RippleNoteEvent(
          source:
              RippleKeySource.keyboard(keyboardKeyId: event.logicalKey.keyId),
          velocity: 0,
          isDown: false,
        ));
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        drawer: const SettingsDrawer(),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const PondCanvasWrapper(),
            Positioned(
              left: 12,
              top: 12,
              child: Material(
                color: Colors.transparent,
                child: Builder(
                  builder: (BuildContext context) {
                    return IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.menu, color: Color(0xFFE8F4FC)),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads [PondController] after [PondScreen] is mounted.
class PondCanvasWrapper extends StatelessWidget {
  const PondCanvasWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final PondController pond = context.watch<PondController>();
    return PondCanvas(controller: pond);
  }
}
