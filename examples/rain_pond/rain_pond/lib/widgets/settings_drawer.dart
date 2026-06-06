import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/pond_controller.dart';
import '../models/visual_settings.dart';

/// Side drawer with sliders for rain and ripple tuning.
class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final PondController pond = context.watch<PondController>();
    final VisualSettings s = pond.settings;

    return Drawer(
      backgroundColor: const Color(0xFF1E2D38).withOpacity(0.97),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (BuildContext context, Widget? _) {
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                Text(
                  'Pond',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFE8F4FC),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 10),
                _ConnectionStatusChip(
                  connected: pond.isConnected,
                  ready: pond.initialized,
                ),
                const SizedBox(height: 12),
                Text(
                  'Keyboard: A–L, ;, \', Enter = test notes.\n'
                  'Dog Paw: connect key_press for live play.',
                  style: TextStyle(
                    color: Colors.blueGrey.shade200,
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
                const Divider(height: 28, color: Color(0xFF3D5A6C)),
                _slider(
                  context,
                  label: 'Baseline rain',
                  value: s.baselineRain,
                  onChanged: (double v) {
                    s.setBaselineRain(v);
                    pond.persistSettings();
                  },
                ),
                _slider(
                  context,
                  label: 'Ripple size',
                  value: s.rippleSizeScale,
                  min: 0.35,
                  max: 2.5,
                  onChanged: (double v) {
                    s.setRippleSizeScale(v);
                    pond.persistSettings();
                  },
                ),
                _slider(
                  context,
                  label: 'Ripple duration',
                  value: s.decayMultiplier,
                  min: 0.25,
                  max: 4,
                  onChanged: (double v) {
                    s.setDecayMultiplier(v);
                    pond.persistSettings();
                  },
                ),
                _slider(
                  context,
                  label: 'Color saturation',
                  value: s.saturation,
                  min: 0.15,
                  max: 1,
                  onChanged: (double v) {
                    s.setSaturation(v);
                    pond.persistSettings();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// One labeled slider row shared by drawer controls.
  Widget _slider(
    BuildContext context, {
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0,
    double max = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.blueGrey.shade100, fontSize: 14),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Pill label for Epiphany / Dog Paw connection state, shown only inside the drawer
/// so the pond stays visually clean when the drawer is closed.
class _ConnectionStatusChip extends StatelessWidget {
  const _ConnectionStatusChip({
    required this.connected,
    required this.ready,
  });

  /// Whether key events are flowing from Dog Paw (`true`) or only local keyboard.
  final bool connected;

  /// Whether [PondController.initialize] has finished its first phase (prefs loaded).
  final bool ready;

  /// Renders the appropriate pill label from [ready] and [connected].
  ///
  /// @pre None.
  /// @post Returns a const-styled [Container] with status text.
  /// @invariant Does not mutate [PondController]; only displays [connected]/[ready].
  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Starting…',
          style: TextStyle(color: Color(0xFFE8F4FC), fontSize: 12),
        ),
      );
    }
    final String text = connected ? 'Dog Paw' : 'Keyboard only';
    final Color bg = connected
        ? const Color(0xFF2A6F4A).withOpacity(0.85)
        : const Color(0xFF6B5B2A).withOpacity(0.85);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFE8F4FC), fontSize: 12),
      ),
    );
  }
}
