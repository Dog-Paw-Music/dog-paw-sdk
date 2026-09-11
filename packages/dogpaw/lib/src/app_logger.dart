import 'dart:developer' as developer;
import 'dart:io';

/// Holds source location information from stack trace parsing
class SourceLocation {
  final String fileName;
  final int lineNumber;
  final int columnNumber;
  final String functionName;

  const SourceLocation({
    required this.fileName,
    required this.lineNumber,
    required this.columnNumber,
    required this.functionName,
  });

  @override
  String toString() => '$fileName:$lineNumber:$columnNumber in $functionName';
}

/// Log level enumeration matching the C++ implementation
enum LogLevel { debug, info, warning, error }

/// Buffered log entry containing level and formatted message
class _BufferedLogEntry {
  final LogLevel level;
  final String formattedMessage;

  _BufferedLogEntry(this.level, this.formattedMessage);
}

/// A centralized logging utility that provides different logging strategies
/// for development and production environments.
///
/// This logger can be used across different Flutter applications in the project.
///
/// Output Buffering:
/// The logger supports buffered output mode for test scenarios where logs should
/// only be displayed on failure. Use startOutputBuffer() to begin buffering,
/// then endOutputBuffer(flush) to either print (flush=true) or discard (flush=false)
/// the buffered messages.
class AppLogger {
  static const bool _isDebugMode = !bool.fromEnvironment('dart.vm.product');
  static final bool _mirrorReleaseLogsToStdout = Platform.isLinux;
  static String _appName = 'FlutterApp';
  static bool _enableSourceLocation = false;
  static bool _buffering = false;
  static final List<_BufferedLogEntry> _buffer = [];

  /// Enable or disable automatic source location detection
  /// Note: This has performance implications, use carefully
  static void enableSourceLocation(bool enable) {
    _enableSourceLocation = enable;
  }

  /// Parse stack trace to extract source location information
  static SourceLocation? _parseSourceLocation(StackTrace stackTrace) {
    if (!_enableSourceLocation) return null;

    try {
      final frames = stackTrace.toString().split('\n');
      // Skip the first frame (this function) and find the caller
      for (int i = 1; i < frames.length; i++) {
        final frame = frames[i].trim();
        if (frame.isEmpty) continue;

        // Parse format: #N FunctionName (file:line:column)
        final match = RegExp(
          r'#\d+\s+(\S+)\s+\(([^:]+):(\d+):(\d+)\)',
        ).firstMatch(frame);
        if (match != null) {
          final functionName = match.group(1) ?? 'unknown';
          final filePath = match.group(2) ?? 'unknown';
          final lineNumber = int.tryParse(match.group(3) ?? '0') ?? 0;
          final columnNumber = int.tryParse(match.group(4) ?? '0') ?? 0;

          // Extract just filename from path
          final fileName = filePath.split(Platform.pathSeparator).last;

          return SourceLocation(
            fileName: fileName,
            lineNumber: lineNumber,
            columnNumber: columnNumber,
            functionName: functionName,
          );
        }
      }
    } catch (e) {
      // If parsing fails, return null and continue without source location
    }
    return null;
  }

  /// Internal logging method with optional source location
  static void _logInternal(
    String level,
    String message,
    String? tag, [
    SourceLocation? location,
  ]) {
    final tagPrefix = tag != null ? '[$tag] ' : '';
    final locationSuffix = location != null
        ? ' [${location.fileName}:${location.lineNumber}] [${location.functionName}]'
        : '';
    final fullMessage = '$level: $tagPrefix$message$locationSuffix';

    // Determine log level for buffering
    LogLevel logLevel;
    switch (level) {
      case 'DEBUG':
        logLevel = LogLevel.debug;
        break;
      case 'INFO':
        logLevel = LogLevel.info;
        break;
      case 'WARNING':
        logLevel = LogLevel.warning;
        break;
      case 'ERROR':
        logLevel = LogLevel.error;
        break;
      default:
        logLevel = LogLevel.info;
    }

    _outputOrBuffer(logLevel, fullMessage);
  }

  /// Output or buffer a formatted message
  static void _outputOrBuffer(LogLevel level, String formattedMessage) {
    if (_buffering) {
      _buffer.add(_BufferedLogEntry(level, formattedMessage));
    } else {
      if (_isDebugMode || _mirrorReleaseLogsToStdout) {
        stdout.writeln(formattedMessage);
      }
      if (!_isDebugMode) {
        developer.log(formattedMessage, name: _appName);
      }
    }
  }

  /// Initialize the logger with a specific app name
  static void initialize(String appName) {
    _appName = appName;
  }

  /// Get the current app name
  static String get appName => _appName;

  //=========================================================================
  // OUTPUT BUFFERING
  //=========================================================================

  /// Start buffering log output instead of printing immediately
  ///
  /// When buffering is active, all log messages are stored in memory instead of
  /// being printed. Use endOutputBuffer() to either print or discard the buffer.
  /// Useful for test scenarios where logs should only be shown on failure.
  ///
  /// [sectionTitle] - Optional title to log when starting the section (logged immediately, not buffered)
  ///
  /// Returns true if buffering started, false if already buffering.
  static bool startOutputBuffer([String sectionTitle = '']) {
    if (_buffering) {
      return false; // Already buffering
    }

    _buffering = true;
    _buffer.clear();

    // Log the section title immediately (not buffered) if provided
    if (sectionTitle.isNotEmpty) {
      // Temporarily disable buffering to output the title
      _buffering = false;
      info('=== BUFFERED SECTION START: $sectionTitle ===');
      _buffering = true;
    }

    return true;
  }

  /// Flush all buffered messages to output
  ///
  /// Prints all buffered messages in order, respecting their original log levels.
  /// Does not stop buffering - continues collecting new messages.
  static void flushOutputBuffer() {
    if (_buffer.isEmpty) {
      return;
    }

    // Output all buffered messages
    for (final entry in _buffer) {
      if (_isDebugMode || _mirrorReleaseLogsToStdout) {
        stdout.writeln(entry.formattedMessage);
      }
      if (!_isDebugMode) {
        developer.log(entry.formattedMessage, name: _appName);
      } 
    }

    // Clear the buffer after flushing
    _buffer.clear();
  }

  /// End output buffering mode
  ///
  /// Stops buffering mode. If flush is true, all buffered messages are printed.
  /// If flush is false, all buffered messages are discarded.
  ///
  /// [flush] - If true, print all buffered messages before ending; if false, discard them
  ///
  /// Returns true if buffering was ended, false if not currently buffering.
  static bool endOutputBuffer([bool flush = false]) {
    if (!_buffering) {
      return false; // Not currently buffering
    }

    if (flush) {
      // Print the buffered messages
      flushOutputBuffer();
    }

    // Clear buffer and stop buffering
    _buffer.clear();
    _buffering = false;

    return true;
  }

  /// Check if output buffering is currently active
  static bool get isBuffering => _buffering;

  /// Get the number of messages currently in the buffer
  static int get bufferSize => _buffer.length;

  //=========================================================================
  // LOGGING METHODS
  //=========================================================================

  /// Log a debug message (only in debug mode)
  static void debug(String message, [String? tag]) {
    if (_isDebugMode) {
      final location = _parseSourceLocation(StackTrace.current);
      _logInternal('DEBUG', message, tag, location);
    }
  }

  /// Log a debug message without source location (for performance)
  static void debugFast(String message, [String? tag]) {
    if (_isDebugMode) {
      final prefix = tag != null ? '[$tag] ' : '';
      stdout.writeln('DEBUG: $prefix$message');
    }
  }

  /// Log an info message
  static void info(String message, [String? tag]) {
    final location = _parseSourceLocation(StackTrace.current);
    _logInternal('INFO', message, tag, location);
  }

  /// Log an info message without source location (for performance)
  static void infoFast(String message, [String? tag]) {
    final prefix = tag != null ? '[$tag] ' : '';
    if (_isDebugMode || _mirrorReleaseLogsToStdout) {
      stdout.writeln('INFO: $prefix$message');
    }
    if (!_isDebugMode) {
      developer.log('$prefix$message', name: _appName);
    }
  }

  /// Log a warning message
  static void warning(String message, [String? tag]) {
    final location = _parseSourceLocation(StackTrace.current);
    _logInternal('WARNING', message, tag, location);
  }

  /// Log a warning message without source location (for performance)
  static void warningFast(String message, [String? tag]) {
    final prefix = tag != null ? '[$tag] ' : '';
    if (_isDebugMode || _mirrorReleaseLogsToStdout) {
      stdout.writeln('WARNING: $prefix$message');
    }
    if (!_isDebugMode) {
      developer.log(
        '$prefix$message',
        name: _appName,
        level: 900,
      ); // Warning level
    }
  }

  /// Log an error message
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    final location = _parseSourceLocation(stackTrace ?? StackTrace.current);
    final locationSuffix = location != null
        ? ' [${location.fileName}:${location.lineNumber}] [${location.functionName}]'
        : '';

    if (_isDebugMode || _mirrorReleaseLogsToStdout) {
      stdout.writeln('ERROR: $message$locationSuffix');
      if (error != null) stdout.writeln('Error details: $error');
      if (stackTrace != null) stdout.writeln('Stack trace: $stackTrace');
    }
    if (!_isDebugMode) {
      developer.log(
        '$message$locationSuffix',
        name: _appName,
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Log an error message without source location (for performance)
  static void errorFast(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (_isDebugMode || _mirrorReleaseLogsToStdout) {
      stdout.writeln('ERROR: $message');
      if (error != null) stdout.writeln('Error details: $error');
      if (stackTrace != null) stdout.writeln('Stack trace: $stackTrace');
    }
    if (!_isDebugMode) {
      developer.log(
        message,
        name: _appName,
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Log with custom level (for advanced usage)
  static void log(
    String message, {
    int? level,
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final location = _parseSourceLocation(stackTrace ?? StackTrace.current);
    final locationSuffix = location != null
        ? ' [${location.fileName}:${location.lineNumber}] [${location.functionName}]'
        : '';

    if (_isDebugMode || _mirrorReleaseLogsToStdout) {
      final levelText = level != null ? 'LEVEL $level: ' : '';
      stdout.writeln('$levelText$message$locationSuffix');
      if (error != null) stdout.writeln('Error details: $error');
      if (stackTrace != null) stdout.writeln('Stack trace: $stackTrace');
    }
    if (!_isDebugMode) {
      developer.log(
        '$message$locationSuffix',
        name: name ?? _appName,
        level: level ?? 500,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Log with custom level without source location (for performance)
  static void logFast(
    String message, {
    int? level,
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_isDebugMode || _mirrorReleaseLogsToStdout) {
      final levelText = level != null ? 'LEVEL $level: ' : '';
      stdout.writeln('$levelText$message');
      if (error != null) stdout.writeln('Error details: $error');
      if (stackTrace != null) stdout.writeln('Stack trace: $stackTrace');
    }
    if (!_isDebugMode) {
      developer.log(
        message,
        name: name ?? _appName,
        level: level ?? 500,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
