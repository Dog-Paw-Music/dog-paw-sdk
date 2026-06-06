import 'dart:async';

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:test/test.dart';

const String _specField = 'spec';
const String _resolvedField = 'resolved';
const String _midiNoteField = 'midiNote';

/// Purpose:
/// Extract the resolved MIDI note from one intent JSON object regardless of
/// whether the note is encoded directly or nested under `spec`/`resolved`.
///
/// Parameters:
/// - `intentJson`: one intent payload returned through DogPaw layout APIs.
///
/// Return value:
/// - The decoded MIDI note when present, otherwise `null`.
///
/// Requirements:
/// - `intentJson` should be shaped like one serialized key intent.
///
/// Guarantees:
/// - The input map is not modified.
///
/// Invariants:
/// - Extraction is read-only and does not depend on server state.
int? _extractMidiNote(dynamic intentJson) {
  if (intentJson is KeyIntent) {
    return intentJson.resolvedMidiNote;
  }
  final dynamic directMidiNote = intentJson[_midiNoteField];
  if (directMidiNote is int) {
    return directMidiNote;
  }

  final dynamic spec = intentJson[_specField];
  if (spec is Map<String, dynamic>) {
    final dynamic specMidiNote = spec[_midiNoteField];
    if (specMidiNote is int) {
      return specMidiNote;
    }
  }

  final dynamic resolved = intentJson[_resolvedField];
  if (resolved is Map<String, dynamic>) {
    final dynamic resolvedMidiNote = resolved[_midiNoteField];
    if (resolvedMidiNote is int) {
      return resolvedMidiNote;
    }
  }

  return null;
}

/// Purpose:
/// Clear every existing layout-stack entry so one integration test does not
/// inherit persistent stack state from another.
///
/// Parameters:
/// - `entity`: connected DogPawEntity used to read and mutate the stack.
///
/// Return value:
/// - Completes when the stack is empty.
///
/// Requirements:
/// - `entity` must already be connected.
///
/// Guarantees:
/// - All existing stack entries are removed before the future completes.
///
/// Invariants:
/// - Referenced layout items are not deleted.
Future<void> _clearLayoutStack(DogPawEntity entity) async {
  final Result<LayoutStackSnapshot> readResult = await entity.readLayoutStack(
    includeResolved: false,
    includeSpec: false,
  );
  expect(readResult.success, isTrue, reason: readResult.error);

  for (final LayoutStackEntry entry in readResult.value!.entries) {
    final Result<bool> removeResult =
        await entity.removeLayoutStackEntry(entry.entryId);
    expect(removeResult.success, isTrue, reason: removeResult.error);
  }
}

Layout _makeSingleNoteLayout(
  String name,
  String displayName,
  String keyId,
  int midiNote, {
  String scope = 'shared',
  String? targetKey,
}) {
  final Map<String, dynamic> intent = <String, dynamic>{
    JsonFields.INTENT: JsonFields.MIDI_NOTE,
    JsonFields.MIDI_NOTE: midiNote,
  };

  return Layout.fromJson(<String, dynamic>{
    JsonFields.NAME: name,
    JsonFields.NAMESPACE_SELECTOR:
        const NamespaceSelector.currentEntity().toJson(),
    JsonFields.SPEC: <String, dynamic>{
      JsonFields.DISPLAY_NAME: displayName,
      JsonFields.SCOPE: scope,
      if (targetKey != null) JsonFields.TARGET_KEY: targetKey,
      JsonFields.KEY_INTENTS: <String, dynamic>{
        keyId: <Map<String, dynamic>>[intent],
      },
    },
  });
}

void main() {
  IntegrationTestFixture.register();

  group('Layout Stack Integration', () {
    test('EmptyStackReadReturnsDefaultResolvedLayout', () async {
      final entity = DogPawEntity(uniqueName('LayoutStackEmptyDefaultTester'));
      final connectResult = await entity.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);
      await _clearLayoutStack(entity);

      final readStackResult = await entity.readLayoutStack();
      expect(readStackResult.success, isTrue, reason: readStackResult.error);

      final snapshot = readStackResult.value!;
      expect(snapshot.entries, isEmpty);
      expect(snapshot.resolvedLayout, isNotNull);
      expect(snapshot.resolvedLayout!.resolved, isNotNull);
      expect(snapshot.resolvedLayout!.resolved!.displayName, equals('Empty Layout'));

      entity.disconnect();
    });

    test('StackReadReturnsOrderedEntriesAndResolvedLayout', () async {
      final entity = DogPawEntity(uniqueName('LayoutStackTester'));
      final connectResult = await entity.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);
      await _clearLayoutStack(entity);

      final lowerLayoutName = uniqueName('stack_lower');
      final upperLayoutName = uniqueName('stack_upper');
      final lowerLayout =
          _makeSingleNoteLayout(lowerLayoutName, 'Stack Lower', '0,0', 60);
      final upperLayout =
          _makeSingleNoteLayout(upperLayoutName, 'Stack Upper', '0,0', 72);

      final createLowerResult =
          await entity.createLayout(lowerLayout, addToLayoutStack: false);
      expect(createLowerResult.success, isTrue,
          reason: createLowerResult.error);

      final createUpperResult =
          await entity.createLayout(upperLayout, addToLayoutStack: false);
      expect(createUpperResult.success, isTrue,
          reason: createUpperResult.error);

      final lowerEntryId = await entity.addLayoutStackEntry(
        DataItemRef(
          name: lowerLayoutName,
          namespaceSelector: const NamespaceSelector.currentEntity(),
        ),
      );
      expect(lowerEntryId.success, isTrue, reason: lowerEntryId.error);

      final upperEntryId = await entity.addLayoutStackEntry(
        DataItemRef(
          name: upperLayoutName,
          namespaceSelector: const NamespaceSelector.currentEntity(),
        ),
      );
      expect(upperEntryId.success, isTrue, reason: upperEntryId.error);

      final readStackResult = await entity.readLayoutStack();
      expect(readStackResult.success, isTrue, reason: readStackResult.error);

      final snapshot = readStackResult.value!;
      expect(snapshot.entries.length, equals(2));
      expect(snapshot.entries[0].layoutRef.name, equals(lowerLayoutName));
      expect(snapshot.entries[1].layoutRef.name, equals(upperLayoutName));

      final resolvedLayout = snapshot.resolvedLayout;
      expect(resolvedLayout, isNotNull);
      expect(resolvedLayout!.resolved, isNotNull);
      final resolvedIntents =
          resolvedLayout.resolved!.keyIntents['0,0'] as List<dynamic>;
      expect(resolvedIntents.length, equals(2));
      expect(
        _extractMidiNote(resolvedIntents[0]),
        equals(60),
      );
      expect(
        _extractMidiNote(resolvedIntents[1]),
        equals(72),
      );

      entity.disconnect();
    });

    test('LayoutReadRoundTripsScopedLayoutMetadata', () async {
      final entity = DogPawEntity(uniqueName('LayoutScopeTester'));
      final connectResult = await entity.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);

      final targetedLayoutName = uniqueName('scoped_layout');
      final targetedLayout = _makeSingleNoteLayout(
        targetedLayoutName,
        'Targeted Layout',
        '0,0',
        67,
        scope: 'targeted',
        targetKey: 'controller:left',
      );

      final createResult =
          await entity.createLayout(targetedLayout, addToLayoutStack: false);
      expect(createResult.success, isTrue, reason: createResult.error);

      final readResult = await entity.readLayout(
        targetedLayoutName,
        namespaceSelector: const NamespaceSelector.currentEntity(),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readResult.success, isTrue, reason: readResult.error);
      expect(readResult.value, isNotNull);

      final Map<String, dynamic> serialized = readResult.value!.toJson();
      final Map<String, dynamic> spec =
          serialized[JsonFields.SPEC] as Map<String, dynamic>;
      expect(spec[JsonFields.SCOPE], equals('targeted'));
      expect(spec[JsonFields.TARGET_KEY], equals('controller:left'));

      entity.disconnect();
    });

    test('StackSubscriptionParsesSnapshotNotifications', () async {
      final entity = DogPawEntity(uniqueName('LayoutStackSubscriptionTester'));
      final connectResult = await entity.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);
      await _clearLayoutStack(entity);
      final notificationCompleter = Completer<void>();
      final subscriptionLayoutName = uniqueName('subscription_layout');

      final subscriptionLayout = _makeSingleNoteLayout(
        subscriptionLayoutName,
        'Subscription Layout',
        '1,1',
        74,
      );

      final createResult = await entity.createLayout(
        subscriptionLayout,
        addToLayoutStack: false,
      );
      expect(createResult.success, isTrue, reason: createResult.error);

      final subscribeResult = await entity.subscribeToLayoutStack(
        (notificationType, ref, snapshot) {
          if (notificationType == 'layout_stack_entry_added' &&
              !notificationCompleter.isCompleted) {
            expect(ref.name, equals('layout_stack'));
            expect(snapshot.entries, isNotEmpty);
            expect(
              snapshot.entries.last.layoutRef.name,
              equals(subscriptionLayoutName),
            );
            notificationCompleter.complete();
          }
        },
        includeResolved: true,
        includeSpec: false,
        sendImmediately: false,
      );
      expect(subscribeResult.success, isTrue, reason: subscribeResult.error);

      final addResult = await entity.addLayoutStackEntry(
        DataItemRef(
          name: subscriptionLayoutName,
          namespaceSelector: const NamespaceSelector.currentEntity(),
        ),
      );
      expect(addResult.success, isTrue, reason: addResult.error);

      await notificationCompleter.future.timeout(const Duration(seconds: 5));

      entity.disconnect();
    });

    test('StackSubscriptionPublishesRecomposedSnapshotWhenReferencedLayoutChanges',
        () async {
      final entity = DogPawEntity(uniqueName('LayoutStackUpdateTester'));
      final connectResult = await entity.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);
      await _clearLayoutStack(entity);

      final layoutName = uniqueName('stack_update_layout');
      final initialLayout =
          _makeSingleNoteLayout(layoutName, 'Initial Layout', '2,2', 64);
      final createResult =
          await entity.createLayout(initialLayout, addToLayoutStack: false);
      expect(createResult.success, isTrue, reason: createResult.error);

      final addResult = await entity.addLayoutStackEntry(
        DataItemRef(
          name: layoutName,
          namespaceSelector: const NamespaceSelector.currentEntity(),
        ),
      );
      expect(addResult.success, isTrue, reason: addResult.error);

      final notificationCompleter = Completer<LayoutStackSnapshot>();
      final subscribeResult = await entity.subscribeToLayoutStack(
        (notificationType, ref, snapshot) {
          if (notificationType == 'layout_stack_changed' &&
              !notificationCompleter.isCompleted) {
            expect(ref.name, equals('layout_stack'));
            notificationCompleter.complete(snapshot);
          }
        },
        includeResolved: true,
        includeSpec: false,
        sendImmediately: false,
      );
      expect(subscribeResult.success, isTrue, reason: subscribeResult.error);

      final updatedLayout =
          _makeSingleNoteLayout(layoutName, 'Updated Layout', '2,2', 81);
      final updateResult = await entity.updateLayout(updatedLayout);
      expect(updateResult.success, isTrue, reason: updateResult.error);

      final LayoutStackSnapshot snapshot =
          await notificationCompleter.future.timeout(const Duration(seconds: 5));
      expect(snapshot.entries.length, equals(1));
      expect(snapshot.resolvedLayout, isNotNull);
      expect(snapshot.resolvedLayout!.resolved, isNotNull);

      final List<dynamic> resolvedIntents =
          snapshot.resolvedLayout!.resolved!.keyIntents['2,2'] as List<dynamic>;
      expect(resolvedIntents.length, equals(1));
      expect(
        _extractMidiNote(resolvedIntents.first),
        equals(81),
      );

      entity.disconnect();
    });

    test('ScopedLayoutViewSeedsAndUpdatesFromInternalCache', () async {
      final entity = DogPawEntity(uniqueName('ScopedLayoutViewTester'));
      final connectResult = await entity.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);
      await _clearLayoutStack(entity);

      final sharedLayoutName = uniqueName('layout_shared');
      final targetedLayoutName = uniqueName('layout_targeted');
      final Layout sharedLayout = _makeSingleNoteLayout(
        sharedLayoutName,
        'Initial Shared Layout',
        '0,0',
        60,
      );
      final Layout targetedLayout = _makeSingleNoteLayout(
        targetedLayoutName,
        'Initial Targeted Layout',
        '0,0',
        81,
        scope: 'targeted',
        targetKey: 'controller:left',
      );
      final createSharedResult =
          await entity.createLayout(sharedLayout, addToLayoutStack: false);
      expect(createSharedResult.success, isTrue,
          reason: createSharedResult.error);
      final createTargetedResult =
          await entity.createLayout(targetedLayout, addToLayoutStack: false);
      expect(createTargetedResult.success, isTrue,
          reason: createTargetedResult.error);

      final addSharedResult = await entity.addLayoutStackEntry(
        DataItemRef(
          name: sharedLayoutName,
          namespaceSelector: const NamespaceSelector.currentEntity(),
        ),
      );
      expect(addSharedResult.success, isTrue, reason: addSharedResult.error);
      final addTargetedResult = await entity.addLayoutStackEntry(
        DataItemRef(
          name: targetedLayoutName,
          namespaceSelector: const NamespaceSelector.currentEntity(),
        ),
      );
      expect(addTargetedResult.success, isTrue,
          reason: addTargetedResult.error);

      final initialViewResult = await entity.getScopedLayoutView(
        const LayoutViewPolicy(
          targetKey: 'controller:left',
          strategy: LayoutViewStrategy.targetedIfAnyOtherwiseShared,
        ),
      );
      expect(initialViewResult.success, isTrue, reason: initialViewResult.error);
      expect(
        initialViewResult.value!.effectiveMidiNoteForKey('0,0'),
        equals(81),
      );

      final Layout updatedLayout = _makeSingleNoteLayout(
        targetedLayoutName,
        'Updated Targeted Layout',
        '0,0',
        89,
        scope: 'targeted',
        targetKey: 'controller:left',
      );
      final updateResult = await entity.updateLayout(updatedLayout);
      expect(updateResult.success, isTrue, reason: updateResult.error);

      final bool sawUpdatedNote = await waitFor(() async {
        final viewResult = await entity.getScopedLayoutView(
          const LayoutViewPolicy(
            targetKey: 'controller:left',
            strategy: LayoutViewStrategy.targetedIfAnyOtherwiseShared,
          ),
        );
        if (!viewResult.success || viewResult.value == null) {
          return false;
        }
        return viewResult.value!.effectiveMidiNoteForKey('0,0') == 89;
      });
      expect(sawUpdatedNote, isTrue);

      entity.disconnect();
    });

    test('ScopedLayoutViewSubscriptionPublishesUpdatedViews', () async {
      final entity =
          DogPawEntity(uniqueName('ScopedLayoutViewSubscriptionTester'));
      final connectResult = await entity.connect();
      expect(connectResult.success, isTrue, reason: connectResult.error);
      await _clearLayoutStack(entity);

      final layoutName = uniqueName('scoped_layout_subscription_layout');
      final Layout initialLayout = _makeSingleNoteLayout(
        layoutName,
        'Initial Scoped Layout Subscription Layout',
        '1,1',
        65,
        scope: 'targeted',
        targetKey: 'controller:left',
      );
      final createResult =
          await entity.createLayout(initialLayout, addToLayoutStack: false);
      expect(createResult.success, isTrue, reason: createResult.error);

      final addResult = await entity.addLayoutStackEntry(
        DataItemRef(
          name: layoutName,
          namespaceSelector: const NamespaceSelector.currentEntity(),
        ),
      );
      expect(addResult.success, isTrue, reason: addResult.error);

      final Completer<ScopedLayoutView> notificationCompleter =
          Completer<ScopedLayoutView>();
      final subscribeResult = await entity.subscribeToScopedLayoutView(
        (ScopedLayoutView view) {
          if (!notificationCompleter.isCompleted) {
            notificationCompleter.complete(view);
          }
        },
        policy: const LayoutViewPolicy(
          targetKey: 'controller:left',
          strategy: LayoutViewStrategy.targetedIfAnyOtherwiseShared,
        ),
        sendImmediately: false,
      );
      expect(subscribeResult.success, isTrue, reason: subscribeResult.error);

      final Layout updatedLayout = _makeSingleNoteLayout(
        layoutName,
        'Updated Scoped Layout Subscription Layout',
        '1,1',
        89,
        scope: 'targeted',
        targetKey: 'controller:left',
      );
      final updateResult = await entity.updateLayout(updatedLayout);
      expect(updateResult.success, isTrue, reason: updateResult.error);

      final ScopedLayoutView updatedView =
          await notificationCompleter.future.timeout(const Duration(seconds: 5));
      expect(updatedView.effectiveMidiNoteForKey('1,1'), equals(89));

      entity.disconnect();
    });
  });
}
