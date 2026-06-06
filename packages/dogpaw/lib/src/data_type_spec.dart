import 'data_types.dart';
import 'range.dart';
import 'json_constants.dart';
import 'json_utils.dart';
import 'data_type_extensions.dart';

/// Complete data type specification with constraints
class DataTypeSpec {
  /// Base data type
  final DataType baseType;

  /// Index specification with dimensions
  final IndexSpec indexSpec;

  /// Valid range for numeric types
  final Range? range;

  /// Valid values for enum types
  final List<String> enumValues;

  /// Name for custom types
  final String? customTypeName;

  /// Constructor with base type
  const DataTypeSpec(
    this.baseType, {
    this.indexSpec = const IndexSpecNone(),
    this.range,
    this.enumValues = const [],
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
  factory DataTypeSpec.createEnum(List<String> values) {
    return DataTypeSpec(
      DataType.enum_,
      enumValues: values,
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
    return <String, dynamic>{
      JsonFields.BASE_TYPE: baseType.toSnakeCase(),
      JsonFields.INDEX_SPEC: indexSpec.toJson(),
      JsonFields.RANGE: range?.toJson(),
      JsonFields.ENUM_VALUES: enumValues,
      JsonFields.CUSTOM_SCHEMA: customTypeName,
    }.toJsonClean();
  }

  /// Create from JSON representation
  factory DataTypeSpec.fromJson(Map<String, dynamic> json) {
    // Parse IndexSpec
    final indexSpec = json.containsKey(JsonFields.INDEX_SPEC)
        ? IndexSpec.fromJson(
            json[JsonFields.INDEX_SPEC] as Map<String, dynamic>)
        : const IndexSpecNone();

    return DataTypeSpec(
      DataType.values.firstWhere(
        (e) =>
            e.toSnakeCase() == json[JsonFields.BASE_TYPE] ||
            e.name == json[JsonFields.BASE_TYPE],
        orElse: () => DataType.float,
      ),
      indexSpec: indexSpec,
      range: json[JsonFields.RANGE] != null
          ? Range.fromJson(json[JsonFields.RANGE])
          : null,
      enumValues: List<String>.from(json[JsonFields.ENUM_VALUES] ?? []),
      customTypeName: json[JsonFields.CUSTOM_SCHEMA],
    );
  }
}
