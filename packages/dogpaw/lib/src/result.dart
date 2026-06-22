import 'json_constants.dart';

/// Result of a command operation
///
/// Contains success flag, optional result payload, and error message if failed.
class CommandResponseResult {
  final bool success;
  final Map<String, dynamic>
      result; // Result payload (may be present on success or failure)
  final String error; // Error message (if !success)

  const CommandResponseResult(this.success, this.result, this.error);

  factory CommandResponseResult.completed(
          [Map<String, dynamic> result = const {}]) =>
      CommandResponseResult(true, result, '');
  factory CommandResponseResult.errorResult(String err,
          [Map<String, dynamic> result = const {}]) =>
      CommandResponseResult(false, result, err);

  @override
  String toString() =>
      'CommandResponseResult(success: $success, result: $result, error: $error)';
}

/// Snapshot of one endpoint's retained state, if any.
///
/// Purpose:
/// Carries the app-facing answer for "what retained state does this endpoint
/// currently expose?" across public query helpers and internal retained-state
/// query command handling.
///
/// Parameters:
/// - [hasState]: whether the endpoint currently has a valid retained state.
/// - [value]: retained scalar value when [hasState] is true.
/// - [timestampUs]: microseconds since the Unix epoch when the retained state
///   most recently became valid.
///
/// Return value:
/// - [toJson] returns the internal command-response payload.
/// - [fromJson] parses that payload back into a typed snapshot.
///
/// Requirements/Preconditions:
/// - When [hasState] is true, [value] should also be present.
///
/// Guarantees/Postconditions:
/// - [toJson] always includes `hasState`.
///
/// Invariants:
/// - This type describes one current snapshot only. It does not encode state
///   history.
class EndpointRetainedStateSnapshot {
  final bool hasState;
  final Object? value;
  final int? timestampUs;

  const EndpointRetainedStateSnapshot({
    required this.hasState,
    this.value,
    this.timestampUs,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hasState': hasState,
        if (value != null) JsonFields.VALUE: value,
        if (timestampUs != null) JsonFields.TIMESTAMP: timestampUs,
      };

  factory EndpointRetainedStateSnapshot.fromJson(Map<String, dynamic> json) {
    return EndpointRetainedStateSnapshot(
      hasState: json['hasState'] as bool? ?? false,
      value: json.containsKey(JsonFields.VALUE) ? json[JsonFields.VALUE] : null,
      timestampUs: (json[JsonFields.TIMESTAMP] as num?)?.toInt(),
    );
  }
}

/// Callback type for "accepted" notifications on blocking commands.
/// Called when the command receiver sends an "accepted" response.
typedef OnAcceptedCallback = void Function(Map<String, dynamic> result);

/// Policy for how Epiphany should behave when a command target is missing.
enum CommandTargetMissingPolicy {
  fail,
  launchIfRegistered,
}

/// Delivery behavior for routing a command through Epiphany.
///
/// Purpose:
/// Controls whether Epiphany should try to launch a missing target before
/// routing a command, and whether it should wait for the target to report ready.
///
/// Parameters:
/// - [ifTargetMissing]: What to do when the target entity is not connected.
/// - [waitForReady]: When true, route only after the target is ready.
///
/// Return value:
/// - [toJson] returns the wire-format JSON for the delivery policy.
/// - [fromJson] parses a wire-format JSON map into a typed policy.
///
/// Requirements:
/// - [fromJson] expects valid Epiphany command-delivery JSON fields.
///
/// Guarantees:
/// - [toJson] always includes both delivery-policy fields.
///
/// Invariants:
/// - This type only affects server-side command delivery behavior. It does not
///   change command payloads or completion-response semantics.
class CommandDeliveryPolicy {
  final CommandTargetMissingPolicy ifTargetMissing;
  final bool waitForReady;

  const CommandDeliveryPolicy({
    this.ifTargetMissing = CommandTargetMissingPolicy.fail,
    this.waitForReady = true,
  });

  Map<String, dynamic> toJson() => {
        JsonFields.IF_TARGET_MISSING:
            ifTargetMissing == CommandTargetMissingPolicy.launchIfRegistered
                ? JsonFields.IF_TARGET_MISSING_LAUNCH_IF_REGISTERED
                : JsonFields.IF_TARGET_MISSING_FAIL,
        JsonFields.WAIT_FOR_READY: waitForReady,
      };

  factory CommandDeliveryPolicy.fromJson(Map<String, dynamic> json) {
    final String ifTargetMissingValue =
        json[JsonFields.IF_TARGET_MISSING] as String? ??
            JsonFields.IF_TARGET_MISSING_FAIL;
    final CommandTargetMissingPolicy ifTargetMissing;
    if (ifTargetMissingValue ==
        JsonFields.IF_TARGET_MISSING_LAUNCH_IF_REGISTERED) {
      ifTargetMissing = CommandTargetMissingPolicy.launchIfRegistered;
    } else if (ifTargetMissingValue == JsonFields.IF_TARGET_MISSING_FAIL) {
      ifTargetMissing = CommandTargetMissingPolicy.fail;
    } else {
      throw ArgumentError(
        'Unknown command target missing policy: $ifTargetMissingValue',
      );
    }

    return CommandDeliveryPolicy(
      ifTargetMissing: ifTargetMissing,
      waitForReady: json[JsonFields.WAIT_FOR_READY] as bool? ?? true,
    );
  }
}

/// Result wrapper for operations that may fail
class Result<T> {
  /// Whether the operation succeeded
  final bool success;

  /// The result value (if successful)
  final T? value;

  /// Error message (if failed)
  final String error;

  /// Constructor with all parameters
  const Result(this.success, this.value, this.error);

  /// Factory method to create a successful result
  ///
  /// [value] - The successful result value
  /// Returns a Result with success=true and the given value
  factory Result.success(T value) => Result(true, value, '');

  /// Factory method to create an error result
  ///
  /// [error] - The error message
  /// Returns a Result with success=false and the given error
  factory Result.error(String error) => Result(false, null, error);

  /// Check if the result is successful
  bool get isSuccess => success;

  /// Check if the result is an error
  bool get isError => !success;

  /// Get the value if successful, otherwise throw an exception
  ///
  /// Returns the value if success=true
  /// Throws StateError if success=false
  T getValue() {
    if (success && value != null) {
      return value!;
    }
    throw StateError('Cannot get value from error result: $error');
  }

  /// Get the error message if failed, otherwise throw an exception
  ///
  /// Returns the error message if success=false
  /// Throws StateError if success=true
  String getError() {
    if (!success) {
      return error;
    }
    throw StateError('Cannot get error from successful result');
  }

  /// Convert to JSON representation
  Map<String, dynamic> toJson() => {
        'success': success,
        'value': value,
        'error': error,
      };

  /// Create from JSON representation
  ///
  /// Note: This factory method cannot properly reconstruct the generic type T
  /// from JSON. It's provided for compatibility but the value will be the raw JSON value.
  factory Result.fromJson(Map<String, dynamic> json) => Result(
        json['success'] ?? false,
        json['value'] as T?,
        json['error'] ?? '',
      );

  @override
  String toString() =>
      success ? 'Result.success($value)' : 'Result.error($error)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Result &&
          runtimeType == other.runtimeType &&
          success == other.success &&
          value == other.value &&
          error == other.error;

  @override
  int get hashCode => Object.hash(success, value, error);
}
