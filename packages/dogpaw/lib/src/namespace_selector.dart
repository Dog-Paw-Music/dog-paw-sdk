import 'json_constants.dart';

/// Type-safe namespace selector for data items
///
/// Data items (themes, scales, layouts, KVs) are organized into namespaces:
/// - One global namespace shared by all entities
/// - One namespace per sourceEntity
///
/// This class provides a type-safe way to specify which namespace(s) to target
/// in list, subscribe, read, update, and delete operations.
class NamespaceSelector {
  final NamespaceSelectorType type;
  final String? sourceEntity;

  /// Global namespace only
  const NamespaceSelector.global()
      : type = NamespaceSelectorType.global,
        sourceEntity = null;

  /// Current entity's namespace
  const NamespaceSelector.currentEntity()
      : type = NamespaceSelectorType.currentEntity,
        sourceEntity = null;

  /// Specific sourceEntity namespace
  const NamespaceSelector.specificEntity(String entity)
      : type = NamespaceSelectorType.specificEntity,
        sourceEntity = entity;

  /// All namespaces (global + all sourceEntities)
  const NamespaceSelector.all()
      : type = NamespaceSelectorType.allEntities,
        sourceEntity = null;

  /// Default constructor creates currentEntity selector
  const NamespaceSelector() : this.currentEntity();

  /// Constructor with type and optional sourceEntity
  const NamespaceSelector._internal(this.type, this.sourceEntity);

  /// Check if this selector targets a specific namespace (not ALL_ENTITIES)
  bool get isSpecific => type != NamespaceSelectorType.allEntities;

  /// Check if this selector is for the global namespace
  bool get isGlobal => type == NamespaceSelectorType.global;

  /// Check if this selector is for the current entity's namespace
  bool get isCurrentEntity => type == NamespaceSelectorType.currentEntity;

  /// Check if this selector is for a specific entity
  bool get isSpecificEntity => type == NamespaceSelectorType.specificEntity;

  /// Check if this selector targets all entities
  bool get isAllEntities => type == NamespaceSelectorType.allEntities;

  /// Convert to JSON representation
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      JsonFields.TYPE: typeToString(type),
    };
    if (sourceEntity != null) {
      result[JsonFields.SOURCE_ENTITY] = sourceEntity;
    }
    return result;
  }

  /// Create from JSON representation
  static NamespaceSelector fromJson(Map<String, dynamic> json) {
    if (!json.containsKey(JsonFields.TYPE)) {
      throw ArgumentError(
          'Invalid namespace selector json: missing type field');
    }
    final type = typeFromString(json[JsonFields.TYPE] as String);
    final sourceEntity = json[JsonFields.SOURCE_ENTITY] as String?;
    return NamespaceSelector._internal(type, sourceEntity);
  }

  /// Convert type enum to string
  static String typeToString(NamespaceSelectorType type) {
    switch (type) {
      case NamespaceSelectorType.global:
        return 'GLOBAL';
      case NamespaceSelectorType.currentEntity:
        return 'CURRENT_ENTITY';
      case NamespaceSelectorType.specificEntity:
        return 'SPECIFIC_ENTITY';
      case NamespaceSelectorType.allEntities:
        return 'ALL_ENTITIES';
    }
  }

  /// Convert string to type enum
  static NamespaceSelectorType typeFromString(String typeStr) {
    switch (typeStr) {
      case 'GLOBAL':
        return NamespaceSelectorType.global;
      case 'CURRENT_ENTITY':
        return NamespaceSelectorType.currentEntity;
      case 'SPECIFIC_ENTITY':
        return NamespaceSelectorType.specificEntity;
      case 'ALL_ENTITIES':
        return NamespaceSelectorType.allEntities;
      default:
        throw ArgumentError('Invalid namespace selector type: $typeStr');
    }
  }

  @override
  String toString() {
    if (isGlobal) {
      return 'GLOBAL';
    } else if (isCurrentEntity) {
      return 'CURRENT_ENTITY';
    } else if (isSpecificEntity) {
      return 'SPECIFIC_ENTITY: ${sourceEntity ?? ""}';
    } else if (isAllEntities) {
      return 'ALL_ENTITIES';
    } else {
      return 'UNKNOWN';
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NamespaceSelector &&
            runtimeType == other.runtimeType &&
            type == other.type &&
            sourceEntity == other.sourceEntity;
  }

  @override
  int get hashCode => Object.hash(type, sourceEntity);
}

enum NamespaceSelectorType {
  /// Global namespace only
  global,

  /// Current entity's namespace
  currentEntity,

  /// Specific sourceEntity namespace (see sourceEntity field)
  specificEntity,

  /// All namespaces (global + all sourceEntities)
  allEntities,
}
