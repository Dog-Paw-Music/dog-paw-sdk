import 'package:dogpaw/dogpaw.dart' as dp;
import 'package:flutter_test/flutter_test.dart';
import 'package:hello_dogpaw/app.dart';
import 'package:hello_dogpaw/controllers/hello_controller.dart';
import 'package:provider/provider.dart';

class StubHelloDogPawClient implements HelloDogPawClient {
  @override
  Future<dp.ConnectionResult> connect() async {
    return dp.ConnectionResult.error('unused in widget test');
  }

  @override
  Future<dp.Result<dp.LocalEndpoint>> createEndpoint(dp.EndpointInfo endpoint) async {
    return dp.Result.error('unused in widget test');
  }

  @override
  void disconnect() {}
}

void main() {
  testWidgets('hello app shows intro text and swatch controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<HelloController>(
        create: (_) => HelloController(client: StubHelloDogPawClient()),
        child: const HelloDogPawApp(),
      ),
    );

    expect(find.text('Hello Dog Paw'), findsOneWidget);
    expect(find.text('Active Keys'), findsOneWidget);
    expect(find.text('Pressed Keys'), findsOneWidget);
    expect(find.textContaining('auto-connects on startup'), findsOneWidget);
  });
}
