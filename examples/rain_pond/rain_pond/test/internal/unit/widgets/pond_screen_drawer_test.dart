import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rain_pond/controllers/pond_controller.dart';
import 'package:rain_pond/services/pond_key_input_service.dart';
import 'package:rain_pond/models/visual_settings.dart';
import 'package:rain_pond/screens/pond_screen.dart';

void main() {
  group('Rain Pond hardware key transitions', () {
    test('treats full press lifecycle as one down and one up', () {
      const dp.KeyEvent activated = dp.KeyEvent(
        type: dp.KeyEventType.activated,
        column: 2,
        row: 3,
        velocity: 0.75,
        oldState: dp.KeyState.rest,
        newState: dp.KeyState.activated,
        timestamp: 100,
      );
      const dp.KeyEvent pressed = dp.KeyEvent(
        type: dp.KeyEventType.pressed,
        column: 2,
        row: 3,
        velocity: 0.75,
        oldState: dp.KeyState.activated,
        newState: dp.KeyState.pressed,
        timestamp: 101,
      );
      const dp.KeyEvent unpressed = dp.KeyEvent(
        type: dp.KeyEventType.unpressed,
        column: 2,
        row: 3,
        velocity: 0.75,
        oldState: dp.KeyState.pressed,
        newState: dp.KeyState.activated,
        timestamp: 102,
      );
      const dp.KeyEvent released = dp.KeyEvent(
        type: dp.KeyEventType.released,
        column: 2,
        row: 3,
        velocity: -0.5,
        oldState: dp.KeyState.activated,
        newState: dp.KeyState.rest,
        timestamp: 103,
      );

      expect(isRippleNoteDownEvent(activated), isFalse);
      expect(isRippleNoteDownEvent(pressed), isTrue);
      expect(isRippleNoteDownEvent(unpressed), isFalse);
      expect(isRippleNoteUpEvent(unpressed), isFalse);
      expect(isRippleNoteUpEvent(released), isTrue);
    });
  });

  testWidgets('settings drawer keeps the smaller teaching-focused control set',
      (WidgetTester tester) async {
    final VisualSettings settings = VisualSettings();
    final PondController pond = PondController(
      entity: dp.DogPawEntity('RainPond'),
      settings: settings,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<VisualSettings>.value(value: settings),
          ChangeNotifierProvider<PondController>.value(value: pond),
        ],
        child: const MaterialApp(home: PondScreen()),
      ),
    );

    await tester.pump();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Baseline rain'), findsOneWidget);
    expect(find.text('Ripple size'), findsOneWidget);
    expect(find.text('Ripple duration'), findsOneWidget);
    expect(find.text('Color saturation'), findsOneWidget);
    expect(find.text('Held ripple intensity'), findsNothing);
    expect(find.text('Bend shimmer'), findsNothing);
    expect(find.textContaining('Keyboard:'), findsOneWidget);
  });
}
