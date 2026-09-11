import 'package:dogpaw/dogpaw.dart';
import 'package:dogpaw/src/json_constants.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _sampleTheme() {
  return const ThemeData(
    displayName: 'Shared Sample',
    primaryColor: '#111111',
    secondaryColor: '#222222',
    accentColor: '#333333',
    backgroundColor: '#444444',
  );
}

ScaleData _sampleScale() {
  return ScaleData(
    displayName: 'Shared Scale Sample',
    rootNote: 0,
    noteCategories: List<int>.generate(12, (int i) => i % 3 == 0 ? 3 : 1),
  );
}

void main() {
  group('System shared theme/scale identity contract', () {
    test('canonical item and endpoint names match migration plan', () {
      expect(kSystemEntityName, 'System');
      expect(kSharedThemeItemName, 'shared_theme');
      expect(kSharedScaleItemName, 'shared_scale');
      expect(kSharedThemeInputEndpointName, 'shared_theme_input');
      expect(kSharedThemeOutputEndpointName, 'shared_theme_output');
      expect(kSharedScaleInputEndpointName, 'shared_scale_input');
      expect(kSharedScaleOutputEndpointName, 'shared_scale_output');
    });

    test('wire type and payload contract names are stable', () {
      expect(kThemeEndpointBaseTypeName, 'theme');
      expect(kScaleEndpointBaseTypeName, 'scale');
      expect(kStatefulThemeActionContractName, 'stateful_theme_action');
      expect(kStatefulScaleActionContractName, 'stateful_scale_action');
      expect(kSetValueActionName, 'set_value');
    });

    test('system namespace selector targets specific System entity', () {
      final NamespaceSelector ns = systemEntityNamespace();
      expect(ns.isSpecificEntity, isTrue);
      expect(ns.sourceEntity, 'System');
      expect(ns.isGlobal, isFalse);
      expect(ns.isCurrentEntity, isFalse);
    });

    test('canonical item refs use System namespace and stable names', () {
      final DataItemRef themeRef = sharedThemeItemRef();
      expect(themeRef.name, 'shared_theme');
      expect(themeRef.namespaceSelector.sourceEntity, 'System');
      expect(isSharedThemeItemRef(themeRef), isTrue);

      final DataItemRef scaleRef = sharedScaleItemRef();
      expect(scaleRef.name, 'shared_scale');
      expect(isSharedScaleItemRef(scaleRef), isTrue);
    });

    test('named data references never use current', () {
      final DataReference<Theme> themeRef = sharedThemeDataReference();
      expect(themeRef.type, ReferenceType.name);
      expect(themeRef.name, 'shared_theme');
      expect(themeRef.namespaceSelector.sourceEntity, 'System');
      expect(themeRef.type, isNot(ReferenceType.current));

      final DataReference<Scale> scaleRef = sharedScaleDataReference();
      expect(scaleRef.type, ReferenceType.name);
      expect(scaleRef.name, 'shared_scale');
      expect(scaleRef.type, isNot(ReferenceType.current));
    });

    test('ref predicates reject near-miss names and namespaces', () {
      expect(
        isSharedThemeItemRef(
          DataItemRef.byName(
            name: 'shared_theme_input',
            namespaceSelector: systemEntityNamespace(),
          ),
        ),
        isFalse,
      );
      expect(
        isSharedThemeItemRef(
          DataItemRef.byName(
            name: 'shared_theme',
            namespaceSelector: const NamespaceSelector.global(),
          ),
        ),
        isFalse,
      );
      expect(
        isSharedThemeItemRef(
          DataItemRef.byName(
            name: 'shared_theme',
            namespaceSelector:
                const NamespaceSelector.specificEntity('DemoMode'),
          ),
        ),
        isFalse,
      );
      expect(
        isSharedScaleItemRef(sharedThemeItemRef()),
        isFalse,
      );
    });
  });

  group('System shared theme/scale stateful spec contract', () {
    test('shared theme stateful spec is ownerManaged with matched output', () {
      final ThemeData theme = _sampleTheme();
      final EndpointStatefulInputSpec spec =
          makeSharedThemeStatefulInputSpec(initialThemeData: theme);

      expect(spec.behavior, StatefulInputBehavior.ownerManaged);
      expect(
        spec.consumptionMode,
        StatefulInputConsumptionMode.callbackAndRetainedState,
      );
      expect(spec.initialValue, theme.toJson());
      expect(spec.matchedOutput, isNotNull);
      expect(spec.matchedOutput!.name, 'shared_theme_output');
      expect(spec.matchedOutput!.flags, <String>['public_state']);
      expect(spec.matchedOutput!.groupKey, 'theme');
    });

    test('shared scale stateful spec is ownerManaged with matched output', () {
      final ScaleData scale = _sampleScale();
      final EndpointStatefulInputSpec spec =
          makeSharedScaleStatefulInputSpec(initialScaleData: scale);

      expect(spec.behavior, StatefulInputBehavior.ownerManaged);
      expect(spec.initialValue, scale.toJson());
      expect(spec.matchedOutput!.name, 'shared_scale_output');
      expect(spec.matchedOutput!.groupKey, 'scale');
    });

    test('shared theme stateful spec omits initial value when not provided',
        () {
      final EndpointStatefulInputSpec spec = makeSharedThemeStatefulInputSpec();
      expect(spec.initialValue, isNull);
      expect(spec.matchedOutput!.name, 'shared_theme_output');
    });

    test('shared theme stateful spec round-trips through JSON', () {
      final ThemeData theme = _sampleTheme();
      final EndpointStatefulInputSpec original =
          makeSharedThemeStatefulInputSpec(initialThemeData: theme);
      final EndpointStatefulInputSpec parsed =
          EndpointStatefulInputSpec.fromJson(original.toJson());

      expect(parsed.behavior, StatefulInputBehavior.ownerManaged);
      expect(parsed.initialValue, theme.toJson());
      expect(parsed.matchedOutput!.name, 'shared_theme_output');
      expect(parsed.matchedOutput!.groupKey, 'theme');
    });
  });

  group('System shared theme/scale action contract', () {
    test('theme set_value action round-trips full object only', () {
      final ThemeData theme = _sampleTheme();
      final Map<String, dynamic> action = makeSharedThemeSetValueAction(theme);

      expect(action[JsonFields.ACTION], 'set_value');
      expect(action[JsonFields.VALUE], theme.toJson());
      expect(action.containsKey('patch'), isFalse);
      expect(action.containsKey('delta'), isFalse);

      final ThemeData? parsed = parseSharedThemeSetValueAction(action);
      expect(parsed, theme);
    });

    test('scale set_value action round-trips full object only', () {
      final ScaleData scale = _sampleScale();
      final Map<String, dynamic> action = makeSharedScaleSetValueAction(scale);

      expect(action[JsonFields.ACTION], 'set_value');
      expect(action[JsonFields.VALUE], scale.toJson());

      final ScaleData? parsed = parseSharedScaleSetValueAction(action);
      expect(parsed, scale);
    });

    test('theme action parser rejects non-set_value and malformed payloads',
        () {
      expect(
        parseSharedThemeSetValueAction(<String, dynamic>{
          JsonFields.ACTION: 'add',
          JsonFields.VALUE: _sampleTheme().toJson(),
        }),
        isNull,
      );
      expect(
        parseSharedThemeSetValueAction(<String, dynamic>{
          JsonFields.ACTION: 'set_value',
          'patch': _sampleTheme().toJson(),
        }),
        isNull,
      );
      expect(
        parseSharedThemeSetValueAction(<String, dynamic>{
          JsonFields.ACTION: 'set_value',
          JsonFields.VALUE: '#ff0000',
        }),
        isNull,
      );
      expect(
        parseSharedThemeSetValueAction(<String, dynamic>{
          JsonFields.ACTION: 'set_value',
          JsonFields.VALUE: <String, dynamic>{
            JsonFields.DISPLAY_NAME: 'Incomplete',
            JsonFields.PRIMARY_COLOR: '#000000',
          },
        }),
        isNull,
      );
    });

    test('scale action parser rejects non-set_value and malformed payloads',
        () {
      expect(
        parseSharedScaleSetValueAction(<String, dynamic>{
          JsonFields.ACTION: 'toggle',
          JsonFields.VALUE: _sampleScale().toJson(),
        }),
        isNull,
      );
      expect(
        parseSharedScaleSetValueAction(<String, dynamic>{
          JsonFields.ACTION: 'set_value',
          JsonFields.VALUE: 12,
        }),
        isNull,
      );
      expect(
        parseSharedScaleSetValueAction(<String, dynamic>{
          JsonFields.ACTION: 'set_value',
          JsonFields.VALUE: <String, dynamic>{
            JsonFields.ROOT_NOTE: 0,
            JsonFields.NOTE_CATEGORIES: <int>[1, 1, 1],
          },
        }),
        isNull,
      );
    });
  });

  group('Phase D layout shared-resolution contract', () {
    test('shared theme choice resolves to System/shared_theme', () {
      final LayoutThemeChoice choice = const LayoutThemeChoice.shared();
      final DataReference<Theme> active = choice.toDataReference();
      expect(active.type, ReferenceType.name);
      expect(active.name, kSharedThemeItemName);
      expect(active.namespaceSelector.sourceEntity, kSystemEntityName);
      expect(active.type, isNot(ReferenceType.current));
    });

    test('shared scale choice resolves to System/shared_scale', () {
      final LayoutScaleChoice choice = const LayoutScaleChoice.shared();
      final DataReference<Scale> active = choice.toDataReference();
      expect(active.type, ReferenceType.name);
      expect(active.name, kSharedScaleItemName);
      expect(active.namespaceSelector.sourceEntity, kSystemEntityName);
      expect(active.type, isNot(ReferenceType.current));
    });

    test('override choices remain inline', () {
      final ThemeData theme = _sampleTheme();
      final ScaleData scale = _sampleScale();

      final DataReference<Theme> themeRef =
          LayoutThemeChoice.overrideValue(theme).toDataReference();
      final DataReference<Scale> scaleRef =
          LayoutScaleChoice.overrideValue(scale).toDataReference();

      expect(themeRef.type, ReferenceType.inline);
      expect(themeRef.inlineData!.spec, theme);
      expect(scaleRef.type, ReferenceType.inline);
      expect(scaleRef.inlineData!.spec, scale);
    });

    test('shared serialization preserves dormant override payloads', () {
      final LayoutThemeChoice themeChoice =
          LayoutThemeChoice.shared(overrideTheme: _sampleTheme());
      final LayoutScaleChoice scaleChoice =
          LayoutScaleChoice.shared(overrideScale: _sampleScale());

      final LayoutThemeChoice restoredTheme =
          LayoutThemeChoice.fromJson(themeChoice.toJson());
      final LayoutScaleChoice restoredScale =
          LayoutScaleChoice.fromJson(scaleChoice.toJson());

      expect(restoredTheme.activeSource, LayoutChoiceActiveSource.shared);
      expect(restoredTheme.overrideTheme, _sampleTheme());
      expect(restoredTheme.toDataReference().type, ReferenceType.name);
      expect(restoredScale.activeSource, LayoutChoiceActiveSource.shared);
      expect(restoredScale.overrideScale, _sampleScale());
      expect(restoredScale.toDataReference().type, ReferenceType.name);
    });
  });
}
