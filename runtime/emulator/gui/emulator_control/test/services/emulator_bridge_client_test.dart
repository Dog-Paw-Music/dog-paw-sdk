import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:emulator_control/services/emulator_bridge_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fetchHealth decodes simulator socket availability', () async {
    final requests = <Uri>[];
    final client = EmulatorBridgeClient(
      baseUri: Uri.parse('http://127.0.0.1:8765'),
      transport: (method, uri, body) async {
        requests.add(uri);
        expect(method, 'GET');
        expect(body, isNull);
        return const BridgeHttpResponse(
          200,
          '{"ok":true,"emulator":"default","instance":"default",'
          '"sockets":{"keyGrid":{"available":true},'
          '"buttonsAndKnobs":{"available":false},'
          '"ledComms":{"available":true}}}',
        );
      },
    );

    final health = await client.fetchHealth();

    expect(requests.single.path, '/api/health');
    expect(health.ok, isTrue);
    expect(health.emulatorName, 'default');
    expect(health.socketAvailable('keyGrid'), isTrue);
    expect(health.socketAvailable('buttonsAndKnobs'), isFalse);
    expect(health.socketAvailable('ledComms'), isTrue);
  });

  test('tapKey posts compact col row payload', () async {
    String? postedBody;
    final client = EmulatorBridgeClient(
      baseUri: Uri.parse('http://127.0.0.1:8765'),
      transport: (method, uri, body) async {
        expect(method, 'POST');
        expect(uri.path, '/api/key/tap');
        postedBody = body;
        return const BridgeHttpResponse(200, '{"ok":true}');
      },
    );

    await client.tapKey(col: 2, row: 3);

    expect(postedBody, '{"col":2,"row":3}');
  });

  test('fetchLedSnapshot decodes visible key layer colors', () async {
    final client = EmulatorBridgeClient(
      baseUri: Uri.parse('http://127.0.0.1:8765'),
      transport: (method, uri, body) async {
        expect(method, 'GET');
        expect(uri.path, '/api/led/snapshot');
        expect(body, isNull);
        return const BridgeHttpResponse(
          200,
          '{"ok":true,"keyLayers":[{"col":4,"row":5,"layer":0,'
          '"left":true,"right":true,"r":10,"g":20,"b":30,"a":255}]}',
        );
      },
    );

    final snapshot = await client.fetchLedSnapshot();

    expect(snapshot.ok, isTrue);
    expect(snapshot.keyLayers.single.col, 4);
    expect(snapshot.keyLayers.single.row, 5);
    expect(snapshot.keyLayers.single.red, 10);
    expect(snapshot.keyLayers.single.green, 20);
    expect(snapshot.keyLayers.single.blue, 30);
    expect(snapshot.keyLayers.single.alpha, 255);
  });

  test('fetchBakSnapshot decodes button and knob state', () async {
    final client = EmulatorBridgeClient(
      baseUri: Uri.parse('http://127.0.0.1:8765'),
      transport: (method, uri, body) async {
        expect(method, 'GET');
        expect(uri.path, '/api/bak/snapshot');
        expect(body, isNull);
        return const BridgeHttpResponse(
          200,
          '{"ok":true,"buttons":[{"index":0,"pressed":true}],'
          '"knobs":[{"index":0,"raw":12,"normalized":0.75}]}',
        );
      },
    );

    final snapshot = await client.fetchBakSnapshot();

    expect(snapshot.ok, isTrue);
    expect(snapshot.buttons.single.pressed, isTrue);
    expect(snapshot.knobs.single.raw, 12);
    expect(snapshot.knobs.single.normalized, 0.75);
  });

  test('setBakKnobNormalized posts normalized payload', () async {
    String? postedBody;
    final client = EmulatorBridgeClient(
      baseUri: Uri.parse('http://127.0.0.1:8765'),
      transport: (method, uri, body) async {
        expect(method, 'POST');
        expect(uri.path, '/api/bak/knob/setNormalized');
        postedBody = body;
        return const BridgeHttpResponse(200, '{"ok":true}');
      },
    );

    await client.setBakKnobNormalized(index: 2, value: 0.25);

    expect(postedBody, '{"index":2,"value":0.25}');
  });

  test('default transport sends explicit content length', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final requestHandled = Completer<void>();
    var observedContentLength = -1;
    var observedBody = '';
    server.listen((request) async {
      observedContentLength = request.contentLength;
      observedBody = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
      requestHandled.complete();
    });

    final client = EmulatorBridgeClient(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    await client.tapBakButton(index: 2);
    await requestHandled.future;

    expect(observedContentLength, observedBody.length);
    expect(observedBody, '{"index":2}');
  });
}
