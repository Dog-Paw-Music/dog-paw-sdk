import 'dart:io';

import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

void main() {
  late Directory testRoot;
  late Directory home;
  late Directory xdgDataHome;
  late Directory runtimeRoot;

  setUp(() {
    testRoot = Directory.systemTemp.createTempSync('dogpaw_dart_dirs_');
    home = Directory('${testRoot.path}/home')..createSync(recursive: true);
    xdgDataHome = Directory('${testRoot.path}/xdg_data')
      ..createSync(recursive: true);
    runtimeRoot = Directory('${testRoot.path}/runtime')
      ..createSync(recursive: true);
  });

  tearDown(() {
    testRoot.deleteSync(recursive: true);
    DogPawEntity.environmentOverrides.clear();
  });

  test('directories use XDG defaults and are created', () {
    DogPawEntity.environmentOverrides.addAll({
      'HOME': home.path,
      'XDG_DATA_HOME': xdgDataHome.path,
      'EPIPHANY_INSTANCE': 'alpha',
      'DOGPAW_RUNTIME_DIR': runtimeRoot.path,
    });

    final entity = DogPawEntity('ExampleEntity');

    expect(
      entity.getInstalledAssetsDirectory(),
      '${xdgDataHome.path}/dogpaw/apps/ExampleEntity/assets',
    );
    expect(
      entity.getPersistentAppDataDirectory(),
      '${xdgDataHome.path}/dogpaw/appFiles/ExampleEntity',
    );
    expect(
      entity.getInstanceFileDirectory(),
      '${xdgDataHome.path}/dogpaw/instances/alpha/appFiles/ExampleEntity',
    );
    expect(
      entity.getInstanceTempDirectory(),
      '${runtimeRoot.path}/alpha/appFiles/ExampleEntity',
    );
    expect(
        Directory(entity.getInstalledAssetsDirectory()).existsSync(), isTrue);
    expect(
        Directory(entity.getPersistentAppDataDirectory()).existsSync(), isTrue);
    expect(Directory(entity.getInstanceFileDirectory()).existsSync(), isTrue);
    expect(Directory(entity.getInstanceTempDirectory()).existsSync(), isTrue);
  });

  test('overrides and emulator roots are honored', () {
    final dataRoot = Directory('${testRoot.path}/dogpaw_data');
    final appRoot = Directory('${testRoot.path}/custom_apps');
    DogPawEntity.environmentOverrides.addAll({
      'DOGPAW_DATA_DIR': dataRoot.path,
      'DOGPAW_APP_DIR': appRoot.path,
      'DOGPAW_EMULATOR_NAME': 'emu_one',
      'EPIPHANY_INSTANCE': 'beta',
      'DOGPAW_RUNTIME_DIR': runtimeRoot.path,
    });

    final entity = DogPawEntity('ExampleEntity');

    expect(
      entity.getInstalledAssetsDirectory(),
      '${appRoot.path}/ExampleEntity/assets',
    );
    expect(
      entity.getPersistentAppDataDirectory(),
      '${dataRoot.path}/emulators/emu_one/appFiles/ExampleEntity',
    );
    expect(
      entity.getInstanceFileDirectory(),
      '${dataRoot.path}/instances/beta/appFiles/ExampleEntity',
    );
    expect(
      entity.getInstanceTempDirectory(),
      '${runtimeRoot.path}/beta/appFiles/ExampleEntity',
    );
  });
}
