import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter_test/flutter_test.dart';
import 'package:hello_dogpaw/app.dart';
import 'package:hello_dogpaw/controllers/hello_controller.dart';
import 'package:provider/provider.dart';

/// Smoke: the shell paints. Connection to Epiphany is not required to pass.
void main() {
  testWidgets('hello app shows title and color rows', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<HelloController>(
        create: (_) => HelloController(
          entity: dp.DogPawEntity('HelloDogPawSmoke'),
        ),
        child: const HelloDogPawApp(),
      ),
    );

    // Let the post-frame start() attempt run (it will fail without Epiphany).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Hello Dog Paw'), findsOneWidget);
    expect(find.text('Active Keys'), findsOneWidget);
    expect(find.text('Pressed Keys'), findsOneWidget);
  });
}
