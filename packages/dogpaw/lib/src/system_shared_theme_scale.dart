/// Purpose:
/// Canonical System-owned shared theme/scale identity and endpoint contracts.
///
/// Architecture:
/// Mirrors `dogpawEntity/cpp/SystemSharedThemeScale.hpp` so Dart apps, editors,
/// and tests use the same names and OWNER_MANAGED input shapes as C++.
import 'data_item_ref.dart';
import 'data_reference.dart';
import 'data_type_spec.dart';
import 'data_types.dart';
import 'connection_policy.dart';
import 'endpoint.dart';
import 'json_constants.dart';
import 'namespace_selector.dart';
import 'scale.dart';
import 'search_criteria.dart';
import 'theme.dart';

/// Entity name that owns shared theme/scale surfaces and named items.
const String kSystemEntityName = 'System';

/// Canonical named Theme item owned by System.
const String kSharedThemeItemName = 'shared_theme';

/// Canonical named Scale item owned by System.
const String kSharedScaleItemName = 'shared_scale';

/// Stateful input endpoint that accepts shared theme writes.
const String kSharedThemeInputEndpointName = 'shared_theme_input';

/// Matched output endpoint that publishes committed shared theme state.
const String kSharedThemeOutputEndpointName = 'shared_theme_output';

/// Stateful input endpoint that accepts shared scale writes.
const String kSharedScaleInputEndpointName = 'shared_scale_input';

/// Matched output endpoint that publishes committed shared scale state.
const String kSharedScaleOutputEndpointName = 'shared_scale_output';

/// Wire base-type name for theme queue endpoints (Phase B DataType).
const String kThemeEndpointBaseTypeName = 'theme';

/// Wire base-type name for scale queue endpoints (Phase B DataType).
const String kScaleEndpointBaseTypeName = 'scale';

/// Message-queue payload contract name for theme stateful actions.
const String kStatefulThemeActionContractName = 'stateful_theme_action';

/// Message-queue payload contract name for scale stateful actions.
const String kStatefulScaleActionContractName = 'stateful_scale_action';

/// v1 theme/scale action verb: full-object replacement only.
const String kSetValueActionName = 'set_value';

/// Matched-output group key for shared theme.
const String kSharedThemeGroupKey = 'theme';

/// Matched-output group key for shared scale.
const String kSharedScaleGroupKey = 'scale';

/// Public-state flag published on matched shared outputs.
const String kPublicStateFlag = 'public_state';

/**
 * Purpose: Namespace selector for the System entity.
 *
 * Parameters: none.
 *
 * Return value: Selector targeting entity namespace `System`.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Returned selector is specificEntity(`System`).
 *
 * Invariants: Pure construction with no I/O.
 */
NamespaceSelector systemEntityNamespace() {
  return const NamespaceSelector.specificEntity(kSystemEntityName);
}

/**
 * Purpose: Build the canonical shared Theme data-item ref.
 *
 * Parameters: none.
 *
 * Return value: `DataItemRef` for `System/shared_theme`.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Name and namespace match the shared theme contract.
 *
 * Invariants: Pure construction.
 */
DataItemRef sharedThemeItemRef() {
  return DataItemRef.byName(
    name: kSharedThemeItemName,
    namespaceSelector: systemEntityNamespace(),
  );
}

/**
 * Purpose: Build the canonical shared Scale data-item ref.
 *
 * Parameters: none.
 *
 * Return value: `DataItemRef` for `System/shared_scale`.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Name and namespace match the shared scale contract.
 *
 * Invariants: Pure construction.
 */
DataItemRef sharedScaleItemRef() {
  return DataItemRef.byName(
    name: kSharedScaleItemName,
    namespaceSelector: systemEntityNamespace(),
  );
}

/**
 * Purpose: Build a named DataReference to the canonical shared Theme item.
 *
 * Parameters: none.
 *
 * Return value: `DataReference` pointing at `System/shared_theme`.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Type is name; never current.
 *
 * Invariants: Pure construction.
 */
DataReference<Theme> sharedThemeDataReference() {
  return DataReference<Theme>.byName(
    kSharedThemeItemName,
    namespaceSelector: systemEntityNamespace(),
  );
}

/**
 * Purpose: Build a named DataReference to the canonical shared Scale item.
 *
 * Parameters: none.
 *
 * Return value: `DataReference` pointing at `System/shared_scale`.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Type is name; never current.
 *
 * Invariants: Pure construction.
 */
DataReference<Scale> sharedScaleDataReference() {
  return DataReference<Scale>.byName(
    kSharedScaleItemName,
    namespaceSelector: systemEntityNamespace(),
  );
}

/**
 * Purpose: Build an app-owned output spec that writes shared theme actions to
 * `System/shared_theme_input`.
 *
 * Parameters:
 * - `displayName`: Human-readable local endpoint label.
 * - `description`: Human-readable local endpoint purpose.
 *
 * Return value: Message-queue THEME output spec with a System input connection
 * rule.
 *
 * Requirements/Preconditions: Labels should be meaningful to endpoint
 * diagnostics.
 *
 * Guarantees/Postconditions: The rule matches only the canonical System shared
 * theme input.
 *
 * Invariants: The helper creates metadata only and performs no runtime I/O.
 */
EndpointSpec makeSharedThemeWriterEndpointSpec({
  required String displayName,
  required String description,
  bool hideFromPicker = false,
}) {
  return EndpointSpec(
    displayName: displayName,
    description: description,
    direction: EndpointDirection.output,
    dataType: const DataTypeSpec(DataType.theme),
    category: EndpointCategory.messageQueue,
    hideFromPicker: hideFromPicker,
    connectionPolicy: ConnectionPolicy(
      endpointConnectionRule: SearchCriteria.andCombination(
        <SearchCriteria>[
          SearchCriteria.directionEquals(EndpointDirection.input),
          SearchCriteria.sourceEntityEquals(kSystemEntityName),
          SearchCriteria.nameEquals(kSharedThemeInputEndpointName),
          SearchCriteria.baseTypeEquals(DataType.theme),
        ],
      ),
    ),
  );
}

/**
 * Purpose: Build an app-owned input spec that subscribes to committed shared
 * theme state from `System/shared_theme_output`.
 *
 * Parameters:
 * - `displayName`: Human-readable local endpoint label.
 * - `description`: Human-readable local endpoint purpose.
 * - `initialThemeData`: Optional ephemeral cache before System publishes.
 *
 * Return value: Stateful message-queue THEME input spec connected to the
 * canonical System matched output.
 *
 * Requirements/Preconditions: Any initial value must be a valid full ThemeData.
 *
 * Guarantees/Postconditions: Incoming committed values replace retained state.
 *
 * Invariants: System's matched output remains the authoritative source.
 */
EndpointSpec makeSharedThemeSubscriberEndpointSpec({
  required String displayName,
  required String description,
  ThemeData? initialThemeData,
  bool hideFromPicker = false,
}) {
  return EndpointSpec(
    displayName: displayName,
    description: description,
    direction: EndpointDirection.input,
    dataType: const DataTypeSpec(DataType.theme),
    category: EndpointCategory.messageQueue,
    hideFromPicker: hideFromPicker,
    connectionPolicy: ConnectionPolicy(
      endpointConnectionRule: SearchCriteria.andCombination(
        <SearchCriteria>[
          SearchCriteria.directionEquals(EndpointDirection.output),
          SearchCriteria.sourceEntityEquals(kSystemEntityName),
          SearchCriteria.nameEquals(kSharedThemeOutputEndpointName),
          SearchCriteria.baseTypeEquals(DataType.theme),
        ],
      ),
    ),
    statefulInput: EndpointStatefulInputSpec(
      behavior: StatefulInputBehavior.autoReduced,
      consumptionMode: StatefulInputConsumptionMode.callbackAndRetainedState,
      initialValue: initialThemeData?.toJson(),
    ),
  );
}

/**
 * Purpose: Build an app-owned output spec that writes shared scale actions to
 * `System/shared_scale_input`.
 *
 * Parameters:
 * - `displayName`: Human-readable local endpoint label.
 * - `description`: Human-readable local endpoint purpose.
 *
 * Return value: Message-queue SCALE output spec with a System input connection
 * rule.
 *
 * Requirements/Preconditions: Labels should be meaningful to endpoint
 * diagnostics.
 *
 * Guarantees/Postconditions: The rule matches only the canonical System shared
 * scale input.
 *
 * Invariants: The helper creates metadata only and performs no runtime I/O.
 */
EndpointSpec makeSharedScaleWriterEndpointSpec({
  required String displayName,
  required String description,
  bool hideFromPicker = false,
}) {
  return EndpointSpec(
    displayName: displayName,
    description: description,
    direction: EndpointDirection.output,
    dataType: const DataTypeSpec(DataType.scale),
    category: EndpointCategory.messageQueue,
    hideFromPicker: hideFromPicker,
    connectionPolicy: ConnectionPolicy(
      endpointConnectionRule: SearchCriteria.andCombination(
        <SearchCriteria>[
          SearchCriteria.directionEquals(EndpointDirection.input),
          SearchCriteria.sourceEntityEquals(kSystemEntityName),
          SearchCriteria.nameEquals(kSharedScaleInputEndpointName),
          SearchCriteria.baseTypeEquals(DataType.scale),
        ],
      ),
    ),
  );
}

/**
 * Purpose: Build an app-owned input spec that subscribes to committed shared
 * scale state from `System/shared_scale_output`.
 *
 * Parameters:
 * - `displayName`: Human-readable local endpoint label.
 * - `description`: Human-readable local endpoint purpose.
 * - `initialScaleData`: Optional ephemeral cache before System publishes.
 *
 * Return value: Stateful message-queue SCALE input spec connected to the
 * canonical System matched output.
 *
 * Requirements/Preconditions: Any initial value must be valid full ScaleData.
 *
 * Guarantees/Postconditions: Incoming committed values replace retained state.
 *
 * Invariants: System's matched output remains the authoritative source.
 */
EndpointSpec makeSharedScaleSubscriberEndpointSpec({
  required String displayName,
  required String description,
  ScaleData? initialScaleData,
  bool hideFromPicker = false,
}) {
  return EndpointSpec(
    displayName: displayName,
    description: description,
    direction: EndpointDirection.input,
    dataType: const DataTypeSpec(DataType.scale),
    category: EndpointCategory.messageQueue,
    hideFromPicker: hideFromPicker,
    connectionPolicy: ConnectionPolicy(
      endpointConnectionRule: SearchCriteria.andCombination(
        <SearchCriteria>[
          SearchCriteria.directionEquals(EndpointDirection.output),
          SearchCriteria.sourceEntityEquals(kSystemEntityName),
          SearchCriteria.nameEquals(kSharedScaleOutputEndpointName),
          SearchCriteria.baseTypeEquals(DataType.scale),
        ],
      ),
    ),
    statefulInput: EndpointStatefulInputSpec(
      behavior: StatefulInputBehavior.autoReduced,
      consumptionMode: StatefulInputConsumptionMode.callbackAndRetainedState,
      initialValue: initialScaleData?.toJson(),
    ),
  );
}

/**
 * Purpose: True when `ref` identifies the canonical shared Theme item.
 *
 * Parameters:
 * - `ref`: Candidate data-item ref.
 *
 * Return value: true when name and System namespace match `shared_theme`.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Exact comparison only.
 *
 * Invariants: No CURRENT or global aliases.
 */
bool isSharedThemeItemRef(DataItemRef ref) {
  return ref == sharedThemeItemRef();
}

/**
 * Purpose: True when `ref` identifies the canonical shared Scale item.
 *
 * Parameters:
 * - `ref`: Candidate data-item ref.
 *
 * Return value: true when name and System namespace match `shared_scale`.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Exact comparison only.
 *
 * Invariants: No CURRENT or global aliases.
 */
bool isSharedScaleItemRef(DataItemRef ref) {
  return ref == sharedScaleItemRef();
}

/**
 * Purpose: Build OWNER_MANAGED matched-output config for shared theme.
 *
 * Parameters: none.
 *
 * Return value: Matched output spec named `shared_theme_output`.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Flags include `public_state`; groupKey is `theme`.
 *
 * Invariants: Does not create runtime endpoints.
 */
MatchedStateOutputSpec makeSharedThemeMatchedOutputSpec() {
  return const MatchedStateOutputSpec(
    name: kSharedThemeOutputEndpointName,
    displayName: 'Shared Theme',
    description: 'Committed System-owned shared theme state for subscribers',
    flags: <String>[kPublicStateFlag],
    groupKey: kSharedThemeGroupKey,
  );
}

/**
 * Purpose: Build OWNER_MANAGED matched-output config for shared scale.
 *
 * Parameters: none.
 *
 * Return value: Matched output spec named `shared_scale_output`.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Flags include `public_state`; groupKey is `scale`.
 *
 * Invariants: Does not create runtime endpoints.
 */
MatchedStateOutputSpec makeSharedScaleMatchedOutputSpec() {
  return const MatchedStateOutputSpec(
    name: kSharedScaleOutputEndpointName,
    displayName: 'Shared Scale',
    description: 'Committed System-owned shared scale state for subscribers',
    flags: <String>[kPublicStateFlag],
    groupKey: kSharedScaleGroupKey,
  );
}

/**
 * Purpose: Build the stateful-input nested spec for shared theme writes.
 *
 * Parameters:
 * - `initialThemeData`: Optional ThemeData seed for retained initialValue.
 *
 * Return value: EndpointStatefulInputSpec for `shared_theme_input`.
 *
 * Requirements/Preconditions: When provided, `initialThemeData` should be valid.
 *
 * Guarantees/Postconditions: behavior is ownerManaged; matched output is set.
 *
 * Invariants: Full-object replacement is the only intended v1 action vocabulary.
 */
EndpointStatefulInputSpec makeSharedThemeStatefulInputSpec({
  ThemeData? initialThemeData,
}) {
  return EndpointStatefulInputSpec(
    behavior: StatefulInputBehavior.ownerManaged,
    consumptionMode: StatefulInputConsumptionMode.callbackAndRetainedState,
    initialValue: initialThemeData?.toJson(),
    matchedOutput: makeSharedThemeMatchedOutputSpec(),
  );
}

/**
 * Purpose: Build the stateful-input nested spec for shared scale writes.
 *
 * Parameters:
 * - `initialScaleData`: Optional ScaleData seed for retained initialValue.
 *
 * Return value: EndpointStatefulInputSpec for `shared_scale_input`.
 *
 * Requirements/Preconditions: When provided, `initialScaleData` should be valid.
 *
 * Guarantees/Postconditions: behavior is ownerManaged; matched output is set.
 *
 * Invariants: Full-object replacement is the only intended v1 action vocabulary.
 */
EndpointStatefulInputSpec makeSharedScaleStatefulInputSpec({
  ScaleData? initialScaleData,
}) {
  return EndpointStatefulInputSpec(
    behavior: StatefulInputBehavior.ownerManaged,
    consumptionMode: StatefulInputConsumptionMode.callbackAndRetainedState,
    initialValue: initialScaleData?.toJson(),
    matchedOutput: makeSharedScaleMatchedOutputSpec(),
  );
}

/**
 * Purpose: Build a v1 full-object theme set_value action payload.
 *
 * Parameters:
 * - `themeData`: Theme payload to install as the shared theme.
 *
 * Return value: JSON map with action=set_value and value=<theme json>.
 *
 * Requirements/Preconditions: `themeData` must serialize via toJson().
 *
 * Guarantees/Postconditions: Only the v1 set_value vocabulary is emitted.
 *
 * Invariants: No patch/delta fields.
 */
Map<String, dynamic> makeSharedThemeSetValueAction(ThemeData themeData) {
  return <String, dynamic>{
    JsonFields.ACTION: kSetValueActionName,
    JsonFields.VALUE: themeData.toJson(),
  };
}

/**
 * Purpose: Build a v1 full-object scale set_value action payload.
 *
 * Parameters:
 * - `scaleData`: Scale payload to install as the shared scale.
 *
 * Return value: JSON map with action=set_value and value=<scale json>.
 *
 * Requirements/Preconditions: `scaleData` must serialize via toJson().
 *
 * Guarantees/Postconditions: Only the v1 set_value vocabulary is emitted.
 *
 * Invariants: No patch/delta fields.
 */
Map<String, dynamic> makeSharedScaleSetValueAction(ScaleData scaleData) {
  return <String, dynamic>{
    JsonFields.ACTION: kSetValueActionName,
    JsonFields.VALUE: scaleData.toJson(),
  };
}

bool _hasRequiredThemeFields(Map<String, dynamic> value) {
  return value.containsKey(JsonFields.DISPLAY_NAME) &&
      value.containsKey(JsonFields.PRIMARY_COLOR) &&
      value.containsKey(JsonFields.SECONDARY_COLOR) &&
      value.containsKey(JsonFields.ACCENT_COLOR) &&
      value.containsKey(JsonFields.BACKGROUND_COLOR);
}

bool _hasRequiredScaleFields(Map<String, dynamic> value) {
  final dynamic categories = value[JsonFields.NOTE_CATEGORIES];
  return value.containsKey(JsonFields.ROOT_NOTE) &&
      categories is List &&
      categories.length == 12;
}

/**
 * Purpose: Parse ThemeData from a set_value action payload.
 *
 * Parameters:
 * - `actionJson`: JSON action object.
 *
 * Return value: Parsed ThemeData, or null when malformed / not set_value.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Rejects non-set_value actions and incomplete theme
 * objects.
 *
 * Invariants: Does not coerce patch-style payloads.
 */
ThemeData? parseSharedThemeSetValueAction(Map<String, dynamic> actionJson) {
  if (actionJson[JsonFields.ACTION] != kSetValueActionName) {
    return null;
  }
  final dynamic value = actionJson[JsonFields.VALUE];
  if (value is! Map<String, dynamic> || !_hasRequiredThemeFields(value)) {
    return null;
  }
  return ThemeData.fromJson(value);
}

/**
 * Purpose: Parse ScaleData from a set_value action payload.
 *
 * Parameters:
 * - `actionJson`: JSON action object.
 *
 * Return value: Parsed ScaleData, or null when malformed / not set_value.
 *
 * Requirements/Preconditions: none.
 *
 * Guarantees/Postconditions: Rejects non-set_value actions and incomplete scale
 * objects.
 *
 * Invariants: Does not coerce patch-style payloads.
 */
ScaleData? parseSharedScaleSetValueAction(Map<String, dynamic> actionJson) {
  if (actionJson[JsonFields.ACTION] != kSetValueActionName) {
    return null;
  }
  final dynamic value = actionJson[JsonFields.VALUE];
  if (value is! Map<String, dynamic> || !_hasRequiredScaleFields(value)) {
    return null;
  }
  return ScaleData.fromJson(value);
}
