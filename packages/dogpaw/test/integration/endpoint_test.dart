// Integration tests for endpoint creation and data flow.
//
// Verifies that data types (especially INT, which was added later) work
// correctly through the full Dart FFI path: endpoint creation → producer
// creation → write → consumer poll → deserialization.
//
// RUN WITH: flutter test test/integration/endpoint_test.dart --concurrency=1

import 'dart:async';

import '../test_support.dart';
import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:test/test.dart';

void main() {
  IntegrationTestFixture.register();

  test('EndpointSpec serializes JACK metadata and flags', () {
    const spec = EndpointSpec(
      direction: EndpointDirection.output,
      dataType: DataTypeSpec(DataType.audioStream),
      category: EndpointCategory.audioStream,
      flags: ['system_audio_out_left', 'preferred'],
      jackClientName: 'Monolith',
      fullJackPortName: 'Monolith:main_out_l',
      jackBindingMode: JackBindingMode.adoptExistingPort,
    );

    final json = spec.toJson();

    expect(
        json[JsonFields.FLAGS], equals(['system_audio_out_left', 'preferred']));
    expect(json[JsonFields.JACK_CLIENT_NAME], equals('Monolith'));
    expect(json[JsonFields.FULL_JACK_PORT_NAME], equals('Monolith:main_out_l'));
    expect(
      json[JsonFields.JACK_BINDING_MODE],
      equals(JsonFields.JACK_BINDING_MODE_ADOPT_EXISTING_PORT),
    );
  });

  test('FollowRequest serializes follower ref and leader criteria', () {
    final request = FollowRequest(
      name: 'follow_scope_left',
      spec: FollowRequestData(
        followerRef: DataItemRef.byName(
          name: 'scope_left',
          namespaceSelector:
              const NamespaceSelector.specificEntity('AudioBridge'),
        ),
        leaderCriteria: SearchCriteria.andCombination([
          SearchCriteria.sourceEntityEquals('System'),
          SearchCriteria.flagContains('system_audio_out_left'),
        ]),
      ),
    );

    final json = request.toJson();

    expect(json[JsonFields.SPEC], isNotNull);
    expect(json[JsonFields.SPEC][JsonFields.FOLLOWER_REF][JsonFields.NAME],
        equals('scope_left'));
    expect(json[JsonFields.SPEC][JsonFields.LEADER_CRITERIA],
        contains(JsonFields.AND));
  });

  test('DataItemRef rejects missing name fields', () {
    expect(
      () => DataItemRef.fromJson({
        JsonFields.NAMESPACE_SELECTOR:
            const NamespaceSelector.currentEntity().toJson(),
      }),
      throwsArgumentError,
    );
  });

  test('SearchCriteria rejects legacy JSON shape', () {
    expect(
      () => SearchCriteria.fromJson({
        'entityId': 'System',
        JsonFields.DIRECTION: JsonFields.DIRECTION_INPUT,
      }),
      throwsArgumentError,
    );
  });

  test('Connection parsing normalizes realized connections to global namespace',
      () {
    final connection = Connection.fromJson({
      JsonFields.NAME: 'source_to_destination',
      JsonFields.NAMESPACE_SELECTOR:
          const NamespaceSelector.currentEntity().toJson(),
      JsonFields.SPEC: {
        JsonFields.SOURCE_REF: {
          JsonFields.NAME: 'source',
          JsonFields.NAMESPACE_SELECTOR:
              const NamespaceSelector.specificEntity('Producer').toJson(),
        },
        JsonFields.DESTINATION_REF: {
          JsonFields.NAME: 'destination',
          JsonFields.NAMESPACE_SELECTOR:
              const NamespaceSelector.specificEntity('Consumer').toJson(),
        },
      },
    });

    expect(connection.namespaceSelector, const NamespaceSelector.global());
  });

  test('LocalEndpoint runtime methods throw without native delegate', () async {
    final LocalEndpoint outputEndpoint = LocalEndpoint(
      name: 'delegate_required_output',
      spec: const EndpointSpec(
        direction: EndpointDirection.output,
        dataType: DataTypeSpec(DataType.int_),
        category: EndpointCategory.messageQueue,
      ),
    );
    expect(
      () => outputEndpoint.write(
        const StatefulIntAction(
          action: StatefulIntActionType.setValue,
          value: 42,
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );

    final LocalEndpoint inputEndpoint = LocalEndpoint(
      name: 'delegate_required_input',
      spec: const EndpointSpec(
        direction: EndpointDirection.input,
        dataType: DataTypeSpec(DataType.int_),
        category: EndpointCategory.messageQueue,
      ),
    );
    expect(
      () => inputEndpoint.poll(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => inputEndpoint.adoptRetainedStateSnapshot(
        const EndpointRetainedStateSnapshot(
          hasState: true,
          value: 5,
          timestampUs: 1,
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );

    final LocalEndpoint fileBackedOutput = LocalEndpoint(
      name: 'delegate_required_file_output',
      spec: const EndpointSpec(
        direction: EndpointDirection.output,
        dataType: DataTypeSpec(DataType.custom, customTypeName: 'json_payload'),
        category: EndpointCategory.fileBacked,
      ),
    );
    await expectLater(
      () => fileBackedOutput.writeFileBacked(<String, dynamic>{'x': 1}),
      throwsA(isA<UnsupportedError>()),
    );

    final LocalEndpoint fileBackedInput = LocalEndpoint(
      name: 'delegate_required_file_input',
      spec: const EndpointSpec(
        direction: EndpointDirection.input,
        dataType: DataTypeSpec(DataType.custom, customTypeName: 'json_payload'),
        category: EndpointCategory.fileBacked,
      ),
    );
    await expectLater(
      () => fileBackedInput.readFileBacked((dynamic _) {}),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      () => fileBackedInput.pollFileBacked((dynamic _) {}),
      throwsA(isA<UnsupportedError>()),
    );
  });

  group('FollowRequest API', () {
    late DogPawEntity sourceOwner;
    late DogPawEntity leaderOwner;
    late DogPawEntity followerOwner;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();

      sourceOwner = DogPawEntity('FollowSource_$suffix');
      expect((await sourceOwner.connect()).success, isTrue);

      leaderOwner = DogPawEntity('FollowLeader_$suffix');
      expect((await leaderOwner.connect()).success, isTrue);

      followerOwner = DogPawEntity('FollowFollower_$suffix');
      expect((await followerOwner.connect()).success, isTrue);

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      followerOwner.disconnect();
      leaderOwner.disconnect();
      sourceOwner.disconnect();
    });

    test('CreateAndListFollowRequest', () async {
      final leaderFlag =
          'dart_follow_flag_${DateTime.now().microsecondsSinceEpoch}';
      const sourceName = 'dart_follow_source';
      const leaderName = 'dart_follow_leader';
      const followerName = 'dart_follow_follower';
      const requestName = 'dart_follow_request';

      expect(
        (await sourceOwner.createEndpoint(EndpointInfo(
          name: sourceName,
          spec: EndpointSpec(
            direction: EndpointDirection.output,
            dataType: DataTypeSpec(DataType.int_),
            category: EndpointCategory.messageQueue,
          ),
        )))
            .success,
        isTrue,
      );

      expect(
        (await leaderOwner.createEndpoint(EndpointInfo(
          name: leaderName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: const DataTypeSpec(DataType.int_),
            category: EndpointCategory.messageQueue,
            flags: [leaderFlag],
          ),
        )))
            .success,
        isTrue,
      );

      expect(
        (await followerOwner.createEndpoint(EndpointInfo(
          name: followerName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec(DataType.int_),
            category: EndpointCategory.messageQueue,
          ),
        )))
            .success,
        isTrue,
      );

      final followRequest = FollowRequest(
        name: requestName,
        spec: FollowRequestData(
          followerRef: DataItemRef.byName(
            name: followerName,
            namespaceSelector:
                NamespaceSelector.specificEntity(followerOwner.entityName),
          ),
          leaderCriteria: SearchCriteria.flagContains(leaderFlag),
        ),
      );

      final createResult =
          await followerOwner.createFollowRequest(followRequest);
      expect(createResult.success, isTrue,
          reason: 'Failed to create follow request: ${createResult.error}');

      final listResult =
          await followerOwner.listFollowRequests(includeSpec: true);
      expect(listResult.success, isTrue,
          reason: 'Failed to list follow requests: ${listResult.error}');
      expect(listResult.value!.any((request) => request.name == requestName),
          isTrue);

      await followerOwner.deleteFollowRequest(requestName);
      await sourceOwner.deleteEndpoint(sourceName);
      await leaderOwner.deleteEndpoint(leaderName);
      await followerOwner.deleteEndpoint(followerName);
    });
  });

  group('Endpoint subscriptions', () {
    late DogPawEntity owner;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      owner = DogPawEntity('EndpointSubscriber_$suffix');
      expect((await owner.connect()).success, isTrue);
      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      owner.disconnect();
    });

    test('subscribeToEndpointsReceivesCreateNotification', () async {
      final epName =
          'endpoint_subscribe_${DateTime.now().microsecondsSinceEpoch}';
      final createCompleter = Completer<EndpointInfo>();

      final subscribeResult = await owner.subscribeToEndpoints(
        (String notificationType, DataItemRef _, dynamic data) {
          if (notificationType.endsWith('create') &&
              data is EndpointInfo &&
              data.name == epName &&
              !createCompleter.isCompleted) {
            createCompleter.complete(data);
          }
        },
        namespaceSelector: NamespaceSelector.specificEntity(owner.entityName),
        includeResolved: true,
        includeSpec: true,
        sendImmediately: false,
      );
      expect(subscribeResult.success, isTrue,
          reason: 'Failed to subscribe to endpoints: ${subscribeResult.error}');

      final createResult = await owner.createEndpoint(EndpointInfo(
        name: epName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(createResult.success, isTrue,
          reason: 'Failed to create endpoint: ${createResult.error}');

      final notifiedEndpoint = await createCompleter.future.timeout(
        const Duration(seconds: 3),
      );
      expect(notifiedEndpoint.name, equals(epName));
    });
  });

  group('Endpoint INT Data Type', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('IntProducer_$suffix');
      producer.setErrorCallback(
          (error) => AppLogger.error('Producer error: $error'));
      final conn1 = await producer.connect();
      expect(conn1.success, isTrue,
          reason: 'Failed to connect producer: ${conn1.error}');

      consumer = DogPawEntity('IntConsumer_$suffix');
      consumer.setErrorCallback(
          (error) => AppLogger.error('Consumer error: $error'));
      final conn2 = await consumer.connect();
      expect(conn2.success, isTrue,
          reason: 'Failed to connect consumer: ${conn2.error}');

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('CreateINTOutputEndpoint', () async {
      final result = await producer.createEndpoint(EndpointInfo(
        name: 'int_out_test',
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(result.success, isTrue,
          reason: 'Failed to create INT output: ${result.error}');
      expect(result.value, isNotNull);
    });

    test('CreateINTInputEndpoint', () async {
      final result = await consumer.createEndpoint(EndpointInfo(
        name: 'int_in_test',
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(result.success, isTrue,
          reason: 'Failed to create INT input: ${result.error}');
      expect(result.value, isNotNull);
    });

    test('INTDataFlowProducerToConsumer', () async {
      final epName = 'int_flow_${DateTime.now().microsecondsSinceEpoch}';

      // Producer creates OUTPUT INT endpoint with auto-connect
      final outResult = await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.input),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(outResult.success, isTrue,
          reason: 'Failed to create output: ${outResult.error}');

      // Consumer creates INPUT INT endpoint with auto-connect
      final inResult = await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(inResult.success, isTrue,
          reason: 'Failed to create input: ${inResult.error}');

      // Wait for auto-connect
      await Future.delayed(const Duration(milliseconds: 1000));

      // Write a value from producer
      const StatefulIntAction testValue = StatefulIntAction(
        action: StatefulIntActionType.setValue,
        value: 42,
      );
      final written = outResult.value!.write(testValue);
      expect(written, isTrue, reason: 'Failed to write INT action');

      final List<StatefulIntAction> receivedActions = <StatefulIntAction>[];
      inResult.value!.setStatefulIntInputCallback(
        (StatefulIntAction action, EndpointSenderInfo senderInfo) {
          receivedActions.add(action);
        },
      );

      for (int attempt = 0; attempt < 20; attempt++) {
        if (receivedActions.isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(receivedActions, isNotEmpty, reason: 'No action received from INT endpoint');
      expect(receivedActions.first.action, equals(testValue.action),
          reason: 'Received action type should match written action');
      expect(receivedActions.first.value, equals(testValue.value),
          reason: 'Received action value should match written action');
    });

    test('INTMultipleValuesDelivered', () async {
      final epName = 'int_multi_${DateTime.now().microsecondsSinceEpoch}';

      final outResult = await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.input),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(outResult.success, isTrue);

      final inResult = await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(inResult.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 1000));

      final List<StatefulIntAction> received = <StatefulIntAction>[];
      inResult.value!.setStatefulIntInputCallback(
        (StatefulIntAction action, EndpointSenderInfo senderInfo) {
          received.add(action);
        },
      );

      // Write several values
      final values = [
        const StatefulIntAction(
          action: StatefulIntActionType.setValue,
          value: 0,
        ),
        const StatefulIntAction(
          action: StatefulIntActionType.setValue,
          value: -500,
        ),
        const StatefulIntAction(
          action: StatefulIntActionType.setValue,
          value: 1000,
        ),
        const StatefulIntAction(
          action: StatefulIntActionType.setValue,
          value: -1000,
        ),
        const StatefulIntAction(
          action: StatefulIntActionType.setValue,
          value: 42,
        ),
      ];
      for (final StatefulIntAction v in values) {
        outResult.value!.write(v);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      for (int attempt = 0; attempt < 30; attempt++) {
        if (received.length >= values.length) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(received.length, equals(values.length),
          reason: 'Should receive all ${values.length} actions');
      for (int i = 0; i < values.length; i++) {
        expect(received[i].action, equals(values[i].action),
            reason: 'Action type at index $i should match');
        expect(received[i].value, equals(values[i].value),
            reason: 'Action value at index $i should match');
      }
    });

    test('OwnedEndpointReadReturnsMetadataAndLookupReturnsLiveHandle',
        () async {
      final epName = 'int_lookup_${DateTime.now().microsecondsSinceEpoch}';

      final createResult = await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(createResult.success, isTrue,
          reason: 'Failed to create owned endpoint: ${createResult.error}');
      expect(createResult.value, isA<LocalEndpoint>());

      final readResult = await producer.readEndpoint(
        epName,
        namespaceSelector:
            NamespaceSelector.specificEntity(producer.entityName),
        includeResolved: true,
        includeSpec: true,
      );
      expect(readResult.success, isTrue,
          reason:
              'Failed to read owned endpoint metadata: ${readResult.error}');
      expect(readResult.value, isA<EndpointInfo>());
      expect(readResult.value, isNot(isA<LocalEndpoint>()));

      final LocalEndpoint? lookedUpByInfo =
          producer.getLocalEndpoint(readResult.value!);
      expect(lookedUpByInfo, same(createResult.value));

      final LocalEndpoint? lookedUpByName =
          producer.getLocalEndpointByName(epName);
      expect(lookedUpByName, same(createResult.value));
    });

    test('LocalEndpointObservesConnectionAddedAndRemoved', () async {
      final epName = 'int_observe_${DateTime.now().microsecondsSinceEpoch}';
      final requestName =
          'int_observe_request_${DateTime.now().microsecondsSinceEpoch}';

      final outResult = await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(outResult.success, isTrue,
          reason: 'Failed to create output endpoint: ${outResult.error}');

      final inResult = await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(inResult.success, isTrue,
          reason: 'Failed to create input endpoint: ${inResult.error}');

      final addedCompleter = Completer<LocalEndpointConnectionAddedEvent>();
      final removedCompleter = Completer<LocalEndpointConnectionRemovedEvent>();
      inResult.value!.setConnectionAddedCallback((event) {
        if (!addedCompleter.isCompleted) {
          addedCompleter.complete(event);
        }
      });
      inResult.value!.setConnectionRemovedCallback((event) {
        if (!removedCompleter.isCompleted) {
          removedCompleter.complete(event);
        }
      });

      final createRequestResult = await producer.createConnectionRequest(
        ConnectionRequest(
          name: requestName,
          spec: ConnectionRequestData(
            sourceRef: DataItemRef.byName(
              name: epName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(producer.entityName),
            ),
            destinationRef: DataItemRef.byName(
              name: epName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(consumer.entityName),
            ),
          ),
        ),
      );
      expect(createRequestResult.success, isTrue,
          reason:
              'Failed to create connection request: ${createRequestResult.error}');

      final addedEvent = await addedCompleter.future.timeout(
        const Duration(seconds: 3),
      );
      expect(addedEvent.connectionName, isNotEmpty);
      expect(addedEvent.peerEndpointRef.name, equals(epName));
      expect(
        addedEvent.peerEndpointRef.namespaceSelector,
        equals(NamespaceSelector.specificEntity(producer.entityName)),
      );

      final deleteRequestResult =
          await producer.deleteConnectionRequest(requestName);
      expect(deleteRequestResult.success, isTrue,
          reason:
              'Failed to delete connection request: ${deleteRequestResult.error}');

      final removedEvent = await removedCompleter.future.timeout(
        const Duration(seconds: 3),
      );
      expect(removedEvent.connectionName, equals(addedEvent.connectionName));
      expect(removedEvent.peerEndpointRef.name, equals(epName));
      expect(
        removedEvent.peerEndpointRef.namespaceSelector,
        equals(NamespaceSelector.specificEntity(producer.entityName)),
      );
    });

    test('MessageQueueFanInPollWithSenderInfoReportsSourceEndpointRef',
        () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final DogPawEntity sourceA = DogPawEntity('SenderSourceA_$suffix');
      final DogPawEntity sourceB = DogPawEntity('SenderSourceB_$suffix');
      final DogPawEntity inputOwner = DogPawEntity('SenderInput_$suffix');

      expect((await sourceA.connect()).success, isTrue);
      expect((await sourceB.connect()).success, isTrue);
      expect((await inputOwner.connect()).success, isTrue);

      addTearDown(() {
        inputOwner.disconnect();
        sourceB.disconnect();
        sourceA.disconnect();
      });

      final sourceAName = 'sender_source_a_$suffix';
      final sourceBName = 'sender_source_b_$suffix';
      final inputName = 'sender_input_$suffix';
      final requestAName = 'sender_request_a_$suffix';
      final requestBName = 'sender_request_b_$suffix';

      final sourceAResult = await sourceA.createEndpoint(EndpointInfo(
        name: sourceAName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(sourceAResult.success, isTrue,
          reason: 'Failed to create source A endpoint: ${sourceAResult.error}');

      final sourceBResult = await sourceB.createEndpoint(EndpointInfo(
        name: sourceBName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(sourceBResult.success, isTrue,
          reason: 'Failed to create source B endpoint: ${sourceBResult.error}');

      final inputResult = await inputOwner.createEndpoint(EndpointInfo(
        name: inputName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(inputResult.success, isTrue,
          reason: 'Failed to create input endpoint: ${inputResult.error}');

      final createRequestAResult = await sourceA.createConnectionRequest(
        ConnectionRequest(
          name: requestAName,
          spec: ConnectionRequestData(
            sourceRef: DataItemRef.byName(
              name: sourceAName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(sourceA.entityName),
            ),
            destinationRef: DataItemRef.byName(
              name: inputName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(inputOwner.entityName),
            ),
          ),
        ),
      );
      expect(createRequestAResult.success, isTrue,
          reason:
              'Failed to create connection request A: ${createRequestAResult.error}');

      final createRequestBResult = await sourceB.createConnectionRequest(
        ConnectionRequest(
          name: requestBName,
          spec: ConnectionRequestData(
            sourceRef: DataItemRef.byName(
              name: sourceBName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(sourceB.entityName),
            ),
            destinationRef: DataItemRef.byName(
              name: inputName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(inputOwner.entityName),
            ),
          ),
        ),
      );
      expect(createRequestBResult.success, isTrue,
          reason:
              'Failed to create connection request B: ${createRequestBResult.error}');

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        sourceAResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.setValue,
            value: 101,
          ),
        ),
        isTrue,
      );
      expect(
        sourceBResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.setValue,
            value: 202,
          ),
        ),
        isTrue,
      );

      final List<Map<String, dynamic>> received = <Map<String, dynamic>>[];
      inputResult.value!.setStatefulIntInputCallback(
        (StatefulIntAction action, EndpointSenderInfo senderInfo) {
          received.add(<String, dynamic>{
            'action': action,
            'senderInfo': senderInfo,
          });
        },
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (received.length >= 2) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(received.length, equals(2));

      final Map<String, dynamic> fromA = received.firstWhere(
        (result) =>
            (result['senderInfo'] as EndpointSenderInfo)
                .sourceEndpointRef
                .name ==
            sourceAName,
      );
      final Map<String, dynamic> fromB = received.firstWhere(
        (result) =>
            (result['senderInfo'] as EndpointSenderInfo)
                .sourceEndpointRef
                .name ==
            sourceBName,
      );

      final StatefulIntAction actionA = fromA['action'] as StatefulIntAction;
      expect(actionA.action, equals(StatefulIntActionType.setValue));
      expect(actionA.value, equals(101));
      expect((fromA['senderInfo'] as EndpointSenderInfo).connectionName, isNotEmpty);
      expect(
        (fromA['senderInfo'] as EndpointSenderInfo)
            .sourceEndpointRef
            .namespaceSelector,
        equals(NamespaceSelector.specificEntity(sourceA.entityName)),
      );

      final StatefulIntAction actionB = fromB['action'] as StatefulIntAction;
      expect(actionB.action, equals(StatefulIntActionType.setValue));
      expect(actionB.value, equals(202));
      expect((fromB['senderInfo'] as EndpointSenderInfo).connectionName, isNotEmpty);
      expect(
        (fromB['senderInfo'] as EndpointSenderInfo)
            .sourceEndpointRef
            .namespaceSelector,
        equals(NamespaceSelector.specificEntity(sourceB.entityName)),
      );
    });
  });

  group('Endpoint TOGGLE Data Type', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('TogProducer_$suffix');
      producer.setErrorCallback(
          (error) => AppLogger.error('Producer error: $error'));
      final conn1 = await producer.connect();
      expect(conn1.success, isTrue);

      consumer = DogPawEntity('TogConsumer_$suffix');
      consumer.setErrorCallback(
          (error) => AppLogger.error('Consumer error: $error'));
      final conn2 = await consumer.connect();
      expect(conn2.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('TOGGLEDataFlowProducerToConsumer', () async {
      final epName = 'tog_flow_${DateTime.now().microsecondsSinceEpoch}';

      final outResult = await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.toggle),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.input),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(outResult.success, isTrue);

      final inResult = await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(DataType.toggle),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(inResult.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 1000));

      // Write true
      final written = outResult.value!.write(
        const StatefulToggleAction(
          action: StatefulToggleActionType.setValue,
          value: true,
        ),
      );
      expect(written, isTrue, reason: 'Failed to write TOGGLE action');

      final List<StatefulToggleAction> receivedActions =
          <StatefulToggleAction>[];
      inResult.value!.setStatefulToggleInputCallback(
        (StatefulToggleAction action, EndpointSenderInfo senderInfo) {
          receivedActions.add(action);
        },
      );

      for (int attempt = 0; attempt < 20; attempt++) {
        if (receivedActions.isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(receivedActions, isNotEmpty, reason: 'No action received from TOGGLE endpoint');
      expect(receivedActions.first.action, equals(StatefulToggleActionType.setValue),
          reason: 'Received toggle action should be setValue');
      expect(receivedActions.first.value, isTrue,
          reason: 'Received toggle action should carry true');
    });
  });

  group('Stateful queue inputs', () {
    late DogPawEntity source;
    late DogPawEntity inputOwner;

    setUp(() async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();

      source = DogPawEntity('StatefulSource_$suffix');
      source.setErrorCallback(
          (error) => AppLogger.error('Stateful source error: $error'));
      final sourceConnect = await source.connect();
      expect(sourceConnect.success, isTrue,
          reason: 'Failed to connect stateful source: ${sourceConnect.error}');

      inputOwner = DogPawEntity('StatefulInput_$suffix');
      inputOwner.setErrorCallback(
          (error) => AppLogger.error('Stateful input error: $error'));
      final inputConnect = await inputOwner.connect();
      expect(inputConnect.success, isTrue,
          reason: 'Failed to connect stateful input: ${inputConnect.error}');

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      inputOwner.disconnect();
      source.disconnect();
    });

    test('StatefulFloatInputAutoReducedRetainsValueBeforeCallback', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'stateful_float_source_$suffix';
      final String inputName = 'stateful_float_input_$suffix';
      final String requestName = 'stateful_float_request_$suffix';

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
          messageQueuePayloadContract:
              MessageQueuePayloadContract.statefulFloatAction,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason:
              'Failed to create stateful float source: ${sourceResult.error}');

      final Result<LocalEndpoint> inputResult =
          await inputOwner.createEndpoint(EndpointInfo(
        name: inputName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
          messageQueuePayloadContract:
              MessageQueuePayloadContract.statefulFloatAction,
          statefulInput: EndpointStatefulInputSpec(
            behavior: StatefulInputBehavior.autoReduced,
            consumptionMode:
                StatefulInputConsumptionMode.callbackAndRetainedState,
            initialValue: 1.0,
          ),
        ),
      ));
      expect(inputResult.success, isTrue,
          reason:
              'Failed to create stateful float input: ${inputResult.error}');

      final Result<bool> createRequestResult =
          await source.createConnectionRequest(
        ConnectionRequest(
          name: requestName,
          spec: ConnectionRequestData(
            sourceRef: DataItemRef.byName(
              name: sourceName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(source.entityName),
            ),
            destinationRef: DataItemRef.byName(
              name: inputName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(inputOwner.entityName),
            ),
          ),
        ),
      );
      expect(createRequestResult.success, isTrue,
          reason:
              'Failed to create stateful float connection: ${createRequestResult.error}');

      await Future.delayed(const Duration(milliseconds: 1000));

      final List<Map<String, dynamic>> receivedActions = <Map<String, dynamic>>[];
      inputResult.value!.setStatefulFloatInputCallback(
        (StatefulFloatAction action, EndpointSenderInfo senderInfo) {
          receivedActions.add(<String, dynamic>{
            'action': action.action,
            'value': action.value,
            'retained': inputResult.value!.getRetainedStatefulFloatValue(),
            'sender': senderInfo.sourceEndpointRef.name,
          });
        },
      );

      expect(
        sourceResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.setValue,
            value: 2.0,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.add,
            value: 0.5,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.add,
            value: 0.0,
          ),
        ),
        isTrue,
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (receivedActions.length >= 3) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(receivedActions.length, equals(3));
      expect(
        receivedActions[0]['action'],
        equals(StatefulFloatActionType.setValue),
      );
      expect(receivedActions[0]['value'], equals(2.0));
      expect(receivedActions[0]['retained'], equals(2.0));
      expect(receivedActions[0]['sender'], equals(sourceName));
      expect(
        receivedActions[1]['action'],
        equals(StatefulFloatActionType.add),
      );
      expect(receivedActions[1]['value'], equals(0.5));
      expect(receivedActions[1]['retained'], equals(2.5));
      expect(receivedActions[1]['sender'], equals(sourceName));
      expect(
        receivedActions[2]['action'],
        equals(StatefulFloatActionType.add),
      );
      expect(receivedActions[2]['value'], equals(0.0));
      expect(receivedActions[2]['retained'], equals(2.5));
      expect(receivedActions[2]['sender'], equals(sourceName));
      expect(inputResult.value!.getRetainedStatefulFloatValue(), equals(2.5));
    });

    test('StatefulIntInputCallbackOnlyReportsActionsWithoutRetainedState',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'stateful_int_source_$suffix';
      final String inputName = 'stateful_int_input_$suffix';
      final String requestName = 'stateful_int_request_$suffix';

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
          messageQueuePayloadContract:
              MessageQueuePayloadContract.statefulIntAction,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason: 'Failed to create stateful int source: ${sourceResult.error}');

      final Result<LocalEndpoint> inputResult =
          await inputOwner.createEndpoint(EndpointInfo(
        name: inputName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
          messageQueuePayloadContract:
              MessageQueuePayloadContract.statefulIntAction,
          statefulInput: EndpointStatefulInputSpec(
            behavior: StatefulInputBehavior.autoReduced,
            consumptionMode: StatefulInputConsumptionMode.callbackOnly,
            initialValue: 11,
          ),
        ),
      ));
      expect(inputResult.success, isTrue,
          reason: 'Failed to create stateful int input: ${inputResult.error}');

      final Result<bool> createRequestResult =
          await source.createConnectionRequest(
        ConnectionRequest(
          name: requestName,
          spec: ConnectionRequestData(
            sourceRef: DataItemRef.byName(
              name: sourceName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(source.entityName),
            ),
            destinationRef: DataItemRef.byName(
              name: inputName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(inputOwner.entityName),
            ),
          ),
        ),
      );
      expect(createRequestResult.success, isTrue,
          reason:
              'Failed to create stateful int connection: ${createRequestResult.error}');

      await Future.delayed(const Duration(milliseconds: 1000));

      final List<Map<String, dynamic>> receivedActions = <Map<String, dynamic>>[];
      inputResult.value!.setStatefulIntInputCallback(
        (StatefulIntAction action, EndpointSenderInfo senderInfo) {
          receivedActions.add(<String, dynamic>{
            'action': action.action,
            'value': action.value,
            'sender': senderInfo.sourceEndpointRef.name,
          });
        },
      );

      expect(
        sourceResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.add,
            value: 4,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.setValue,
            value: 23,
          ),
        ),
        isTrue,
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (receivedActions.length >= 2) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(receivedActions.length, equals(2));
      expect(receivedActions[0]['action'], equals(StatefulIntActionType.add));
      expect(receivedActions[0]['value'], equals(4));
      expect(receivedActions[0]['sender'], equals(sourceName));
      expect(
        receivedActions[1]['action'],
        equals(StatefulIntActionType.setValue),
      );
      expect(receivedActions[1]['value'], equals(23));
      expect(receivedActions[1]['sender'], equals(sourceName));
      expect(inputResult.value!.getRetainedStatefulIntValue(), isNull);
    });

    test('StatefulToggleInputRetainedOnlyUpdatesWithoutCallback', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'stateful_toggle_source_$suffix';
      final String inputName = 'stateful_toggle_input_$suffix';
      final String requestName = 'stateful_toggle_request_$suffix';

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.toggle),
          category: EndpointCategory.messageQueue,
          messageQueuePayloadContract:
              MessageQueuePayloadContract.statefulToggleAction,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason:
              'Failed to create stateful toggle source: ${sourceResult.error}');

      final Result<LocalEndpoint> inputResult =
          await inputOwner.createEndpoint(EndpointInfo(
        name: inputName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.toggle),
          category: EndpointCategory.messageQueue,
          messageQueuePayloadContract:
              MessageQueuePayloadContract.statefulToggleAction,
          statefulInput: EndpointStatefulInputSpec(
            behavior: StatefulInputBehavior.autoReduced,
            consumptionMode: StatefulInputConsumptionMode.retainedStateOnly,
            initialValue: false,
          ),
        ),
      ));
      expect(inputResult.success, isTrue,
          reason:
              'Failed to create stateful toggle input: ${inputResult.error}');

      final Result<bool> createRequestResult =
          await source.createConnectionRequest(
        ConnectionRequest(
          name: requestName,
          spec: ConnectionRequestData(
            sourceRef: DataItemRef.byName(
              name: sourceName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(source.entityName),
            ),
            destinationRef: DataItemRef.byName(
              name: inputName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(inputOwner.entityName),
            ),
          ),
        ),
      );
      expect(createRequestResult.success, isTrue,
          reason:
              'Failed to create stateful toggle connection: ${createRequestResult.error}');

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        sourceResult.value!.write(
          const StatefulToggleAction(
            action: StatefulToggleActionType.setValue,
            value: true,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulToggleAction(
            action: StatefulToggleActionType.toggle,
            value: false,
          ),
        ),
        isTrue,
      );

      bool? retainedValue;
      for (int attempt = 0; attempt < 30; attempt++) {
        retainedValue = inputResult.value!.getRetainedStatefulToggleValue();
        if (retainedValue == false) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(retainedValue, isFalse);
    });

    test('CreateStatefulInputWithMatchedOutputPublishesCommittedFloatState',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'matched_source_$suffix';
      final String inputName = 'matched_input_$suffix';
      final String matchedOutputName = 'matched_output_$suffix';
      final String subscriberName = 'matched_subscriber_$suffix';
      final String sourceToInputRequestName =
          'matched_source_to_input_request_$suffix';
      final String outputToSubscriberRequestName =
          'matched_output_to_subscriber_request_$suffix';

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason: 'Failed to create matched source: ${sourceResult.error}');

      final Result<StatefulEndpointPair> pairResult =
          await inputOwner.createStatefulInputWithMatchedOutput(
        EndpointInfo(
          name: inputName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec(DataType.float),
            category: EndpointCategory.messageQueue,
            statefulInput: EndpointStatefulInputSpec(
              behavior: StatefulInputBehavior.autoReduced,
              consumptionMode:
                  StatefulInputConsumptionMode.callbackAndRetainedState,
              initialValue: 1.0,
              matchedOutput: MatchedStateOutputSpec(
                name: matchedOutputName,
                displayName: 'Matched Float State',
                description: 'Publishes accepted committed float state',
                flags: <String>['public_state'],
                groupKey: 'volume',
              ),
            ),
          ),
        ),
      );
      expect(pairResult.success, isTrue,
          reason:
              'Failed to create stateful input pair: ${pairResult.error}');
      expect(pairResult.value!.input.name, equals(inputName));
      expect(pairResult.value!.matchedOutput.name, equals(matchedOutputName));
      expect(
        pairResult.value!.matchedOutput.spec!.direction,
        equals(EndpointDirection.output),
      );
      expect(
        pairResult.value!.matchedOutput.spec!.dataType.baseType,
        equals(DataType.float),
      );

      final Result<LocalEndpoint> subscriberResult =
          await inputOwner.createEndpoint(EndpointInfo(
        name: subscriberName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(subscriberResult.success, isTrue,
          reason:
              'Failed to create matched subscriber: ${subscriberResult.error}');

      final List<Map<String, dynamic>> publishedActions = <Map<String, dynamic>>[];
      subscriberResult.value!.setStatefulFloatInputCallback(
        (StatefulFloatAction action, EndpointSenderInfo senderInfo) {
          publishedActions.add(<String, dynamic>{
            'action': action.action,
            'value': action.value,
            'sender': senderInfo.sourceEndpointRef.name,
          });
        },
      );

      final Result<bool> createSourceToInputRequest =
          await source.createConnectionRequest(
        ConnectionRequest(
          name: sourceToInputRequestName,
          spec: ConnectionRequestData(
            sourceRef: DataItemRef.byName(
              name: sourceName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(source.entityName),
            ),
            destinationRef: DataItemRef.byName(
              name: inputName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(inputOwner.entityName),
            ),
          ),
        ),
      );
      expect(createSourceToInputRequest.success, isTrue,
          reason:
              'Failed to connect source to input: ${createSourceToInputRequest.error}');

      final Result<bool> createOutputToSubscriberRequest =
          await inputOwner.createConnectionRequest(
        ConnectionRequest(
          name: outputToSubscriberRequestName,
          spec: ConnectionRequestData(
            sourceRef: DataItemRef.byName(
              name: matchedOutputName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(inputOwner.entityName),
            ),
            destinationRef: DataItemRef.byName(
              name: subscriberName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(inputOwner.entityName),
            ),
          ),
        ),
      );
      expect(createOutputToSubscriberRequest.success, isTrue,
          reason:
              'Failed to connect matched output to subscriber: ${createOutputToSubscriberRequest.error}');

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        sourceResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.setValue,
            value: 2.0,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.add,
            value: 0.5,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.add,
            value: 0.0,
          ),
        ),
        isTrue,
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (publishedActions.length >= 2) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(publishedActions.length, equals(2));
      expect(
        publishedActions[0]['action'],
        equals(StatefulFloatActionType.setValue),
      );
      expect(publishedActions[0]['value'], equals(2.0));
      expect(publishedActions[0]['sender'], equals(matchedOutputName));
      expect(
        publishedActions[1]['action'],
        equals(StatefulFloatActionType.setValue),
      );
      expect(publishedActions[1]['value'], equals(2.5));
      expect(publishedActions[1]['sender'], equals(matchedOutputName));
      expect(pairResult.value!.input.getRetainedStatefulFloatValue(), equals(2.5));
    });

    test('OwnerManagedStatefulInputDefersCommitUntilExplicitAdopt', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'owner_managed_source_$suffix';
      final String inputName = 'owner_managed_input_$suffix';
      final String matchedOutputName = 'owner_managed_output_$suffix';
      final String subscriberName = 'owner_managed_subscriber_$suffix';
      final String sourceToInputRequestName =
          'owner_managed_source_to_input_request_$suffix';
      final String outputToSubscriberRequestName =
          'owner_managed_output_to_subscriber_request_$suffix';

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason:
              'Failed to create owner-managed source: ${sourceResult.error}');

      final Result<StatefulEndpointPair> pairResult =
          await inputOwner.createStatefulInputWithMatchedOutput(
        EndpointInfo(
          name: inputName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec(DataType.float),
            category: EndpointCategory.messageQueue,
            statefulInput: EndpointStatefulInputSpec(
              behavior: StatefulInputBehavior.ownerManaged,
              consumptionMode:
                  StatefulInputConsumptionMode.callbackAndRetainedState,
              initialValue: 1.0,
              matchedOutput: MatchedStateOutputSpec(
                name: matchedOutputName,
              ),
            ),
          ),
        ),
      );
      expect(pairResult.success, isTrue,
          reason:
              'Failed to create owner-managed stateful pair: ${pairResult.error}');

      final Result<LocalEndpoint> subscriberResult =
          await inputOwner.createEndpoint(EndpointInfo(
        name: subscriberName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(subscriberResult.success, isTrue,
          reason:
              'Failed to create owner-managed subscriber: ${subscriberResult.error}');

      final List<Map<String, dynamic>> ownerActions = <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> publishedActions = <Map<String, dynamic>>[];
      pairResult.value!.input.setStatefulFloatInputCallback(
        (StatefulFloatAction action, EndpointSenderInfo senderInfo) {
          ownerActions.add(<String, dynamic>{
            'action': action.action,
            'value': action.value,
            'retained': pairResult.value!.input.getRetainedStatefulFloatValue(),
            'sender': senderInfo.sourceEndpointRef.name,
            'connectionName': senderInfo.connectionName,
          });
        },
      );
      subscriberResult.value!.setStatefulFloatInputCallback(
        (StatefulFloatAction action, EndpointSenderInfo senderInfo) {
          publishedActions.add(<String, dynamic>{
            'action': action.action,
            'value': action.value,
            'sender': senderInfo.sourceEndpointRef.name,
          });
        },
      );

      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: sourceToInputRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: sourceName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      expect(
        (await inputOwner.createConnectionRequest(
          ConnectionRequest(
            name: outputToSubscriberRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: matchedOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: subscriberName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        sourceResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.setValue,
            value: 2.0,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.add,
            value: 0.5,
          ),
        ),
        isTrue,
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (ownerActions.length >= 2) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(ownerActions.length, equals(2));
      expect(publishedActions, isEmpty);
      expect(ownerActions[0]['action'], equals(StatefulFloatActionType.setValue));
      expect(ownerActions[0]['value'], equals(2.0));
      expect(ownerActions[0]['retained'], equals(1.0));
      expect(ownerActions[0]['sender'], equals(sourceName));
      expect(ownerActions[1]['action'], equals(StatefulFloatActionType.add));
      expect(ownerActions[1]['value'], equals(0.5));
      expect(ownerActions[1]['retained'], equals(1.0));
      expect(ownerActions[1]['sender'], equals(sourceName));
      expect(pairResult.value!.input.getRetainedStatefulFloatValue(), equals(1.0));

      final EndpointSenderInfo senderInfo = EndpointSenderInfo(
        connectionName: ownerActions[1]['connectionName'] as String,
        sourceEndpointRef: DataItemRef.byName(
          name: sourceName,
          namespaceSelector: NamespaceSelector.specificEntity(source.entityName),
        ),
      );
      expect(
        pairResult.value!.input.adoptRetainedStateSnapshot(
          const EndpointRetainedStateSnapshot(
            hasState: true,
            value: 2.5,
            timestampUs: 424242,
          ),
          senderInfo: senderInfo,
        ),
        isTrue,
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (publishedActions.isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(ownerActions.length, equals(2));
      expect(publishedActions.length, equals(1));
      expect(
        publishedActions[0]['action'],
        equals(StatefulFloatActionType.setValue),
      );
      expect(publishedActions[0]['value'], equals(2.5));
      expect(publishedActions[0]['sender'], equals(matchedOutputName));
      expect(pairResult.value!.input.getRetainedStatefulFloatValue(), equals(2.5));
      expect(
        pairResult.value!.input.getRetainedStateSnapshot().timestampUs,
        equals(424242),
      );
    });

    test('OwnerManagedExplicitCommitCanSuppressMatchedOutputPublication',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String inputName = 'owner_managed_silent_input_$suffix';
      final String matchedOutputName = 'owner_managed_silent_output_$suffix';
      final String subscriberName = 'owner_managed_silent_subscriber_$suffix';
      final String outputToSubscriberRequestName =
          'owner_managed_silent_output_to_subscriber_request_$suffix';

      final Result<StatefulEndpointPair> pairResult =
          await inputOwner.createStatefulInputWithMatchedOutput(
        EndpointInfo(
          name: inputName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec(DataType.int_),
            category: EndpointCategory.messageQueue,
            statefulInput: EndpointStatefulInputSpec(
              behavior: StatefulInputBehavior.ownerManaged,
              consumptionMode: StatefulInputConsumptionMode.retainedStateOnly,
              initialValue: 0,
              matchedOutput: MatchedStateOutputSpec(
                name: matchedOutputName,
              ),
            ),
          ),
        ),
      );
      expect(pairResult.success, isTrue,
          reason:
              'Failed to create silent owner-managed stateful pair: ${pairResult.error}');

      final Result<LocalEndpoint> subscriberResult =
          await inputOwner.createEndpoint(EndpointInfo(
        name: subscriberName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(subscriberResult.success, isTrue,
          reason:
              'Failed to create silent owner-managed subscriber: ${subscriberResult.error}');

      final List<int> publishedValues = <int>[];
      subscriberResult.value!.setStatefulIntInputCallback(
        (StatefulIntAction action, EndpointSenderInfo senderInfo) {
          publishedValues.add(action.value);
        },
      );

      expect(
        (await inputOwner.createConnectionRequest(
          ConnectionRequest(
            name: outputToSubscriberRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: matchedOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: subscriberName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        pairResult.value!.input.adoptRetainedStateSnapshot(
          const EndpointRetainedStateSnapshot(
            hasState: true,
            value: 9,
            timestampUs: 111,
          ),
          publishMatchedOutput: false,
        ),
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 300));

      expect(publishedValues, isEmpty);
      expect(pairResult.value!.input.getRetainedStatefulIntValue(), equals(9));
      expect(
        pairResult.value!.input.getRetainedStateSnapshot().timestampUs,
        equals(111),
      );
    });

    test('MatchedOutputPublishesCommittedStateToMultipleSubscribers', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'matched_multi_source_$suffix';
      final String inputName = 'matched_multi_input_$suffix';
      final String matchedOutputName = 'matched_multi_output_$suffix';
      final String subscriberAName = 'matched_multi_subscriber_a_$suffix';
      final String subscriberBName = 'matched_multi_subscriber_b_$suffix';
      final String sourceToInputRequestName =
          'matched_multi_source_to_input_request_$suffix';
      final String outputToSubscriberARequestName =
          'matched_multi_output_to_subscriber_a_request_$suffix';
      final String outputToSubscriberBRequestName =
          'matched_multi_output_to_subscriber_b_request_$suffix';
      final DogPawEntity subscriberBOwner =
          DogPawEntity('MatchedMultiSubscriberB_$suffix');
      subscriberBOwner.setErrorCallback(
        (error) => AppLogger.error('Matched multi subscriber B error: $error'),
      );
      final subscriberBConnect = await subscriberBOwner.connect();
      expect(subscriberBConnect.success, isTrue,
          reason:
              'Failed to connect matched multi subscriber B: ${subscriberBConnect.error}');
      addTearDown(() => subscriberBOwner.disconnect());

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason: 'Failed to create matched multi source: ${sourceResult.error}');

      final Result<StatefulEndpointPair> pairResult =
          await inputOwner.createStatefulInputWithMatchedOutput(
        EndpointInfo(
          name: inputName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec(DataType.int_),
            category: EndpointCategory.messageQueue,
            statefulInput: EndpointStatefulInputSpec(
              behavior: StatefulInputBehavior.autoReduced,
              consumptionMode:
                  StatefulInputConsumptionMode.retainedStateOnly,
              initialValue: 0,
              matchedOutput: MatchedStateOutputSpec(
                name: matchedOutputName,
              ),
            ),
          ),
        ),
      );
      expect(pairResult.success, isTrue,
          reason:
              'Failed to create matched multi input pair: ${pairResult.error}');

      final Result<LocalEndpoint> subscriberAResult =
          await source.createEndpoint(EndpointInfo(
        name: subscriberAName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(subscriberAResult.success, isTrue,
          reason:
              'Failed to create matched multi subscriber A: ${subscriberAResult.error}');

      final Result<LocalEndpoint> subscriberBResult =
          await subscriberBOwner.createEndpoint(EndpointInfo(
        name: subscriberBName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(subscriberBResult.success, isTrue,
          reason:
              'Failed to create matched multi subscriber B: ${subscriberBResult.error}');

      final List<int> valuesA = <int>[];
      final List<int> valuesB = <int>[];
      subscriberAResult.value!.setStatefulIntInputCallback(
        (StatefulIntAction action, EndpointSenderInfo senderInfo) {
          valuesA.add(action.value);
        },
      );
      subscriberBResult.value!.setStatefulIntInputCallback(
        (StatefulIntAction action, EndpointSenderInfo senderInfo) {
          valuesB.add(action.value);
        },
      );

      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: sourceToInputRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: sourceName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      expect(
        (await inputOwner.createConnectionRequest(
          ConnectionRequest(
            name: outputToSubscriberARequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: matchedOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: subscriberAName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      expect(
        (await inputOwner.createConnectionRequest(
          ConnectionRequest(
            name: outputToSubscriberBRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: matchedOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: subscriberBName,
                namespaceSelector: NamespaceSelector.specificEntity(
                  subscriberBOwner.entityName,
                ),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        sourceResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.add,
            value: 4,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.setValue,
            value: 23,
          ),
        ),
        isTrue,
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (valuesA.length >= 2 && valuesB.length >= 2) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(valuesA, equals(<int>[4, 23]));
      expect(valuesB, equals(<int>[4, 23]));
    });

    test('ShimBackedMatchedOutputPublishesCommittedState', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'matched_shim_source_$suffix';
      final String inputName = 'matched_shim_input_$suffix';
      final String matchedOutputName = 'matched_shim_output_$suffix';
      final String shimOutputName = 'matched_shim_public_$suffix';
      final String subscriberName = 'matched_shim_subscriber_$suffix';
      final String sourceToInputRequestName =
          'matched_shim_source_to_input_request_$suffix';
      final String shimToSubscriberRequestName =
          'matched_shim_to_subscriber_request_$suffix';
      final DogPawEntity subscriberOwner =
          DogPawEntity('MatchedShimSubscriber_$suffix');
      subscriberOwner.setErrorCallback(
        (error) => AppLogger.error('Matched shim subscriber error: $error'),
      );
      final subscriberConnect = await subscriberOwner.connect();
      expect(subscriberConnect.success, isTrue,
          reason:
              'Failed to connect matched shim subscriber: ${subscriberConnect.error}');
      addTearDown(() => subscriberOwner.disconnect());

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.toggle),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason: 'Failed to create matched shim source: ${sourceResult.error}');

      final Result<StatefulEndpointPair> pairResult =
          await inputOwner.createStatefulInputWithMatchedOutput(
        EndpointInfo(
          name: inputName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec(DataType.toggle),
            category: EndpointCategory.messageQueue,
            statefulInput: EndpointStatefulInputSpec(
              behavior: StatefulInputBehavior.autoReduced,
              consumptionMode:
                  StatefulInputConsumptionMode.retainedStateOnly,
              initialValue: false,
              matchedOutput: MatchedStateOutputSpec(name: matchedOutputName),
            ),
          ),
        ),
      );
      expect(pairResult.success, isTrue,
          reason:
              'Failed to create matched shim input pair: ${pairResult.error}');

      final Result<LocalEndpoint> shimResult =
          await inputOwner.createEndpoint(EndpointInfo(
        name: shimOutputName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.toggle),
          category: EndpointCategory.messageQueue,
          shimTargetRef: DataItemRef.byName(
            name: matchedOutputName,
            namespaceSelector:
                NamespaceSelector.specificEntity(inputOwner.entityName),
          ),
        ),
      ));
      expect(shimResult.success, isTrue,
          reason: 'Failed to create matched shim output: ${shimResult.error}');

      final Result<LocalEndpoint> subscriberResult =
          await subscriberOwner.createEndpoint(EndpointInfo(
        name: subscriberName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.toggle),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(subscriberResult.success, isTrue,
          reason:
              'Failed to create matched shim subscriber endpoint: ${subscriberResult.error}');

      final List<Map<String, dynamic>> values = <Map<String, dynamic>>[];
      subscriberResult.value!.setStatefulToggleInputCallback(
        (StatefulToggleAction action, EndpointSenderInfo senderInfo) {
          values.add(<String, dynamic>{
            'value': action.value,
            'sender': senderInfo.sourceEndpointRef.name,
          });
        },
      );

      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: sourceToInputRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: sourceName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      expect(
        (await inputOwner.createConnectionRequest(
          ConnectionRequest(
            name: shimToSubscriberRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: shimOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: subscriberName,
                namespaceSelector: NamespaceSelector.specificEntity(
                  subscriberOwner.entityName,
                ),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        sourceResult.value!.write(
          const StatefulToggleAction(
            action: StatefulToggleActionType.setValue,
            value: true,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulToggleAction(
            action: StatefulToggleActionType.toggle,
            value: false,
          ),
        ),
        isTrue,
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (values.length >= 2) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(values.length, equals(2));
      expect(values[0]['sender'], equals(shimOutputName));
      expect(values[0]['value'], isTrue);
      expect(values[1]['sender'], equals(shimOutputName));
      expect(values[1]['value'], isFalse);
    });

    test('QueryEndpointRetainedStateReturnsTimestampForLastSetValue',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String outputName = 'retained_query_output_$suffix';

      final Result<LocalEndpoint> outputResult =
          await source.createEndpoint(EndpointInfo(
        name: outputName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(outputResult.success, isTrue,
          reason:
              'Failed to create retained query output: ${outputResult.error}');

      expect(
        outputResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.setValue,
            value: 1.25,
          ),
        ),
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final Result<EndpointRetainedStateSnapshot> queryResult =
          await inputOwner.queryEndpointRetainedState(
        outputName,
        namespaceSelector: NamespaceSelector.specificEntity(source.entityName),
      );
      expect(queryResult.success, isTrue,
          reason:
              'Failed to query retained state: ${queryResult.error}');
      expect(queryResult.value!.hasState, isTrue);
      expect(queryResult.value!.value, equals(1.25));
      expect(queryResult.value!.timestampUs, isNotNull);
      expect(queryResult.value!.timestampUs!, greaterThan(0));
      expect(outputResult.value!.getRetainedStateSnapshot().hasState, isTrue);
      expect(outputResult.value!.getRetainedStateSnapshot().value, equals(1.25));
      expect(outputResult.value!.getRetainedStateSnapshot().timestampUs, isNotNull);
    });

    test('QueryEndpointRetainedStateInvalidatesAfterDeltaAction', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String outputName = 'retained_query_invalidated_$suffix';

      final Result<LocalEndpoint> outputResult =
          await source.createEndpoint(EndpointInfo(
        name: outputName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(outputResult.success, isTrue,
          reason:
              'Failed to create retained invalidation output: ${outputResult.error}');

      expect(
        outputResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.setValue,
            value: 12,
          ),
        ),
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final initialQueryResult = await inputOwner.queryEndpointRetainedState(
        outputName,
        namespaceSelector: NamespaceSelector.specificEntity(source.entityName),
      );
      expect(initialQueryResult.success, isTrue);
      expect(initialQueryResult.value!.hasState, isTrue);

      expect(
        outputResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.add,
            value: 3,
          ),
        ),
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final invalidatedQueryResult =
          await inputOwner.queryEndpointRetainedState(
        outputName,
        namespaceSelector: NamespaceSelector.specificEntity(source.entityName),
      );
      expect(invalidatedQueryResult.success, isTrue);
      expect(invalidatedQueryResult.value!.hasState, isFalse);
      expect(invalidatedQueryResult.value!.value, isNull);
      expect(invalidatedQueryResult.value!.timestampUs, isNull);
      expect(outputResult.value!.getRetainedStateSnapshot().hasState, isFalse);
      expect(outputResult.value!.getRetainedStateSnapshot().value, isNull);
      expect(outputResult.value!.getRetainedStateSnapshot().timestampUs, isNull);
    });

    test('QueryEndpointRetainedStateUsesManualResponderCallback', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String outputName = 'manual_retained_output_$suffix';

      final Result<LocalEndpoint> outputResult =
          await source.createEndpoint(EndpointInfo(
        name: outputName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.toggle),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(outputResult.success, isTrue,
          reason:
              'Failed to create manual retained output: ${outputResult.error}');

      source.registerEndpointRetainedStateQueryCallback(
        outputName,
        (LocalEndpoint endpoint) => const EndpointRetainedStateSnapshot(
          hasState: true,
          value: true,
          timestampUs: 424242,
        ),
      );
      addTearDown(
        () => source.clearEndpointRetainedStateQueryCallback(outputName),
      );

      final queryResult = await inputOwner.queryEndpointRetainedState(
        outputName,
        namespaceSelector: NamespaceSelector.specificEntity(source.entityName),
      );
      expect(queryResult.success, isTrue);
      expect(queryResult.value!.hasState, isTrue);
      expect(queryResult.value!.value, isTrue);
      expect(queryResult.value!.timestampUs, equals(424242));
    });

    test('StatefulInputBootstrapsFromFirstConnectedOutputOnlyOnce', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String outputAName = 'bootstrap_output_a_$suffix';
      final String outputBName = 'bootstrap_output_b_$suffix';
      final String inputName = 'bootstrap_input_$suffix';
      final String requestAName = 'bootstrap_request_a_$suffix';
      final String requestBName = 'bootstrap_request_b_$suffix';
      final DogPawEntity otherSource = DogPawEntity('BootstrapSourceB_$suffix');
      otherSource.setErrorCallback(
        (error) => AppLogger.error('Bootstrap source B error: $error'),
      );
      final otherConnect = await otherSource.connect();
      expect(otherConnect.success, isTrue,
          reason:
              'Failed to connect bootstrap source B: ${otherConnect.error}');
      addTearDown(() => otherSource.disconnect());

      final outputAResult = await source.createEndpoint(EndpointInfo(
        name: outputAName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(outputAResult.success, isTrue);

      final outputBResult = await otherSource.createEndpoint(EndpointInfo(
        name: outputBName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(outputBResult.success, isTrue);

      expect(
        outputAResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.setValue,
            value: 4.0,
          ),
        ),
        isTrue,
      );
      expect(
        outputBResult.value!.write(
          const StatefulFloatAction(
            action: StatefulFloatActionType.setValue,
            value: 9.0,
          ),
        ),
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final inputResult = await inputOwner.createEndpoint(EndpointInfo(
        name: inputName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
          statefulInput: EndpointStatefulInputSpec(
            behavior: StatefulInputBehavior.autoReduced,
            consumptionMode: StatefulInputConsumptionMode.retainedStateOnly,
            initialValue: 0.0,
          ),
        ),
      ));
      expect(inputResult.success, isTrue,
          reason: 'Failed to create bootstrap input: ${inputResult.error}');

      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: requestAName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: outputAName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      double? retainedValue;
      for (int attempt = 0; attempt < 30; attempt++) {
        retainedValue = inputResult.value!.getRetainedStatefulFloatValue();
        if (retainedValue == 4.0) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      expect(retainedValue, equals(4.0));

      expect(
        (await otherSource.createConnectionRequest(
          ConnectionRequest(
            name: requestBName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: outputBName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(otherSource.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      expect(inputResult.value!.getRetainedStatefulFloatValue(), equals(4.0));
    });

    test('CreateStatefulInputWithMatchedOutputPublishesCommittedEnumState',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'enum_source_$suffix';
      final String inputName = 'enum_input_$suffix';
      final String matchedOutputName = 'enum_output_$suffix';
      final String subscriberName = 'enum_subscriber_$suffix';
      final String sourceToInputRequestName = 'enum_source_to_input_$suffix';
      final String outputToSubscriberRequestName =
          'enum_output_to_subscriber_$suffix';
      final List<EnumOption> enumOptions = const <EnumOption>[
        EnumOption(id: 2, label: 'Clean'),
        EnumOption(id: 7, label: 'Crunch'),
        EnumOption(id: 11, label: 'Lead'),
      ];

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec.createEnum(enumOptions),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason: 'Failed to create enum source: ${sourceResult.error}');

      final Result<StatefulEndpointPair> pairResult =
          await inputOwner.createStatefulInputWithMatchedOutput(
        EndpointInfo(
          name: inputName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec.createEnum(enumOptions),
            category: EndpointCategory.messageQueue,
            statefulInput: EndpointStatefulInputSpec(
              behavior: StatefulInputBehavior.autoReduced,
              consumptionMode:
                  StatefulInputConsumptionMode.callbackAndRetainedState,
              initialValue: 2,
              matchedOutput: MatchedStateOutputSpec(name: matchedOutputName),
            ),
          ),
        ),
      );
      expect(pairResult.success, isTrue,
          reason:
              'Failed to create enum stateful endpoint pair: ${pairResult.error}');

      final Result<LocalEndpoint> subscriberResult =
          await source.createEndpoint(EndpointInfo(
        name: subscriberName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec.createEnum(enumOptions),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(subscriberResult.success, isTrue,
          reason:
              'Failed to create enum subscriber endpoint: ${subscriberResult.error}');
      final List<int> observedIds = <int>[];
      subscriberResult.value!.setStatefulEnumInputCallback(
        (StatefulEnumAction action, EndpointSenderInfo senderInfo) {
          observedIds.add(action.value);
        },
      );

      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: sourceToInputRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: sourceName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: outputToSubscriberRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: matchedOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: subscriberName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        sourceResult.value!.write(
          const StatefulEnumAction(
            action: StatefulEnumActionType.step,
            value: 1,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulEnumAction(
            action: StatefulEnumActionType.step,
            value: 1,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulEnumAction(
            action: StatefulEnumActionType.step,
            value: 1,
          ),
        ),
        isTrue,
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (observedIds.length >= 3) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(observedIds, equals(<int>[7, 11, 2]));

      final Result<EndpointRetainedStateSnapshot> queryResult =
          await source.queryEndpointRetainedState(
        matchedOutputName,
        namespaceSelector:
            NamespaceSelector.specificEntity(inputOwner.entityName),
      );
      expect(queryResult.success, isTrue);
      expect(queryResult.value!.hasState, isTrue);
      expect(queryResult.value!.value, equals(2));
    });

    test('StatefulEnumInputAcceptsCompatibleIntActionsAndDefinesEdgeCases',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'int_enum_source_$suffix';
      final String inputName = 'int_enum_input_$suffix';
      final String matchedOutputName = 'int_enum_output_$suffix';
      final String subscriberName = 'int_enum_subscriber_$suffix';
      final String sourceToInputRequestName = 'int_enum_source_to_input_$suffix';
      final String outputToSubscriberRequestName =
          'int_enum_output_to_subscriber_$suffix';
      final List<EnumOption> enumOptions = const <EnumOption>[
        EnumOption(id: 2, label: 'Clean'),
        EnumOption(id: 7, label: 'Crunch'),
        EnumOption(id: 11, label: 'Lead'),
      ];

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason: 'Failed to create int source: ${sourceResult.error}');

      final Result<StatefulEndpointPair> pairResult =
          await inputOwner.createStatefulInputWithMatchedOutput(
        EndpointInfo(
          name: inputName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec.createEnum(enumOptions),
            category: EndpointCategory.messageQueue,
            statefulInput: EndpointStatefulInputSpec(
              behavior: StatefulInputBehavior.autoReduced,
              consumptionMode:
                  StatefulInputConsumptionMode.callbackAndRetainedState,
              initialValue: 2,
              matchedOutput: MatchedStateOutputSpec(name: matchedOutputName),
            ),
          ),
        ),
      );
      expect(pairResult.success, isTrue,
          reason:
              'Failed to create int->enum stateful endpoint pair: ${pairResult.error}');

      final Result<LocalEndpoint> subscriberResult =
          await source.createEndpoint(EndpointInfo(
        name: subscriberName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec.createEnum(enumOptions),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(subscriberResult.success, isTrue,
          reason:
              'Failed to create enum subscriber endpoint: ${subscriberResult.error}');

      final List<StatefulEnumAction> observedActions = <StatefulEnumAction>[];
      final List<int> observedCommittedIds = <int>[];
      pairResult.value!.input.setStatefulEnumInputCallback(
        (StatefulEnumAction action, EndpointSenderInfo senderInfo) {
          observedActions.add(action);
        },
      );
      subscriberResult.value!.setStatefulEnumInputCallback(
        (StatefulEnumAction action, EndpointSenderInfo senderInfo) {
          if (action.action == StatefulEnumActionType.setId) {
            observedCommittedIds.add(action.value);
          }
        },
      );

      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: sourceToInputRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: sourceName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: outputToSubscriberRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: matchedOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: subscriberName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        sourceResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.add,
            value: 1,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.add,
            value: 2,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.add,
            value: 0,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.setValue,
            value: 11,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.setValue,
            value: 999,
          ),
        ),
        isTrue,
      );

      for (int attempt = 0;
          attempt < 30 &&
              (observedActions.length < 5 || observedCommittedIds.length < 3);
          attempt++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(observedActions.length, equals(5));
      expect(observedActions[0].action, equals(StatefulEnumActionType.step));
      expect(observedActions[0].value, equals(1));
      expect(observedActions[1].action, equals(StatefulEnumActionType.step));
      expect(observedActions[1].value, equals(2));
      expect(observedActions[2].action, equals(StatefulEnumActionType.step));
      expect(observedActions[2].value, equals(0));
      expect(observedActions[3].action, equals(StatefulEnumActionType.setId));
      expect(observedActions[3].value, equals(11));
      expect(observedActions[4].action, equals(StatefulEnumActionType.setId));
      expect(observedActions[4].value, equals(999));
      expect(observedCommittedIds, equals(<int>[7, 2, 11]));

      final retainedInputResult = await source.queryEndpointRetainedState(
        inputName,
        namespaceSelector:
            NamespaceSelector.specificEntity(inputOwner.entityName),
      );
      expect(retainedInputResult.success, isTrue);
      expect(retainedInputResult.value!.hasState, isTrue);
      expect(retainedInputResult.value!.value, equals(11));

      final retainedOutputResult = await source.queryEndpointRetainedState(
        matchedOutputName,
        namespaceSelector:
            NamespaceSelector.specificEntity(inputOwner.entityName),
      );
      expect(retainedOutputResult.success, isTrue);
      expect(retainedOutputResult.value!.hasState, isTrue);
      expect(retainedOutputResult.value!.value, equals(11));
    });

    test('StatefulEnumBootstrapAdoptsValidIntStateAndRejectsInvalidIntState',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final List<EnumOption> enumOptions = const <EnumOption>[
        EnumOption(id: 2, label: 'Clean'),
        EnumOption(id: 7, label: 'Crunch'),
        EnumOption(id: 11, label: 'Lead'),
      ];

      final String validOutputName = 'int_enum_valid_output_$suffix';
      final validOutputResult = await source.createEndpoint(EndpointInfo(
        name: validOutputName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(validOutputResult.success, isTrue);
      expect(
        validOutputResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.setValue,
            value: 7,
          ),
        ),
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final String validInputName = 'int_enum_valid_input_$suffix';
      final validInputResult = await inputOwner.createEndpoint(EndpointInfo(
        name: validInputName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec.createEnum(enumOptions),
          category: EndpointCategory.messageQueue,
          statefulInput: const EndpointStatefulInputSpec(
            behavior: StatefulInputBehavior.autoReduced,
            consumptionMode: StatefulInputConsumptionMode.retainedStateOnly,
            initialValue: 2,
          ),
        ),
      ));
      expect(validInputResult.success, isTrue);

      final String validRequestName = 'int_enum_valid_request_$suffix';
      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: validRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: validOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: validInputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 500));

      final validBootstrapResult = await source.queryEndpointRetainedState(
        validInputName,
        namespaceSelector:
            NamespaceSelector.specificEntity(inputOwner.entityName),
      );
      expect(validBootstrapResult.success, isTrue);
      expect(validBootstrapResult.value!.hasState, isTrue);
      expect(validBootstrapResult.value!.value, equals(7));

      final String invalidOutputName = 'int_enum_invalid_output_$suffix';
      final invalidOutputResult = await source.createEndpoint(EndpointInfo(
        name: invalidOutputName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(invalidOutputResult.success, isTrue);
      expect(
        invalidOutputResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.setValue,
            value: 999,
          ),
        ),
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final String invalidInputName = 'int_enum_invalid_input_$suffix';
      final invalidInputResult = await inputOwner.createEndpoint(EndpointInfo(
        name: invalidInputName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec.createEnum(enumOptions),
          category: EndpointCategory.messageQueue,
          statefulInput: const EndpointStatefulInputSpec(
            behavior: StatefulInputBehavior.autoReduced,
            consumptionMode: StatefulInputConsumptionMode.retainedStateOnly,
            initialValue: 2,
          ),
        ),
      ));
      expect(invalidInputResult.success, isTrue);

      final String invalidRequestName = 'int_enum_invalid_request_$suffix';
      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: invalidRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: invalidOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: invalidInputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 500));

      final invalidBootstrapResult = await source.queryEndpointRetainedState(
        invalidInputName,
        namespaceSelector:
            NamespaceSelector.specificEntity(inputOwner.entityName),
      );
      expect(invalidBootstrapResult.success, isTrue);
      expect(invalidBootstrapResult.value!.hasState, isTrue);
      expect(invalidBootstrapResult.value!.value, equals(2));

      final String addOutputName = 'int_enum_add_output_$suffix';
      final addOutputResult = await source.createEndpoint(EndpointInfo(
        name: addOutputName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.int_),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(addOutputResult.success, isTrue);
      expect(
        addOutputResult.value!.write(
          const StatefulIntAction(
            action: StatefulIntActionType.add,
            value: 1,
          ),
        ),
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final String addInputName = 'int_enum_add_input_$suffix';
      final addInputResult = await inputOwner.createEndpoint(EndpointInfo(
        name: addInputName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec.createEnum(enumOptions),
          category: EndpointCategory.messageQueue,
          statefulInput: const EndpointStatefulInputSpec(
            behavior: StatefulInputBehavior.autoReduced,
            consumptionMode: StatefulInputConsumptionMode.retainedStateOnly,
            initialValue: 2,
          ),
        ),
      ));
      expect(addInputResult.success, isTrue);

      final String addRequestName = 'int_enum_add_request_$suffix';
      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: addRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: addOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: addInputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 500));

      final addBootstrapResult = await source.queryEndpointRetainedState(
        addInputName,
        namespaceSelector:
            NamespaceSelector.specificEntity(inputOwner.entityName),
      );
      expect(addBootstrapResult.success, isTrue);
      expect(addBootstrapResult.value!.hasState, isTrue);
      expect(addBootstrapResult.value!.value, equals(2));
    });

    test('QueryEndpointRetainedStateInvalidatesAfterEnumMetadataChange',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String outputName = 'enum_metadata_output_$suffix';
      final List<EnumOption> originalOptions = const <EnumOption>[
        EnumOption(id: 2, label: 'Clean'),
        EnumOption(id: 7, label: 'Crunch'),
      ];
      final List<EnumOption> updatedOptions = const <EnumOption>[
        EnumOption(id: 100, label: 'Mono'),
        EnumOption(id: 200, label: 'Stereo'),
      ];

      final Result<LocalEndpoint> outputResult =
          await source.createEndpoint(EndpointInfo(
        name: outputName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec.createEnum(originalOptions),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(outputResult.success, isTrue,
          reason:
              'Failed to create enum metadata output: ${outputResult.error}');

      expect(
        outputResult.value!.write(
          const StatefulEnumAction(
            action: StatefulEnumActionType.setId,
            value: 7,
          ),
        ),
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final initialQueryResult = await inputOwner.queryEndpointRetainedState(
        outputName,
        namespaceSelector: NamespaceSelector.specificEntity(source.entityName),
      );
      expect(initialQueryResult.success, isTrue);
      expect(initialQueryResult.value!.hasState, isTrue);
      expect(initialQueryResult.value!.value, equals(7));

      final updateResult = await source.setEndpoint(EndpointInfo(
        name: outputName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec.createEnum(updatedOptions),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(updateResult.success, isTrue,
          reason:
              'Failed to update enum metadata output: ${updateResult.error}');

      final invalidatedQueryResult =
          await inputOwner.queryEndpointRetainedState(
        outputName,
        namespaceSelector: NamespaceSelector.specificEntity(source.entityName),
      );
      expect(invalidatedQueryResult.success, isTrue);
      expect(invalidatedQueryResult.value!.hasState, isFalse);
      expect(invalidatedQueryResult.value!.value, isNull);
      expect(invalidatedQueryResult.value!.timestampUs, isNull);
      expect(outputResult.value!.getRetainedStateSnapshot().hasState, isFalse);
      expect(outputResult.value!.getRetainedStateSnapshot().value, isNull);
      expect(outputResult.value!.getRetainedStateSnapshot().timestampUs, isNull);
    });

    test('StatefulEnumBootstrapIgnoresInvalidatedOutputState', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String invalidOutputName = 'enum_invalid_output_$suffix';
      final String validOutputName = 'enum_valid_output_$suffix';
      final String inputName = 'enum_bootstrap_input_$suffix';
      final String invalidRequestName = 'enum_invalid_request_$suffix';
      final String validRequestName = 'enum_valid_request_$suffix';
      final List<EnumOption> originalOptions = const <EnumOption>[
        EnumOption(id: 2, label: 'Clean'),
        EnumOption(id: 7, label: 'Crunch'),
      ];
      final List<EnumOption> updatedOptions = const <EnumOption>[
        EnumOption(id: 100, label: 'Mono'),
        EnumOption(id: 200, label: 'Stereo'),
      ];
      final List<EnumOption> validOptions = const <EnumOption>[
        EnumOption(id: 2, label: 'Clean'),
        EnumOption(id: 7, label: 'Crunch'),
        EnumOption(id: 11, label: 'Lead'),
      ];
      final DogPawEntity otherSource = DogPawEntity('EnumBootstrapSource_$suffix');
      otherSource.setErrorCallback(
        (error) => AppLogger.error('Enum bootstrap source B error: $error'),
      );
      final otherConnect = await otherSource.connect();
      expect(otherConnect.success, isTrue,
          reason:
              'Failed to connect enum bootstrap source B: ${otherConnect.error}');
      addTearDown(() => otherSource.disconnect());

      final invalidOutputResult = await source.createEndpoint(EndpointInfo(
        name: invalidOutputName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec.createEnum(originalOptions),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(invalidOutputResult.success, isTrue);
      expect(
        invalidOutputResult.value!.write(
          const StatefulEnumAction(
            action: StatefulEnumActionType.setId,
            value: 7,
          ),
        ),
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final invalidUpdateResult = await source.setEndpoint(EndpointInfo(
        name: invalidOutputName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec.createEnum(updatedOptions),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(invalidUpdateResult.success, isTrue);

      final validOutputResult = await otherSource.createEndpoint(EndpointInfo(
        name: validOutputName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec.createEnum(validOptions),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(validOutputResult.success, isTrue);
      expect(
        validOutputResult.value!.write(
          const StatefulEnumAction(
            action: StatefulEnumActionType.setId,
            value: 11,
          ),
        ),
        isTrue,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final inputResult = await inputOwner.createEndpoint(EndpointInfo(
        name: inputName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec.createEnum(validOptions),
          category: EndpointCategory.messageQueue,
          statefulInput: EndpointStatefulInputSpec(
            behavior: StatefulInputBehavior.autoReduced,
            consumptionMode: StatefulInputConsumptionMode.retainedStateOnly,
            initialValue: 2,
          ),
        ),
      ));
      expect(inputResult.success, isTrue,
          reason:
              'Failed to create enum bootstrap input: ${inputResult.error}');

      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: invalidRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: invalidOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      final bootstrapQueryResult = await inputOwner.queryEndpointRetainedState(
        inputName,
        namespaceSelector:
            NamespaceSelector.specificEntity(inputOwner.entityName),
      );
      expect(bootstrapQueryResult.success, isTrue);
      expect(bootstrapQueryResult.value!.hasState, isTrue);
      expect(bootstrapQueryResult.value!.value, equals(2));

      expect(
        (await otherSource.createConnectionRequest(
          ConnectionRequest(
            name: validRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: validOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(otherSource.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      final laterQueryResult = await inputOwner.queryEndpointRetainedState(
        inputName,
        namespaceSelector:
            NamespaceSelector.specificEntity(inputOwner.entityName),
      );
      expect(laterQueryResult.success, isTrue);
      expect(laterQueryResult.value!.hasState, isTrue);
      expect(laterQueryResult.value!.value, equals(2));
    });

    test('CreateStatefulInputWithMatchedOutputPublishesCommittedColorState',
        () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'color_source_$suffix';
      final String inputName = 'color_input_$suffix';
      final String matchedOutputName = 'color_output_$suffix';
      final String subscriberName = 'color_subscriber_$suffix';
      final String sourceToInputRequestName = 'color_source_to_input_$suffix';
      final String outputToSubscriberRequestName =
          'color_output_to_subscriber_$suffix';

      final Result<LocalEndpoint> sourceResult =
          await source.createEndpoint(EndpointInfo(
        name: sourceName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.color),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(sourceResult.success, isTrue,
          reason: 'Failed to create color source: ${sourceResult.error}');

      final Result<StatefulEndpointPair> pairResult =
          await inputOwner.createStatefulInputWithMatchedOutput(
        EndpointInfo(
          name: inputName,
          spec: EndpointSpec(
            direction: EndpointDirection.input,
            dataType: const DataTypeSpec(DataType.color),
            category: EndpointCategory.messageQueue,
            statefulInput: EndpointStatefulInputSpec(
              behavior: StatefulInputBehavior.autoReduced,
              consumptionMode:
                  StatefulInputConsumptionMode.callbackAndRetainedState,
              initialValue: 0xff000000,
              matchedOutput: MatchedStateOutputSpec(name: matchedOutputName),
            ),
          ),
        ),
      );
      expect(pairResult.success, isTrue,
          reason:
              'Failed to create color stateful endpoint pair: ${pairResult.error}');

      final Result<LocalEndpoint> subscriberResult =
          await source.createEndpoint(EndpointInfo(
        name: subscriberName,
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.color),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(subscriberResult.success, isTrue,
          reason:
              'Failed to create color subscriber endpoint: ${subscriberResult.error}');
      final List<int> observedColors = <int>[];
      subscriberResult.value!.setStatefulColorInputCallback(
        (StatefulColorAction action, EndpointSenderInfo senderInfo) {
          observedColors.add(action.value);
        },
      );

      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: sourceToInputRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: sourceName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );
      expect(
        (await source.createConnectionRequest(
          ConnectionRequest(
            name: outputToSubscriberRequestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: matchedOutputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: subscriberName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
            ),
          ),
        ))
            .success,
        isTrue,
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      expect(
        sourceResult.value!.write(
          const StatefulColorAction(
            action: StatefulColorActionType.setValue,
            value: 0xff336699,
          ),
        ),
        isTrue,
      );
      expect(
        sourceResult.value!.write(
          const StatefulColorAction(
            action: StatefulColorActionType.setValue,
            value: 0xff112233,
          ),
        ),
        isTrue,
      );

      for (int attempt = 0; attempt < 30; attempt++) {
        if (observedColors.length >= 2) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(observedColors, equals(<int>[0xff336699, 0xff112233]));

      final Result<EndpointRetainedStateSnapshot> queryResult =
          await source.queryEndpointRetainedState(
        matchedOutputName,
        namespaceSelector:
            NamespaceSelector.specificEntity(inputOwner.entityName),
      );
      expect(queryResult.success, isTrue);
      expect(queryResult.value!.hasState, isTrue);
      expect(queryResult.value!.value, equals(0xff112233));
    });

    test('Scalar queue defaults to action contract and callback without '
        'statefulInput', () async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String sourceName = 'default_action_source_$suffix';
      final String inputName = 'default_action_input_$suffix';
      final String requestName = 'default_action_request_$suffix';
      final DogPawEntity observer = DogPawEntity('DefaultActionObserver_$suffix');
      observer.setErrorCallback(
        (error) => AppLogger.error('Default action observer error: $error'),
      );
      final observerConnect = await observer.connect();
      expect(observerConnect.success, isTrue,
          reason:
              'Failed to connect default action observer: ${observerConnect.error}');

      try {
        final Result<LocalEndpoint> sourceResult =
            await source.createEndpoint(EndpointInfo(
          name: sourceName,
          spec: const EndpointSpec(
            direction: EndpointDirection.output,
            dataType: DataTypeSpec(DataType.float),
            category: EndpointCategory.messageQueue,
          ),
        ));
        expect(sourceResult.success, isTrue,
            reason:
                'Failed to create default action source: ${sourceResult.error}');

        final Result<LocalEndpoint> inputResult =
            await inputOwner.createEndpoint(EndpointInfo(
          name: inputName,
          spec: const EndpointSpec(
            direction: EndpointDirection.input,
            dataType: DataTypeSpec(DataType.float),
            category: EndpointCategory.messageQueue,
          ),
        ));
        expect(inputResult.success, isTrue,
            reason:
                'Failed to create default action input: ${inputResult.error}');

        final readSourceResult = await observer.readEndpoint(
          sourceName,
          namespaceSelector: NamespaceSelector.specificEntity(source.entityName),
          includeResolved: true,
          includeSpec: true,
        );
        expect(readSourceResult.success, isTrue,
            reason:
                'Failed to read default action source: ${readSourceResult.error}');
        expect(
          readSourceResult.value!.spec!.messageQueuePayloadContract,
          equals(MessageQueuePayloadContract.statefulFloatAction),
        );

        final readInputResult = await observer.readEndpoint(
          inputName,
          namespaceSelector:
              NamespaceSelector.specificEntity(inputOwner.entityName),
          includeResolved: true,
          includeSpec: true,
        );
        expect(readInputResult.success, isTrue,
            reason:
                'Failed to read default action input: ${readInputResult.error}');
        expect(
          readInputResult.value!.spec!.messageQueuePayloadContract,
          equals(MessageQueuePayloadContract.statefulFloatAction),
        );
        expect(readInputResult.value!.spec!.statefulInput, isNull);

        final List<Map<String, dynamic>> receivedActions =
            <Map<String, dynamic>>[];
        inputResult.value!.setStatefulFloatInputCallback(
          (StatefulFloatAction action, EndpointSenderInfo senderInfo) {
            receivedActions.add(<String, dynamic>{
              'action': action.action,
              'value': action.value,
              'sender': senderInfo.sourceEndpointRef.name,
            });
          },
        );
        expect(inputResult.value!.getRetainedStatefulFloatValue(), isNull);

        final Result<bool> createRequestResult =
            await source.createConnectionRequest(
          ConnectionRequest(
            name: requestName,
            spec: ConnectionRequestData(
              sourceRef: DataItemRef.byName(
                name: sourceName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(source.entityName),
              ),
              destinationRef: DataItemRef.byName(
                name: inputName,
                namespaceSelector:
                    NamespaceSelector.specificEntity(inputOwner.entityName),
              ),
            ),
          ),
        );
        expect(createRequestResult.success, isTrue,
            reason:
                'Failed to create default action connection: ${createRequestResult.error}');

        await Future.delayed(const Duration(milliseconds: 1000));

        expect(
          sourceResult.value!.write(
            const StatefulFloatAction(
              action: StatefulFloatActionType.setValue,
              value: 3.0,
            ),
          ),
          isTrue,
        );
        expect(
          sourceResult.value!.write(
            const StatefulFloatAction(
              action: StatefulFloatActionType.add,
              value: 0.5,
            ),
          ),
          isTrue,
        );

        for (int attempt = 0; attempt < 30; attempt++) {
          if (receivedActions.length >= 2) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }

        expect(receivedActions.length, equals(2));
        expect(
          receivedActions[0]['action'],
          equals(StatefulFloatActionType.setValue),
        );
        expect(receivedActions[0]['value'], equals(3.0));
        expect(receivedActions[0]['sender'], equals(sourceName));
        expect(
          receivedActions[1]['action'],
          equals(StatefulFloatActionType.add),
        );
        expect(receivedActions[1]['value'], equals(0.5));
        expect(receivedActions[1]['sender'], equals(sourceName));
        expect(inputResult.value!.getRetainedStatefulFloatValue(), isNull);
      } finally {
        observer.disconnect();
      }
    });

    test('setEndpoint rejects payload-contract-only message-queue shape changes',
        () async {
      final String endpointName =
          'payload_contract_shape_${DateTime.now().microsecondsSinceEpoch}';

      final Result<LocalEndpoint> createResult =
          await source.createEndpoint(EndpointInfo(
        name: endpointName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(createResult.success, isTrue,
          reason: 'Failed to create shape-test endpoint: ${createResult.error}');

      final updateResult = await source.setEndpoint(EndpointInfo(
        name: endpointName,
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.float),
          category: EndpointCategory.messageQueue,
          messageQueuePayloadContract:
              MessageQueuePayloadContract.statefulIntAction,
        ),
      ));
      expect(updateResult.success, isFalse);
      expect(updateResult.error, contains('Delete and recreate'));
    });
  });

  group('Endpoint SCOPE_BUFFER Data Type', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('ScopeProducer_$suffix');
      producer.setErrorCallback(
          (error) => AppLogger.error('Producer error: $error'));
      final conn1 = await producer.connect();
      expect(conn1.success, isTrue);

      consumer = DogPawEntity('ScopeConsumer_$suffix');
      consumer.setErrorCallback(
          (error) => AppLogger.error('Consumer error: $error'));
      final conn2 = await consumer.connect();
      expect(conn2.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('CreateSCOPE_BUFFEROutputEndpoint', () async {
      final result = await producer.createEndpoint(EndpointInfo(
        name: 'scope_out_test',
        spec: const EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec(DataType.scopeBuffer),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(result.success, isTrue,
          reason: 'Failed to create SCOPE_BUFFER output: ${result.error}');
      expect(result.value, isNotNull);
    });

    test('CreateSCOPE_BUFFERInputEndpoint', () async {
      final result = await consumer.createEndpoint(EndpointInfo(
        name: 'scope_in_test',
        spec: const EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec(DataType.scopeBuffer),
          category: EndpointCategory.messageQueue,
        ),
      ));
      expect(result.success, isTrue,
          reason: 'Failed to create SCOPE_BUFFER input: ${result.error}');
      expect(result.value, isNotNull);
    });

    test('SCOPE_BUFFERDataFlowProducerToConsumer', () async {
      final epName = 'scope_flow_${DateTime.now().microsecondsSinceEpoch}';

      final outResult = await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.scopeBuffer),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.input),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(outResult.success, isTrue);

      final inResult = await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(DataType.scopeBuffer),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(inResult.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 1000));

      final leftSamples = List<double>.generate(64, (i) => i * 0.01);
      final rightSamples = List<double>.generate(64, (i) => -i * 0.01);
      final scopeData = ScopeBufferData(
        sampleCount: 1000,
        sampleRateHz: 1200,
        framesPerPayload: 64,
        leftSamples: leftSamples,
        rightSamples: rightSamples,
      );

      final written = outResult.value!.write(scopeData);
      expect(written, isTrue, reason: 'Failed to write SCOPE_BUFFER value');

      await Future.delayed(const Duration(milliseconds: 500));

      final polled = inResult.value!.poll();
      expect(polled, isNotEmpty,
          reason: 'No data polled from SCOPE_BUFFER endpoint');
      final received = polled.first as ScopeBufferData;
      expect(received.sampleCount, equals(1000));
      expect(received.sampleRateHz, equals(1200));
      expect(received.framesPerPayload, equals(64));
      expect(received.leftSamples, hasLength(64));
      expect(received.rightSamples, hasLength(64));
      expect(received.leftSamples[0], equals(0.0));
      expect(received.leftSamples[63], closeTo(0.63, 0.01));
      expect(received.rightSamples[0], equals(0.0));
      expect(received.rightSamples[63], closeTo(-0.63, 0.01));
    });
  });

  group('Endpoint DPP_EDITOR_MESSAGE Data Type', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('DppEditorMessageProducer_$suffix');
      producer.setErrorCallback(
          (String error) => AppLogger.error('Producer error: $error'));
      final ConnectionResult producerConnect = await producer.connect();
      expect(producerConnect.success, isTrue);

      consumer = DogPawEntity('DppEditorMessageConsumer_$suffix');
      consumer.setErrorCallback(
          (String error) => AppLogger.error('Consumer error: $error'));
      final ConnectionResult consumerConnect = await consumer.connect();
      expect(consumerConnect.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('DPP_EDITOR_MESSAGEDataFlowProducerToConsumer', () async {
      final String epName =
          'dpp_editor_message_${DateTime.now().microsecondsSinceEpoch}';

      final Result<LocalEndpoint> outResult =
          await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.dppEditorMessage),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.input),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(outResult.success, isTrue);

      final Result<LocalEndpoint> inResult =
          await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(DataType.dppEditorMessage),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(inResult.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 1000));

      final Map<String, dynamic> payload = <String, dynamic>{
        'type': 1,
        'channel': 2,
        'note': 64,
        'param_index': 17,
        'value': 0.625,
        'value2': 0.0,
      };
      final bool written = outResult.value!.write(payload);
      expect(written, isTrue,
          reason: 'Failed to write DPP_EDITOR_MESSAGE payload');

      await Future.delayed(const Duration(milliseconds: 500));

      final List<dynamic> polled = inResult.value!.poll();
      expect(polled, isNotEmpty,
          reason: 'No data polled from DPP_EDITOR_MESSAGE endpoint');
      final Map<String, dynamic> received =
          polled.first as Map<String, dynamic>;
      expect(received['type'], equals(1));
      expect(received['channel'], equals(2));
      expect(received['note'], equals(64));
      expect(received['param_index'], equals(17));
      expect(received['value'], closeTo(0.625, 0.000001));
      expect(received['value2'], closeTo(0.0, 0.000001));
    });
  });

  group('Endpoint VOICE_MESSAGE Data Type', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('VoiceMessageProducer_$suffix');
      producer.setErrorCallback(
          (String error) => AppLogger.error('Producer error: $error'));
      final ConnectionResult producerConnect = await producer.connect();
      expect(producerConnect.success, isTrue);

      consumer = DogPawEntity('VoiceMessageConsumer_$suffix');
      consumer.setErrorCallback(
          (String error) => AppLogger.error('Consumer error: $error'));
      final ConnectionResult consumerConnect = await consumer.connect();
      expect(consumerConnect.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('VOICE_MESSAGEDataFlowProducerToConsumer', () async {
      final String epName =
          'voice_message_${DateTime.now().microsecondsSinceEpoch}';

      final Result<LocalEndpoint> outResult =
          await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.voiceMessage),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.input),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(outResult.success, isTrue);

      final Result<LocalEndpoint> inResult =
          await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(DataType.voiceMessage),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(inResult.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 1000));

      final Map<String, dynamic> payload = <String, dynamic>{
        'kind': 3,
        'voice': <String, dynamic>{
          'regionId': 9,
          'regionInstanceId': 42,
          'logicalVoiceId': 123,
          'slotIdx': 4,
        },
        'relatedVoice': <String, dynamic>{
          'regionId': 9,
          'regionInstanceId': 24,
          'logicalVoiceId': 77,
          'slotIdx': -1,
        },
        'hasRelatedMember': true,
        'relatedMember': <String, dynamic>{
          'keySource': <String, dynamic>{
            'origin': 0,
            'channel': 0,
            'note': 0,
            'col': 6,
            'row': 7,
          },
          'noteValue': 74.0,
          'velocity': 0.33,
          'pressure': 0.5,
          'bend': 0.2,
          'slide': 0.1,
          'row': 7.0,
          'column': 6.0,
        },
        'memberCount': 2,
        'members': <Map<String, dynamic>>[
          <String, dynamic>{
            'keySource': <String, dynamic>{
              'origin': 0,
              'channel': 0,
              'note': 0,
              'col': 1,
              'row': 1,
            },
            'noteValue': 60.0,
            'velocity': 0.8,
            'pressure': 0.4,
            'bend': -0.1,
            'slide': 0.0,
            'row': 1.0,
            'column': 1.0,
          },
          <String, dynamic>{
            'keySource': <String, dynamic>{
              'origin': 1,
              'channel': 2,
              'note': 64,
              'col': 0,
              'row': 0,
            },
            'noteValue': 64.0,
            'velocity': 0.25,
            'pressure': 0.9,
            'bend': 0.3,
            'slide': 0.2,
            'row': 0.0,
            'column': 0.0,
          },
        ],
      };
      final bool written = outResult.value!.write(payload);
      expect(written, isTrue, reason: 'Failed to write VOICE_MESSAGE payload');

      await Future.delayed(const Duration(milliseconds: 500));

      final List<dynamic> polled = inResult.value!.poll();
      expect(polled, isNotEmpty,
          reason: 'No data polled from VOICE_MESSAGE endpoint');
      final Map<String, dynamic> received =
          polled.first as Map<String, dynamic>;
      expect(received['kind'], equals(3));
      expect(
        received['voice'],
        equals(<String, dynamic>{
          'regionId': 9,
          'regionInstanceId': 42,
          'logicalVoiceId': 123,
          'slotIdx': 4,
        }),
      );
      expect(
        received['relatedVoice'],
        equals(<String, dynamic>{
          'regionId': 9,
          'regionInstanceId': 24,
          'logicalVoiceId': 77,
          'slotIdx': -1,
        }),
      );
      expect(received['hasRelatedMember'], isTrue);
      final Map<String, dynamic> relatedMember =
          Map<String, dynamic>.from(received['relatedMember'] as Map);
      expect(
        relatedMember['keySource'],
        equals(<String, dynamic>{
          'origin': 0,
          'channel': 0,
          'note': 0,
          'col': 6,
          'row': 7,
        }),
      );
      expect(relatedMember['noteValue'], closeTo(74.0, 0.000001));
      expect(relatedMember['velocity'], closeTo(0.33, 0.000001));
      expect(relatedMember['pressure'], closeTo(0.5, 0.000001));
      expect(relatedMember['bend'], closeTo(0.2, 0.000001));
      expect(relatedMember['slide'], closeTo(0.1, 0.000001));
      expect(relatedMember['row'], closeTo(7.0, 0.000001));
      expect(relatedMember['column'], closeTo(6.0, 0.000001));
      expect(received['memberCount'], equals(2));
      final List<dynamic> members = received['members'] as List<dynamic>;
      expect(members, hasLength(2));
      final Map<String, dynamic> firstMember =
          Map<String, dynamic>.from(members[0] as Map);
      expect(
        firstMember['keySource'],
        equals(<String, dynamic>{
          'origin': 0,
          'channel': 0,
          'note': 0,
          'col': 1,
          'row': 1,
        }),
      );
      expect(firstMember['noteValue'], closeTo(60.0, 0.000001));
      expect(firstMember['velocity'], closeTo(0.8, 0.000001));
      expect(firstMember['pressure'], closeTo(0.4, 0.000001));
      expect(firstMember['bend'], closeTo(-0.1, 0.000001));
      expect(firstMember['slide'], closeTo(0.0, 0.000001));
      expect(firstMember['row'], closeTo(1.0, 0.000001));
      expect(firstMember['column'], closeTo(1.0, 0.000001));

      final Map<String, dynamic> secondMember =
          Map<String, dynamic>.from(members[1] as Map);
      expect(
        secondMember['keySource'],
        equals(<String, dynamic>{
          'origin': 1,
          'channel': 2,
          'note': 64,
          'col': 0,
          'row': 0,
        }),
      );
      expect(secondMember['noteValue'], closeTo(64.0, 0.000001));
      expect(secondMember['velocity'], closeTo(0.25, 0.000001));
      expect(secondMember['pressure'], closeTo(0.9, 0.000001));
      expect(secondMember['bend'], closeTo(0.3, 0.000001));
      expect(secondMember['slide'], closeTo(0.2, 0.000001));
      expect(secondMember['row'], closeTo(0.0, 0.000001));
      expect(secondMember['column'], closeTo(0.0, 0.000001));
    });
  });

  group('Endpoint VOICE_OUTPUT_VALUE Data Type', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('VoiceOutputValueProducer_$suffix');
      producer.setErrorCallback(
          (String error) => AppLogger.error('Producer error: $error'));
      final ConnectionResult producerConnect = await producer.connect();
      expect(producerConnect.success, isTrue);

      consumer = DogPawEntity('VoiceOutputValueConsumer_$suffix');
      consumer.setErrorCallback(
          (String error) => AppLogger.error('Consumer error: $error'));
      final ConnectionResult consumerConnect = await consumer.connect();
      expect(consumerConnect.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('VOICE_OUTPUT_VALUEDataFlowProducerToConsumer', () async {
      final String epName =
          'voice_output_value_${DateTime.now().microsecondsSinceEpoch}';

      final Result<LocalEndpoint> outResult =
          await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.voiceOutputValue),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.input),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(outResult.success, isTrue);

      final Result<LocalEndpoint> inResult =
          await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(DataType.voiceOutputValue),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(inResult.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 1000));

      final Map<String, dynamic> payload = <String, dynamic>{
        'region_id': 5,
        'region_instance_id': 19,
        'logical_voice_id': 321,
        'slot_idx': 7,
        'output_index': 2,
        'value': 0.875,
      };
      final bool written = outResult.value!.write(payload);
      expect(written, isTrue,
          reason: 'Failed to write VOICE_OUTPUT_VALUE payload');

      await Future.delayed(const Duration(milliseconds: 500));

      final List<dynamic> polled = inResult.value!.poll();
      expect(polled, isNotEmpty,
          reason: 'No data polled from VOICE_OUTPUT_VALUE endpoint');
      final Map<String, dynamic> received =
          polled.first as Map<String, dynamic>;
      expect(received['region_id'], equals(5));
      expect(received['region_instance_id'], equals(19));
      expect(received['logical_voice_id'], equals(321));
      expect(received['slot_idx'], equals(7));
      expect(received['output_index'], equals(2));
      expect(received['value'], closeTo(0.875, 0.000001));
    });
  });

  group('Endpoint GLOBAL_OUTPUT_VALUE Data Type', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('GlobalOutputValueProducer_$suffix');
      producer.setErrorCallback(
          (String error) => AppLogger.error('Producer error: $error'));
      final ConnectionResult producerConnect = await producer.connect();
      expect(producerConnect.success, isTrue);

      consumer = DogPawEntity('GlobalOutputValueConsumer_$suffix');
      consumer.setErrorCallback(
          (String error) => AppLogger.error('Consumer error: $error'));
      final ConnectionResult consumerConnect = await consumer.connect();
      expect(consumerConnect.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('GLOBAL_OUTPUT_VALUEDataFlowProducerToConsumer', () async {
      final String epName =
          'global_output_value_${DateTime.now().microsecondsSinceEpoch}';

      final Result<LocalEndpoint> outResult =
          await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.globalOutputValue),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.input),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(outResult.success, isTrue);

      final Result<LocalEndpoint> inResult =
          await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(DataType.globalOutputValue),
          category: EndpointCategory.messageQueue,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(inResult.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 1000));

      final Map<String, dynamic> payload = <String, dynamic>{
        'output_index': 4,
        'value': -0.5,
      };
      final bool written = outResult.value!.write(payload);
      expect(written, isTrue,
          reason: 'Failed to write GLOBAL_OUTPUT_VALUE payload');

      await Future.delayed(const Duration(milliseconds: 500));

      final List<dynamic> polled = inResult.value!.poll();
      expect(polled, isNotEmpty,
          reason: 'No data polled from GLOBAL_OUTPUT_VALUE endpoint');
      final Map<String, dynamic> received =
          polled.first as Map<String, dynamic>;
      expect(received['output_index'], equals(4));
      expect(received['value'], closeTo(-0.5, 0.000001));
    });
  });

  group('Endpoint FILE_BACKED Data Type', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('FileBackedProducer_$suffix');
      producer.setErrorCallback(
          (error) => AppLogger.error('Producer error: $error'));
      final ConnectionResult producerConnect = await producer.connect();
      expect(producerConnect.success, isTrue);

      consumer = DogPawEntity('FileBackedConsumer_$suffix');
      consumer.setErrorCallback(
          (error) => AppLogger.error('Consumer error: $error'));
      final ConnectionResult consumerConnect = await consumer.connect();
      expect(consumerConnect.success, isTrue);

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('FILE_BACKEDPollDetectsChangesWhileReadReturnsCurrentContents',
        () async {
      final String epName =
          'file_backed_${DateTime.now().microsecondsSinceEpoch}';

      final Result<LocalEndpoint> outResult =
          await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(
            DataType.custom,
            customTypeName: 'json_payload',
          ),
          category: EndpointCategory.fileBacked,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.input),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(outResult.success, isTrue,
          reason: 'Failed to create file-backed output: ${outResult.error}');

      final Result<LocalEndpoint> inResult =
          await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: const DataTypeSpec(
            DataType.custom,
            customTypeName: 'json_payload',
          ),
          category: EndpointCategory.fileBacked,
          connectionPolicy: ConnectionPolicy(
            autoConnectCriteria: SearchCriteria.andCombination([
              SearchCriteria.directionEquals(EndpointDirection.output),
              SearchCriteria.nameEquals(epName),
            ]),
          ),
        ),
      ));
      expect(inResult.success, isTrue,
          reason: 'Failed to create file-backed input: ${inResult.error}');

      await Future.delayed(const Duration(milliseconds: 1000));

      final List<dynamic> initialPollValues = <dynamic>[];
      final bool initialPollResult =
          await inResult.value!.pollFileBacked(initialPollValues.add);
      expect(initialPollResult, isFalse,
          reason: 'Initial file-backed poll should observe no changes');
      expect(initialPollValues, isEmpty);

      final Map<String, dynamic> firstPayload = <String, dynamic>{
        'message': 'first',
        'count': 1,
      };
      final bool firstWriteResult =
          await outResult.value!.writeFileBacked(firstPayload);
      expect(firstWriteResult, isTrue,
          reason: 'Failed to write first file-backed payload');

      await Future.delayed(const Duration(milliseconds: 500));

      final List<dynamic> polledValues = <dynamic>[];
      final bool pollResult =
          await inResult.value!.pollFileBacked(polledValues.add);
      expect(pollResult, isTrue,
          reason: 'File-backed poll should detect the new payload');
      expect(polledValues, hasLength(1));
      expect(polledValues.single, equals(firstPayload));

      final List<dynamic> drainedPollValues = <dynamic>[];
      final bool drainedPollResult =
          await inResult.value!.pollFileBacked(drainedPollValues.add);
      expect(drainedPollResult, isFalse,
          reason: 'A second poll without a write should observe no changes');
      expect(drainedPollValues, isEmpty);

      final Map<String, dynamic> secondPayload = <String, dynamic>{
        'message': 'second',
        'count': 2,
      };
      final bool secondWriteResult =
          await outResult.value!.writeFileBacked(secondPayload);
      expect(secondWriteResult, isTrue,
          reason: 'Failed to write second file-backed payload');

      await Future.delayed(const Duration(milliseconds: 500));

      final List<dynamic> readValues = <dynamic>[];
      final bool readResult =
          await inResult.value!.readFileBacked(readValues.add);
      expect(readResult, isTrue,
          reason: 'File-backed read should return current contents');
      expect(readValues, hasLength(1));
      expect(readValues.single, equals(secondPayload));
    });
  });

  group('LocalEndpoint runtime observation callbacks', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('RuntimeCallbackProducer_$suffix');
      expect((await producer.connect()).success, isTrue);

      consumer = DogPawEntity('RuntimeCallbackConsumer_$suffix');
      expect((await consumer.connect()).success, isTrue);

      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      consumer.disconnect();
      producer.disconnect();
    });

    test('InputLocalEndpointObservesConnectionIndexSpecChanges', () async {
      final epName =
          'continuous_observe_${DateTime.now().microsecondsSinceEpoch}';
      final requestName =
          'continuous_observe_request_${DateTime.now().microsecondsSinceEpoch}';

      final outResult = await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec.createIndexedFloat(const IndexSpecVoice(2)),
          category: EndpointCategory.continuous,
        ),
      ));
      expect(outResult.success, isTrue,
          reason: 'Failed to create continuous output: ${outResult.error}');

      final inResult = await consumer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.input,
          dataType: DataTypeSpec.createIndexedFloat(const IndexSpecVoice(2)),
          category: EndpointCategory.continuous,
        ),
      ));
      expect(inResult.success, isTrue,
          reason: 'Failed to create continuous input: ${inResult.error}');

      final indexSpecCompleter =
          Completer<LocalEndpointConnectionIndexSpecChangedEvent>();
      inResult.value!.setConnectionIndexSpecChangedCallback((event) {
        if (!indexSpecCompleter.isCompleted) {
          indexSpecCompleter.complete(event);
        }
      });

      final createRequestResult = await producer.createConnectionRequest(
        ConnectionRequest(
          name: requestName,
          spec: ConnectionRequestData(
            sourceRef: DataItemRef.byName(
              name: epName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(producer.entityName),
            ),
            destinationRef: DataItemRef.byName(
              name: epName,
              namespaceSelector:
                  NamespaceSelector.specificEntity(consumer.entityName),
            ),
          ),
        ),
      );
      expect(createRequestResult.success, isTrue,
          reason:
              'Failed to create connection request: ${createRequestResult.error}');

      await Future.delayed(const Duration(milliseconds: 500));

      final updateResult = await producer.setEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: DataTypeSpec.createIndexedFloat(const IndexSpecVoice(4)),
          category: EndpointCategory.continuous,
        ),
      ));
      expect(updateResult.success, isTrue,
          reason: 'Failed to update continuous output: ${updateResult.error}');

      final event = await indexSpecCompleter.future.timeout(
        const Duration(seconds: 3),
      );
      expect(event.connectionName, isNotEmpty);
      expect(event.peerEndpointRef.name, equals(epName));
      expect(
        event.peerEndpointRef.namespaceSelector,
        equals(NamespaceSelector.specificEntity(producer.entityName)),
      );
      expect(event.newIndexSpec, equals(const IndexSpecVoice(4)));
    });
  });
}
