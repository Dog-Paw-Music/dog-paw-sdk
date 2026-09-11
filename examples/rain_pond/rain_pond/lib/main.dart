import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'controllers/pond_controller.dart';
import 'models/visual_settings.dart';

/// Compose dependencies and launch Flutter.
///
/// Keep this file thin: entity + settings + controller, then hand UI to
/// [RainPondApp]. Dog Paw connect/endpoints live in [PondKeyInputService].
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  dp.AppLogger.initialize('RainPond');
  final VisualSettings visualSettings = VisualSettings();
  final dp.DogPawEntity entity = dp.DogPawEntity('RainPond');
  final PondController pond = PondController(
    entity: entity,
    settings: visualSettings,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<VisualSettings>.value(value: visualSettings),
        ChangeNotifierProvider<PondController>.value(value: pond),
      ],
      child: const RainPondApp(),
    ),
  );
}
