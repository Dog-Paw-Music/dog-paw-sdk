import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDogPawEntity extends dp.DogPawEntity {
  final List<dp.EndpointInfo> availableEndpoints;
  final List<dp.ConnectionRule> connectionRules;
  final List<dp.ConnectionRule> createdRules = <dp.ConnectionRule>[];
  final List<String> deletedRequestNames = <String>[];
  String? searchError;
  String? listRulesError;

  _FakeDogPawEntity({
    required this.availableEndpoints,
    List<dp.ConnectionRule>? initialRules,
    this.searchError,
    this.listRulesError,
  })  : connectionRules = List<dp.ConnectionRule>.from(
          initialRules ?? <dp.ConnectionRule>[],
        ),
        super('fake_entity');

  @override
  Future<dp.Result<List<dp.EndpointInfo>>> searchEndpoints(
    dp.SearchCriteria criteria,
  ) async {
    if (searchError != null) {
      return dp.Result<List<dp.EndpointInfo>>.error(searchError!);
    }
    return dp.Result<List<dp.EndpointInfo>>.success(availableEndpoints);
  }

  @override
  Future<dp.Result<List<dp.ConnectionRule>>> listConnectionRules({
    dp.NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    if (listRulesError != null) {
      return dp.Result<List<dp.ConnectionRule>>.error(listRulesError!);
    }
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
}

/// Build one endpoint fixture for connection-picker widget tests.
///
/// Parameters:
/// - [entityName]: Owning entity id.
/// - [endpointName]: Endpoint id.
/// - [displayName]: Musician-facing endpoint label.
/// - [direction]: Endpoint direction.
/// - [ownerDisplayName]: Optional human-facing owner folder title.
/// - [groupKey]: Optional pairing key.
/// - [flags]: Semantic flags (not used for hierarchy).
/// - [display]: Optional folder hierarchy override.
/// - [jackClientName]: Raw JACK client (must never render).
/// - [fullJackPortName]: Raw JACK port (must never render).
///
/// Return value:
/// - An [dp.EndpointInfo] suitable for fake-entity picker tests.
///
/// Requirements/Preconditions:
/// - [entityName] and [endpointName] must be non-empty.
///
/// Guarantees/Postconditions:
/// - Spec uses float base type for compatibility filtering.
///
/// Invariants:
/// - Does not contact Epiphany.
dp.EndpointInfo _buildEndpoint({
  required String entityName,
  required String endpointName,
  required String displayName,
  required dp.EndpointDirection direction,
  String? ownerDisplayName,
  String? groupKey,
  List<String> flags = const <String>[],
  dp.EndpointDisplaySpec? display,
  String? jackClientName,
  String? fullJackPortName,
  dp.EndpointCategory category = dp.EndpointCategory.messageQueue,
  dp.DataType baseType = dp.DataType.float,
  dp.IndexSpec indexSpec = const dp.IndexSpecNone(),
  dp.ProjectionHints? projectionHints,
}) {
  return dp.EndpointInfo(
    name: endpointName,
    namespaceSelector: dp.NamespaceSelector.specificEntity(entityName),
    ownerDisplayName: ownerDisplayName ?? entityName,
    spec: dp.EndpointSpec(
      displayName: displayName,
      direction: direction,
      dataType: dp.DataTypeSpec(baseType, indexSpec: indexSpec),
      category: category,
      flags: flags,
      groupKey: groupKey,
      display: display,
      jackClientName: jackClientName,
      fullJackPortName: fullJackPortName,
      projectionHints: projectionHints,
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
  Future<void> pumpConnectionPicker(
    WidgetTester tester, {
    required _FakeDogPawEntity entity,
    required dp.EndpointInfo focusedEndpoint,
    Future<void> Function()? onRefresh,
    VoidCallback? onDismiss,
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
            child: ConnectionPicker(
              entity: entity,
              focusedEndpoint: focusedEndpoint,
              onRefresh: onRefresh,
              onDismiss: onDismiss,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('loads candidates into top-level folders',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
      ownerDisplayName: 'LV2Host',
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
          entityName: 'System',
          endpointName: 'speaker_left',
          displayName: 'Left Speaker',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'System',
          groupKey: 'system_audio_out',
          flags: const <String>['system_audio_out_left'],
          display: const dp.EndpointDisplaySpec(
            topLevelCategory: dp.kDisplayCategorySystem,
            categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
          ),
          jackClientName: 'raw_jack_client',
          fullJackPortName: 'system:playback_1',
        ),
        _buildEndpoint(
          entityName: 'System',
          endpointName: 'speaker_right',
          displayName: 'Right Speaker',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'System',
          groupKey: 'system_audio_out',
          flags: const <String>['system_audio_out_right'],
          display: const dp.EndpointDisplaySpec(
            topLevelCategory: dp.kDisplayCategorySystem,
            categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
          ),
          jackClientName: 'raw_jack_client',
          fullJackPortName: 'system:playback_2',
        ),
        _buildEndpoint(
          entityName: 'Knobs',
          endpointName: 'knob_a',
          displayName: 'Knob A',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'Knobs',
        ),
        _buildEndpoint(
          entityName: 'RandomLFO_1',
          endpointName: 'lfo_out',
          displayName: 'LFO Out',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'RandomLFO',
        ),
      ],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    expect(find.byKey(const Key('connection-folder-System')), findsOneWidget);
    expect(find.byKey(const Key('connection-folder-Knobs')), findsOneWidget);
    expect(
        find.byKey(const Key('connection-folder-RandomLFO')), findsOneWidget);
    expect(find.text('System I/O'), findsNothing);
    expect(find.text('raw_jack_client'), findsNothing);
    expect(find.text('system:playback_1'), findsNothing);
    expect(find.text('system:playback_2'), findsNothing);
  });

  testWidgets('tap folder pushes breadcrumb and Back pops',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
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
        ),
        _buildEndpoint(
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
        ),
      ],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    expect(
        find.byKey(const Key('connection-picker-breadcrumb')), findsOneWidget);
    expect(
      find.byKey(const Key('connection-picker-breadcrumb-Home')),
      findsOneWidget,
    );
    expect(
      find.textContaining('(source) -> Cutoff'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('connection-folder-System')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('connection-picker-breadcrumb-System')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('connection-folder-Audio & MIDI')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const Key('connection-picker-breadcrumb-Home')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-folder-System')), findsOneWidget);
  });

  testWidgets('focus context uses source/destination placeholders',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
      ownerDisplayName: 'DPPHost',
    );
    final dp.EndpointInfo focusedOutput = _buildEndpoint(
      entityName: 'System',
      endpointName: 'knob_a',
      displayName: 'Knob A',
      direction: dp.EndpointDirection.output,
      ownerDisplayName: 'System',
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
          entityName: 'Knobs',
          endpointName: 'knob_b',
          displayName: 'Knob B',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'Knobs',
        ),
        _buildEndpoint(
          entityName: 'DPPHost',
          endpointName: 'resonance',
          displayName: 'Resonance',
          direction: dp.EndpointDirection.input,
          ownerDisplayName: 'DPPHost',
        ),
      ],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );
    expect(
      find.text('(source) -> Cutoff - DPPHost'),
      findsOneWidget,
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedOutput,
    );
    expect(
      find.text('Knob A - System -> (destination)'),
      findsOneWidget,
    );
  });

  testWidgets('Back at root is a no-op', (WidgetTester tester) async {
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

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    await tester.tap(find.byKey(const Key('connection-picker-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-folder-Knobs')), findsOneWidget);
    expect(
      find.byKey(const Key('connection-picker-breadcrumb-Home')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('connection-picker-breadcrumb-System')),
      findsNothing,
    );
  });

  testWidgets('tap leaf creates then deletes a single connection',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    int refreshCount = 0;
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

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
      onRefresh: () async {
        refreshCount += 1;
      },
    );

    await tester.tap(find.byKey(const Key('connection-folder-Knobs')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
    await tester.pumpAndSettle();

    expect(entity.createdRules, hasLength(1));
    expect(
        entity.createdRules.first.spec!.destinationRef.name, equals('cutoff'));
    expect(refreshCount, equals(1));
    // Connected state is chrome-only (no CONNECTED status label).
    expect(find.textContaining('CONNECTED'), findsNothing);
    expect(find.text('Knob A'), findsOneWidget);

    await tester.tap(find.byKey(const Key('connection-leaf-Knob A')));
    await tester.pumpAndSettle();

    expect(entity.connectionRules, isEmpty);
    expect(entity.deletedRequestNames, hasLength(1));
    expect(refreshCount, equals(2));
  });

  testWidgets(
      'tap paired leaf with one member already connected skips that member '
      'and creates no duplicate rule (opaque-name selector match)',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
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

    // Pre-seed a rule for the Left member under an opaque name, simulating a
    // rule created in an earlier session. Opaque names mean the picker must
    // rely on selector match (not name equality) to avoid a duplicate.
    final dp.ConnectionRule preexistingLeftRule = _buildConnectionRule(
      name: 'pre-existing-opaque-name-0001',
      source: speakerLeft,
      destination: focusedInput,
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[speakerLeft, speakerRight],
      initialRules: <dp.ConnectionRule>[preexistingLeftRule],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    await tester.tap(find.byKey(const Key('connection-folder-System')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connection-folder-Audio & MIDI')));
    await tester.pumpAndSettle();

    // Partially connected (only Left) so the pair is not fully connected;
    // tapping triggers the connect branch, which must skip Left.
    await tester.tap(find.byKey(const Key('connection-leaf-Main Speakers')));
    await tester.pumpAndSettle();

    // No duplicate rule was created for the Left pair: exactly one rule
    // remains that matches speakerLeft <-> focusedInput.
    final Iterable<dp.ConnectionRule> leftMatches =
        entity.connectionRules.where((dp.ConnectionRule rule) {
      final dp.ConnectionRuleData? data = rule.spec ?? rule.resolved;
      return data != null &&
          data.sourceRef.name == speakerLeft.name &&
          data.destinationRef.name == focusedInput.name;
    });
    expect(leftMatches, hasLength(1));
    expect(leftMatches.single.name, equals(preexistingLeftRule.name));
    // Exactly one create call happened, and it was for Right, not Left.
    expect(entity.createdRules, hasLength(1));
    expect(
      entity.createdRules.single.spec!.sourceRef.name,
      equals(speakerRight.name),
    );

    // Right member had no existing rule, so it was created fresh.
    final Iterable<dp.ConnectionRule> rightMatches =
        entity.connectionRules.where((dp.ConnectionRule rule) {
      final dp.ConnectionRuleData? data = rule.spec ?? rule.resolved;
      return data != null &&
          data.sourceRef.name == speakerRight.name &&
          data.destinationRef.name == focusedInput.name;
    });
    expect(rightMatches, hasLength(1));
    expect(entity.connectionRules, hasLength(2));
  });

  testWidgets('tap paired leaf creates and deletes both member rules',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
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
        ),
        _buildEndpoint(
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
        ),
      ],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    await tester.tap(find.byKey(const Key('connection-folder-System')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connection-folder-Audio & MIDI')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('connection-leaf-Main Speakers')));
    await tester.pumpAndSettle();

    expect(entity.createdRules, hasLength(2));

    await tester.tap(find.byKey(const Key('connection-leaf-Main Speakers')));
    await tester.pumpAndSettle();

    expect(entity.connectionRules, isEmpty);
    expect(entity.deletedRequestNames, hasLength(2));
  });

  testWidgets('focused output flow targets compatible inputs',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedOutput = _buildEndpoint(
      entityName: 'Knobs',
      endpointName: 'knob_a',
      displayName: 'Knob A',
      direction: dp.EndpointDirection.output,
      ownerDisplayName: 'Knobs',
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
          entityName: 'DPPHost',
          endpointName: 'cutoff',
          displayName: 'Cutoff',
          direction: dp.EndpointDirection.input,
          ownerDisplayName: 'LV2Host',
        ),
      ],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedOutput,
    );

    await tester.tap(find.byKey(const Key('connection-folder-LV2Host')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connection-leaf-Cutoff')));
    await tester.pumpAndSettle();

    expect(entity.createdRules, hasLength(1));
    expect(entity.createdRules.first.spec!.sourceRef.name, equals('knob_a'));
    expect(
        entity.createdRules.first.spec!.destinationRef.name, equals('cutoff'));
  });

  testWidgets('projected create writes default strategy from source hints',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'System',
      endpointName: 'cv_1_send',
      displayName: 'CV 1',
      direction: dp.EndpointDirection.input,
    );
    final dp.EndpointInfo pressureOutput = _buildEndpoint(
      entityName: 'BladeHW',
      endpointName: 'key_pressure',
      displayName: 'Key Pressure',
      direction: dp.EndpointDirection.output,
      ownerDisplayName: 'Blade Hardware',
      indexSpec: const dp.IndexSpecKey(8, 8),
      projectionHints: const dp.ProjectionHints(
        strategies: <dp.ProjectionStrategyHint>[
          dp.ProjectionStrategyHint(name: dp.JsonFields.CONVERSION_MAX_VALUE),
          dp.ProjectionStrategyHint(
              name: dp.JsonFields.CONVERSION_AVERAGE_VALUE),
          dp.ProjectionStrategyHint(name: dp.JsonFields.CONVERSION_LAST_ACTIVE),
          dp.ProjectionStrategyHint(
              name: dp.JsonFields.CONVERSION_FIRST_ACTIVE),
        ],
        strategiesProvided: true,
      ),
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[pressureOutput],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    await tester.tap(find.byKey(const Key('connection-folder-Blade Hardware')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connection-leaf-Key Pressure')));
    await tester.pumpAndSettle();

    expect(entity.createdRules, hasLength(1));
    expect(
      entity.createdRules.single.spec!.indexConversion?.strategy,
      dp.JsonFields.CONVERSION_MAX_VALUE,
    );
  });

  testWidgets('projected create writes bipolar max_abs default',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'System',
      endpointName: 'cv_1_send',
      displayName: 'CV 1',
      direction: dp.EndpointDirection.input,
    );
    final dp.EndpointInfo bendOutput = _buildEndpoint(
      entityName: 'BladeHW',
      endpointName: 'key_bend',
      displayName: 'Key Bend',
      direction: dp.EndpointDirection.output,
      ownerDisplayName: 'Blade Hardware',
      indexSpec: const dp.IndexSpecKey(8, 8),
      projectionHints: const dp.ProjectionHints(
        polarity: dp.ProjectionPolarity.bipolar,
        activity: dp.ProjectionActivityRule.absAboveThreshold,
        strategies: <dp.ProjectionStrategyHint>[
          dp.ProjectionStrategyHint(name: dp.JsonFields.CONVERSION_MAX_ABS),
          dp.ProjectionStrategyHint(name: dp.JsonFields.CONVERSION_MAX_VALUE),
          dp.ProjectionStrategyHint(name: dp.JsonFields.CONVERSION_MIN_VALUE),
          dp.ProjectionStrategyHint(
              name: dp.JsonFields.CONVERSION_AVERAGE_VALUE),
          dp.ProjectionStrategyHint(name: dp.JsonFields.CONVERSION_LAST_ACTIVE),
          dp.ProjectionStrategyHint(
              name: dp.JsonFields.CONVERSION_FIRST_ACTIVE),
        ],
        strategiesProvided: true,
      ),
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[bendOutput],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    await tester.tap(find.byKey(const Key('connection-folder-Blade Hardware')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connection-leaf-Key Bend')));
    await tester.pumpAndSettle();

    expect(entity.createdRules, hasLength(1));
    expect(
      entity.createdRules.single.spec!.indexConversion?.strategy,
      dp.JsonFields.CONVERSION_MAX_ABS,
    );
  });

  testWidgets('category-mismatched continuous candidates are unavailable',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'System',
      endpointName: 'cv_1_send',
      displayName: 'CV 1',
      direction: dp.EndpointDirection.input,
    );
    final dp.EndpointInfo continuousOutput = _buildEndpoint(
      entityName: 'XY',
      endpointName: 'x_value',
      displayName: 'X Value',
      direction: dp.EndpointDirection.output,
      ownerDisplayName: 'XY Pad',
      category: dp.EndpointCategory.continuous,
      indexSpec: const dp.IndexSpecKey(8, 8),
    );
    final dp.EndpointInfo pressureOutput = _buildEndpoint(
      entityName: 'BladeHW',
      endpointName: 'key_pressure',
      displayName: 'Key Pressure',
      direction: dp.EndpointDirection.output,
      ownerDisplayName: 'Blade Hardware',
      indexSpec: const dp.IndexSpecKey(8, 8),
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[continuousOutput, pressureOutput],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    expect(find.byKey(const Key('connection-folder-XY Pad')), findsNothing);
    expect(find.byKey(const Key('connection-folder-Blade Hardware')),
        findsOneWidget);
  });

  testWidgets('search mode shows flattened matches and clear returns to tree',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
          entityName: 'picoComms',
          endpointName: 'expression',
          displayName: 'Expression Pedal',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'System',
          display: const dp.EndpointDisplaySpec(
            topLevelCategory: dp.kDisplayCategorySystem,
            categoryPath: <String>[dp.kDisplayCategoryIO],
          ),
        ),
        _buildEndpoint(
          entityName: 'Knobs',
          endpointName: 'volume',
          displayName: 'Volume',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'Knobs',
        ),
      ],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    await tester.tap(find.byKey(const Key('connection-picker-search')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('touchscreen-virtual-keyboard')), findsNothing);
    expect(find.byKey(const Key('connection-picker-search-field')),
        findsOneWidget);

    final TextField searchField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('connection-picker-search-field')),
        matching: find.byType(TextField),
      ),
    );
    searchField.controller!.text = 'pedal';
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-leaf-Expression Pedal')),
        findsOneWidget);
    expect(find.textContaining('System'), findsWidgets);
    expect(find.byKey(const Key('connection-folder-System')), findsNothing);
    expect(find.byKey(const Key('connection-folder-Knobs')), findsNothing);

    await tester.tap(find.byKey(const Key('connection-picker-search-clear')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-folder-System')), findsOneWidget);
    expect(find.byKey(const Key('connection-folder-Knobs')), findsOneWidget);
    expect(find.byKey(const Key('touchscreen-virtual-keyboard')), findsNothing);
  });

  testWidgets('search leaf cards keep full-size text across the card width',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
          entityName: 'picoComms',
          endpointName: 'expression',
          displayName: 'Expression Pedal',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'System',
          display: const dp.EndpointDisplaySpec(
            topLevelCategory: dp.kDisplayCategorySystem,
            categoryPath: <String>[
              dp.kDisplayCategoryIO,
              'Extra Nested Folder',
            ],
          ),
        ),
      ],
    );

    // Short height mimics dialog panel with keyboard reclaiming space.
    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
      surfaceSize: const Size(900, 520),
    );

    await tester.tap(find.byKey(const Key('connection-picker-search')));
    await tester.pumpAndSettle();

    final TextField searchField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('connection-picker-search-field')),
        matching: find.byType(TextField),
      ),
    );
    searchField.controller!.text = 'pedal';
    await tester.pumpAndSettle();

    final Finder leaf =
        find.byKey(const Key('connection-leaf-Expression Pedal'));
    expect(leaf, findsOneWidget);
    expect(
      find.descendant(of: leaf, matching: find.byType(FittedBox)),
      findsNothing,
    );

    final Text title = tester.widget<Text>(
      find.descendant(of: leaf, matching: find.text('Expression Pedal')),
    );
    expect(title.style?.fontSize, equals(25));

    final RenderBox leafBox = tester.renderObject(leaf);
    final RenderBox titleBox = tester.renderObject(
      find.descendant(of: leaf, matching: find.text('Expression Pedal')),
    );
    // Title layout width should use most of the card (not a half-width scale).
    expect(titleBox.size.width, greaterThan(leafBox.size.width * 0.55));
  });

  testWidgets('missing focused spec shows safe UI',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedMissingSpec = dp.EndpointInfo.full(
      name: 'broken',
      namespaceSelector: dp.NamespaceSelector.specificEntity('DPPHost'),
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: const <dp.EndpointInfo>[],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedMissingSpec,
    );

    expect(find.textContaining('missing routing metadata'), findsOneWidget);
    expect(find.byKey(const Key('connection-picker-rail')), findsNothing);
  });

  testWidgets('load error shows safe UI', (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: const <dp.EndpointInfo>[],
      searchError: 'search failed',
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    expect(find.text('search failed'), findsOneWidget);
    expect(find.byKey(const Key('connection-picker-rail')), findsNothing);
  });

  testWidgets('empty compatible set shows safe UI',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: const <dp.EndpointInfo>[],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    expect(
      find.text('No compatible endpoints are currently available.'),
      findsOneWidget,
    );
  });

  testWidgets('horizontal rail peeks a partial card when overflowing',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final List<dp.EndpointInfo> endpoints = <dp.EndpointInfo>[];
    for (int i = 0; i < 8; i++) {
      endpoints.add(
        _buildEndpoint(
          entityName: 'App$i',
          endpointName: 'out_$i',
          displayName: 'Out $i',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'Folder $i',
        ),
      );
    }
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: endpoints,
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
      surfaceSize: const Size(700, 500),
    );

    final RenderBox railBox = tester.renderObject(
      find.byKey(const Key('connection-picker-rail')),
    );
    final Offset railTopLeft = railBox.localToGlobal(Offset.zero);
    final double railRight = railTopLeft.dx + railBox.size.width;

    bool foundPeek = false;
    for (int i = 0; i < 8; i++) {
      final Finder folder = find.byKey(Key('connection-folder-Folder $i'));
      if (folder.evaluate().isEmpty) {
        continue;
      }
      final RenderBox cardBox = tester.renderObject(folder);
      final Offset cardTopLeft = cardBox.localToGlobal(Offset.zero);
      final double cardRight = cardTopLeft.dx + cardBox.size.width;
      final bool intersectsRail =
          cardTopLeft.dx < railRight && cardRight > railTopLeft.dx;
      if (intersectsRail && cardRight > railRight) {
        foundPeek = true;
        break;
      }
    }

    expect(foundPeek, isTrue);
  });

  testWidgets('connection dialog opens and closes without layout failure',
      (WidgetTester tester) async {
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

    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  showConnectionPickerDialog(
                    context: context,
                    entity: entity,
                    focusedEndpoint: focusedInput,
                  );
                },
                child: const Text('Open Connection Dialog'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Connection Dialog'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-picker-dismiss')), findsOneWidget);
    expect(find.byKey(const Key('connection-picker-dialog-panel')),
        findsOneWidget);
    expect(find.byKey(const Key('connection-folder-Knobs')), findsOneWidget);
    expect(find.text('Done'), findsNothing);

    final Size panelSize =
        tester.getSize(find.byKey(const Key('connection-picker-dialog-panel')));
    expect(panelSize.height, lessThan(600));
    expect(panelSize.height, closeTo(600 * (2 / 3), 40.0));

    await tester.tap(find.byKey(const Key('connection-picker-dismiss')));
    await tester.pumpAndSettle();

    expect(find.text('Open Connection Dialog'), findsOneWidget);
  });

  testWidgets('dialog search focuses compositor-backed search field',
      (WidgetTester tester) async {
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

    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  showConnectionPickerDialog(
                    context: context,
                    entity: entity,
                    focusedEndpoint: focusedInput,
                  );
                },
                child: const Text('Open Connection Dialog'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Connection Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('connection-picker-search')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('touchscreen-virtual-keyboard')), findsNothing);
    expect(find.byKey(const Key('connection-picker-search-field')), findsOneWidget);
    expect(find.byKey(const Key('connection-picker-dialog-panel')), findsOneWidget);
  });

  testWidgets(
      'embedded in scroll view keeps sibling diagnostics below the picker',
      (WidgetTester tester) async {
    final dp.EndpointInfo focused = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
      ownerDisplayName: 'LV2Host',
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
          entityName: 'Knobs',
          endpointName: 'knob_3',
          displayName: 'Knob 3',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'Knobs',
        ),
        _buildEndpoint(
          entityName: 'System',
          endpointName: 'playback_1',
          displayName: 'Main Speakers L',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'System',
          groupKey: 'system_audio_out',
          display: const dp.EndpointDisplaySpec(
            topLevelCategory: dp.kDisplayCategorySystem,
            categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
          ),
        ),
      ],
    );

    const String diagnosticsMarker = 'CONNECTION_DIAGNOSTICS_JSON_MARKER';
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ConnectionPicker(
                  entity: entity,
                  focusedEndpoint: focused,
                ),
                const SizedBox(height: 16),
                Text(
                  diagnosticsMarker,
                  key: const Key('connection-diagnostics-marker'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('connection-picker-rail')), findsOneWidget);
    expect(
        find.byKey(const Key('connection-diagnostics-marker')), findsOneWidget);

    final double railBottom = tester
        .getBottomLeft(find.byKey(const Key('connection-picker-rail')))
        .dy;
    final double diagnosticsTop = tester
        .getTopLeft(find.byKey(const Key('connection-diagnostics-marker')))
        .dy;
    expect(diagnosticsTop, greaterThan(railBottom));
  });

  testWidgets('picker reloads when the focused endpoint changes',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
      ownerDisplayName: 'LV2Host',
    );
    final dp.EndpointInfo focusedOutput = _buildEndpoint(
      entityName: 'Knobs',
      endpointName: 'knob_a',
      displayName: 'Knob A',
      direction: dp.EndpointDirection.output,
      ownerDisplayName: 'Knobs',
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
          entityName: 'Knobs',
          endpointName: 'knob_b',
          displayName: 'Knob B',
          direction: dp.EndpointDirection.output,
          ownerDisplayName: 'Knobs',
        ),
        _buildEndpoint(
          entityName: 'DPPHost',
          endpointName: 'resonance',
          displayName: 'Resonance',
          direction: dp.EndpointDirection.input,
          ownerDisplayName: 'LV2Host',
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionPicker(
            entity: entity,
            focusedEndpoint: focusedInput,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-folder-Knobs')), findsOneWidget);
    expect(find.byKey(const Key('connection-folder-LV2Host')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionPicker(
            entity: entity,
            focusedEndpoint: focusedOutput,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-folder-Knobs')), findsNothing);
    expect(find.byKey(const Key('connection-folder-LV2Host')), findsOneWidget);
  });
}
