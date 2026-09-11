import 'data_types.dart';
import 'range.dart';
import 'json_constants.dart';
import 'json_utils.dart';
import 'data_type_extensions.dart';

/// One stable id/label option for an enum endpoint.
class EnumOption {
  final int id;
  final String label;

  const EnumOption({
    required this.id,
    required this.label,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.ID: id,
        JsonFields.LABEL: label,
      };

  factory EnumOption.fromJson(Map<String, dynamic> json) {
    return EnumOption(
      id: json[JsonFields.ID] as int? ?? 0,
      label: json[JsonFields.LABEL] as String? ?? '',
    );
  }
}

/// Complete data type specification with constraints
class DataTypeSpec {
  /// Base data type
  final DataType baseType;

  /// Index specification with dimensions
  final IndexSpec indexSpec;

  /// Valid range for numeric types
  final Range? range;

  /// Stable id/label metadata for enum types
  final List<EnumOption> enumOptions;

  /// Name for custom types
  final String? customTypeName;

  /// Constructor with base type
  const DataTypeSpec(
    this.baseType, {
    this.indexSpec = const IndexSpecNone(),
    this.range,
    this.enumOptions = const <EnumOption>[],
    this.customTypeName,
  });

  /// Factory method to create a float type with range
  factory DataTypeSpec.createFloat({double min = 0.0, double max = 1.0}) {
    return DataTypeSpec(
      DataType.float,
      range: Range.fromValues(min, max),
    );
  }

  /// Factory method to create an enum type with values
  factory DataTypeSpec.createEnum(List<EnumOption> values) {
    return DataTypeSpec(
      DataType.enum_,
      enumOptions: values,
    );
  }

  /// Factory method to create an indexed float type
  factory DataTypeSpec.createIndexedFloat(
    IndexSpec indexSpec, {
    double min = 0.0,
    double max = 1.0,
  }) {
    return DataTypeSpec(
      DataType.float,
      indexSpec: indexSpec,
      range: Range.fromValues(min, max),
    );
  }

  /// Convert to JSON representation
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> constraints = <String, dynamic>{
      JsonFields.RANGE: range?.toJson(),
      JsonFields.ENUM_OPTIONS: enumOptions.map((option) => option.toJson()).toList(),
      JsonFields.CUSTOM_SCHEMA: customTypeName,
    }.toJsonClean();

    return <String, dynamic>{
      JsonFields.BASE_TYPE: baseType.toSnakeCase(),
      JsonFields.INDEX_SPEC: indexSpec.toJson(),
      JsonFields.CONSTRAINTS: constraints.isEmpty ? null : constraints,
    }.toJsonClean();
  }

  /// Create from JSON representation
  factory DataTypeSpec.fromJson(Map<String, dynamic> json) {
    // Parse IndexSpec
    final indexSpec = json.containsKey(JsonFields.INDEX_SPEC)
        ? IndexSpec.fromJson(
            json[JsonFields.INDEX_SPEC] as Map<String, dynamic>)
        : const IndexSpecNone();

    final Map<String, dynamic> constraints =
        json[JsonFields.CONSTRAINTS] as Map<String, dynamic>? ??
            const <String, dynamic>{};

    return DataTypeSpec(
      DataType.values.firstWhere(
        (e) =>
            e.toSnakeCase() == json[JsonFields.BASE_TYPE] ||
            e.name == json[JsonFields.BASE_TYPE],
        orElse: () => DataType.float,
      ),
      indexSpec: indexSpec,
      range: constraints[JsonFields.RANGE] != null
          ? Range.fromJson(constraints[JsonFields.RANGE])
          : null,
      enumOptions: (constraints[JsonFields.ENUM_OPTIONS] as List<dynamic>? ??
              const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(EnumOption.fromJson)
          .toList(),
      customTypeName: constraints[JsonFields.CUSTOM_SCHEMA] as String?,
    );
  }
}
