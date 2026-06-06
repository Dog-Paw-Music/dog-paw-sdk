import 'dart:convert';
import 'dart:ui';

import 'package:emulator_control/app.dart';
import 'package:emulator_control/models/emulator_bridge_models.dart';
import 'package:emulator_control/services/emulator_bridge_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('key grid half fills receive non-zero painted layout size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const LedSnapshot snapshot = LedSnapshot(
      ok: true,
      keyLayers: [
        LedKeyLayer(
          col: 1,
          row: 1,
          left: true,
          right: true,
          red: 255,
          green: 0,
          blue: 0,
          alpha: 255,
        ),
        LedKeyLayer(
          col: 2,
          row: 3,
          left: true,
          right: true,
          red: 0,
          green: 255,
          blue: 0,
          alpha: 255,
        ),
        LedKeyLayer(
          col: 6,
          row: 4,
          left: true,
          right: true,
          red: 0,
          green: 80,
          blue: 255,
          alpha: 255,
        ),
      ],
    );
    await tester.pumpWidget(
      EmulatorControlApp(
        health: const BridgeHealth(
          ok: true,
          emulatorName: 'default',
          instanceName: 'default',
          sockets: {
            'keyGrid': SimulatorSocketStatus(available: true),
            'buttonsAndKnobs': SimulatorSocketStatus(available: true),
            'ledComms': SimulatorSocketStatus(available: true),
          },
        ),
        snapshot: snapshot,
        bakSnapshot: const BakSnapshot(ok: true, buttons: [], knobs: []),
        onKeyStateChange: (request) async {},
        onKeyPatternPlay: (path) async {},
        onKeyPatternLoop: (path) async {},
        onKeyPatternStop: () async {},
        onBakButtonTap: (index) async {},
        onBakKnobRotate: (index, delta) async {},
        onBakKnobSetRaw: (index, raw) async {},
        onBakKnobSetNormalized: (index, value) async {},
      ),
    );
    await tester.pumpAndSettle();

    for (final Color expectedColor in const <Color>[
      Color(0xFFFF0000),
      Color(0xFF00FF00),
      Color(0xFF0050FF),
    ]) {
      final Finder halfFillFinder = find.byWidgetPredicate(
        (Widget widget) => widget is ColoredBox && widget.color == expectedColor,
      );
      expect(halfFillFinder, findsNWidgets(2));
      for (final Element element in halfFillFinder.evaluate()) {
        final RenderBox renderBox = element.renderObject! as RenderBox;
        expect(renderBox.size.width, greaterThan(0));
        expect(renderBox.size.height, greaterThan(0));
      }
    }
  });

  testWidgets('shows bridge health, key grid, and BAK controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const health = BridgeHealth(
      ok: true,
      emulatorName: 'default',
      instanceName: 'default',
      sockets: {
        'keyGrid': SimulatorSocketStatus(available: true),
        'buttonsAndKnobs': SimulatorSocketStatus(available: true),
        'ledComms': SimulatorSocketStatus(available: false),
      },
    );
    const snapshot = LedSnapshot(
      ok: true,
      keyLayers: [
        LedKeyLayer(
          col: 0,
          row: 7,
          left: true,
          right: false,
          red: 20,
          green: 40,
          blue: 60,
          alpha: 255,
        ),
        LedKeyLayer(
          col: 0,
          row: 7,
          left: false,
          right: true,
          red: 70,
          green: 90,
          blue: 110,
          alpha: 255,
        ),
      ],
    );
    const bakSnapshot = BakSnapshot(
      ok: true,
      buttons: [
        BakButtonState(index: 0, pressed: true),
      ],
      knobs: [
        BakKnobState(index: 0, raw: 12, normalized: 0.75),
      ],
    );

    await tester.pumpWidget(
      EmulatorControlApp(
        health: health,
        snapshot: snapshot,
        bakSnapshot: bakSnapshot,
        onKeyStateChange: (request) async {},
        onKeyPatternPlay: (path) async {},
        onKeyPatternLoop: (path) async {},
        onKeyPatternStop: () async {},
        onBakButtonTap: (index) async {},
        onBakKnobRotate: (index, delta) async {},
        onBakKnobSetRaw: (index, raw) async {},
        onBakKnobSetNormalized: (index, value) async {},
      ),
    );

    expect(find.text('Dog Paw Emulator Control'), findsOneWidget);
    expect(find.text('Bridge: default / default'), findsOneWidget);
    expect(find.text('Key Grid'), findsOneWidget);
    expect(find.text('BAK Controls'), findsOneWidget);
    expect(find.text('Key Patterns'), findsNothing);
    expect(find.text('Load'), findsNothing);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Loop'), findsNothing);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('LEDComms: offline'), findsOneWidget);
    expect(find.text('Raw: 12'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('shows a help action with written control guidance', (tester) async {
    await tester.pumpWidget(
      EmulatorControlApp(
        health: const BridgeHealth(
          ok: true,
          emulatorName: 'default',
          instanceName: 'default',
          sockets: {
            'keyGrid': SimulatorSocketStatus(available: true),
            'buttonsAndKnobs': SimulatorSocketStatus(available: true),
            'ledComms': SimulatorSocketStatus(available: true),
          },
        ),
        snapshot: const LedSnapshot(ok: true, keyLayers: []),
        bakSnapshot: const BakSnapshot(ok: true, buttons: [], knobs: []),
        onKeyStateChange: (request) async {},
        onKeyPatternPlay: (path) async {},
        onKeyPatternLoop: (path) async {},
        onKeyPatternStop: () async {},
        onBakButtonTap: (index) async {},
        onBakKnobRotate: (index, delta) async {},
        onBakKnobSetRaw: (index, raw) async {},
        onBakKnobSetNormalized: (index, value) async {},
      ),
    );

    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(find.text('Emulator control guide'), findsOneWidget);
    expect(find.textContaining('Left click presses a key'), findsOneWidget);
    expect(find.textContaining('Right click sends the active state'), findsOneWidget);
  });

  testWidgets('renders the key grid without a scrollable grid view', (tester) async {
    await tester.pumpWidget(
      EmulatorControlApp(
        health: const BridgeHealth(
          ok: true,
          emulatorName: 'default',
          instanceName: 'default',
          sockets: {
            'keyGrid': SimulatorSocketStatus(available: true),
            'buttonsAndKnobs': SimulatorSocketStatus(available: true),
            'ledComms': SimulatorSocketStatus(available: true),
          },
        ),
        snapshot: const LedSnapshot(ok: true, keyLayers: []),
        bakSnapshot: const BakSnapshot(ok: true, buttons: [], knobs: []),
        onKeyStateChange: (request) async {},
        onKeyPatternPlay: (path) async {},
        onKeyPatternLoop: (path) async {},
        onKeyPatternStop: () async {},
        onBakButtonTap: (index) async {},
        onBakKnobRotate: (index, delta) async {},
        onBakKnobSetRaw: (index, raw) async {},
        onBakKnobSetNormalized: (index, value) async {},
      ),
    );

    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('BAK raw and normalized controls send expected values', (
    tester,
  ) async {
    final List<int> rawValues = <int>[];
    final List<double> normalizedValues = <double>[];

    await tester.pumpWidget(
      EmulatorControlApp(
        health: const BridgeHealth(
          ok: true,
          emulatorName: 'default',
          instanceName: 'default',
          sockets: {
            'keyGrid': SimulatorSocketStatus(available: true),
            'buttonsAndKnobs': SimulatorSocketStatus(available: true),
            'ledComms': SimulatorSocketStatus(available: false),
          },
        ),
        snapshot: const LedSnapshot(ok: true, keyLayers: []),
        bakSnapshot: const BakSnapshot(
          ok: true,
          buttons: [],
          knobs: [
            BakKnobState(index: 0, raw: 12, normalized: 0.75),
          ],
        ),
        onKeyStateChange: (request) async {},
        onKeyPatternPlay: (path) async {},
        onKeyPatternLoop: (path) async {},
        onKeyPatternStop: () async {},
        onBakButtonTap: (index) async {},
        onBakKnobRotate: (index, delta) async {
          rawValues.add(delta);
        },
        onBakKnobSetRaw: (index, raw) async {
          rawValues.add(raw);
        },
        onBakKnobSetNormalized: (index, value) async {
          normalizedValues.add(value);
        },
      ),
    );

    final Slider rawSlider = tester.widget<Slider>(find.byType(Slider).at(0));
    final Slider normalizedSlider = tester.widget<Slider>(
      find.byType(Slider).at(1),
    );

    rawSlider.onChanged!(25.0);
    normalizedSlider.onChanged!(0.25);
    await tester.tap(find.byTooltip('Rotate knob 0 left'));
    await tester.tap(find.byTooltip('Rotate knob 0 right'));

    expect(rawValues, <int>[-25, 1, -1]);
    expect(normalizedValues, <double>[0.25]);
  });

  testWidgets('shows bridge error when key press is rejected', (tester) async {
    int keyStateRequests = 0;
    final client = EmulatorBridgeClient(
      baseUri: Uri.parse('http://127.0.0.1:8765'),
      transport: (method, uri, body) async {
        if (uri.path == '/api/health') {
          return const BridgeHttpResponse(
            200,
            '{"ok":true,"emulator":"default","instance":"default",'
            '"sockets":{"keyGrid":{"available":true},'
            '"buttonsAndKnobs":{"available":false},'
            '"ledComms":{"available":false}}}',
          );
        }
        if (uri.path == '/api/key/set') {
          keyStateRequests += 1;
          return const BridgeHttpResponse(
            502,
            '{"ok":false,"error":"PicoCommsSimulator rejected command",'
            '"detail":"ERROR Unknown KeyGridSimulator control action: set_key"}',
          );
        }
        throw StateError('Unexpected request: ${uri.path}');
      },
    );

    await tester.pumpWidget(EmulatorControlRoot(client: client));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('0,7')),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(keyStateRequests, 2);
    expect(find.textContaining('PicoCommsSimulator rejected command'), findsOneWidget);
    expect(
      find.textContaining('Unknown KeyGridSimulator control action: set_key'),
      findsOneWidget,
    );
  });

  testWidgets('maps mouse buttons and drag position to rich key state updates', (
    tester,
  ) async {
    final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
    final client = EmulatorBridgeClient(
      baseUri: Uri.parse('http://127.0.0.1:8765'),
      transport: (method, uri, body) async {
        if (uri.path == '/api/health') {
          return const BridgeHttpResponse(
            200,
            '{"ok":true,"emulator":"default","instance":"default",'
            '"sockets":{"keyGrid":{"available":true},'
            '"buttonsAndKnobs":{"available":false},'
            '"ledComms":{"available":false}}}',
          );
        }
        if (uri.path == '/api/key/set') {
          requests.add((body == null ? <String, Object?>{} : Map<String, Object?>.from(jsonDecode(body) as Map)));
          return const BridgeHttpResponse(200, '{"ok":true}');
        }
        throw StateError('Unexpected request: ${uri.path}');
      },
    );

    await tester.pumpWidget(EmulatorControlRoot(client: client));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final Finder tileListener = find.ancestor(
      of: find.text('0,7'),
      matching: find.byType(Listener),
    );
    final Rect tileRect = tester.getRect(tileListener.first);

    final TestGesture secondary = await tester.startGesture(
      tileRect.topLeft + const Offset(8, 8),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await secondary.up();
    await tester.pump(const Duration(milliseconds: 100));

    final TestGesture primary = await tester.startGesture(
      tileRect.bottomRight - const Offset(8, 8),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await primary.moveTo(tileRect.centerRight - const Offset(4, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await primary.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(requests[0]['state'], 'active');
    expect((requests[0]['vertical'] as num) > 0, isTrue);
    expect((requests[0]['horizontal'] as num) < 0, isTrue);

    expect(requests[2]['state'], 'pressed');
    expect((requests[2]['vertical'] as num) < 0, isTrue);
    expect((requests[2]['horizontal'] as num) > 0, isTrue);

    expect(requests[3]['state'], 'pressed');
    expect((requests[3]['horizontal'] as num) > 0, isTrue);
    expect(requests[4]['state'], 'rest');
  });

  testWidgets('polls LED snapshots faster than health and BAK', (tester) async {
    int healthRequests = 0;
    int ledSnapshotRequests = 0;
    int bakSnapshotRequests = 0;
    final client = EmulatorBridgeClient(
      baseUri: Uri.parse('http://127.0.0.1:8765'),
      transport: (method, uri, body) async {
        if (uri.path == '/api/health') {
          healthRequests += 1;
          return const BridgeHttpResponse(
            200,
            '{"ok":true,"emulator":"default","instance":"default",'
            '"sockets":{"keyGrid":{"available":true},'
            '"buttonsAndKnobs":{"available":true},'
            '"ledComms":{"available":true}}}',
          );
        }
        if (uri.path == '/api/led/snapshot') {
          ledSnapshotRequests += 1;
          return const BridgeHttpResponse(200, '{"ok":true,"keyLayers":[]}');
        }
        if (uri.path == '/api/bak/snapshot') {
          bakSnapshotRequests += 1;
          return const BridgeHttpResponse(
            200,
            '{"ok":true,"buttons":[],"knobs":[]}',
          );
        }
        throw StateError('Unexpected request: ${uri.path}');
      },
    );

    await tester.pumpWidget(EmulatorControlRoot(client: client));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    expect(healthRequests, 1);
    expect(bakSnapshotRequests, 1);
    expect(ledSnapshotRequests, greaterThanOrEqualTo(4));
  });
}
