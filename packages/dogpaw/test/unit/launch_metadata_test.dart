import 'dart:io';

import 'package:dogpaw/dogpaw.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDogpawLaunchMetadata', () {
    test('reads JSON metadata through the standard launch flag', () async {
      final Directory tempDirectory = await Directory.systemTemp.createTemp(
        'dogpaw_launch_metadata_test_',
      );

      try {
        final File metadataFile =
            File('${tempDirectory.path}/launch_metadata.json');
        await metadataFile.writeAsString(
          '{"page":"scale","actions":["openDialog"]}',
        );

        final Map<String, dynamic>? metadata = await parseDogpawLaunchMetadata(
          executableArguments: <String>[
            '--dogpaw-launch-metadata',
            metadataFile.path,
          ],
        );

        expect(metadata, isNotNull);
        expect(metadata!['page'], equals('scale'));
        expect(metadata['actions'], equals(const <String>['openDialog']));
      } finally {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });

    test('returns null when no launch metadata flag is present', () async {
      final Map<String, dynamic>? metadata = await parseDogpawLaunchMetadata(
        executableArguments: const <String>['--verbose'],
      );

      expect(metadata, isNull);
    });
  });
}
