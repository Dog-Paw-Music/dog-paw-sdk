import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'controllers/hello_controller.dart';

/// Purpose:
///     Compose the minimal hello example and launch Flutter.
/// Parameters:
///     None.
/// Return value:
///     None.
/// Requirements:
///     Flutter bindings and the Dog Paw package must be available.
/// Guarantees:
///     Initializes logging, creates the hello controller, and starts the root
///     widget tree.
/// Invariants:
///     Keeps dependency composition in main.dart while leaving runtime logic in
///     HelloController.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  dp.AppLogger.initialize('HelloDogPaw');

  runApp(
    ChangeNotifierProvider<HelloController>(
      create: (_) => HelloController(
        client: EntityHelloDogPawClient(
          dp.DogPawEntity('HelloDogPaw'),
        ),
      ),
      child: const HelloDogPawApp(),
    ),
  );
}
