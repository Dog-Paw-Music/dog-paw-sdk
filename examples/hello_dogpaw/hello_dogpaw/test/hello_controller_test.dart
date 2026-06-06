import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter_test/flutter_test.dart';
import 'package:hello_dogpaw/controllers/hello_controller.dart';

class FakeHelloDogPawClient implements HelloDogPawClient {
  FakeHelloDogPawClient({
    required this.result,
  });

  final dp.ConnectionResult result;
  bool disconnected = false;
  final List<String> createdEndpointNames = <String>[];

  @override
  Future<dp.ConnectionResult> connect() async => result;

  @override
  Future<dp.Result<dp.LocalEndpoint>> createEndpoint(dp.EndpointInfo endpoint) async {
    createdEndpointNames.add(endpoint.name);
    return dp.Result.success(
      FakeLocalEndpoint.fromEndpointInfo(endpoint),
    );
  }

  @override
  void disconnect() {
    disconnected = true;
  }
}

class FakeLocalEndpoint extends dp.LocalEndpoint {
  FakeLocalEndpoint._({
    required super.name,
    required super.spec,
    super.namespaceSelector,
  });

  factory FakeLocalEndpoint.fromEndpointInfo(dp.EndpointInfo info) {
    final dp.EndpointSpec? initialSpec = info.spec ?? info.resolved;
    if (initialSpec == null) {
      throw StateError('FakeLocalEndpoint requires endpoint metadata.');
    }
    final FakeLocalEndpoint endpoint = FakeLocalEndpoint._(
      name: info.name,
      spec: initialSpec,
      namespaceSelector: info.namespaceSelector,
    );
    endpoint.copyMetadataFrom(info);
    return endpoint;
  }

  @override
  bool write(dynamic data) => true;

  @override
  List<dynamic> poll({String? connectionName}) => <dynamic>[];
}

void main() {
  test('start configures hello runtime when Dog Paw connection succeeds', () async {
    bool completed = false;
    final dp.ConnectionHandle handle = dp.ConnectionHandle((_) async {
      completed = true;
    });
    final HelloController controller = HelloController(
      client: FakeHelloDogPawClient(
        result: dp.ConnectionResult.success(handle),
      ),
    );

    await controller.start();

    expect(controller.isReady, isTrue);
    expect(controller.statusMessage, 'Connected and listening for key events.');
    expect(completed, isTrue);
    expect(controller.availableSwatches, hasLength(4));
  });

  test('start surfaces an error when Dog Paw connection fails', () async {
    final HelloController controller = HelloController(
      client: FakeHelloDogPawClient(
        result: dp.ConnectionResult.error('server unavailable'),
      ),
    );

    await controller.start();

    expect(controller.isReady, isFalse);
    expect(controller.statusMessage, contains('server unavailable'));
  });
}
