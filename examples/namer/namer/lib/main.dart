import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dogpaw/dogpaw.dart' as dp;
import 'app.dart';
import 'controllers/home_controller.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => _createHomeController(),
      child: const NamerApp(),
    ),
  );
}

/// Create and configure the HomeController with its dependencies.
/// 
/// This is the dependency composition root for the app.
/// Creates DogPawEntity, NamerService, NamingSchemeService and injects
/// them into HomeController.
HomeController _createHomeController() {
  final dogPawEntity = dp.DogPawEntity('Namer');
  
  // NamerService and NamingSchemeService will be created by the controller
  // once it has the local directory from the entity after connection.
  // For now, we just pass the entity.
  return HomeController(
    entity: dogPawEntity,
  );
}
