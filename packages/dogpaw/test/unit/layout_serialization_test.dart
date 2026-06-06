import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:test/test.dart';

const String _legacyBaseLayoutsField = 'baseLayouts';

void main() {
  group('Layout serialization', () {
    test('legacy baseLayouts input is not preserved on round-trip', () {
      final Layout layout = Layout.fromJson(<String, dynamic>{
        JsonFields.NAME: 'layout_with_legacy_base',
        JsonFields.NAMESPACE_SELECTOR:
            const NamespaceSelector.global().toJson(),
        JsonFields.SPEC: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Legacy Base Layout Input',
          _legacyBaseLayoutsField: <Map<String, dynamic>>[
            <String, dynamic>{
              JsonFields.NAME: 'base_layout',
              JsonFields.NAMESPACE_SELECTOR:
                  const NamespaceSelector.global().toJson(),
            },
          ],
        },
      });

      final Map<String, dynamic> serialized = layout.toJson();
      expect(serialized.containsKey(JsonFields.SPEC), isTrue);

      final Map<String, dynamic> spec =
          serialized[JsonFields.SPEC] as Map<String, dynamic>;
      expect(spec.containsKey(_legacyBaseLayoutsField), isFalse);
    });

    test('shared layout scope round-trips through layout JSON', () {
      final Layout layout = Layout.fromJson(<String, dynamic>{
        JsonFields.NAME: 'shared_layout',
        JsonFields.NAMESPACE_SELECTOR:
            const NamespaceSelector.global().toJson(),
        JsonFields.SPEC: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Shared Layout',
          JsonFields.SCOPE: 'shared',
        },
      });

      final Map<String, dynamic> serialized = layout.toJson();
      final Map<String, dynamic> spec =
          serialized[JsonFields.SPEC] as Map<String, dynamic>;
      expect(spec[JsonFields.SCOPE], equals('shared'));
      expect(spec.containsKey(JsonFields.TARGET_KEY), isFalse);
    });

    test('targeted layout scope round-trips targetKey through layout JSON', () {
      final Layout layout = Layout.fromJson(<String, dynamic>{
        JsonFields.NAME: 'targeted_layout',
        JsonFields.NAMESPACE_SELECTOR:
            const NamespaceSelector.global().toJson(),
        JsonFields.SPEC: <String, dynamic>{
          JsonFields.DISPLAY_NAME: 'Targeted Layout',
          JsonFields.SCOPE: 'targeted',
          JsonFields.TARGET_KEY: 'controller:left',
        },
      });

      final Map<String, dynamic> serialized = layout.toJson();
      final Map<String, dynamic> spec =
          serialized[JsonFields.SPEC] as Map<String, dynamic>;
      expect(spec[JsonFields.SCOPE], equals('targeted'));
      expect(spec[JsonFields.TARGET_KEY], equals('controller:left'));
    });
  });
}
