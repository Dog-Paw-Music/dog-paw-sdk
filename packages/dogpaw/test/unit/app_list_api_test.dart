import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

void main() {
  test('listApps is exposed as a public DogPawEntity request API', () async {
    final DogPawEntity entity = DogPawEntity('AppListApiContract');

    final Result<Map<String, dynamic>> result = await entity.listApps();

    expect(result.success, isFalse);
    expect(result.error, contains('DogPawEntity is not connected'));
  });
}
