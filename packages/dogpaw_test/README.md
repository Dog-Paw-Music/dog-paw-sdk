# dogpaw_test

Public Dog Paw test helpers for app authors.

Use this package when you are writing:

- widget tests for Dog Paw Flutter UI
- integration tests that need Epiphany
- installed-layout launch tests for apps under test

Some internal repo-only helpers such as `TestEntities` exist outside this
public package surface and are intentionally not covered here.

## What It Exports

- `IntegrationTestFixture` for Epiphany lifecycle management
- `integrationTest()` for buffered log sections
- `DogpawIntegrationTestConfiguration` for explicit runtime and staging config
- `DogpawAppInstallSource` and `stageInstalledDogpawApps()` for installed-layout staging
- `wrapForTest()`, `wrapDialogForTest()`, and `defaultTestTheme()`
- `uniqueName()`, `waitFor()`, and `waitForValue()`

## Why Installed Layout Staging

Public app-integration tests should exercise the same runtime contract that real
installs use. `dogpaw_test` stages apps into `DOGPAW_APP_DIR` and launches
Epiphany against that installed app registry, instead of relying on source-tree
fallbacks such as `DOGPAW_APP_DEV_ROOTS`.

This keeps the public test story consistent between:

- the monorepo
- an exported SDK
- future automation that prepares test environments explicitly

## Basic Widget Test

```dart
import 'package:dogpaw_test/dogpaw_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows my widget', (tester) async {
    await tester.pumpWidget(wrapForTest(MyWidget()));
    expect(find.text('Hello'), findsOneWidget);
  });
}
```

## Basic Integration Test

```dart
import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw_test/dogpaw_test.dart';

void main() {
  IntegrationTestFixture.register();

  integrationTest('connects to Epiphany', () async {
    final entity = DogPawEntity(uniqueName('MyTestEntity'));
    final result = await entity.connect();
    expect(result.success, isTrue, reason: result.error);
    entity.disconnect();
  });
}
```

`IntegrationTestFixture` resolves Epiphany in this order:

- `DogpawIntegrationTestConfiguration.epiphanyPath`
- `EPIPHANY_PATH`
- the packaged SDK runtime binary under `runtime/bin/<platform>/Epiphany`
- nearby local build outputs when running from a source checkout

That means:

- in an exported SDK, the default packaged runtime can be discovered
  automatically
- in a source checkout, common local build outputs can be discovered
  automatically for convenience, but `EPIPHANY_PATH` and `epiphanyPath`
  remain the most predictable overrides

## Staging An App Under Test

```dart
import 'package:dogpaw_test/dogpaw_test.dart';

Future<void> main() async {
  final DogpawAppInstallSource launchTestStub =
      await buildLaunchTestStubInstallSource();

  IntegrationTestFixture.register(
    configuration: DogpawIntegrationTestConfiguration(
      installedApps: <DogpawAppInstallSource>[
        launchTestStub,
      ],
    ),
  );
}
```
