import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build one endpoint fixture for navigation-model unit tests.
///
/// Parameters:
/// - `entityName`: Owning entity id (`sourceEntity`).
/// - `endpointName`: Endpoint id within that entity.
/// - `displayName`: Musician-facing endpoint label.
/// - `direction`: Endpoint direction.
/// - `ownerDisplayName`: Optional human-facing owner label from Epiphany.
/// - `groupKey`: Optional pairing key.
/// - `display`: Optional folder hierarchy override.
/// - `category`: Endpoint transport category.
/// - `baseType`: Endpoint payload base type.
/// - `indexSpec`: Endpoint index shape.
/// - `hideFromPicker`: Whether picker helpers should omit the endpoint.
///
/// Return value:
/// - An `EndpointInfo` suitable for pure navigation-model tests.
///
/// Requirements/Preconditions:
/// - `entityName` and `endpointName` must be non-empty.
///
/// Guarantees/Postconditions:
/// - Spec uses float message-queue metadata (routing details unused by model).
///
/// Invariants:
/// - Does not contact Epiphany.
dp.EndpointInfo _endpoint({
  required String entityName,
  required String endpointName,
  required String displayName,
  dp.EndpointDirection direction = dp.EndpointDirection.output,
  String? ownerDisplayName,
  String? groupKey,
  dp.EndpointDisplaySpec? display,
  dp.EndpointCategory category = dp.EndpointCategory.messageQueue,
  dp.DataType baseType = dp.DataType.float,
  dp.IndexSpec indexSpec = const dp.IndexSpecNone(),
  dp.ProjectionHints? projectionHints,
  bool hideFromPicker = false,
}) {
  return dp.EndpointInfo(
    name: endpointName,
    namespaceSelector: dp.NamespaceSelector.specificEntity(entityName),
    ownerDisplayName: ownerDisplayName,
    spec: dp.EndpointSpec(
      displayName: displayName,
      direction: direction,
      dataType: dp.DataTypeSpec(baseType, indexSpec: indexSpec),
      category: category,
      groupKey: groupKey,
      display: display,
      projectionHints: projectionHints,
      hideFromPicker: hideFromPicker,
    ),
  );
}

/// Build one connection rule linking [source] to [destination].
///
/// Parameters:
/// - `source`: Source endpoint.
/// - `destination`: Destination endpoint.
///
/// Return value:
/// - A `ConnectionRule` with deterministic naming.
///
/// Requirements/Preconditions:
/// - Both endpoints have stable name + namespace identity.
///
/// Guarantees/Postconditions:
/// - Rule refs match the given endpoints exactly.
///
/// Invariants:
/// - No remote state is touched.
dp.ConnectionRule _rule({
  required dp.EndpointInfo source,
  required dp.EndpointInfo destination,
}) {
  return dp.ConnectionRule(
    name: '${source.namespaceSelector.sourceEntity}_${source.name}_to_'
        '${destination.namespaceSelector.sourceEntity}_${destination.name}',
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
  final dp.EndpointInfo focused = _endpoint(
    entityName: 'FocusApp',
    endpointName: 'focused_in',
    displayName: 'Focused Input',
    direction: dp.EndpointDirection.input,
    ownerDisplayName: 'Focus App',
  );

  group('resolveEndpointNavigationPath', () {
    test('defaults top-level to owner display name', () {
      final dp.EndpointInfo endpoint = _endpoint(
        entityName: 'RandomLFO_1',
        endpointName: 'out',
        displayName: 'Out',
        ownerDisplayName: 'RandomLFO',
      );

      expect(
        resolveEndpointNavigationPath(endpoint),
        equals(<String>['RandomLFO']),
      );
    });

    test('falls back to entity id when owner display name is missing', () {
      final dp.EndpointInfo endpoint = _endpoint(
        entityName: 'RandomLFO_1',
        endpointName: 'out',
        displayName: 'Out',
      );

      expect(
        resolveEndpointNavigationPath(endpoint),
        equals(<String>['RandomLFO_1']),
      );
    });

    test('overrides top-level to System when display.topLevelCategory set', () {
      final dp.EndpointInfo endpoint = _endpoint(
        entityName: 'System',
        endpointName: 'speakers_l',
        displayName: 'Left',
        ownerDisplayName: 'System',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );

      expect(
        resolveEndpointNavigationPath(endpoint),
        equals(<String>[
          dp.kDisplayCategorySystem,
          dp.kDisplayCategoryAudioAndMidi,
        ]),
      );
    });

    test('appends nested categoryPath multi-segment', () {
      final dp.EndpointInfo endpoint = _endpoint(
        entityName: 'MyPlugin_2',
        endpointName: 'cutoff',
        displayName: 'Cutoff',
        ownerDisplayName: 'MyPlugin',
        display: const dp.EndpointDisplaySpec(
          categoryPath: <String>['Filters', 'Filter 1'],
        ),
      );

      expect(
        resolveEndpointNavigationPath(endpoint),
        equals(<String>['MyPlugin', 'Filters', 'Filter 1']),
      );
    });

    test('skips whitespace-only categoryPath segments', () {
      final dp.EndpointInfo endpoint = _endpoint(
        entityName: 'App_1',
        endpointName: 'x',
        displayName: 'X',
        ownerDisplayName: 'App',
        display: const dp.EndpointDisplaySpec(
          categoryPath: <String>['  ', 'Nested', ''],
        ),
      );

      expect(
        resolveEndpointNavigationPath(endpoint),
        equals(<String>['App', 'Nested']),
      );
    });
  });

  group('isCompatibleConnectionPair', () {
    test('includes key and voice float message queues for none float focus',
        () {
      final dp.EndpointInfo noneFloatInput = _endpoint(
        entityName: 'System',
        endpointName: 'cv_1_send',
        displayName: 'CV 1',
        direction: dp.EndpointDirection.input,
      );
      final dp.EndpointInfo keyFloatOutput = _endpoint(
        entityName: 'BladeHW',
        endpointName: 'key_pressure',
        displayName: 'Key Pressure',
        indexSpec: const dp.IndexSpecKey(8, 8),
      );
      final dp.EndpointInfo voiceFloatOutput = _endpoint(
        entityName: 'VoiceFixture',
        endpointName: 'voice_level',
        displayName: 'Voice Level',
        indexSpec: const dp.IndexSpecVoice(16),
      );

      expect(
        isCompatibleConnectionPair(noneFloatInput, keyFloatOutput),
        isTrue,
      );
      expect(
        isCompatibleConnectionPair(noneFloatInput, voiceFloatOutput),
        isTrue,
      );
    });

    test('excludes continuous non-float and float2 message queue peers', () {
      final dp.EndpointInfo noneFloatInput = _endpoint(
        entityName: 'System',
        endpointName: 'cv_1_send',
        displayName: 'CV 1',
        direction: dp.EndpointDirection.input,
      );
      final dp.EndpointInfo continuousFloatOutput = _endpoint(
        entityName: 'XY',
        endpointName: 'x_value',
        displayName: 'X Value',
        category: dp.EndpointCategory.continuous,
      );
      final dp.EndpointInfo keyIntOutput = _endpoint(
        entityName: 'BladeHW',
        endpointName: 'key_number',
        displayName: 'Key Number',
        baseType: dp.DataType.int_,
        indexSpec: const dp.IndexSpecKey(8, 8),
      );
      final dp.EndpointInfo keyFloat2Output = _endpoint(
        entityName: 'AudioBridge',
        endpointName: 'level_meter',
        displayName: 'Level Meter',
        baseType: dp.DataType.float2,
        indexSpec: const dp.IndexSpecKey(8, 8),
      );

      expect(
        isCompatibleConnectionPair(noneFloatInput, continuousFloatOutput),
        isFalse,
      );
      expect(
        isCompatibleConnectionPair(noneFloatInput, keyIntOutput),
        isFalse,
      );
      expect(
        isCompatibleConnectionPair(noneFloatInput, keyFloat2Output),
        isFalse,
      );
    });

    test('projectable picker candidates include MQ key and voice floats only',
        () {
      final dp.EndpointInfo noneFloatInput = _endpoint(
        entityName: 'System',
        endpointName: 'cv_1_send',
        displayName: 'CV 1',
        direction: dp.EndpointDirection.input,
      );
      final dp.EndpointInfo keyFloatOutput = _endpoint(
        entityName: 'BladeHW',
        endpointName: 'key_pressure',
        displayName: 'Key Pressure',
        indexSpec: const dp.IndexSpecKey(8, 8),
      );
      final dp.EndpointInfo voiceFloatOutput = _endpoint(
        entityName: 'VoiceFixture',
        endpointName: 'voice_float',
        displayName: 'Voice Float',
        indexSpec: const dp.IndexSpecVoice(4),
      );
      final dp.EndpointInfo continuousFloatOutput = _endpoint(
        entityName: 'XY',
        endpointName: 'x',
        displayName: 'X',
        category: dp.EndpointCategory.continuous,
        indexSpec: const dp.IndexSpecKey(8, 8),
      );
      final dp.EndpointInfo wrongCategoryOutput = _endpoint(
        entityName: 'Audio',
        endpointName: 'level',
        displayName: 'Level',
        category: dp.EndpointCategory.audioStream,
      );
      final dp.EndpointInfo float2Output = _endpoint(
        entityName: 'AudioBridge',
        endpointName: 'level_meter',
        displayName: 'Level Meter',
        baseType: dp.DataType.float2,
        indexSpec: const dp.IndexSpecKey(8, 8),
      );

      final List<dp.EndpointInfo> candidates = <dp.EndpointInfo>[
        keyFloatOutput,
        voiceFloatOutput,
        continuousFloatOutput,
        wrongCategoryOutput,
        float2Output,
      ].where((dp.EndpointInfo candidate) {
        return isCompatibleConnectionPair(noneFloatInput, candidate);
      }).toList();

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: noneFloatInput,
        candidates: candidates,
      );

      expect(
        model.search('').map((ConnectionNavLeafCard leaf) => leaf.title),
        equals(<String>['BladeHW > Key Pressure', 'VoiceFixture > Voice Float']
            .map((String breadcrumb) => breadcrumb.split(' > ').last)),
      );
      expect(
        model.search('').expand(
              (ConnectionNavLeafCard leaf) =>
                  leaf.members.map((dp.EndpointInfo member) => member.name),
            ),
        unorderedEquals(<String>['key_pressure', 'voice_float']),
      );
    });

    test('default projected index conversion follows source hints', () {
      final dp.EndpointInfo noneFloatInput = _endpoint(
        entityName: 'System',
        endpointName: 'cv_1_send',
        displayName: 'CV 1',
        direction: dp.EndpointDirection.input,
      );
      final dp.EndpointInfo pressureOutput = _endpoint(
        entityName: 'BladeHW',
        endpointName: 'key_pressure',
        displayName: 'Key Pressure',
        indexSpec: const dp.IndexSpecKey(8, 8),
        projectionHints: const dp.ProjectionHints(
          strategies: <dp.ProjectionStrategyHint>[
            dp.ProjectionStrategyHint(name: dp.JsonFields.CONVERSION_MAX_VALUE),
            dp.ProjectionStrategyHint(
                name: dp.JsonFields.CONVERSION_AVERAGE_VALUE),
            dp.ProjectionStrategyHint(
                name: dp.JsonFields.CONVERSION_LAST_ACTIVE),
            dp.ProjectionStrategyHint(
                name: dp.JsonFields.CONVERSION_FIRST_ACTIVE),
          ],
          strategiesProvided: true,
        ),
      );
      final dp.EndpointInfo bendOutput = _endpoint(
        entityName: 'BladeHW',
        endpointName: 'key_bend',
        displayName: 'Key Bend',
        indexSpec: const dp.IndexSpecKey(8, 8),
        projectionHints: const dp.ProjectionHints(
          polarity: dp.ProjectionPolarity.bipolar,
          activity: dp.ProjectionActivityRule.absAboveThreshold,
          strategies: <dp.ProjectionStrategyHint>[
            dp.ProjectionStrategyHint(name: dp.JsonFields.CONVERSION_MAX_ABS),
            dp.ProjectionStrategyHint(name: dp.JsonFields.CONVERSION_MAX_VALUE),
          ],
          strategiesProvided: true,
        ),
      );
      final dp.EndpointInfo noneOutput = _endpoint(
        entityName: 'Level',
        endpointName: 'level_mono',
        displayName: 'Level Mono',
      );
      final dp.EndpointInfo keyInput = _endpoint(
        entityName: 'Fixture',
        endpointName: 'uniform_float_input',
        displayName: 'Uniform Input',
        direction: dp.EndpointDirection.input,
        indexSpec: const dp.IndexSpecKey(8, 8),
      );

      expect(
        defaultIndexConversionForConnectionPair(pressureOutput, noneFloatInput)
            ?.strategy,
        dp.JsonFields.CONVERSION_MAX_VALUE,
      );
      expect(
        defaultIndexConversionForConnectionPair(bendOutput, noneFloatInput)
            ?.strategy,
        dp.JsonFields.CONVERSION_MAX_ABS,
      );
      expect(
        defaultIndexConversionForConnectionPair(noneOutput, keyInput)?.strategy,
        dp.JsonFields.CONVERSION_UNIFORM,
      );
    });
  });

  group('ConnectionNavigationModel', () {
    test('groupKey pair under same path becomes one leaf', () {
      final dp.EndpointInfo left = _endpoint(
        entityName: 'System',
        endpointName: 'out_l',
        displayName: 'Left',
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final dp.EndpointInfo right = _endpoint(
        entityName: 'System',
        endpointName: 'out_r',
        displayName: 'Right',
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[left, right],
      );

      final List<ConnectionNavCard> systemLevel = model.cardsAt(
        <String>[dp.kDisplayCategorySystem],
      );
      expect(systemLevel, hasLength(1));
      expect(systemLevel.single, isA<ConnectionNavFolderCard>());
      expect(
        (systemLevel.single as ConnectionNavFolderCard).title,
        equals(dp.kDisplayCategoryAudioAndMidi),
      );

      final List<ConnectionNavCard> audioLevel = model.cardsAt(
        <String>[dp.kDisplayCategorySystem, dp.kDisplayCategoryAudioAndMidi],
      );
      expect(audioLevel, hasLength(1));
      final ConnectionNavLeafCard leaf =
          audioLevel.single as ConnectionNavLeafCard;
      expect(leaf.title, equals('Main Speakers'));
      expect(leaf.members, hasLength(2));
    });

    test('same groupKey on different paths yields two leaves', () {
      final dp.EndpointInfo a = _endpoint(
        entityName: 'Plugin_1',
        endpointName: 'a',
        displayName: 'A',
        ownerDisplayName: 'Plugin',
        groupKey: 'stereo_pair',
        display: const dp.EndpointDisplaySpec(
          categoryPath: <String>['Bus A'],
        ),
      );
      final dp.EndpointInfo b = _endpoint(
        entityName: 'Plugin_1',
        endpointName: 'b',
        displayName: 'B',
        ownerDisplayName: 'Plugin',
        groupKey: 'stereo_pair',
        display: const dp.EndpointDisplaySpec(
          categoryPath: <String>['Bus B'],
        ),
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[a, b],
      );

      final List<ConnectionNavCard> busA = model.cardsAt(
        <String>['Plugin', 'Bus A'],
      );
      final List<ConnectionNavCard> busB = model.cardsAt(
        <String>['Plugin', 'Bus B'],
      );
      expect(busA, hasLength(1));
      expect(busB, hasLength(1));
      expect((busA.single as ConnectionNavLeafCard).title, equals('A'));
      expect((busB.single as ConnectionNavLeafCard).title, equals('B'));
    });

    test('unknown multi-member groupKey uses groupKey as leaf title', () {
      final dp.EndpointInfo a = _endpoint(
        entityName: 'Knobs',
        endpointName: 'knob_a',
        displayName: 'Knob A',
        ownerDisplayName: 'Knobs',
        groupKey: 'Main Knobs',
      );
      final dp.EndpointInfo b = _endpoint(
        entityName: 'Knobs',
        endpointName: 'knob_b',
        displayName: 'Knob B',
        ownerDisplayName: 'Knobs',
        groupKey: 'Main Knobs',
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[a, b],
      );

      final List<ConnectionNavCard> cards = model.cardsAt(<String>['Knobs']);
      expect(cards, hasLength(1));
      final ConnectionNavLeafCard leaf = cards.single as ConnectionNavLeafCard;
      expect(leaf.title, equals('Main Knobs'));
      expect(leaf.members, hasLength(2));
    });

    test('omits empty nested folder when focused is its only peer', () {
      final dp.EndpointInfo onlyInNested = _endpoint(
        entityName: 'FocusApp',
        endpointName: 'focused_in',
        displayName: 'Focused Input',
        direction: dp.EndpointDirection.input,
        ownerDisplayName: 'Focus App',
        display: const dp.EndpointDisplaySpec(
          categoryPath: <String>['Solo Nest'],
        ),
      );
      final dp.EndpointInfo sibling = _endpoint(
        entityName: 'Other',
        endpointName: 'peer',
        displayName: 'Peer',
        ownerDisplayName: 'Other App',
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: onlyInNested,
        candidates: <dp.EndpointInfo>[onlyInNested, sibling],
      );

      expect(
        model.cardsAt(const <String>[]).map((ConnectionNavCard c) => c.title),
        equals(<String>['Other App']),
      );
      expect(model.cardsAt(<String>['Focus App']), isEmpty);
    });

    test('hides folder transitively when only descendants are empty', () {
      final dp.EndpointInfo deepFocused = _endpoint(
        entityName: 'FocusApp',
        endpointName: 'focused_in',
        displayName: 'Focused Input',
        direction: dp.EndpointDirection.input,
        ownerDisplayName: 'Focus App',
        display: const dp.EndpointDisplaySpec(
          categoryPath: <String>['Mid', 'Deep'],
        ),
      );
      final dp.EndpointInfo other = _endpoint(
        entityName: 'Zed',
        endpointName: 'z',
        displayName: 'Z',
        ownerDisplayName: 'Zed',
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: deepFocused,
        candidates: <dp.EndpointInfo>[deepFocused, other],
      );

      expect(
        model.cardsAt(const <String>[]).map((ConnectionNavCard c) => c.title),
        equals(<String>['Zed']),
      );
      expect(model.cardsAt(<String>['Focus App']), isEmpty);
      expect(model.cardsAt(<String>['Focus App', 'Mid']), isEmpty);
    });

    test('excludes focused endpoint even when passed in candidates', () {
      final dp.EndpointInfo peer = _endpoint(
        entityName: 'PeerApp',
        endpointName: 'peer_out',
        displayName: 'Peer Out',
        ownerDisplayName: 'Peer App',
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[focused, peer],
      );

      final List<ConnectionNavCard> root = model.cardsAt(const <String>[]);
      expect(root, hasLength(1));
      expect(root.single.title, equals('Peer App'));

      final List<ConnectionNavCard> peerFolder = model.cardsAt(
        <String>['Peer App'],
      );
      expect(peerFolder, hasLength(1));
      expect(
        (peerFolder.single as ConnectionNavLeafCard).title,
        equals('Peer Out'),
      );
    });

    test('search matches nested leaf and shows full breadcrumb', () {
      final dp.EndpointInfo pedal = _endpoint(
        entityName: 'System',
        endpointName: 'expr',
        displayName: 'Expression Pedal',
        ownerDisplayName: 'System',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryIO],
        ),
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[pedal],
      );

      final List<ConnectionNavLeafCard> hits = model.search('pedal');
      expect(hits, hasLength(1));
      expect(hits.single.title, equals('Expression Pedal'));
      expect(
        hits.single.breadcrumb,
        equals(
          '${dp.kDisplayCategorySystem} > ${dp.kDisplayCategoryIO} > '
          'Expression Pedal',
        ),
      );
    });

    test('search matches path segments case-insensitively', () {
      final dp.EndpointInfo leaf = _endpoint(
        entityName: 'Plugin_1',
        endpointName: 'cutoff',
        displayName: 'Cutoff',
        ownerDisplayName: 'MyPlugin',
        display: const dp.EndpointDisplaySpec(
          categoryPath: <String>['Filters', 'Filter 1'],
        ),
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[leaf],
      );

      final List<ConnectionNavLeafCard> hits = model.search('FILTERS');
      expect(hits, hasLength(1));
      expect(hits.single.title, equals('Cutoff'));
    });

    test('orders System first then alphabetical at top level', () {
      final dp.EndpointInfo systemLeaf = _endpoint(
        entityName: 'System',
        endpointName: 'key',
        displayName: 'Key 1',
        ownerDisplayName: 'System',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryKeys],
        ),
      );
      final dp.EndpointInfo alpha = _endpoint(
        entityName: 'Alpha_1',
        endpointName: 'a',
        displayName: 'A',
        ownerDisplayName: 'Alpha',
      );
      final dp.EndpointInfo zebra = _endpoint(
        entityName: 'Zebra_1',
        endpointName: 'z',
        displayName: 'Z',
        ownerDisplayName: 'Zebra',
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[zebra, systemLeaf, alpha],
      );

      expect(
        model.cardsAt(const <String>[]).map((ConnectionNavCard c) => c.title),
        equals(<String>[
          dp.kDisplayCategorySystem,
          'Alpha',
          'Zebra',
        ]),
      );
    });

    test('lists mixed System Keys / Audio & MIDI / I/O under System', () {
      // Realistic Phase 5 migrated metadata: pico Keys + System audio pair + I/O.
      final dp.EndpointInfo keys = _endpoint(
        entityName: 'BladeHW',
        endpointName: 'key_position',
        displayName: 'Key Position',
        ownerDisplayName: 'Blade Hardware',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryKeys],
        ),
      );
      final dp.EndpointInfo speakersL = _endpoint(
        entityName: 'System',
        endpointName: 'system:playback_1',
        displayName: 'system:playback_1',
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final dp.EndpointInfo speakersR = _endpoint(
        entityName: 'System',
        endpointName: 'system:playback_2',
        displayName: 'system:playback_2',
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final dp.EndpointInfo io = _endpoint(
        entityName: 'BladeHW',
        endpointName: 'usb_status',
        displayName: 'USB Status',
        ownerDisplayName: 'Blade HW',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryIO],
        ),
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[io, speakersR, keys, speakersL],
      );

      expect(
        model.cardsAt(<String>[dp.kDisplayCategorySystem]).map(
            (ConnectionNavCard c) => c.title),
        equals(<String>[
          dp.kDisplayCategoryAudioAndMidi,
          dp.kDisplayCategoryIO,
          dp.kDisplayCategoryKeys,
        ]),
      );

      expect(
        model.cardsAt(<String>[
          dp.kDisplayCategorySystem,
          dp.kDisplayCategoryKeys,
        ]).map((ConnectionNavCard c) => c.title),
        equals(<String>['Key Position']),
      );
      expect(
        model.cardsAt(<String>[
          dp.kDisplayCategorySystem,
          dp.kDisplayCategoryAudioAndMidi,
        ]).map((ConnectionNavCard c) => c.title),
        equals(<String>['Main Speakers']),
      );
      expect(
        model.cardsAt(<String>[
          dp.kDisplayCategorySystem,
          dp.kDisplayCategoryIO,
        ]).map((ConnectionNavCard c) => c.title),
        equals(<String>['USB Status']),
      );
    });

    test('omits endpoints with hideFromPicker from navigation', () {
      final dp.EndpointInfo visible = _endpoint(
        entityName: 'BladeHW',
        endpointName: 'key_press',
        displayName: 'Key Press',
        ownerDisplayName: 'Blade Hardware',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryKeys],
        ),
      );
      final dp.EndpointInfo hiddenMod = _endpoint(
        entityName: 'BladeHW',
        endpointName: 'mod_key_toggle',
        displayName: 'Mod Key Toggle',
        ownerDisplayName: 'Blade Hardware',
        hideFromPicker: true,
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryIO],
        ),
      );
      final dp.EndpointInfo hiddenTheme = _endpoint(
        entityName: 'System',
        endpointName: 'shared_theme_in',
        displayName: 'Shared Theme Input',
        ownerDisplayName: 'System',
        hideFromPicker: true,
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryOther],
        ),
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[visible, hiddenMod, hiddenTheme],
      );

      expect(
        model.cardsAt(<String>[dp.kDisplayCategorySystem]).map(
            (ConnectionNavCard c) => c.title),
        equals(<String>[dp.kDisplayCategoryKeys]),
      );
      expect(
        model.cardsAt(<String>[
          dp.kDisplayCategorySystem,
          dp.kDisplayCategoryKeys,
        ]).map((ConnectionNavCard c) => c.title),
        equals(<String>['Key Press']),
      );
      expect(
        model.cardsAt(<String>[
          dp.kDisplayCategorySystem,
          dp.kDisplayCategoryIO,
        ]),
        isEmpty,
      );
      expect(
        model.cardsAt(<String>[
          dp.kDisplayCategorySystem,
          dp.kDisplayCategoryOther,
        ]),
        isEmpty,
      );
    });

    test('folder connected-count counts connected leaves; pairs count as one',
        () {
      final dp.EndpointInfo left = _endpoint(
        entityName: 'System',
        endpointName: 'out_l',
        displayName: 'Left',
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final dp.EndpointInfo right = _endpoint(
        entityName: 'System',
        endpointName: 'out_r',
        displayName: 'Right',
        ownerDisplayName: 'System',
        groupKey: 'system_audio_out',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final dp.EndpointInfo midi = _endpoint(
        entityName: 'System',
        endpointName: 'midi_out',
        displayName: 'MIDI Out',
        ownerDisplayName: 'System',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[left, right, midi],
        connectionRules: <dp.ConnectionRule>[
          _rule(source: left, destination: focused),
          _rule(source: right, destination: focused),
        ],
      );

      final ConnectionNavFolderCard audioFolder = model
          .cardsAt(<String>[dp.kDisplayCategorySystem])
          .whereType<ConnectionNavFolderCard>()
          .singleWhere(
            (ConnectionNavFolderCard c) =>
                c.title == dp.kDisplayCategoryAudioAndMidi,
          );
      expect(audioFolder.compatibleLeafCount, equals(2));
      expect(audioFolder.connectedLeafCount, equals(1));

      final List<ConnectionNavCard> leaves = model.cardsAt(
        <String>[dp.kDisplayCategorySystem, dp.kDisplayCategoryAudioAndMidi],
      );
      final ConnectionNavLeafCard speakers =
          leaves.whereType<ConnectionNavLeafCard>().singleWhere(
                (ConnectionNavLeafCard c) => c.title == 'Main Speakers',
              );
      final ConnectionNavLeafCard midiLeaf =
          leaves.whereType<ConnectionNavLeafCard>().singleWhere(
                (ConnectionNavLeafCard c) => c.title == 'MIDI Out',
              );
      expect(speakers.isFullyConnected, isTrue);
      expect(midiLeaf.isFullyConnected, isFalse);
    });

    test('uses known groupKey title map for system_audio_in', () {
      final dp.EndpointInfo left = _endpoint(
        entityName: 'System',
        endpointName: 'in_l',
        displayName: 'In Left',
        ownerDisplayName: 'System',
        groupKey: 'system_audio_in',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );
      final dp.EndpointInfo right = _endpoint(
        entityName: 'System',
        endpointName: 'in_r',
        displayName: 'In Right',
        ownerDisplayName: 'System',
        groupKey: 'system_audio_in',
        display: const dp.EndpointDisplaySpec(
          topLevelCategory: dp.kDisplayCategorySystem,
          categoryPath: <String>[dp.kDisplayCategoryAudioAndMidi],
        ),
      );

      final ConnectionNavigationModel model = ConnectionNavigationModel.build(
        focusedEndpoint: focused,
        candidates: <dp.EndpointInfo>[left, right],
      );

      final ConnectionNavLeafCard leaf = model.cardsAt(
        <String>[dp.kDisplayCategorySystem, dp.kDisplayCategoryAudioAndMidi],
      ).single as ConnectionNavLeafCard;
      expect(leaf.title, equals('Main Audio Input'));
    });
  });
}
