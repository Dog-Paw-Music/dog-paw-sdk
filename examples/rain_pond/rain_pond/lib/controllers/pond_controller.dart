import 'dart:math' as math;
import 'dart:ui';

import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/foundation.dart';

import '../models/ripple_key_source.dart';
import '../models/ripple_note_event.dart';
import '../models/surface_ripple.dart';
import '../models/visual_settings.dart';
import '../services/pond_key_input_service.dart';
import '../services/visual_settings_store.dart';
import '../utils/ripple_physics.dart';

/// Owns simulation state, settings, and optional Dog Paw key input.
///
/// The canvas calls [advance] each frame; note events come from hardware or UI.
class PondController extends ChangeNotifier {
  PondController({
    required dp.DogPawEntity entity,
    VisualSettings? settings,
    math.Random? random,
    bool startInitialized = false,
  })  : _entity = entity,
        settings = settings ?? VisualSettings() {
    _rng = random ?? math.Random();
    _initialized = startInitialized;
  }

  final dp.DogPawEntity _entity;
  final VisualSettings settings;

  PondKeyInputService? _keyService;
  bool _isConnected = false;
  bool _initialized = false;
  late math.Random _rng;

  final List<SurfaceRipple> _ripples = [];
  double _ambientAccumulator = 0;
  Size _lastSize = const Size(400, 400);

  /// Random position + hue for an active press, keyed like [KeySource] in C++.
  final Map<RippleKeySource, _PressVisual> _pressVisualBySource = {};

  bool get isConnected => _isConnected;
  bool get initialized => _initialized;

  /// Live ripples for painting (do not mutate from widgets).
  List<SurfaceRipple> get ripples => List.unmodifiable(_ripples);

  /// Loads prefs, connects to Epiphany (non-fatal on failure), starts key service.
  ///
  /// @return Connection handle to [complete] after first frame, or null.
  Future<dp.ConnectionHandle?> initialize() async {
    final VisualSettings loaded = await VisualSettingsStore.load();
    settings.loadFrom(loaded);

    // Run rain/ripple simulation while Epiphany connects (connect can be slow).
    _initialized = true;
    notifyListeners();

    _keyService = PondKeyInputService(
      entity: _entity,
      onNoteEvent: _onNoteEvent,
      onHeldNoteExpression: updateHeldNoteExpression,
    );
    final dp.ConnectionHandle? handle = await _keyService!.connect();
    _isConnected = handle != null;
    if (!_isConnected) {
      AppLogger.info('RainPond: running offline (keyboard only)');
    }
    notifyListeners();
    return handle;
  }

  /// Updates canvas size used for spawning at stable positions.
  void setCanvasSize(Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    _lastSize = size;
  }

  /// Feeds a note from keyboard simulation.
  ///
  /// Purpose:
  ///     Shares the same ripple path for desktop keyboard testing and Dog Paw
  ///     hardware input so visuals stay consistent across both entry points.
  /// Parameters:
  ///     event: Keyboard-derived [RippleNoteEvent] carrying source, velocity, and
  ///     press/release state.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `event.source` should use [RippleKeySource.keyboard] for keyboard input.
  /// Guarantees:
  ///     Forwards the event through the same handler used by hardware input.
  /// Invariants:
  ///     Does not bypass controller ripple spawning rules.
  void submitKeyboardNote(RippleNoteEvent event) {
    _onNoteEvent(event);
  }

  /// Updates the continuous pressure and bend state for a key that is already held.
  ///
  /// Purpose:
  ///     Accepts normalized `key_position` data from [PondKeyInputService] so
  ///     held notes can keep generating visual motion after the first strike.
  /// Parameters:
  ///     source: Physical key whose expression changed.
  ///     pressure: Normalized hold pressure in the range `0..1`.
  ///     bend: Horizontal bend in the range `-1..1`.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `source` should already have an active entry in `_pressVisualBySource`.
  /// Guarantees:
  ///     Updates retained expression for that key or ignores out-of-order input.
  /// Invariants:
  ///     Does not create or remove held-key entries.
  void updateHeldNoteExpression({
    required RippleKeySource source,
    required double pressure,
    required double bend,
  }) {
    final _PressVisual? visual = _pressVisualBySource[source];
    if (visual == null) {
      return;
    }
    visual.pressure = pressure.clamp(0.0, 1.0);
    visual.bend = bend.clamp(-1.0, 1.0);
    visual.nextRepeatDelaySec = math.min(
      visual.nextRepeatDelaySec,
      _nextHeldRepeatDelaySec(
        pressure: visual.pressure,
        intensity: settings.heldRippleIntensity,
      ),
    );
  }

  /// Advances rain and ripples by [dt].
  ///
  /// @param dt Frame delta; clamped internally.
  void advance(Duration dt) {
    if (!_initialized) {
      return;
    }
    final double sec = dt.inMicroseconds / 1e6;
    if (sec <= 0) {
      return;
    }
    _ripples.removeWhere((SurfaceRipple r) => !r.advance(sec));
    _spawnHeldEchoes(sec);
    _spawnAmbient(sec);
  }

  /// Persists current slider values.
  Future<void> persistSettings() {
    return VisualSettingsStore.save(settings);
  }

  @override
  void dispose() {
    _keyService?.dispose();
    super.dispose();
  }

  void _onNoteEvent(RippleNoteEvent e) {
    final double w = _lastSize.width;
    final double h = _lastSize.height;
    if (e.isDown) {
      final double hue = randomHueWithSpread(_rng, settings.hueSpread);
      final Offset c = randomRipplePosition(_rng, w, h);
      _pressVisualBySource[e.source] = _PressVisual(
        cx: c.dx,
        cy: c.dy,
        hue: hue,
        nextRepeatDelaySec: _nextHeldRepeatDelaySec(
          pressure: 0.0,
          intensity: settings.heldRippleIntensity,
        ),
      );
      _spawnNoteRipple(
        velocity: e.velocity,
        isRelease: false,
        center: c,
        hue: hue,
      );
    } else {
      final _PressVisual? vis = _pressVisualBySource.remove(e.source);
      if (vis == null) {
        return;
      }
      _spawnNoteRipple(
        velocity: 0.35,
        isRelease: true,
        center: Offset(vis.cx, vis.cy),
        hue: vis.hue,
      );
    }
  }

  /// Spawns held-note repeat ripples and bend shimmer echoes for active keys.
  ///
  /// Purpose:
  ///     Keeps sustained notes visually alive using controller-owned timing
  ///     rather than pushing animation state into the painter or widgets.
  /// Parameters:
  ///     dtSec: Elapsed frame time in seconds; must be positive.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `advance()` must already have clamped `dtSec` to a positive value.
  /// Guarantees:
  ///     Higher pressure shortens the repeat interval. Non-zero bend adds faint
  ///     offset echoes that read as sideways shimmer.
  /// Invariants:
  ///     Does not change the cached base center or hue for any held key.
  void _spawnHeldEchoes(double dtSec) {
    if (_pressVisualBySource.isEmpty || settings.heldRippleIntensity <= 0.0) {
      return;
    }
    final double heldIntensity = settings.heldRippleIntensity;
    final double bendIntensity = settings.bendShimmerIntensity;
    for (final _PressVisual visual in _pressVisualBySource.values) {
      if (visual.pressure <= 0.01) {
        continue;
      }
      visual.repeatAccumulatorSec += dtSec;
      while (visual.repeatAccumulatorSec >= visual.nextRepeatDelaySec) {
        visual.repeatAccumulatorSec -= visual.nextRepeatDelaySec;
        _spawnHeldRepeatRipple(visual, heldIntensity);
        if (bendIntensity > 0.0 && visual.bend.abs() >= 0.05) {
          _spawnBendShimmerRipple(visual, bendIntensity);
        }
        visual.nextRepeatDelaySec = _nextHeldRepeatDelaySec(
          pressure: visual.pressure,
          intensity: heldIntensity,
        );
      }
    }
  }

  void _spawnNoteRipple({
    required double velocity,
    required bool isRelease,
    required Offset center,
    required double hue,
  }) {
    final double dur = noteRippleDurationSec(
          decayMultiplier: settings.decayMultiplier,
        ) *
        (isRelease ? 0.55 : 1.0);
    final double maxR = noteMaxRadiusPx(
          velocity: isRelease ? 0.2 : velocity,
          velocitySensitivity: settings.velocitySensitivity,
          baseRadiusPx: isRelease ? 22 : 38,
          noteScale: settings.rippleSizeScale,
        ) *
        (isRelease ? 0.55 : 1.0);
    final double stroke = noteStrokeWidthPx(
      velocity: velocity,
      lineScale: settings.lineWeightScale,
      baseWidth: isRelease ? 1.2 : 2.0,
    );
    final Color col = ringColorFromHue(
      hue: hue,
      saturation: settings.saturation,
      lightness: settings.lightness,
      alpha: isRelease ? 0.28 : 0.55,
    );
    _ripples.add(SurfaceRipple(
      cx: center.dx,
      cy: center.dy,
      ageSec: 0,
      durationSec: dur,
      maxRadiusPx: maxR,
      strokeWidthPx: stroke,
      color: col,
      isAmbient: false,
    ));
    _trimRipples();
  }

  /// Adds one transparent repeat ripple at the original held-note position.
  ///
  /// Purpose:
  ///     Makes sustained pressure visible without changing the existing press and
  ///     release ripple language.
  /// Parameters:
  ///     visual: Cached hue, center, and live expression for the held key.
  ///     intensity: User-selected held-ripple strength.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `visual.pressure` must already be normalized to `0..1`.
  /// Guarantees:
  ///     Appends one non-ambient ripple at the original note location.
  /// Invariants:
  ///     Leaves the cached held-key metadata unchanged.
  void _spawnHeldRepeatRipple(_PressVisual visual, double intensity) {
    final double pressure = visual.pressure.clamp(0.0, 1.0);
    final double alpha = (0.08 + pressure * 0.14 * intensity).clamp(0.05, 0.26);
    final double sizeScale = (0.32 + pressure * 0.32 + intensity * 0.08).clamp(
      0.25,
      0.9,
    );
    _ripples.add(
      SurfaceRipple(
        cx: visual.cx,
        cy: visual.cy,
        ageSec: 0,
        durationSec: (0.42 + pressure * 0.28).clamp(0.28, 0.85),
        maxRadiusPx: noteMaxRadiusPx(
              velocity: pressure,
              velocitySensitivity: settings.velocitySensitivity,
              baseRadiusPx: 18,
              noteScale: settings.rippleSizeScale,
            ) *
            sizeScale,
        strokeWidthPx: noteStrokeWidthPx(
              velocity: pressure,
              lineScale: settings.lineWeightScale,
              baseWidth: 1.1,
            ) *
            0.72,
        color: ringColorFromHue(
          hue: visual.hue,
          saturation: settings.saturation,
          lightness: settings.lightness,
          alpha: alpha,
        ),
        isAmbient: false,
      ),
    );
    _trimRipples();
  }

  /// Adds a faint offset echo that follows the current bend direction.
  ///
  /// Purpose:
  ///     Gives bend its own visual identity while staying inside Rain Pond's
  ///     existing ripple aesthetic.
  /// Parameters:
  ///     visual: Cached held-note data including the latest bend amount.
  ///     intensity: User-selected bend shimmer strength.
  /// Return value:
  ///     None.
  /// Requirements:
  ///     `visual.bend` must be normalized to `-1..1`.
  /// Guarantees:
  ///     Appends one offset ripple sharing the held note's hue.
  /// Invariants:
  ///     Does not move the original held-note center.
  void _spawnBendShimmerRipple(_PressVisual visual, double intensity) {
    final double bend = visual.bend.clamp(-1.0, 1.0);
    final double pressure = visual.pressure.clamp(0.0, 1.0);
    final double distance = bend *
        (8.0 + 30.0 * intensity.clamp(0.0, 1.5)) *
        (0.55 + pressure * 0.45);
    _ripples.add(
      SurfaceRipple(
        cx: visual.cx + distance,
        cy: visual.cy,
        ageSec: 0,
        durationSec: 0.34 + bend.abs() * 0.18,
        maxRadiusPx: (16.0 + pressure * 18.0) * (0.45 + intensity * 0.2),
        strokeWidthPx: 1.0 + pressure * 1.5,
        color: ringColorFromHue(
          hue: visual.hue,
          saturation: settings.saturation,
          lightness: (settings.lightness + 0.06).clamp(0.0, 1.0),
          alpha: (0.06 + bend.abs() * 0.09 * intensity).clamp(0.05, 0.2),
        ),
        isAmbient: false,
      ),
    );
    _trimRipples();
  }

  /// Chooses the next held-ripple delay from pressure, slider intensity, and jitter.
  ///
  /// Purpose:
  ///     Keeps sustained ripples organic instead of perfectly periodic while
  ///     still making harder pressure feel more energetic.
  /// Parameters:
  ///     pressure: Normalized pressure value in the range `0..1`.
  ///     intensity: Held-ripple slider value in the range `0..1.5`.
  /// Return value:
  ///     Delay in seconds until the next held ripple should spawn.
  /// Requirements:
  ///     Inputs should already be within their documented ranges.
  /// Guarantees:
  ///     Returns a positive delay bounded to a visually stable range.
  /// Invariants:
  ///     Reads controller RNG but does not mutate held-key caches.
  double _nextHeldRepeatDelaySec({
    required double pressure,
    required double intensity,
  }) {
    final double pressureClamped = pressure.clamp(0.0, 1.0);
    final double intensityClamped = intensity.clamp(0.0, 1.5);
    final double speed =
        (0.2 + pressureClamped * 0.8) * (0.35 + intensityClamped * 0.65);
    final double baseDelay = (1.15 - speed * 0.95).clamp(0.18, 1.15);
    final double jitter = 0.78 + _rng.nextDouble() * 0.44;
    return (baseDelay * jitter).clamp(0.14, 1.35);
  }

  void _spawnAmbient(double dtSec) {
    // Lower threshold + higher rate so default slider reads as steady light rain.
    const double spawnThreshold = 0.48;
    final double rate = settings.baselineRain * 7.5;
    _ambientAccumulator += rate * dtSec;
    final double w = _lastSize.width;
    final double h = _lastSize.height;
    while (_ambientAccumulator >= spawnThreshold) {
      _ambientAccumulator -= spawnThreshold;
      final double cx = _rng.nextDouble() * w;
      final double cy = _rng.nextDouble() * h;
      final double scale = settings.ambientRippleScale;
      _ripples.add(SurfaceRipple(
        cx: cx,
        cy: cy,
        ageSec: 0,
        durationSec: 0.55 + _rng.nextDouble() * 0.35,
        maxRadiusPx: (11 + _rng.nextDouble() * 18) * scale,
        strokeWidthPx: (1.15 + _rng.nextDouble() * 0.85) * scale,
        color: Color.fromRGBO(
          215,
          240,
          255,
          0.28 + _rng.nextDouble() * 0.14,
        ),
        isAmbient: true,
      ));
      _trimRipples();
    }
  }

  void _trimRipples() {
    final int max = settings.maxRipples;
    while (_ripples.length > max) {
      _ripples.removeAt(0);
    }
  }
}

/// Cached center and hue for a held key so release matches press.
class _PressVisual {
  _PressVisual({
    required this.cx,
    required this.cy,
    required this.hue,
    required this.nextRepeatDelaySec,
  });

  final double cx;
  final double cy;
  final double hue;
  double pressure = 0.0;
  double bend = 0.0;
  double repeatAccumulatorSec = 0.0;
  double nextRepeatDelaySec;
}
