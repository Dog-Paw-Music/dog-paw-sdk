import 'package:dogpaw_widgets/dogpaw_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('white keys keep their placement and black keys grow taller',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: 420,
              child: PianoKeyboard(
                height: 140,
                colorForNote: (_) => Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder blackKey = find
        .ancestor(
          of: find.text('Db'),
          matching: find.byType(GestureDetector),
        )
        .first;
    final Finder whiteKey = find
        .ancestor(
          of: find.text('C'),
          matching: find.byType(GestureDetector),
        )
        .first;

    final Size blackKeySize = tester.getSize(blackKey);
    final Rect blackKeyRect = tester.getRect(blackKey);
    final Rect whiteKeyRect = tester.getRect(whiteKey);

    expect(blackKeyRect.top, equals(whiteKeyRect.top));
    expect(blackKeySize.height, greaterThan(blackKeySize.width));
    expect(blackKeySize, const Size(36, 48));
  });
}
