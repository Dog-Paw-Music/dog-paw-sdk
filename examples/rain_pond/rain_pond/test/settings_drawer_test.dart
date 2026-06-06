import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rain_pond/controllers/pond_controller.dart';
import 'package:rain_pond/models/visual_settings.dart';
import 'package:rain_pond/widgets/settings_drawer.dart';

void main() {
  testWidgets('settings drawer keeps a small teaching-focused control set', (
    WidgetTester tester,
  ) async {
    final VisualSettings settings = VisualSettings();
    final PondController controller = PondController(
      entity: dp.DogPawEntity('RainPondTest'),
      settings: settings,
      startInitialized: true,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<VisualSettings>.value(value: settings),
          ChangeNotifierProvider<PondController>.value(value: controller),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsDrawer(),
          ),
        ),
      ),
    );

    expect(find.text('Baseline rain'), findsOneWidget);
    expect(find.text('Ripple size'), findsOneWidget);
    expect(find.text('Ripple duration'), findsOneWidget);
    expect(find.text('Color saturation'), findsOneWidget);

    expect(find.text('Velocity → size'), findsNothing);
    expect(find.text('Held ripple intensity'), findsNothing);
    expect(find.text('Bend shimmer'), findsNothing);
    expect(find.text('Random hue range'), findsNothing);
    expect(find.text('Line weight'), findsNothing);
    expect(find.text('Ambient ripple size'), findsNothing);
    expect(find.textContaining('Max ripples:'), findsNothing);
  });
}
