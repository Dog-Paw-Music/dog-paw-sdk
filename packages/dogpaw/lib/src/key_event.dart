import 'data_types.dart';
import 'json_constants.dart';

/// Event type enumeration
enum KeyEventType {
  /// Key was activated (detected but not fully pressed)
  activated,

  /// Key was pressed (fully pressed)
  pressed,

  /// Key was unpressed (released from pressed state)
  unpressed,

  /// Key was released (returned to rest state)
  released,
}

/// Key event data derived from DPQueue.hpp KeyMsg structure
class KeyEvent {
  /// Event type (activated/pressed/released transition)
  final KeyEventType type;

  /// Key column position
  final int column;

  /// Key row position
  final int row;

  /// Key press velocity
  final double velocity;

  /// Previous key state
  final KeyState oldState;

  /// New key state
  final KeyState newState;

  /// Event timestamp (microseconds)
  final int timestamp;

  /// Constructor with all parameters
  const KeyEvent({
    required this.type,
    required this.column,
    required this.row,
    required this.velocity,
    required this.oldState,
    required this.newState,
    required this.timestamp,
  });

  /// Convert to JSON representation
  Map<String, dynamic> toJson() => {
        JsonFields.KEY_EVENT_TYPE: type.name,
        JsonFields.COLUMN: column,
        JsonFields.ROW: row,
        JsonFields.VELOCITY: velocity,
        JsonFields.OLD_STATE: oldState.name,
        JsonFields.NEW_STATE: newState.name,
        JsonFields.TIMESTAMP: timestamp,
      };

  /// Create from JSON representation
  factory KeyEvent.fromJson(Map<String, dynamic> json) {
    // Handle legacy "type" if needed, or "keyEventType"
    final typeStr = json[JsonFields.KEY_EVENT_TYPE] ?? json['type'];
    return KeyEvent(
      type: KeyEventType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => KeyEventType.pressed,
      ),
      column: json[JsonFields.COLUMN] ?? 0,
      row: json[JsonFields.ROW] ?? 0,
      velocity: json[JsonFields.VELOCITY]?.toDouble() ?? 0.0,
      oldState: KeyState.values.firstWhere(
        (e) => e.name == json[JsonFields.OLD_STATE],
        orElse: () => KeyState.rest,
      ),
      newState: KeyState.values.firstWhere(
        (e) => e.name == json[JsonFields.NEW_STATE],
        orElse: () => KeyState.rest,
      ),
      timestamp: json[JsonFields.TIMESTAMP] ?? 0,
    );
  }

  @override
  String toString() =>
      'KeyEvent(type: $type, column: $column, row: $row, velocity: $velocity, ts: $timestamp, oldState: $oldState, newState: $newState)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyEvent &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          column == other.column &&
          row == other.row &&
          velocity == other.velocity &&
          oldState == other.oldState &&
          newState == other.newState &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      Object.hash(type, column, row, velocity, oldState, newState, timestamp);
}
