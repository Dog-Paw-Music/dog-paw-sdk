import 'data_types.dart';
import 'range.dart';
import 'json_constants.dart';
import 'json_utils.dart';

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
  factory MappingConfig.fromJson(Map<String, dynamic> json) {
    return MappingConfig(
      type: MappingType.values.firstWhere(
        (e) => e.name == json[JsonFields.MAPPING_TYPE],
        orElse: () => MappingType.linear,
      ),
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
