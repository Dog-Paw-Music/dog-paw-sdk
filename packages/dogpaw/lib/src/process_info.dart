import 'json_constants.dart';
import 'json_utils.dart';

/// Process information structure
class ProcessInfo {
  /// Process ID
  final String id;

  /// Process name
  final String name;

  /// Command line used to launch
  final String command;

  /// System process ID
  final int pid;

  /// ISO timestamp when process started
  final String startTime;

  /// Whether process is currently running
  final bool isRunning;

  /// Process type (process, flutter_app, etc.)
  final String type;

  /// Dog Paw app name (if this process belongs to a dog paw app)
  final String? dogPawAppName;

  /// Dog Paw process name (if this is a child process of a dog paw app)
  final String? dogPawProcessName;

  /// Default constructor
  const ProcessInfo({
    required this.id,
    required this.name,
    required this.command,
    required this.pid,
    required this.startTime,
    required this.isRunning,
    required this.type,
    this.dogPawAppName,
    this.dogPawProcessName,
  });

  /// Convert to JSON representation
  Map<String, dynamic> toJson() => {
        JsonFields.PROCESS_ID: id,
        JsonFields.PROCESS_NAME: name,
        JsonFields.PROCESS_COMMAND: command,
        JsonFields.PID: pid,
        JsonFields.START_TIME: startTime,
        JsonFields.RUNNING: isRunning,
        JsonFields.PROCESS_TYPE: type,
        if (dogPawAppName != null) 'dogPawAppName': dogPawAppName,
        if (dogPawProcessName != null) 'dogPawProcessName': dogPawProcessName,
      }.toJsonClean();

  /// Create from JSON representation
  factory ProcessInfo.fromJson(Map<String, dynamic> json) => ProcessInfo(
        id: json[JsonFields.PROCESS_ID] ??
            json['processId'] ??
            json['id'] ??
            '', // Fallback
        name: json[JsonFields.PROCESS_NAME] ?? json['name'] ?? '',
        command: json[JsonFields.PROCESS_COMMAND] ?? json['command'] ?? '',
        pid: json[JsonFields.PID] ?? 0,
        startTime: json[JsonFields.START_TIME] ?? '',
        isRunning: json[JsonFields.RUNNING] ?? json['isRunning'] ?? false,
        type: json[JsonFields.PROCESS_TYPE] ?? json['type']?.toString() ?? '',
        dogPawAppName: json['dogPawAppName'],
        dogPawProcessName: json['dogPawProcessName'],
      );

  @override
  String toString() =>
      'ProcessInfo(id: $id, name: $name, pid: $pid, isRunning: $isRunning)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProcessInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          command == other.command &&
          pid == other.pid &&
          startTime == other.startTime &&
          isRunning == other.isRunning &&
          type == other.type &&
          dogPawAppName == other.dogPawAppName &&
          dogPawProcessName == other.dogPawProcessName;

  @override
  int get hashCode => Object.hash(id, name, command, pid, startTime, isRunning,
      type, dogPawAppName, dogPawProcessName);
}
