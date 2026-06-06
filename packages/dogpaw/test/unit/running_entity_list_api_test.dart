import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

void main() {
  test('listRunningEntities is exposed as a public DogPawEntity request API',
      () async {
    final DogPawEntity entity = DogPawEntity('RunningEntityListApiContract');

    final Result<Map<String, dynamic>> result = await entity.listRunningEntities();

    expect(result.success, isFalse);
    expect(result.error, contains('DogPawEntity is not connected'));
  });
}
