import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpHost(
  WidgetTester tester, {
  required Widget child,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('showSystemKeyboardTextInputDialog', () {
    testWidgets('Cancel returns null', (WidgetTester tester) async {
      String? result = 'sentinel';

      await _pumpHost(
        tester,
        child: Builder(
          builder: (BuildContext context) {
            return FilledButton(
              onPressed: () async {
                result = await showSystemKeyboardTextInputDialog(
                  context: context,
                  title: 'Save As',
                  initialValue: 'User 1',
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Save As'), findsOneWidget);
      expect(
        find.byKey(const Key('touchscreen-virtual-keyboard')),
        findsNothing,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('OK returns trimmed non-empty text', (WidgetTester tester) async {
      String? result;

      await _pumpHost(
        tester,
        child: Builder(
          builder: (BuildContext context) {
            return FilledButton(
              onPressed: () async {
                result = await showSystemKeyboardTextInputDialog(
                  context: context,
                  title: 'Save As',
                  initialValue: '  My Preset  ',
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, 'My Preset');
    });
  });
}
