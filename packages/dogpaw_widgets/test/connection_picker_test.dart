import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDogPawEntity extends dp.DogPawEntity {
  final List<dp.EndpointInfo> availableEndpoints;
  final List<dp.ConnectionRequest> connectionRequests;
  final List<dp.ConnectionRequest> createdRequests = <dp.ConnectionRequest>[];
  final List<String> deletedRequestNames = <String>[];

  _FakeDogPawEntity({
    required this.availableEndpoints,
    List<dp.ConnectionRequest>? initialRequests,
  })  : connectionRequests = List<dp.ConnectionRequest>.from(
          initialRequests ?? <dp.ConnectionRequest>[],
        ),
        super('fake_entity');

  @override
  Future<dp.Result<List<dp.EndpointInfo>>> searchEndpoints(
    dp.SearchCriteria criteria,
  ) async {
    return dp.Result<List<dp.EndpointInfo>>.success(availableEndpoints);
  }

  @override
  Future<dp.Result<List<dp.ConnectionRequest>>> listConnectionRequests({
    dp.NamespaceSelector? namespaceSelector,
    bool includeResolved = false,
    bool includeSpec = false,
  }) async {
    return dp.Result<List<dp.ConnectionRequest>>.success(
      List<dp.ConnectionRequest>.from(connectionRequests),
    );
  }

  @override
  Future<dp.Result<bool>> createConnectionRequest(
    dp.ConnectionRequest connectionRequest,
  ) async {
    createdRequests.add(connectionRequest);
    connectionRequests.add(connectionRequest);
    return dp.Result<bool>.success(true);
  }

  @override
  Future<dp.Result<bool>> deleteConnectionRequest(
    String name, {
    dp.NamespaceSelector? namespaceSelector,
  }) async {
    deletedRequestNames.add(name);
    connectionRequests.removeWhere(
      (dp.ConnectionRequest request) => request.name == name,
    );
    return dp.Result<bool>.success(true);
  }
}

dp.EndpointInfo _buildEndpoint({
  required String entityName,
  required String endpointName,
  required String displayName,
  required dp.EndpointDirection direction,
  String? groupKey,
  List<String> flags = const <String>[],
  String? jackClientName,
  String? fullJackPortName,
}) {
  return dp.EndpointInfo(
    name: endpointName,
    namespaceSelector: dp.NamespaceSelector.specificEntity(entityName),
    spec: dp.EndpointSpec(
      displayName: displayName,
      direction: direction,
      dataType: const dp.DataTypeSpec(dp.DataType.float),
      flags: flags,
      groupKey: groupKey,
      jackClientName: jackClientName,
      fullJackPortName: fullJackPortName,
    ),
  );
}

dp.ConnectionRequest _buildConnectionRequest({
  required String name,
  required dp.EndpointInfo source,
  required dp.EndpointInfo destination,
}) {
  return dp.ConnectionRequest(
    name: name,
    spec: dp.ConnectionRequestData(
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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ConnectionPicker(
            entity: entity,
            focusedEndpoint: focusedEndpoint,
            onRefresh: onRefresh,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('focused input flow groups candidates and hides JACK names',
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
          groupKey: 'Main Speakers',
          flags: const <String>['system_audio_out_left'],
          jackClientName: 'raw_jack_client',
          fullJackPortName: 'system:playback_1',
        ),
        _buildEndpoint(
          entityName: 'System',
          endpointName: 'speaker_right',
          displayName: 'Right Speaker',
          direction: dp.EndpointDirection.output,
          groupKey: 'Main Speakers',
          flags: const <String>['system_audio_out_right'],
          jackClientName: 'raw_jack_client',
          fullJackPortName: 'system:playback_2',
        ),
      ],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    expect(find.byKey(const Key('connection-group-Main Speakers')), findsOneWidget);
    expect(find.text('Main Speakers'), findsOneWidget);
    expect(find.text('System'), findsWidgets);
    expect(find.text('2 endpoints'), findsOneWidget);
    expect(find.text('raw_jack_client'), findsNothing);
    expect(find.text('system:playback_1'), findsNothing);
    expect(find.text('System'), findsWidgets);
    expect(find.text('System I/O'), findsOneWidget);
  });

  testWidgets('connect action creates grouped requests for focused input',
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
          groupKey: 'Main Knobs',
        ),
        _buildEndpoint(
          entityName: 'Knobs',
          endpointName: 'knob_b',
          displayName: 'Knob B',
          direction: dp.EndpointDirection.output,
          groupKey: 'Main Knobs',
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

    await tester.tap(find.byKey(const Key('connection-group-action-Main Knobs')));
    await tester.pumpAndSettle();

    expect(entity.createdRequests, hasLength(2));
    expect(entity.createdRequests.first.spec!.destinationRef.name, equals('cutoff'));
    expect(refreshCount, equals(1));
  });

  testWidgets('focused output flow targets compatible inputs',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedOutput = _buildEndpoint(
      entityName: 'Knobs',
      endpointName: 'knob_a',
      displayName: 'Knob A',
      direction: dp.EndpointDirection.output,
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
          entityName: 'DPPHost',
          endpointName: 'cutoff',
          displayName: 'Cutoff',
          direction: dp.EndpointDirection.input,
          groupKey: 'Filter',
        ),
      ],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedOutput,
    );

    await tester.tap(find.byKey(const Key('connection-group-action-Filter')));
    await tester.pumpAndSettle();

    expect(entity.createdRequests, hasLength(1));
    expect(entity.createdRequests.first.spec!.sourceRef.name, equals('knob_a'));
    expect(entity.createdRequests.first.spec!.destinationRef.name, equals('cutoff'));
  });

  testWidgets('existing grouped requests render a disconnect action',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final dp.EndpointInfo knobA = _buildEndpoint(
      entityName: 'Knobs',
      endpointName: 'knob_a',
      displayName: 'Knob A',
      direction: dp.EndpointDirection.output,
      groupKey: 'Main Knobs',
    );
    final dp.EndpointInfo knobB = _buildEndpoint(
      entityName: 'Knobs',
      endpointName: 'knob_b',
      displayName: 'Knob B',
      direction: dp.EndpointDirection.output,
      groupKey: 'Main Knobs',
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[knobA, knobB],
      initialRequests: <dp.ConnectionRequest>[
        _buildConnectionRequest(name: 'req_a', source: knobA, destination: focusedInput),
        _buildConnectionRequest(name: 'req_b', source: knobB, destination: focusedInput),
      ],
    );

    await pumpConnectionPicker(
      tester,
      entity: entity,
      focusedEndpoint: focusedInput,
    );

    expect(find.text('Disconnect'), findsOneWidget);
  });

  testWidgets('disconnect action removes matching grouped requests',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final dp.EndpointInfo knobA = _buildEndpoint(
      entityName: 'Knobs',
      endpointName: 'knob_a',
      displayName: 'Knob A',
      direction: dp.EndpointDirection.output,
      groupKey: 'Main Knobs',
    );
    final dp.EndpointInfo knobB = _buildEndpoint(
      entityName: 'Knobs',
      endpointName: 'knob_b',
      displayName: 'Knob B',
      direction: dp.EndpointDirection.output,
      groupKey: 'Main Knobs',
    );
    int refreshCount = 0;
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[knobA, knobB],
      initialRequests: <dp.ConnectionRequest>[
        _buildConnectionRequest(name: 'req_a', source: knobA, destination: focusedInput),
        _buildConnectionRequest(name: 'req_b', source: knobB, destination: focusedInput),
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

    await tester.tap(find.byKey(const Key('connection-group-action-Main Knobs')));
    await tester.pumpAndSettle();

    expect(entity.connectionRequests, isEmpty);
    expect(entity.deletedRequestNames, containsAll(<String>['req_a', 'req_b']));
    expect(refreshCount, equals(1));
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
          groupKey: 'Main Knobs',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Material(
              child: FilledButton(
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

    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Open Connection Dialog'), findsOneWidget);
  });

  testWidgets('picker reloads when the focused endpoint changes',
      (WidgetTester tester) async {
    final dp.EndpointInfo focusedInput = _buildEndpoint(
      entityName: 'DPPHost',
      endpointName: 'cutoff',
      displayName: 'Cutoff',
      direction: dp.EndpointDirection.input,
    );
    final dp.EndpointInfo focusedOutput = _buildEndpoint(
      entityName: 'Knobs',
      endpointName: 'knob_a',
      displayName: 'Knob A',
      direction: dp.EndpointDirection.output,
    );
    final _FakeDogPawEntity entity = _FakeDogPawEntity(
      availableEndpoints: <dp.EndpointInfo>[
        _buildEndpoint(
          entityName: 'Knobs',
          endpointName: 'knob_b',
          displayName: 'Knob B',
          direction: dp.EndpointDirection.output,
          groupKey: 'Main Knobs',
        ),
        _buildEndpoint(
          entityName: 'DPPHost',
          endpointName: 'resonance',
          displayName: 'Resonance',
          direction: dp.EndpointDirection.input,
          groupKey: 'Filter',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ConnectionPicker(
            entity: entity,
            focusedEndpoint: focusedInput,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-group-Main Knobs')), findsOneWidget);
    expect(find.byKey(const Key('connection-group-Filter')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ConnectionPicker(
            entity: entity,
            focusedEndpoint: focusedOutput,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-group-Main Knobs')), findsNothing);
    expect(find.byKey(const Key('connection-group-Filter')), findsOneWidget);
  });
}
