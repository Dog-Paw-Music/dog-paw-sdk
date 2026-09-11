import 'data_types.dart';
import 'range.dart';
import 'json_constants.dart';
import 'json_utils.dart';

/// Resolve a wire mapping-type value into the shared vocabulary.
///
/// [wireValue] is the raw `mappingType` entry of a mapping object, or null when
/// the object asserts no type. Returns [MappingType.linear] for an unasserted
/// type and throws [ArgumentError] for anything outside the vocabulary shared
/// with Epiphany, so key or vocabulary drift surfaces instead of silently
/// degrading every mapping to linear. Leaves [wireValue] unchanged.
MappingType _mappingTypeFromJson(Object? wireValue) {
  if (wireValue == null) {
    return MappingType.linear;
  }
  for (final MappingType candidate in MappingType.values) {
    if (candidate.name == wireValue) {
      return candidate;
    }
  }
  throw ArgumentError.value(
    wireValue,
    JsonFields.MAPPING_TYPE,
    'Unsupported mapping type; expected one of '
    '${MappingType.values.map((MappingType type) => type.name).join(', ')}',
  );
}

/// Mapping configuration for value transformation in connections
class MappingConfig {
  /// Type of mapping to use
  final MappingType type;

  /// Input value range
  final Range? inputRange;

  /// Output value range
  final Range? outputRange;

  /// Curve parameter for non-linear mappings
  final double curve;

  /// Mathematical expression for expression mapping
  final String expression;

  /// Default constructor
  const MappingConfig({
    this.type = MappingType.linear,
    this.inputRange,
    this.outputRange,
    this.curve = 0.5,
    this.expression = '',
  });

  /// Convert to JSON representation
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      JsonFields.MAPPING_TYPE: type.name,
      JsonFields.INPUT_RANGE: inputRange?.toJson(),
      JsonFields.OUTPUT_RANGE: outputRange?.toJson(),
      JsonFields.CURVE: curve,
      JsonFields.EXPRESSION: expression,
    }.toJsonClean();
  }

  /// Create from JSON representation
  ///
  /// [json] must be a protocol mapping object. An absent mapping type yields
  /// the shared default; a present but unrecognized one throws.
  factory MappingConfig.fromJson(Map<String, dynamic> json) {
    return MappingConfig(
      type: _mappingTypeFromJson(json[JsonFields.MAPPING_TYPE]),
      inputRange: json[JsonFields.INPUT_RANGE] != null
          ? Range.fromJson(json[JsonFields.INPUT_RANGE])
          : null,
      outputRange: json[JsonFields.OUTPUT_RANGE] != null
          ? Range.fromJson(json[JsonFields.OUTPUT_RANGE])
          : null,
      curve: json[JsonFields.CURVE]?.toDouble() ?? 0.5,
      expression: json[JsonFields.EXPRESSION] ?? '',
    );
  }
}
