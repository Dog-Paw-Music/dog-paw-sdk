import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:dogpaw_widgets/src/inputs/compositor_keyboard_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCompositorKeyboardControl
    implements CompositorKeyboardControl {
  int showCount = 0;
  int hideCount = 0;

  @override
  Future<void> show() async {
    showCount += 1;
  }

  @override
  Future<void> hide() async {
    hideCount += 1;
  }
}

/// Pump [child] inside a large enough MaterialApp for text-field tests.
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
  group('SystemKeyboardTextField', () {
    testWidgets('renders an editable field without an embedded keyboard',
        (WidgetTester tester) async {
      final TextEditingController textController = TextEditingController();
      addTearDown(textController.dispose);

      await _pumpHost(
        tester,
        child: SystemKeyboardTextField(
          key: const Key('system-keyboard-field'),
          textController: textController,
          hintText: 'Name',
        ),
      );

      expect(find.byKey(const Key('touchscreen-virtual-keyboard')),
          findsNothing);

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isFalse);
      expect(field.enabled, isTrue);
    });

    testWidgets('accepts programmatic and typed text',
        (WidgetTester tester) async {
      final TextEditingController textController = TextEditingController();
      addTearDown(textController.dispose);

      await _pumpHost(
        tester,
        child: SystemKeyboardTextField(
          textController: textController,
          hintText: 'Name',
        ),
      );

      await tester.enterText(find.byType(TextField), 'Alpha!');
      await tester.pumpAndSettle();

      expect(textController.text, 'Alpha!');
    });

    testWidgets('obscureText starts hidden and toggle reveals text',
        (WidgetTester tester) async {
      final TextEditingController textController =
          TextEditingController(text: 'secret');
      addTearDown(textController.dispose);

      await _pumpHost(
        tester,
        child: SystemKeyboardTextField(
          textController: textController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
      );

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(
        find.byKey(const Key('system-keyboard-text-obscure-toggle')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('system-keyboard-text-obscure-toggle')),
      );
      await tester.pumpAndSettle();

      final TextField revealed =
          tester.widget<TextField>(find.byType(TextField));
      expect(revealed.obscureText, isFalse);
    });

    testWidgets('onSubmitted fires when the user submits the field',
        (WidgetTester tester) async {
      final TextEditingController textController =
          TextEditingController(text: 'Alpha');
      int submitCount = 0;
      addTearDown(textController.dispose);

      await _pumpHost(
        tester,
        child: SystemKeyboardTextField(
          textController: textController,
          onSubmitted: () {
            submitCount += 1;
          },
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(submitCount, 1);
    });

    testWidgets('optional bottom inset reserves space below the field',
        (WidgetTester tester) async {
      final TextEditingController textController = TextEditingController();
      addTearDown(textController.dispose);

      await _pumpHost(
        tester,
        child: SystemKeyboardTextField(
          textController: textController,
          keyboardBottomInset: 280,
        ),
      );

      expect(find.byKey(const Key('system-keyboard-bottom-inset')),
          findsOneWidget);
      final SizedBox inset = tester.widget<SizedBox>(
        find.byKey(const Key('system-keyboard-bottom-inset')),
      );
      expect(inset.height, 280);
    });

    testWidgets('shows compositor keyboard on tap and hides on unfocus',
        (WidgetTester tester) async {
      final TextEditingController textController = TextEditingController();
      final _RecordingCompositorKeyboardControl keyboardControl =
          _RecordingCompositorKeyboardControl();
      addTearDown(textController.dispose);

      await _pumpHost(
        tester,
        child: SystemKeyboardTextField(
          textController: textController,
          compositorKeyboardControl: keyboardControl,
        ),
      );

      expect(keyboardControl.showCount, 0);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(keyboardControl.showCount, greaterThanOrEqualTo(1));

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(keyboardControl.hideCount, greaterThanOrEqualTo(1));
    });

    testWidgets('autofocus requests compositor keyboard show',
        (WidgetTester tester) async {
      final TextEditingController textController = TextEditingController();
      final _RecordingCompositorKeyboardControl keyboardControl =
          _RecordingCompositorKeyboardControl();
      addTearDown(textController.dispose);

      await _pumpHost(
        tester,
        child: SystemKeyboardTextField(
          textController: textController,
          autofocus: true,
          compositorKeyboardControl: keyboardControl,
        ),
      );

      expect(keyboardControl.showCount, greaterThanOrEqualTo(1));
    });
  });
}
