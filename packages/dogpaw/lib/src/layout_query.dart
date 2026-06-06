import 'key_intent.dart';
import 'layout_stack.dart';
import 'layout.dart';

/// Selects which subset of the persisted layout stack should form one view.
enum LayoutViewStrategy {
  sharedOnly,
  targetedOnly,
  targetedIfAnyOtherwiseShared,
  sharedPlusTargeted,
}

/// Policy describing which scoped layout view one consumer wants.
class LayoutViewPolicy {
  final String? targetKey;
  final LayoutViewStrategy strategy;

  /// Purpose:
  /// Describe how one consumer wants shared and targeted layouts selected from
  /// the persistent layout stack.
  ///
  /// Parameters:
  /// - `targetKey`: optional stable consumer-facing key used to match targeted
  ///   layouts.
  /// - `strategy`: layout selection behavior for shared vs targeted layouts.
  ///
  /// Return value:
  /// - A new immutable view policy.
  ///
  /// Requirements:
  /// - `targetKey`, when present, should be a non-empty stable identifier.
  ///
  /// Guarantees:
  /// - Stores the provided strategy and target key exactly.
  ///
  /// Invariants:
  /// - Constructing this value does not contact Epiphany or mutate layout data.
  const LayoutViewPolicy({
    this.targetKey,
    this.strategy = LayoutViewStrategy.targetedIfAnyOtherwiseShared,
  });
}

/// Read-only interpreted view over one already-selected resolved layout.
class ScopedLayoutView {
  final LayoutViewPolicy policy;
  final Layout resolvedLayout;
  final Map<String, List<KeyIntent>> _effectiveIntentsByKey;
  final Map<String, int> _effectiveMidiNotesByKey;
  final Map<int, List<String>> _keysByEffectiveMidiNote;

  /// Purpose:
  /// Materialize one resolved scoped layout view so consumers can ask
  /// key-to-note and note-to-keys questions without reparsing layout JSON.
  ///
  /// Parameters:
  /// - `resolvedLayout`: already-selected resolved layout for this view.
  /// - `policy`: the selection policy that produced this view.
  ///
  /// Return value:
  /// - A new immutable scoped layout view.
  ///
  /// Requirements:
  /// - `resolvedLayout.resolved` or `.spec` should contain the effective layout
  ///   payload for this view.
  ///
  /// Guarantees:
  /// - Effective maps are derived once during construction.
  ///
  /// Invariants:
  /// - Construction does not mutate the source key-intent map.
  ScopedLayoutView(
    this.resolvedLayout,
    this.policy,
  )   : _effectiveIntentsByKey = <String, List<KeyIntent>>{},
        _effectiveMidiNotesByKey = <String, int>{},
        _keysByEffectiveMidiNote = <int, List<String>>{} {
    final LayoutData? resolvedData = resolvedLayout.resolved ?? resolvedLayout.spec;
    final Map<String, List<KeyIntent>> resolvedKeyIntents = coerceKeyIntentsByKey(
      resolvedData?.keyIntents ?? const <String, dynamic>{},
    );
    for (final MapEntry<String, List<KeyIntent>> entry
        in resolvedKeyIntents.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final List<KeyIntent> effectiveIntents = List<KeyIntent>.from(entry.value);
      _effectiveIntentsByKey[entry.key] = effectiveIntents;
      final int? midiNote = _selectEffectiveMidiNote(effectiveIntents);
      if (midiNote != null) {
        _effectiveMidiNotesByKey[entry.key] = midiNote;
        _keysByEffectiveMidiNote.putIfAbsent(midiNote, () => <String>[]);
        _keysByEffectiveMidiNote[midiNote]!.add(entry.key);
      }
    }
  }

  /// Build one scoped view directly from a resolved layout payload.
  factory ScopedLayoutView.fromResolvedLayout(
    Layout layout,
    LayoutViewPolicy policy,
  ) {
    return ScopedLayoutView(layout, policy);
  }

  List<KeyIntent> effectiveIntentsForKey(String keyId) {
    return List<KeyIntent>.from(
      _effectiveIntentsByKey[keyId] ?? const <KeyIntent>[],
    );
  }

  int? effectiveMidiNoteForKey(String keyId) {
    return _effectiveMidiNotesByKey[keyId];
  }

  Map<String, int> effectiveMidiNotesByKey() {
    return Map<String, int>.from(_effectiveMidiNotesByKey);
  }

  Map<int, List<String>> keysByEffectiveMidiNote() {
    return _keysByEffectiveMidiNote.map(
      (int midiNote, List<String> keyIds) =>
          MapEntry<int, List<String>>(midiNote, List<String>.from(keyIds)),
    );
  }
}

/// Selects how targeted and untargeted intents should be interpreted.
enum LayoutTargetingMode {
  preferTargeted,
  strictTargetOnly,
  strictWhenAnyTargeted,
}

/// Targeting policy for one interpreted layout view.
class LayoutTargetingPolicy {
  final String? targetEntity;
  final LayoutTargetingMode mode;

  /// Purpose:
  /// Describe how one consumer wants to interpret targeted and untargeted key
  /// intents.
  ///
  /// Parameters:
  /// - `targetEntity`: optional entity to match against `targetEntity` intent metadata.
  /// - `mode`: selection behavior when targeted and untargeted intents coexist.
  ///
  /// Return value:
  /// - A new immutable policy object.
  ///
  /// Requirements:
  /// - `targetEntity`, when present, should be a non-empty runtime entity name.
  ///
  /// Guarantees:
  /// - The policy stores the provided filter and mode exactly.
  ///
  /// Invariants:
  /// - Constructing this value does not contact Epiphany or mutate layout data.
  const LayoutTargetingPolicy({
    this.targetEntity,
    this.mode = LayoutTargetingMode.strictWhenAnyTargeted,
  });
}

/// Read-only interpreted view over one resolved layout for one target policy.
class TargetedLayoutView {
  final LayoutTargetingPolicy policy;
  final Map<String, List<KeyIntent>> _effectiveIntentsByKey;
  final Map<String, int> _effectiveMidiNotesByKey;
  final Map<int, List<String>> _keysByEffectiveMidiNote;

  /// Purpose:
  /// Materialize the effective intent view for one target so callers can ask
  /// single-key and whole-map questions without reapplying targeting logic.
  ///
  /// Parameters:
  /// - `resolvedKeyIntents`: resolved lower-to-higher-layer intents keyed by grid key id.
  /// - `policy`: targeting rules for interpreting those intents.
  ///
  /// Return value:
  /// - A new immutable targeted layout view.
  ///
  /// Requirements:
  /// - `resolvedKeyIntents` should preserve resolved layer order.
  ///
  /// Guarantees:
  /// - All effective maps are derived once during construction.
  ///
  /// Invariants:
  /// - Constructing this value does not mutate the source key-intent map.
  TargetedLayoutView(
    Map<String, List<KeyIntent>> resolvedKeyIntents,
    this.policy,
  )   : _effectiveIntentsByKey = <String, List<KeyIntent>>{},
        _effectiveMidiNotesByKey = <String, int>{},
        _keysByEffectiveMidiNote = <int, List<String>>{} {
    for (final MapEntry<String, List<KeyIntent>> entry
        in resolvedKeyIntents.entries) {
      final List<KeyIntent> effectiveIntents =
          _selectIntentsForKey(entry.value, policy);
      if (effectiveIntents.isEmpty) {
        continue;
      }

      _effectiveIntentsByKey[entry.key] = effectiveIntents;
      final int? midiNote = _selectEffectiveMidiNote(effectiveIntents);
      if (midiNote != null) {
        _effectiveMidiNotesByKey[entry.key] = midiNote;
        _keysByEffectiveMidiNote.putIfAbsent(midiNote, () => <String>[]);
        _keysByEffectiveMidiNote[midiNote]!.add(entry.key);
      }
    }
  }

  /// Return the effective intents for one key.
  List<KeyIntent> effectiveIntentsForKey(String keyId) {
    return List<KeyIntent>.from(
      _effectiveIntentsByKey[keyId] ?? const <KeyIntent>[],
    );
  }

  /// Return the effective MIDI note for one key.
  int? effectiveMidiNoteForKey(String keyId) {
    return _effectiveMidiNotesByKey[keyId];
  }

  /// Return the effective key-to-note map.
  Map<String, int> effectiveMidiNotesByKey() {
    return Map<String, int>.from(_effectiveMidiNotesByKey);
  }

  /// Return the reverse note-to-keys map.
  Map<int, List<String>> keysByEffectiveMidiNote() {
    return _keysByEffectiveMidiNote.map(
      (int midiNote, List<String> keyIds) =>
          MapEntry<int, List<String>>(midiNote, List<String>.from(keyIds)),
    );
  }
}

/// Immutable query wrapper around one raw layout stack snapshot.
class LayoutQuerySnapshot {
  final LayoutStackSnapshot rawSnapshot;
  final Map<String, List<KeyIntent>> resolvedKeyIntents;

  /// Purpose:
  /// Keep the raw stack snapshot available while exposing typed targeted query
  /// views derived from the resolved layout.
  ///
  /// Parameters:
  /// - `rawSnapshot`: raw stack snapshot from DogPawEntity.
  ///
  /// Return value:
  /// - A new immutable query snapshot wrapper.
  ///
  /// Requirements:
  /// - `rawSnapshot` should come from a valid stack read or notification.
  ///
  /// Guarantees:
  /// - `resolvedKeyIntents` is a typed view over the snapshot's resolved layout.
  ///
  /// Invariants:
  /// - Constructing this value does not mutate the raw snapshot.
  LayoutQuerySnapshot(this.rawSnapshot)
      : resolvedKeyIntents = coerceKeyIntentsByKey(
          rawSnapshot.resolvedLayout?.resolved?.keyIntents ?? const <String, dynamic>{},
        );

  /// Build one targeted interpretation view over this snapshot.
  TargetedLayoutView forTarget(LayoutTargetingPolicy policy) {
    return TargetedLayoutView(resolvedKeyIntents, policy);
  }
}

List<KeyIntent> _selectIntentsForKey(
  List<KeyIntent> resolvedIntents,
  LayoutTargetingPolicy policy,
) {
  final List<KeyIntent> untargetedIntents = <KeyIntent>[];
  final List<KeyIntent> matchingTargetedIntents = <KeyIntent>[];
  bool hasAnyTargetedIntent = false;

  for (final KeyIntent intent in resolvedIntents) {
    final String? targetEntity = intent.targetEntity;
    if (targetEntity == null || targetEntity.isEmpty) {
      untargetedIntents.add(intent);
      continue;
    }

    hasAnyTargetedIntent = true;
    if (policy.targetEntity != null && targetEntity == policy.targetEntity) {
      matchingTargetedIntents.add(intent);
    }
  }

  if (policy.mode == LayoutTargetingMode.strictTargetOnly) {
    return matchingTargetedIntents;
  }
  if (policy.mode == LayoutTargetingMode.preferTargeted) {
    if (matchingTargetedIntents.isNotEmpty) {
      return matchingTargetedIntents;
    }
    return untargetedIntents;
  }
  if (hasAnyTargetedIntent) {
    return matchingTargetedIntents;
  }
  return untargetedIntents;
}

int? _selectEffectiveMidiNote(List<KeyIntent> effectiveIntents) {
  int? selectedMidiNote;
  for (final KeyIntent intent in effectiveIntents) {
    if (intent.resolvedMidiNote != null) {
      selectedMidiNote = intent.resolvedMidiNote;
    }
  }
  return selectedMidiNote;
}
