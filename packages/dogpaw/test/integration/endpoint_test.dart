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
      () => outputEndpoint.write(42),
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
          spec: const EndpointSpec(
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
          spec: const EndpointSpec(
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
      const int testValue = 42;
      final written = outResult.value!.write(testValue);
      expect(written, isTrue, reason: 'Failed to write INT value');

      // Poll from consumer
      await Future.delayed(const Duration(milliseconds: 500));
      final polled = inResult.value!.poll();
      expect(polled, isNotEmpty, reason: 'No data polled from INT endpoint');
      expect(polled.first, equals(testValue),
          reason: 'Polled value should match written value');
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

      // Write several values
      final values = [0, -500, 1000, -1000, 42];
      for (final v in values) {
        outResult.value!.write(v);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // Poll all available messages
      final List<dynamic> received = [];
      List<dynamic> batch;
      do {
        batch = inResult.value!.poll();
        received.addAll(batch);
      } while (batch.isNotEmpty);

      expect(received.length, equals(values.length),
          reason: 'Should receive all ${values.length} messages');
      for (int i = 0; i < values.length; i++) {
        expect(received[i], equals(values[i]),
            reason: 'Value at index $i should match');
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

      expect(sourceAResult.value!.write(101), isTrue);
      expect(sourceBResult.value!.write(202), isTrue);

      await Future.delayed(const Duration(milliseconds: 500));

      final List<LocalEndpointPollResult> polled =
          inputResult.value!.pollWithSenderInfo();
      expect(polled.length, equals(2));

      final LocalEndpointPollResult fromA = polled.firstWhere(
        (result) => result.senderInfo.sourceEndpointRef.name == sourceAName,
      );
      final LocalEndpointPollResult fromB = polled.firstWhere(
        (result) => result.senderInfo.sourceEndpointRef.name == sourceBName,
      );

      expect(fromA.data, equals(101));
      expect(fromA.senderInfo.connectionName, isNotEmpty);
      expect(
        fromA.senderInfo.sourceEndpointRef.namespaceSelector,
        equals(NamespaceSelector.specificEntity(sourceA.entityName)),
      );

      expect(fromB.data, equals(202));
      expect(fromB.senderInfo.connectionName, isNotEmpty);
      expect(
        fromB.senderInfo.sourceEndpointRef.namespaceSelector,
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
      final written = outResult.value!.write(true);
      expect(written, isTrue, reason: 'Failed to write TOGGLE value');

      await Future.delayed(const Duration(milliseconds: 500));

      final polled = inResult.value!.poll();
      expect(polled, isNotEmpty, reason: 'No data polled from TOGGLE endpoint');
      expect(polled.first, isTrue, reason: 'Polled value should be true');
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

  group('Endpoint DPP_PARAM_QUEUE Data Type', () {
    late DogPawEntity producer;
    late DogPawEntity consumer;

    setUp(() async {
      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();

      producer = DogPawEntity('DppParamQueueProducer_$suffix');
      producer.setErrorCallback(
          (String error) => AppLogger.error('Producer error: $error'));
      final ConnectionResult producerConnect = await producer.connect();
      expect(producerConnect.success, isTrue);

      consumer = DogPawEntity('DppParamQueueConsumer_$suffix');
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

    test('DPP_PARAM_QUEUEDataFlowProducerToConsumer', () async {
      final String epName =
          'dpp_param_queue_${DateTime.now().microsecondsSinceEpoch}';

      final Result<LocalEndpoint> outResult =
          await producer.createEndpoint(EndpointInfo(
        name: epName,
        spec: EndpointSpec(
          direction: EndpointDirection.output,
          dataType: const DataTypeSpec(DataType.dppParamQueue),
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
          dataType: const DataTypeSpec(DataType.dppParamQueue),
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
        'param_index': 17,
        'reserved': 0,
        'value': 0.625,
      };
      final bool written = outResult.value!.write(payload);
      expect(written, isTrue,
          reason: 'Failed to write DPP_PARAM_QUEUE payload');

      await Future.delayed(const Duration(milliseconds: 500));

      final List<dynamic> polled = inResult.value!.poll();
      expect(polled, isNotEmpty,
          reason: 'No data polled from DPP_PARAM_QUEUE endpoint');
      final Map<String, dynamic> received =
          polled.first as Map<String, dynamic>;
      expect(received['param_index'], equals(17));
      expect(received['reserved'], equals(0));
      expect(received['value'], closeTo(0.625, 0.000001));
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
