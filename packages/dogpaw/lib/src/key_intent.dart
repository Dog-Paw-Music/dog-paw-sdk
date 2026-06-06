import 'json_constants.dart';
import 'json_utils.dart';

/// Intent families supported by layout key intents.
enum KeyIntentType {
  midiNote,
  midiCc,
  printConsole,
  custom,
}

/// MIDI note intent payload.
class MidiNoteData {
  final int? midiNote;
  final String? noteName;
  final int? semitonesFromRoot;
  final int? scaleDegreesFromRoot;
  final int? octave;
  final int? midiChannel;

  /// Purpose:
  /// Store one typed MIDI-note intent payload for layout serialization and
  /// query helpers.
  ///
  /// Parameters:
  /// - `midiNote`: direct resolved or specified MIDI note number.
  /// - `noteName`: optional note name such as `C4`.
  /// - `semitonesFromRoot`: optional chromatic offset from the active scale root.
  /// - `scaleDegreesFromRoot`: optional scale-degree offset from the active root.
  /// - `octave`: optional octave for scale-relative notes.
  /// - `midiChannel`: optional MIDI channel.
  ///
  /// Return value:
  /// - A new immutable `MidiNoteData`.
  ///
  /// Requirements:
  /// - At least one note-specifying field should normally be present.
  ///
  /// Guarantees:
  /// - The payload is stored exactly as provided.
  ///
  /// Invariants:
  /// - Constructing this object does not resolve scale references or contact Epiphany.
  const MidiNoteData({
    this.midiNote,
    this.noteName,
    this.semitonesFromRoot,
    this.scaleDegreesFromRoot,
    this.octave,
    this.midiChannel,
  });

  /// Serialize this payload to Dog Paw intent JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.INTENT: JsonFields.MIDI_NOTE,
        JsonFields.MIDI_NOTE_FIELD: midiNote,
        JsonFields.NOTE_NAME: noteName,
        JsonFields.SEMITONES_FROM_ROOT: semitonesFromRoot,
        JsonFields.SCALE_DEGREES_FROM_ROOT: scaleDegreesFromRoot,
        JsonFields.OCTAVE: octave,
        JsonFields.MIDI_CHANNEL: midiChannel,
      }.toJsonClean();

  /// Parse one MIDI note payload from wire-format JSON.
  factory MidiNoteData.fromJson(Map<String, dynamic> json) {
    return MidiNoteData(
      midiNote: json[JsonFields.MIDI_NOTE_FIELD] as int?,
      noteName: json[JsonFields.NOTE_NAME] as String?,
      semitonesFromRoot: json[JsonFields.SEMITONES_FROM_ROOT] as int?,
      scaleDegreesFromRoot:
          json[JsonFields.SCALE_DEGREES_FROM_ROOT] as int?,
      octave: json[JsonFields.OCTAVE] as int?,
      midiChannel: json[JsonFields.MIDI_CHANNEL] as int?,
    );
  }
}

/// MIDI CC operating modes.
enum MidiCCMode {
  continuous,
  toggle,
}

/// MIDI CC modulation sources.
enum MidiCCSource {
  horizontalPosition,
  verticalPosition,
}

/// MIDI CC intent payload.
class MidiCCData {
  final int? ccNumber;
  final String? ccName;
  final MidiCCMode mode;
  final MidiCCSource source;
  final int midiChannel;

  /// Purpose:
  /// Store one typed MIDI-CC intent payload for layout serialization.
  ///
  /// Parameters:
  /// - `ccNumber`: numeric CC identifier when using numeric addressing.
  /// - `ccName`: named CC identifier when using symbolic addressing.
  /// - `mode`: continuous or toggle delivery mode.
  /// - `source`: input source that drives the CC.
  /// - `midiChannel`: MIDI channel.
  ///
  /// Return value:
  /// - A new immutable `MidiCCData`.
  ///
  /// Requirements:
  /// - At least one of `ccNumber` or `ccName` should be present.
  ///
  /// Guarantees:
  /// - The payload is stored exactly as provided.
  ///
  /// Invariants:
  /// - Constructing this object does not contact Epiphany.
  const MidiCCData({
    this.ccNumber,
    this.ccName,
    this.mode = MidiCCMode.continuous,
    this.source = MidiCCSource.verticalPosition,
    this.midiChannel = 0,
  });

  /// Serialize this payload to Dog Paw intent JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.INTENT: JsonFields.MIDI_CC,
        JsonFields.CC_NUMBER: ccNumber,
        JsonFields.CC_NAME: ccName,
        JsonFields.MODE: mode == MidiCCMode.toggle
            ? JsonFields.TOGGLE
            : JsonFields.CONTINUOUS,
        JsonFields.SOURCE: source == MidiCCSource.horizontalPosition
            ? JsonFields.HORIZONTAL_POSITION
            : JsonFields.VERTICAL_POSITION,
        JsonFields.MIDI_CHANNEL: midiChannel,
      }.toJsonClean();

  /// Parse one MIDI CC payload from wire-format JSON.
  factory MidiCCData.fromJson(Map<String, dynamic> json) {
    final String modeValue = json[JsonFields.MODE] as String? ?? '';
    final String sourceValue = json[JsonFields.SOURCE] as String? ?? '';
    return MidiCCData(
      ccNumber: json[JsonFields.CC_NUMBER] as int?,
      ccName: json[JsonFields.CC_NAME] as String?,
      mode: modeValue == JsonFields.TOGGLE
          ? MidiCCMode.toggle
          : MidiCCMode.continuous,
      source: sourceValue == JsonFields.HORIZONTAL_POSITION
          ? MidiCCSource.horizontalPosition
          : MidiCCSource.verticalPosition,
      midiChannel: json[JsonFields.MIDI_CHANNEL] as int? ?? 0,
    );
  }
}

/// Key-state values for console-print transition intents.
enum ConsolePrintKeyState {
  rest,
  active,
  pressed,
}

/// Transition guard for console-print intents.
class ConsolePrintStateTransition {
  final ConsolePrintKeyState? startState;
  final ConsolePrintKeyState triggerState;

  /// Purpose:
  /// Describe the key-state transition that should trigger a console-print intent.
  ///
  /// Parameters:
  /// - `startState`: optional starting state requirement.
  /// - `triggerState`: required trigger state.
  ///
  /// Return value:
  /// - A new immutable transition descriptor.
  ///
  /// Requirements:
  /// - `triggerState` must be a valid key-state enum value.
  ///
  /// Guarantees:
  /// - The transition is stored exactly as provided.
  ///
  /// Invariants:
  /// - Constructing this object does not contact Epiphany.
  const ConsolePrintStateTransition({
    this.startState,
    this.triggerState = ConsolePrintKeyState.active,
  });

  /// Serialize this transition to Dog Paw intent JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.START_STATE: startState == null
            ? null
            : _consolePrintKeyStateToJson(startState!),
        JsonFields.TRIGGER_STATE:
            _consolePrintKeyStateToJson(triggerState),
      }.toJsonClean();

  /// Parse one console-print transition from wire-format JSON.
  factory ConsolePrintStateTransition.fromJson(Map<String, dynamic> json) {
    return ConsolePrintStateTransition(
      startState: _consolePrintKeyStateFromJson(
          json[JsonFields.START_STATE] as String?),
      triggerState: _consolePrintKeyStateFromJson(
              json[JsonFields.TRIGGER_STATE] as String?) ??
          ConsolePrintKeyState.active,
    );
  }
}

/// Console-print intent payload.
class ConsolePrintData {
  final String message;
  final ConsolePrintStateTransition? stateTransition;

  /// Purpose:
  /// Store one console-print intent payload for typed layout serialization.
  ///
  /// Parameters:
  /// - `message`: text to print.
  /// - `stateTransition`: optional trigger transition.
  ///
  /// Return value:
  /// - A new immutable `ConsolePrintData`.
  ///
  /// Requirements:
  /// - `message` should be non-empty for useful output.
  ///
  /// Guarantees:
  /// - The payload is stored exactly as provided.
  ///
  /// Invariants:
  /// - Constructing this object does not contact Epiphany.
  const ConsolePrintData({
    required this.message,
    this.stateTransition,
  });

  /// Serialize this payload to Dog Paw intent JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.INTENT: JsonFields.PRINT_CONSOLE,
        JsonFields.MESSAGE: message,
        JsonFields.STATE_TRANSITION: stateTransition?.toJson(),
      }.toJsonClean();

  /// Parse one console-print payload from wire-format JSON.
  factory ConsolePrintData.fromJson(Map<String, dynamic> json) {
    final dynamic rawTransition = json[JsonFields.STATE_TRANSITION];
    return ConsolePrintData(
      message: json[JsonFields.MESSAGE] as String? ?? '',
      stateTransition:
          rawTransition is Map<String, dynamic>
              ? ConsolePrintStateTransition.fromJson(rawTransition)
              : null,
    );
  }
}

/// Custom intent payload.
class CustomData {
  final Map<String, dynamic> payload;

  /// Purpose:
  /// Store an arbitrary custom key-intent payload while still participating in
  /// typed intent parsing.
  ///
  /// Parameters:
  /// - `payload`: arbitrary custom payload fields.
  ///
  /// Return value:
  /// - A new immutable `CustomData`.
  ///
  /// Requirements:
  /// - `payload` should already satisfy the caller's custom schema.
  ///
  /// Guarantees:
  /// - The payload map is stored by value.
  ///
  /// Invariants:
  /// - Constructing this object does not validate custom schema content.
  const CustomData({
    this.payload = const <String, dynamic>{},
  });

  /// Serialize this payload to Dog Paw intent JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.INTENT: JsonFields.CUSTOM,
        JsonFields.CUSTOM_PAYLOAD: payload,
      }.toJsonClean();

  /// Parse one custom payload from wire-format JSON.
  factory CustomData.fromJson(Map<String, dynamic> json) {
    final dynamic payload = json[JsonFields.CUSTOM_PAYLOAD];
    if (payload is Map<String, dynamic>) {
      return CustomData(payload: payload);
    }
    return CustomData(payload: Map<String, dynamic>.from(json));
  }
}

/// Typed layout key intent.
class KeyIntent {
  final KeyIntentType type;
  final MidiNoteData? midiNoteData;
  final MidiCCData? midiCcData;
  final ConsolePrintData? consolePrintData;
  final CustomData? customData;
  final String? targetEntity;

  /// Purpose:
  /// Store one typed key intent with optional runtime target metadata.
  ///
  /// Parameters:
  /// - `type`: intent family discriminator.
  /// - `midiNoteData`: MIDI-note payload when `type` is `midiNote`.
  /// - `midiCcData`: MIDI-CC payload when `type` is `midiCc`.
  /// - `consolePrintData`: console payload when `type` is `printConsole`.
  /// - `customData`: custom payload when `type` is `custom`.
  /// - `targetEntity`: optional runtime entity target.
  ///
  /// Return value:
  /// - A new immutable `KeyIntent`.
  ///
  /// Requirements:
  /// - Exactly one payload should match `type`.
  ///
  /// Guarantees:
  /// - The intent family and target metadata are stored exactly as provided.
  ///
  /// Invariants:
  /// - Constructing this object does not contact Epiphany.
  const KeyIntent._({
    required this.type,
    this.midiNoteData,
    this.midiCcData,
    this.consolePrintData,
    this.customData,
    this.targetEntity,
  });

  /// Create one typed MIDI-note intent.
  const KeyIntent.midiNote(
    MidiNoteData data, {
    String? targetEntity,
  })  : type = KeyIntentType.midiNote,
        midiNoteData = data,
        midiCcData = null,
        consolePrintData = null,
        customData = null,
        targetEntity = targetEntity;

  /// Create one typed MIDI-CC intent.
  const KeyIntent.midiCc(
    MidiCCData data, {
    String? targetEntity,
  })  : type = KeyIntentType.midiCc,
        midiNoteData = null,
        midiCcData = data,
        consolePrintData = null,
        customData = null,
        targetEntity = targetEntity;

  /// Create one typed console-print intent.
  const KeyIntent.printConsole(
    ConsolePrintData data, {
    String? targetEntity,
  })  : type = KeyIntentType.printConsole,
        midiNoteData = null,
        midiCcData = null,
        consolePrintData = data,
        customData = null,
        targetEntity = targetEntity;

  /// Create one typed custom intent.
  const KeyIntent.custom(
    CustomData data, {
    String? targetEntity,
  })  : type = KeyIntentType.custom,
        midiNoteData = null,
        midiCcData = null,
        consolePrintData = null,
        customData = data,
        targetEntity = targetEntity;

  /// Parse one typed key intent from Dog Paw JSON.
  factory KeyIntent.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> objectToParse =
        _unwrapIntentEnvelope(json);
    final String intentType =
        objectToParse[JsonFields.INTENT] as String? ?? '';
    final String? targetEntity =
        objectToParse[JsonFields.TARGET_ENTITY] as String?;

    if (intentType == JsonFields.MIDI_NOTE) {
      return KeyIntent.midiNote(
        MidiNoteData.fromJson(objectToParse),
        targetEntity: targetEntity,
      );
    }
    if (intentType == JsonFields.MIDI_CC) {
      return KeyIntent.midiCc(
        MidiCCData.fromJson(objectToParse),
        targetEntity: targetEntity,
      );
    }
    if (intentType == JsonFields.PRINT_CONSOLE) {
      return KeyIntent.printConsole(
        ConsolePrintData.fromJson(objectToParse),
        targetEntity: targetEntity,
      );
    }
    return KeyIntent.custom(
      CustomData.fromJson(objectToParse),
      targetEntity: targetEntity,
    );
  }

  /// Serialize this key intent to Dog Paw JSON.
  Map<String, dynamic> toJson() {
    Map<String, dynamic> result;
    switch (type) {
      case KeyIntentType.midiNote:
        result = midiNoteData?.toJson() ?? const <String, dynamic>{};
        break;
      case KeyIntentType.midiCc:
        result = midiCcData?.toJson() ?? const <String, dynamic>{};
        break;
      case KeyIntentType.printConsole:
        result = consolePrintData?.toJson() ?? const <String, dynamic>{};
        break;
      case KeyIntentType.custom:
        result = customData?.toJson() ?? const <String, dynamic>{};
        break;
    }
    if (targetEntity != null && targetEntity!.isNotEmpty) {
      result = <String, dynamic>{
        ...result,
        JsonFields.TARGET_ENTITY: targetEntity,
      };
    }
    return result;
  }

  /// Return the resolved MIDI note when this intent is a MIDI-note intent.
  int? get resolvedMidiNote => midiNoteData?.midiNote;
}

/// Parse a raw key-intents map into typed `KeyIntent` lists.
Map<String, List<KeyIntent>> coerceKeyIntentsByKey(dynamic rawKeyIntents) {
  if (rawKeyIntents is! Map) {
    return <String, List<KeyIntent>>{};
  }

  final Map<String, List<KeyIntent>> result = <String, List<KeyIntent>>{};
  for (final MapEntry<dynamic, dynamic> entry in rawKeyIntents.entries) {
    final String keyId = entry.key.toString();
    final dynamic rawIntents = entry.value;
    if (rawIntents is! List) {
      result[keyId] = <KeyIntent>[];
      continue;
    }

    final List<KeyIntent> intents = <KeyIntent>[];
    for (final dynamic rawIntent in rawIntents) {
      if (rawIntent is KeyIntent) {
        intents.add(rawIntent);
      } else if (rawIntent is Map<String, dynamic>) {
        intents.add(KeyIntent.fromJson(rawIntent));
      } else if (rawIntent is Map) {
        intents.add(KeyIntent.fromJson(Map<String, dynamic>.from(rawIntent)));
      }
    }
    result[keyId] = intents;
  }
  return result;
}

/// Serialize a possibly typed key-intents map back to JSON.
Map<String, dynamic> keyIntentsToJson(dynamic rawKeyIntents) {
  if (rawKeyIntents is! Map) {
    return <String, dynamic>{};
  }

  final Map<String, dynamic> result = <String, dynamic>{};
  for (final MapEntry<dynamic, dynamic> entry in rawKeyIntents.entries) {
    final String keyId = entry.key.toString();
    final dynamic rawIntents = entry.value;
    if (rawIntents is! List) {
      result[keyId] = <dynamic>[];
      continue;
    }

    result[keyId] = rawIntents.map((dynamic rawIntent) {
      if (rawIntent is KeyIntent) {
        return rawIntent.toJson();
      }
      return rawIntent;
    }).toList();
  }
  return result;
}

String _consolePrintKeyStateToJson(ConsolePrintKeyState state) {
  switch (state) {
    case ConsolePrintKeyState.rest:
      return JsonFields.KEY_STATE_REST;
    case ConsolePrintKeyState.active:
      return JsonFields.KEY_STATE_ACTIVE;
    case ConsolePrintKeyState.pressed:
      return JsonFields.KEY_STATE_PRESSED;
  }
}

ConsolePrintKeyState? _consolePrintKeyStateFromJson(String? value) {
  if (value == JsonFields.KEY_STATE_REST) {
    return ConsolePrintKeyState.rest;
  }
  if (value == JsonFields.KEY_STATE_PRESSED) {
    return ConsolePrintKeyState.pressed;
  }
  if (value == JsonFields.KEY_STATE_ACTIVE) {
    return ConsolePrintKeyState.active;
  }
  return null;
}

Map<String, dynamic> _unwrapIntentEnvelope(Map<String, dynamic> json) {
  final dynamic resolved = json[JsonFields.RESOLVED];
  if (resolved is Map<String, dynamic>) {
    return resolved;
  }
  if (resolved is Map) {
    return Map<String, dynamic>.from(resolved);
  }

  final dynamic spec = json[JsonFields.SPEC];
  if (spec is Map<String, dynamic>) {
    return spec;
  }
  if (spec is Map) {
    return Map<String, dynamic>.from(spec);
  }
  return json;
}
