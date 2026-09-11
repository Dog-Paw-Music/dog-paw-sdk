import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'controllers/hello_controller.dart';

/// Compose dependencies and launch Flutter.
///
/// Keep this file thin: create the Dog Paw entity, hand it to the controller,
/// then hand the UI to [HelloDogPawApp].
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  dp.AppLogger.initialize('HelloDogPaw');

  // The entity name must be unique among apps talking to this Epiphany instance.
  final dp.DogPawEntity entity = dp.DogPawEntity('HelloDogPaw');

  runApp(
    ChangeNotifierProvider<HelloController>(
      create: (_) => HelloController(entity: entity),
      child: const HelloDogPawApp(),
    ),
  );
}
