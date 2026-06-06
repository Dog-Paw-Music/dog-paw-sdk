import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

Layout _makeResolvedLayout(Map<String, List<KeyIntent>> intentsByKey) {
  return Layout.full(
    name: 'resolved_layout',
    namespaceSelector: const NamespaceSelector.global(),
    resolved: LayoutData(
      displayName: 'Resolved Layout',
      keyIntents: intentsByKey,
    ),
  );
}

ScopedLayoutView _makeScopedView(Map<String, List<KeyIntent>> intentsByKey) {
  return ScopedLayoutView.fromResolvedLayout(
    _makeResolvedLayout(intentsByKey),
    const LayoutViewPolicy(
      strategy: LayoutViewStrategy.sharedOnly,
    ),
  );
}

KeyIntent _makeMidiNoteIntent(int midiNote) {
  return KeyIntent.midiNote(
    MidiNoteData(midiNote: midiNote),
  );
}

void main() {
  group('ScopedLayoutView', () {
    test('effective midi note maps use resolved layout data', () {
      final ScopedLayoutView view = _makeScopedView(<String, List<KeyIntent>>{
        '0,0': <KeyIntent>[_makeMidiNoteIntent(60)],
        '1,0': <KeyIntent>[_makeMidiNoteIntent(61), _makeMidiNoteIntent(72)],
        '2,0': <KeyIntent>[_makeMidiNoteIntent(72)],
      });

      expect(view.effectiveMidiNotesByKey(), <String, int>{
        '0,0': 60,
        '1,0': 72,
        '2,0': 72,
      });
      expect(view.keysByEffectiveMidiNote(), <int, List<String>>{
        60: <String>['0,0'],
        72: <String>['1,0', '2,0'],
      });
    });

    test('effective midi note for one key uses the highest-layer note', () {
      final ScopedLayoutView view = _makeScopedView(<String, List<KeyIntent>>{
        '0,0': <KeyIntent>[_makeMidiNoteIntent(60), _makeMidiNoteIntent(81)],
      });

      expect(view.effectiveMidiNoteForKey('0,0'), equals(81));
      expect(view.effectiveIntentsForKey('0,0'), hasLength(2));
    });
  });
}
