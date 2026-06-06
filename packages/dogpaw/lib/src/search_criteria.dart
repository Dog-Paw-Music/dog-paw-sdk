import 'data_types.dart';
import 'json_constants.dart';
import 'data_type_extensions.dart';

/// Search condition for endpoint discovery
class SearchCondition {
  final String field;
  final String operator;
  final dynamic value;

  const SearchCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        JsonFields.FIELD: field,
        JsonFields.OPERATOR: operator,
        JsonFields.VALUE: value,
      };
}

/// Search criteria for finding endpoints
class SearchCriteria {
  final SearchCondition? condition;
  final List<SearchCriteria>? andCriteria;
  final List<SearchCriteria>? orCriteria;

  /// Default constructor for the structured criteria format shared with C++.
  const SearchCriteria({
    this.condition,
    this.andCriteria,
    this.orCriteria,
  });

  /// Helper constructors matching C++ API

  static SearchCriteria fromCondition(String field, String op, dynamic value) {
    return SearchCriteria(
      condition: SearchCondition(field: field, operator: op, value: value),
    );
  }

  static SearchCriteria directionEquals(EndpointDirection dir) {
    return fromCondition(JsonFields.DIRECTION, 'equals', dir.name);
  }

  static SearchCriteria baseTypeEquals(DataType type) {
    return fromCondition(JsonFields.BASE_TYPE, 'equals', type.toSnakeCase());
  }

  static SearchCriteria sourceEntityEquals(String sourceEntity) {
    return fromCondition(
        JsonFields.SOURCE_ENTITY, JsonFields.EQUALS, sourceEntity);
  }

  static SearchCriteria nameEquals(String name) {
    return fromCondition(JsonFields.NAME, JsonFields.EQUALS, name);
  }

  static SearchCriteria flagContains(String flag) {
    return fromCondition(JsonFields.FLAGS, JsonFields.CONTAINS, flag);
  }

  static SearchCriteria andCombination(List<SearchCriteria> criteria) {
    return SearchCriteria(andCriteria: criteria);
  }

  static SearchCriteria orCombination(List<SearchCriteria> criteria) {
    return SearchCriteria(orCriteria: criteria);
  }

  /// Convert to JSON representation
  Map<String, dynamic> toJson() {
    if (condition != null) {
      return condition!.toJson();
    }
    if (andCriteria != null) {
      return {JsonFields.AND: andCriteria!.map((c) => c.toJson()).toList()};
    }
    if (orCriteria != null) {
      return {JsonFields.OR: orCriteria!.map((c) => c.toJson()).toList()};
    }

    throw StateError(
      'SearchCriteria must contain a condition, andCriteria, or orCriteria',
    );
  }

  /// Create from JSON representation
  factory SearchCriteria.fromJson(Map<String, dynamic> json) {
    if (json.containsKey(JsonFields.AND)) {
      return SearchCriteria(
        andCriteria: (json[JsonFields.AND] as List)
            .map((item) =>
                SearchCriteria.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
    }

    if (json.containsKey(JsonFields.OR)) {
      return SearchCriteria(
        orCriteria: (json[JsonFields.OR] as List)
            .map((item) =>
                SearchCriteria.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
    }

    if (json.containsKey(JsonFields.FIELD) &&
        json.containsKey(JsonFields.OPERATOR) &&
        json.containsKey(JsonFields.VALUE)) {
      return SearchCriteria(
        condition: SearchCondition(
          field: json[JsonFields.FIELD] as String,
          operator: json[JsonFields.OPERATOR] as String,
          value: json[JsonFields.VALUE],
        ),
      );
    }

    throw ArgumentError(
      'Invalid SearchCriteria JSON: expected condition, and, or',
    );
  }

  @override
  String toString() {
    if (condition != null) return 'SearchCriteria($condition)';
    if (andCriteria != null) return 'SearchCriteria(AND: $andCriteria)';
    if (orCriteria != null) return 'SearchCriteria(OR: $orCriteria)';
    return 'SearchCriteria(<invalid>)';
  }
}
