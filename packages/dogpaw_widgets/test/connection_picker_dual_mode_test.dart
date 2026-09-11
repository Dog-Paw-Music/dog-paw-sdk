import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake `DogPawEntity` that actually evaluates search criteria (direction /
/// base type / and / or), so endpoint-mode direction-filter tests exercise
/// the picker's real criteria construction instead of a permissive stub.
class _FakeDogPawEntity extends dp.DogPawEntity {
  final List<dp.EndpointInfo> availableEndpoints;
  final List<dp.ConnectionRule> connectionRules;
  final List<dp.ConnectionRule> createdRules = <dp.ConnectionRule>[];
  final List<String> deletedRequestNames = <String>[];

  _FakeDogPawEntity({
    required this.availableEndpoints,
    List<dp.ConnectionRule>? initialRules,
  })  : connectionRules = List<dp.ConnectionRule>.from(
          initialRules ?? <dp.ConnectionRule>[],
        ),
        super('fake_entity');

  @override
  Future<dp.Result<List<dp.EndpointInfo>>> searchEndpoints(
    dp.SearchCriteria criteria,
  ) async {
    final List<dp.EndpointInfo> filtered = availableEndpoints
        .where((dp.EndpointInfo endpoint) => _matches(endpoint, criteria))
        .toList();
    return dp.Result<List<dp.EndpointInfo>>.success(filtered);
  }

  @override
  Future<dp.Result<List<dp.ConnectionRule>>> listConnectionRules({
    dp.NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    return dp.Result<List<dp.ConnectionRule>>.success(
      List<dp.ConnectionRule>.from(connectionRules),
    );
  }

  @override
  Future<dp.Result<bool>> createConnectionRule(
    dp.ConnectionRule connectionRule,
  ) async {
    createdRules.add(connectionRule);
    connectionRules.add(connectionRule);
    return dp.Result<bool>.success(true);
  }

  @override
  Future<dp.Result<bool>> deleteConnectionRule(
    String name, {
    dp.NamespaceSelector? namespaceSelector,
  }) async {
    deletedRequestNames.add(name);
    connectionRules.removeWhere(
      (dp.ConnectionRule rule) => rule.name == name,
    );
    return dp.Result<bool>.success(true);
  }

  bool _matches(dp.EndpointInfo endpoint, dp.SearchCriteria criteria) {
    if (criteria.andCriteria != null) {
      return criteria.andCriteria!
          .every((dp.SearchCriteria c) => _matches(endpoint, c));
    }
    if (criteria.orCriteria != null) {
      return criteria.orCriteria!
          .any((dp.SearchCriteria c) => _matches(endpoint, c));
    }
    final dp.SearchCondition? condition = criteria.condition;
    if (condition == null) {
      return true;
    }
    final dp.EndpointSpec? spec = endpoint.spec ?? endpoint.resolved;
    if (spec == null) {
      return false;
    }
    if (condition.field == 'direction' && condition.operator == 'equals') {
      return spec.direction.name == condition.value;
    }
    if (condition.field == 'baseType' && condition.operator == 'equals') {
      return spec.dataType.baseType.name == condition.value;
    }
    return true;
  }
}

dp.EndpointInfo _buildEndpoint({
  required String entityName,
  required String endpointName,
  required String displayName,
  required dp.EndpointDirection direction,
  String? ownerDisplayName,
  String? groupKey,
  dp.EndpointDisplaySpec? display,
  dp.EndpointCategory category = dp.EndpointCategory.messageQueue,
  dp.DataType baseType = dp.DataType.float,
}) {
  return dp.EndpointInfo(
    name: endpointName,
    namespaceSelector: dp.NamespaceSelector.specificEntity(entityName),
    ownerDisplayName: ownerDisplayName ?? entityName,
    spec: dp.EndpointSpec(
      displayName: displayName,
      direction: direction,
      dataType: dp.DataTypeSpec(baseType),
      category: category,
      groupKey: groupKey,
      display: display,
    ),
  );
}

dp.ConnectionRule _buildConnectionRule({
  required String name,
  required dp.EndpointInfo source,
  required dp.EndpointInfo destination,
}) {
  return dp.ConnectionRule(
    name: name,
    spec: dp.ConnectionRuleData(
      sourceRef: dp.DataItemRef.byName(
        name: source.name,
        namespaceSelector: source.namespaceSelector,
      ),
      destinationRef: dp.DataItemRef.byName(
        name: destination.name,
        namespaceSelector: destination.namespaceSelector,
      ),
    ),
  );
}

void main() {
  Future<void> pumpPicker(
    WidgetTester tester, {
    required Widget child,
    Size surfaceSize = const Size(900, 600),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: surfaceSize.width,
            height: surfaceSize.height,
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('endpoint mode direction filters', () {
    late dp.EndpointInfo sourceA;
    late dp.EndpointInfo sourceB;
    late dp.EndpointInfo destA;
    late _FakeDogPawEntity entity;

    setUp(() {
      sourceA = _buildEndpoint(
        entityName: 'Knobs',
        endpointName: 'knob_a',
        displayName: 'Knob A',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Knobs',
      );
      sourceB = _buildEndpoint(
        entityName: 'Knobs',
        endpointName: 'knob_b',
        displayName: 'Knob B',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Knobs',
      );
      destA = _buildEndpoint(
        entityName: 'DPPHost',
        endpointName: 'cutoff',
        displayName: 'Cutoff',
        direction: dp.EndpointDirection.input,
        ownerDisplayName: 'DPPHost',
      );
      entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[sourceA, sourceB, destA],
      );
    });

    testWidgets('sources filter shows only outputs', (tester) async {
      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.sources,
        ),
      );

      expect(find.byKey(const Key('connection-folder-Knobs')), findsOneWidget);
      expect(find.byKey(const Key('connection-folder-DPPHost')), findsNothing);
    });

    testWidgets('destinations filter shows only inputs', (tester) async {
      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.destinations,
        ),
      );

      expect(find.byKey(const Key('connection-folder-DPPHost')), findsOneWidget);
      expect(find.byKey(const Key('connection-folder-Knobs')), findsNothing);
    });

    testWidgets('both filter shows every direction', (tester) async {
      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.both,
        ),
      );

      expect(find.byKey(const Key('connection-folder-Knobs')), findsOneWidget);
      expect(find.byKey(const Key('connection-folder-DPPHost')), findsOneWidget);
    });
  });

  group('endpoint mode selection', () {
    testWidgets('single-select returns one leaf immediately',
        (tester) async {
      final dp.EndpointInfo knobA = _buildEndpoint(
        entityName: 'Knobs',
        endpointName: 'knob_a',
        displayName: 'Knob A',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Knobs',
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[knobA],
      );
      List<EndpointLeafSelection>? reported;

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.sources,
          onEndpointsSelected: (leaves) {
            reported = leaves;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported, hasLength(1));
      expect(reported!.single.title, equals('Knob A'));
      expect(reported!.single.members.single.name, equals('knob_a'));
    });

    testWidgets('groupKey leaf returns multiple members in one selection',
        (tester) async {
      final dp.EndpointInfo left = _buildEndpoint(
        entityName: 'System',
        endpointName: 'speaker_left',
        displayName: 'Left Speaker',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final dp.EndpointInfo right = _buildEndpoint(
        entityName: 'System',
        endpointName: 'speaker_right',
        displayName: 'Right Speaker',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[left, right],
      );
      List<EndpointLeafSelection>? reported;

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.sources,
          onEndpointsSelected: (leaves) {
            reported = leaves;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-System')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-folder-Audio & MIDI')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-leaf-Main Speakers')));
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported, hasLength(1));
      expect(reported!.single.members, hasLength(2));
      expect(reported!.single.groupKey, equals('system_audio_out'));
    });

    testWidgets('multi-select confirm returns N selected leaves',
        (tester) async {
      final dp.EndpointInfo knobA = _buildEndpoint(
        entityName: 'Knobs',
        endpointName: 'knob_a',
        displayName: 'Knob A',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Knobs',
      );
      final dp.EndpointInfo knobB = _buildEndpoint(
        entityName: 'Knobs',
        endpointName: 'knob_b',
        displayName: 'Knob B',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Knobs',
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[knobA, knobB],
      );
      List<EndpointLeafSelection>? reported;
      bool dismissed = false;

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.sources,
          multiSelect: true,
          onEndpointsSelected: (leaves) {
            reported = leaves;
          },
          onDismiss: () {
            dismissed = true;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();

      // Confirm is disabled until at least one leaf is selected.
      final FilledButton confirmDisabled = tester.widget<FilledButton>(
        find.byKey(const Key('connection-picker-multiselect-confirm')),
      );
      expect(confirmDisabled.onPressed, isNull);

      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-leaf-Knob B')));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      expect(reported, isNull); // not yet confirmed

      await tester.tap(
        find.byKey(const Key('connection-picker-multiselect-confirm')),
      );
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported, hasLength(2));
      expect(dismissed, isFalse);
    });

    testWidgets('multi-select cancel dismisses without reporting a selection',
        (tester) async {
      final dp.EndpointInfo knobA = _buildEndpoint(
        entityName: 'Knobs',
        endpointName: 'knob_a',
        displayName: 'Knob A',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Knobs',
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[knobA],
      );
      List<EndpointLeafSelection>? reported;
      bool dismissed = false;

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.sources,
          multiSelect: true,
          onEndpointsSelected: (leaves) {
            reported = leaves;
          },
          onDismiss: () {
            dismissed = true;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('connection-picker-multiselect-cancel')),
      );
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
      expect(reported, isNull);
    });
  });

  group('connection mode without focusedEndpoint', () {
    test('fails fast via assertion', () {
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: const <dp.EndpointInfo>[],
      );
      expect(
        () => ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.connection,
        ),
        throwsAssertionError,
      );
    });
  });

  group('connection mode mutation results and chrome', () {
    late dp.EndpointInfo focusedInput;
    late dp.EndpointInfo knobA;

    setUp(() {
      focusedInput = _buildEndpoint(
        entityName: 'DPPHost',
        endpointName: 'cutoff',
        displayName: 'Cutoff',
        direction: dp.EndpointDirection.input,
      );
      knobA = _buildEndpoint(
        entityName: 'Knobs',
        endpointName: 'knob_a',
        displayName: 'Knob A',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Knobs',
      );
    });

    testWidgets('mutations report created then deleted with pair refs',
        (tester) async {
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[knobA],
      );
      final List<List<ConnectionRuleMutation>> mutationBatches =
          <List<ConnectionRuleMutation>>[];
      int refreshCount = 0;

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          focusedEndpoint: focusedInput,
          onRefresh: () async {
            refreshCount += 1;
          },
          onMutated: (mutations) {
            mutationBatches.add(mutations);
          },
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();

      expect(refreshCount, equals(1));
      expect(mutationBatches, hasLength(1));
      expect(mutationBatches.single, hasLength(1));
      final ConnectionRuleMutation created = mutationBatches.single.single;
      expect(created.kind, equals(ConnectionRuleMutationKind.created));
      expect(created.sourceRef.name, equals('knob_a'));
      expect(created.destinationRef.name, equals('cutoff'));
      expect(created.ruleName, isNotEmpty);

      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();

      expect(refreshCount, equals(2));
      expect(mutationBatches, hasLength(2));
      final ConnectionRuleMutation deleted = mutationBatches.last.single;
      expect(deleted.kind, equals(ConnectionRuleMutationKind.deleted));
      expect(deleted.ruleName, equals(created.ruleName));
      expect(deleted.sourceRef.name, equals('knob_a'));
      expect(deleted.destinationRef.name, equals('cutoff'));
    });

    testWidgets(
        'mutations report skippedExisting for the already-connected member '
        'of a partially-connected paired leaf', (tester) async {
      final dp.EndpointInfo speakerLeft = _buildEndpoint(
        entityName: 'System',
        endpointName: 'speaker_left',
        displayName: 'Left Speaker',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final dp.EndpointInfo speakerRight = _buildEndpoint(
        entityName: 'System',
        endpointName: 'speaker_right',
        displayName: 'Right Speaker',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      // Pre-seed only the Left member's rule under an opaque name, so the
      // pair is partially (not fully) connected and tapping triggers the
      // connect branch, which must report Left as skippedExisting rather
      // than creating a duplicate.
      final dp.ConnectionRule preexistingLeftRule = _buildConnectionRule(
        name: 'pre-existing-opaque-name-0001',
        source: speakerLeft,
        destination: focusedInput,
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[speakerLeft, speakerRight],
        initialRules: <dp.ConnectionRule>[preexistingLeftRule],
      );
      final List<List<ConnectionRuleMutation>> mutationBatches =
          <List<ConnectionRuleMutation>>[];

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          focusedEndpoint: focusedInput,
          onMutated: (mutations) {
            mutationBatches.add(mutations);
          },
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-System')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('connection-folder-Audio & MIDI')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-leaf-Main Speakers')));
      await tester.pumpAndSettle();

      expect(mutationBatches, hasLength(1));
      final List<ConnectionRuleMutation> batch = mutationBatches.single;
      expect(batch, hasLength(2));

      final ConnectionRuleMutation skipped = batch.singleWhere(
        (ConnectionRuleMutation m) => m.sourceRef.name == 'speaker_left',
      );
      expect(skipped.kind, equals(ConnectionRuleMutationKind.skippedExisting));
      expect(skipped.ruleName, equals('pre-existing-opaque-name-0001'));
      expect(skipped.destinationRef.name, equals('cutoff'));

      final ConnectionRuleMutation created = batch.singleWhere(
        (ConnectionRuleMutation m) => m.sourceRef.name == 'speaker_right',
      );
      expect(created.kind, equals(ConnectionRuleMutationKind.created));
      expect(created.destinationRef.name, equals('cutoff'));

      // Still exactly one rule for the Left pair (no duplicate created).
      expect(
        entity.connectionRules.where(
          (dp.ConnectionRule rule) {
            final dp.ConnectionRuleData? data = rule.spec ?? rule.resolved;
            return data != null && data.sourceRef.name == 'speaker_left';
          },
        ),
        hasLength(1),
      );
    });

    testWidgets('default chrome: matching rule -> lit; unmatched -> unlit',
        (tester) async {
      final dp.ConnectionRule preexisting = _buildConnectionRule(
        name: 'opaque-rule-name',
        source: knobA,
        destination: focusedInput,
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[knobA],
        initialRules: <dp.ConnectionRule>[preexisting],
      );

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          focusedEndpoint: focusedInput,
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();

      // Connected vs idle is chrome fill only — no CONNECT/CONNECTED labels.
      expect(find.textContaining('CONNECTED'), findsNothing);
      expect(find.text('CONNECT'), findsNothing);
      expect(find.text('Knob A'), findsOneWidget);
    });

    testWidgets('host leafChrome muted renders de-emphasized and blocks '
        'delete', (tester) async {
      final dp.ConnectionRule preexisting = _buildConnectionRule(
        name: 'opaque-rule-name',
        source: knobA,
        destination: focusedInput,
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[knobA],
        initialRules: <dp.ConnectionRule>[preexisting],
      );
      final List<List<ConnectionRuleMutation>> mutationBatches =
          <List<ConnectionRuleMutation>>[];

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          focusedEndpoint: focusedInput,
          leafChrome: (leaf) => ConnectionPickerLeafChrome.muted,
          onMutated: (mutations) {
            mutationBatches.add(mutations);
          },
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();

      expect(find.text('LINKED'), findsNothing);
      expect(find.textContaining('CONNECTED'), findsNothing);
      expect(find.text('Knob A'), findsOneWidget);

      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();

      // Muted blocks delete via the picker: rule remains, no mutation fired.
      expect(entity.connectionRules, hasLength(1));
      expect(entity.deletedRequestNames, isEmpty);
      expect(mutationBatches, isEmpty);
    });

    testWidgets('host leafChrome lit still connects/disconnects as today',
        (tester) async {
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[knobA],
      );

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          focusedEndpoint: focusedInput,
          leafChrome: (leaf) => ConnectionPickerLeafChrome.lit,
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();

      // unlit-equivalent underlying state (not yet connected) but host forces
      // lit chrome; tap should still connect (today's create behavior).
      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();

      expect(entity.createdRules, hasLength(1));

      // Now the pair is connected; host still forces lit; tap disconnects.
      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();

      expect(entity.connectionRules, isEmpty);
      expect(entity.deletedRequestNames, hasLength(1));
    });
  });

  group('leaf card chrome', () {
    testWidgets('endpoint mode shows name without SELECT and direction/type '
        'header', (tester) async {
      final dp.EndpointInfo knobA = _buildEndpoint(
        entityName: 'Knobs',
        endpointName: 'knob_a',
        displayName: 'Knob A',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Knobs',
        category: dp.EndpointCategory.continuous,
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[knobA],
      );

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.sources,
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();

      expect(find.text('Knob A'), findsOneWidget);
      expect(find.text('SELECT'), findsNothing);
      expect(find.text('SELECTED'), findsNothing);
      expect(find.text('output'), findsOneWidget);
      expect(find.byIcon(Icons.category), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
    });

    testWidgets('input leaf uses input label; midi uses piano',
        (tester) async {
      final dp.EndpointInfo midiIn = _buildEndpoint(
        entityName: 'System',
        endpointName: 'uart_midi_in',
        displayName: 'MIDI DIN',
        direction: dp.EndpointDirection.input,
        ownerDisplayName: 'System',
        category: dp.EndpointCategory.jackMidiStream,
        baseType: dp.DataType.midiMessage,
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[midiIn],
      );

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.destinations,
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-System')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('connection-folder-Audio & MIDI')),
      );
      await tester.pumpAndSettle();

      expect(find.text('MIDI DIN'), findsOneWidget);
      expect(find.text('input'), findsOneWidget);
      expect(find.byIcon(Icons.piano), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });

    testWidgets('audio leaf uses speaker type icon', (tester) async {
      final dp.EndpointInfo left = _buildEndpoint(
        entityName: 'System',
        endpointName: 'speaker_left',
        displayName: 'Left Speaker',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'System',
        category: dp.EndpointCategory.audioStream,
        baseType: dp.DataType.audioStream,
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final dp.EndpointInfo right = _buildEndpoint(
        entityName: 'System',
        endpointName: 'speaker_right',
        displayName: 'Right Speaker',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'System',
        category: dp.EndpointCategory.audioStream,
        baseType: dp.DataType.audioStream,
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[left, right],
      );

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.sources,
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-System')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('connection-folder-Audio & MIDI')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main Speakers'), findsOneWidget);
      expect(find.text('output'), findsOneWidget);
      expect(find.byIcon(Icons.speaker), findsOneWidget);
    });

    testWidgets('ledMessage leaf uses lightbulb type icon', (tester) async {
      final dp.EndpointInfo ledOut = _buildEndpoint(
        entityName: 'Animations',
        endpointName: 'led_out',
        displayName: 'LED Output',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Animations',
        category: dp.EndpointCategory.messageQueue,
        baseType: dp.DataType.ledMessage,
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[ledOut],
      );

      await pumpPicker(
        tester,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.sources,
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Animations')));
      await tester.pumpAndSettle();

      expect(find.text('LED Output'), findsOneWidget);
      expect(find.byIcon(Icons.lightbulb), findsOneWidget);
    });

    testWidgets('rail sizes cards for ~2.5 visible span', (tester) async {
      const Size surfaceSize = Size(900, 600);
      final dp.EndpointInfo knobA = _buildEndpoint(
        entityName: 'Knobs',
        endpointName: 'knob_a',
        displayName: 'Knob A',
        direction: dp.EndpointDirection.output,
        ownerDisplayName: 'Knobs',
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[knobA],
      );

      await pumpPicker(
        tester,
        surfaceSize: surfaceSize,
        child: ConnectionPicker(
          entity: entity,
          mode: ConnectionPickerMode.endpoint,
          directionFilter: EndpointDirectionFilter.sources,
        ),
      );

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();

      // available = 900 - 32 padding; cardWidth = (available - 2*12) / 2.5
      const double expectedWidth = (900 - 32 - 24) / 2.5;
      final Size leafSize =
          tester.getSize(find.byKey(const Key('connection-leaf-Knob A')));
      expect(leafSize.width, closeTo(expectedWidth, 0.5));
    });
  });

  group('dialog result sealing', () {
    testWidgets('dismiss without action returns ConnectionPickerDismissed',
        (tester) async {
      final dp.EndpointInfo focusedInput = _buildEndpoint(
        entityName: 'DPPHost',
        endpointName: 'cutoff',
        displayName: 'Cutoff',
        direction: dp.EndpointDirection.input,
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[
          _buildEndpoint(
            entityName: 'Knobs',
            endpointName: 'knob_a',
            displayName: 'Knob A',
            direction: dp.EndpointDirection.output,
            ownerDisplayName: 'Knobs',
          ),
        ],
      );
      ConnectionPickerResult? result;

      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    result = await showConnectionPickerDialog(
                      context: context,
                      entity: entity,
                      focusedEndpoint: focusedInput,
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('connection-picker-dismiss')));
      await tester.pumpAndSettle();

      expect(result, isA<ConnectionPickerDismissed>());
    });

    testWidgets(
        'mutation then dismiss returns ConnectionPickerMutated with handles '
        'and invokes onRefresh',
        (tester) async {
      final dp.EndpointInfo focusedInput = _buildEndpoint(
        entityName: 'DPPHost',
        endpointName: 'cutoff',
        displayName: 'Cutoff',
        direction: dp.EndpointDirection.input,
      );
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[
          _buildEndpoint(
            entityName: 'Knobs',
            endpointName: 'knob_a',
            displayName: 'Knob A',
            direction: dp.EndpointDirection.output,
            ownerDisplayName: 'Knobs',
          ),
        ],
      );
      ConnectionPickerResult? result;
      int refreshCount = 0;

      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    result = await showConnectionPickerDialog(
                      context: context,
                      entity: entity,
                      focusedEndpoint: focusedInput,
                      onRefresh: () async {
                        refreshCount += 1;
                      },
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();

      expect(refreshCount, equals(1));

      await tester.tap(find.byKey(const Key('connection-picker-dismiss')));
      await tester.pumpAndSettle();

      expect(result, isA<ConnectionPickerMutated>());
      final ConnectionPickerMutated mutated = result as ConnectionPickerMutated;
      expect(mutated.mutations, hasLength(1));
      expect(mutated.mutations.single.kind, equals(ConnectionRuleMutationKind.created));
      expect(mutated.mutations.single.sourceRef.name, equals('knob_a'));
      expect(mutated.mutations.single.destinationRef.name, equals('cutoff'));
    });

    testWidgets('endpoint-mode dialog smoke open/close returns selection',
        (tester) async {
      final _FakeDogPawEntity entity = _FakeDogPawEntity(
        availableEndpoints: <dp.EndpointInfo>[
          _buildEndpoint(
            entityName: 'Knobs',
            endpointName: 'knob_a',
            displayName: 'Knob A',
            direction: dp.EndpointDirection.output,
            ownerDisplayName: 'Knobs',
          ),
        ],
      );
      ConnectionPickerResult? result;

      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    result = await showConnectionPickerDialog(
                      context: context,
                      entity: entity,
                      mode: ConnectionPickerMode.endpoint,
                      directionFilter: EndpointDirectionFilter.sources,
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('connection-picker-dialog-panel')), findsOneWidget);

      await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
      await tester.pumpAndSettle();

      expect(result, isA<ConnectionPickerEndpointsSelected>());
      final ConnectionPickerEndpointsSelected selected =
          result as ConnectionPickerEndpointsSelected;
      expect(selected.leaves.single.members.single.name, equals('knob_a'));
    });
  });
}
