/// Status for one private simulator socket exposed by the emulator bridge.
///
/// Purpose: describes whether one backend simulator endpoint is ready for GUI
/// actions.
/// Parameters: [available] is true when the bridge reports the socket path
/// exists.
/// Return value: immutable model object.
/// Requirements: values should come from `/api/health`.
/// Guarantees: construction does not perform I/O.
/// Invariants: this model does not own socket lifetime.
class SimulatorSocketStatus {
  const SimulatorSocketStatus({required this.available});

  final bool available;

  /// Decode one socket status object from bridge JSON.
  ///
  /// Purpose: keeps `/api/health` parsing tolerant of extra bridge fields.
  /// Parameters: [jsonValue] must be a JSON object with optional `available`.
  /// Return value: decoded status, defaulting to unavailable when malformed.
  /// Requirements: callers should pass one `sockets.<name>` object.
  /// Guarantees: never throws for missing fields.
  /// Invariants: unknown fields are ignored.
  factory SimulatorSocketStatus.fromJson(Object? jsonValue) {
    if (jsonValue is! Map<String, Object?>) {
      return const SimulatorSocketStatus(available: false);
    }
    return SimulatorSocketStatus(available: jsonValue['available'] == true);
  }
}

/// Health response returned by the emulator bridge.
///
/// Purpose: gives the GUI a compact readiness summary for the selected emulator.
/// Parameters: [ok] is the bridge-level success flag; [emulatorName] and
/// [instanceName] identify the emulator; [sockets] stores backend availability.
/// Return value: immutable health model.
/// Requirements: values should come from `/api/health`.
/// Guarantees: construction does not perform network or filesystem access.
/// Invariants: socket keys remain bridge API names such as `keyGrid`.
class BridgeHealth {
  const BridgeHealth({
    required this.ok,
    required this.emulatorName,
    required this.instanceName,
    required this.sockets,
  });

  final bool ok;
  final String emulatorName;
  final String instanceName;
  final Map<String, SimulatorSocketStatus> sockets;

  /// Decode bridge health JSON into a model.
  ///
  /// Purpose: maps raw bridge response data into typed GUI state.
  /// Parameters: [jsonValue] must be the decoded `/api/health` object.
  /// Return value: decoded health model.
  /// Requirements: bridge fields should match the Python bridge schema.
  /// Guarantees: missing names become `unknown`, missing sockets become empty.
  /// Invariants: unknown socket entries are preserved by name.
  factory BridgeHealth.fromJson(Map<String, Object?> jsonValue) {
    final socketValues = jsonValue['sockets'];
    final sockets = <String, SimulatorSocketStatus>{};
    if (socketValues is Map<String, Object?>) {
      for (final entry in socketValues.entries) {
        sockets[entry.key] = SimulatorSocketStatus.fromJson(entry.value);
      }
    }
    return BridgeHealth(
      ok: jsonValue['ok'] == true,
      emulatorName: jsonValue['emulator'] as String? ?? 'unknown',
      instanceName: jsonValue['instance'] as String? ?? 'unknown',
      sockets: sockets,
    );
  }

  /// Return whether a named simulator socket is available.
  ///
  /// Purpose: lets UI widgets ask readiness questions without duplicating map
  /// lookup defaults.
  /// Parameters: [name] is a bridge socket key such as `ledComms`.
  /// Return value: true only when that socket is present and available.
  /// Requirements: [name] must use the bridge API socket naming.
  /// Guarantees: absent names return false.
  /// Invariants: the underlying [sockets] map is not mutated.
  bool socketAvailable(String name) {
    return sockets[name]?.available == true;
  }
}

/// Logical key state used by the emulator control GUI.
///
/// Purpose: gives Flutter, the bridge client, and tests one shared vocabulary
/// for the key states that the PicoComms simulator accepts.
/// Parameters: none.
/// Return value: enum value naming one logical key state.
/// Requirements: values must stay aligned with the Python bridge schema.
/// Guarantees: names are stable for JSON encoding via [bridgeName].
/// Invariants: ordering has no semantic meaning.
enum EmulatorKeyState {
  rest('rest'),
  active('active'),
  pressed('pressed');

  const EmulatorKeyState(this.bridgeName);

  final String bridgeName;
}

/// One interactive key update requested by the emulator control GUI.
///
/// Purpose: carries the desired logical state plus continuous position values
/// for one key interaction update headed to the bridge.
/// Parameters: [col] and [row] identify the key; [state] is the target logical
/// state; [velocity] is a normalized 0..1 magnitude; [vertical] and [horizontal]
/// are normalized key-position values in range -1..1.
/// Return value: immutable request model.
/// Requirements: coordinates should be in range 0..7.
/// Guarantees: construction performs no I/O or clamping.
/// Invariants: values represent one complete bridge request payload.
class KeyInteractionRequest {
  const KeyInteractionRequest({
    required this.col,
    required this.row,
    required this.state,
    required this.velocity,
    required this.vertical,
    required this.horizontal,
  });

  final int col;
  final int row;
  final EmulatorKeyState state;
  final double velocity;
  final double vertical;
  final double horizontal;
}

/// One visible LED layer entry from the LEDComms snapshot.
///
/// Purpose: represents a colored key that the emulator GUI can draw.
/// Parameters: [col] and [row] are logical Dog Paw coordinates; [red],
/// [green], [blue], and [alpha] are 8-bit color channels.
/// Return value: immutable LED key model.
/// Requirements: coordinates should be in range 0..7 and channels 0..255.
/// Guarantees: construction does not clamp values.
/// Invariants: coordinates use the Dog Paw logical `(col,row)` convention.
class LedKeyLayer {
  const LedKeyLayer({
    required this.col,
    required this.row,
    this.left = true,
    this.right = true,
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
  });

  final int col;
  final int row;
  final bool left;
  final bool right;
  final int red;
  final int green;
  final int blue;
  final int alpha;

  /// Decode one LED key layer from bridge JSON.
  ///
  /// Purpose: translates LEDComms introspection payloads into typed GUI color
  /// data.
  /// Parameters: [jsonValue] must contain integer `col`, `row`, and top-level
  /// `r`, `g`, `b`, `a` channel values.
  /// Return value: decoded key layer.
  /// Requirements: callers should pass one object from `keyLayers`.
  /// Guarantees: missing color channels default to transparent black.
  /// Invariants: unknown fields are ignored.
  factory LedKeyLayer.fromJson(Map<String, Object?> jsonValue) {
    return LedKeyLayer(
      col: jsonValue['col'] as int? ?? 0,
      row: jsonValue['row'] as int? ?? 0,
      left: jsonValue['left'] as bool? ?? true,
      right: jsonValue['right'] as bool? ?? true,
      red: jsonValue['r'] as int? ?? 0,
      green: jsonValue['g'] as int? ?? 0,
      blue: jsonValue['b'] as int? ?? 0,
      alpha: jsonValue['a'] as int? ?? 0,
    );
  }
}

/// LEDComms snapshot returned by the emulator bridge.
///
/// Purpose: stores the current simulated key LED state for rendering.
/// Parameters: [ok] is the bridge/simulator success flag and [keyLayers] are
/// visible key color entries.
/// Return value: immutable snapshot model.
/// Requirements: values should come from `/api/led/snapshot`.
/// Guarantees: construction does not perform network access.
/// Invariants: layer ordering remains the bridge response ordering.
class LedSnapshot {
  const LedSnapshot({required this.ok, required this.keyLayers});

  final bool ok;
  final List<LedKeyLayer> keyLayers;

  /// Decode a LED snapshot JSON object.
  ///
  /// Purpose: maps raw LEDComms bridge data into typed render state.
  /// Parameters: [jsonValue] must be the decoded `/api/led/snapshot` object.
  /// Return value: decoded LED snapshot.
  /// Requirements: `keyLayers`, when present, should be a JSON list.
  /// Guarantees: malformed layer entries are skipped.
  /// Invariants: snapshot parsing does not alter bridge data.
  factory LedSnapshot.fromJson(Map<String, Object?> jsonValue) {
    final layersJson = jsonValue['keyLayers'];
    final layers = <LedKeyLayer>[];
    if (layersJson is List<Object?>) {
      for (final layerJson in layersJson) {
        if (layerJson is Map<String, Object?>) {
          layers.add(LedKeyLayer.fromJson(layerJson));
        }
      }
    }
    return LedSnapshot(ok: jsonValue['ok'] == true, keyLayers: layers);
  }

  /// Find the first LED layer for one key coordinate.
  ///
  /// Purpose: lets the grid renderer color each key without knowing snapshot
  /// storage details.
  /// Parameters: [col] and [row] are logical Dog Paw coordinates in range 0..7.
  /// Return value: matching LED layer, or null when no color is visible.
  /// Requirements: callers should pass valid key coordinates.
  /// Guarantees: does not mutate [keyLayers].
  /// Invariants: row/column coordinate semantics remain unchanged.
  LedKeyLayer? keyLayerAt({required int col, required int row}) {
    for (final layer in keyLayers) {
      if (layer.col == col && layer.row == row) {
        return layer;
      }
    }
    return null;
  }

  /// Find the first visible left-half LED layer for one key coordinate.
  ///
  /// Purpose: lets the grid renderer draw independent left and right key colors.
  /// Parameters: [col] and [row] are logical Dog Paw coordinates in range 0..7.
  /// Return value: matching left-half layer, or null when none is visible.
  /// Requirements: callers should pass valid key coordinates.
  /// Guarantees: does not mutate [keyLayers].
  /// Invariants: only layers with [LedKeyLayer.left] set are considered.
  LedKeyLayer? leftKeyLayerAt({required int col, required int row}) {
    for (final layer in keyLayers) {
      if (layer.col == col && layer.row == row && layer.left) {
        return layer;
      }
    }
    return null;
  }

  /// Find the first visible right-half LED layer for one key coordinate.
  ///
  /// Purpose: lets the grid renderer draw independent left and right key colors.
  /// Parameters: [col] and [row] are logical Dog Paw coordinates in range 0..7.
  /// Return value: matching right-half layer, or null when none is visible.
  /// Requirements: callers should pass valid key coordinates.
  /// Guarantees: does not mutate [keyLayers].
  /// Invariants: only layers with [LedKeyLayer.right] set are considered.
  LedKeyLayer? rightKeyLayerAt({required int col, required int row}) {
    for (final layer in keyLayers) {
      if (layer.col == col && layer.row == row && layer.right) {
        return layer;
      }
    }
    return null;
  }
}

/// One BAK button state from the emulator bridge.
///
/// Purpose: represents current simulated pressed/released state for one button.
/// Parameters: [index] is the zero-based button index; [pressed] is true while
/// the simulator considers it held down.
/// Return value: immutable button state model.
/// Requirements: [index] should be in the bridge-supported BAK range.
/// Guarantees: construction performs no I/O.
/// Invariants: button state is a snapshot, not an event stream.
class BakButtonState {
  const BakButtonState({required this.index, required this.pressed});

  final int index;
  final bool pressed;

  /// Decode one button state object from BAK snapshot JSON.
  ///
  /// Purpose: maps raw bridge JSON into a typed GUI model.
  /// Parameters: [jsonValue] must contain `index` and `pressed` fields.
  /// Return value: decoded button state.
  /// Requirements: callers should pass one object from `buttons`.
  /// Guarantees: missing fields default to index 0 and released.
  /// Invariants: unknown fields are ignored.
  factory BakButtonState.fromJson(Map<String, Object?> jsonValue) {
    return BakButtonState(
      index: jsonValue['index'] as int? ?? 0,
      pressed: jsonValue['pressed'] == true,
    );
  }
}

/// One BAK knob state from the emulator bridge.
///
/// Purpose: carries both raw encoder position and normalized value for one
/// simulated knob.
/// Parameters: [index] is the knob index; [raw] is the synthetic encoder
/// position; [normalized] is the provider-owned value in range 0..1.
/// Return value: immutable knob state model.
/// Requirements: bridge data should use Dog Paw BAK knob indices.
/// Guarantees: construction performs no clamping.
/// Invariants: raw and normalized values come from the same BAK snapshot.
class BakKnobState {
  const BakKnobState({
    required this.index,
    required this.raw,
    required this.normalized,
  });

  final int index;
  final int raw;
  final double normalized;

  /// Decode one knob state object from BAK snapshot JSON.
  ///
  /// Purpose: maps raw bridge JSON into typed knob render/control state.
  /// Parameters: [jsonValue] must contain `index`, `raw`, and `normalized`.
  /// Return value: decoded knob state.
  /// Requirements: `normalized` should be numeric.
  /// Guarantees: missing fields default to zero.
  /// Invariants: unknown fields are ignored.
  factory BakKnobState.fromJson(Map<String, Object?> jsonValue) {
    final normalized = jsonValue['normalized'];
    return BakKnobState(
      index: jsonValue['index'] as int? ?? 0,
      raw: jsonValue['raw'] as int? ?? 0,
      normalized: normalized is num ? normalized.toDouble() : 0.0,
    );
  }
}

/// ButtonsAndKnobs snapshot returned by the emulator bridge.
///
/// Purpose: stores current simulated BAK button and knob state for GUI controls.
/// Parameters: [ok] is the bridge/simulator success flag; [buttons] and [knobs]
/// are state entries indexed by BAK control number.
/// Return value: immutable BAK snapshot model.
/// Requirements: values should come from `/api/bak/snapshot`.
/// Guarantees: construction performs no network access.
/// Invariants: state entries preserve bridge response ordering.
class BakSnapshot {
  const BakSnapshot({
    required this.ok,
    required this.buttons,
    required this.knobs,
  });

  final bool ok;
  final List<BakButtonState> buttons;
  final List<BakKnobState> knobs;

  /// Decode a BAK snapshot JSON object.
  ///
  /// Purpose: maps raw BAK bridge data into typed GUI state.
  /// Parameters: [jsonValue] must be the decoded `/api/bak/snapshot` object.
  /// Return value: decoded BAK snapshot.
  /// Requirements: `buttons` and `knobs`, when present, should be JSON lists.
  /// Guarantees: malformed entries are skipped.
  /// Invariants: parsing does not alter bridge data.
  factory BakSnapshot.fromJson(Map<String, Object?> jsonValue) {
    final buttons = <BakButtonState>[];
    final buttonsJson = jsonValue['buttons'];
    if (buttonsJson is List<Object?>) {
      for (final buttonJson in buttonsJson) {
        if (buttonJson is Map<String, Object?>) {
          buttons.add(BakButtonState.fromJson(buttonJson));
        }
      }
    }

    final knobs = <BakKnobState>[];
    final knobsJson = jsonValue['knobs'];
    if (knobsJson is List<Object?>) {
      for (final knobJson in knobsJson) {
        if (knobJson is Map<String, Object?>) {
          knobs.add(BakKnobState.fromJson(knobJson));
        }
      }
    }

    return BakSnapshot(
      ok: jsonValue['ok'] == true,
      buttons: buttons,
      knobs: knobs,
    );
  }

  /// Return state for one knob index.
  ///
  /// Purpose: lets widgets render a stable control row for each BAK knob.
  /// Parameters: [index] is the zero-based knob index.
  /// Return value: matching knob state, or a centered default when absent.
  /// Requirements: [index] should be a BAK knob index.
  /// Guarantees: never returns null.
  /// Invariants: [knobs] is not mutated.
  BakKnobState knobAt(int index) {
    for (final knob in knobs) {
      if (knob.index == index) {
        return knob;
      }
    }
    return BakKnobState(index: index, raw: 0, normalized: 0.5);
  }

  /// Return state for one button index.
  ///
  /// Purpose: lets widgets show current button pressed state.
  /// Parameters: [index] is the zero-based button index.
  /// Return value: matching button state, or released default when absent.
  /// Requirements: [index] should be a BAK button index.
  /// Guarantees: never returns null.
  /// Invariants: [buttons] is not mutated.
  BakButtonState buttonAt(int index) {
    for (final button in buttons) {
      if (button.index == index) {
        return button;
      }
    }
    return BakButtonState(index: index, pressed: false);
  }
}
