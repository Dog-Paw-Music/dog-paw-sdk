import 'key_event.dart';

/// Near-press position data derived from DPQueue.hpp NearPressPositionData structure
/// Contains raw sensor data around key press events
class NearPressPositionData {
  /// Number of sensor data points
  static const int numPoints = 32;

  /// Array of sensor data values (32 points)
  final List<double> sensorData;

  /// The key event that triggered this data collection
  final KeyEvent keyEvent;

  /// Constructor with required parameters
  const NearPressPositionData({
    required this.sensorData,
    required this.keyEvent,
  }) : assert(sensorData.length == numPoints,
            'sensorData must contain exactly $numPoints elements');

  /// Convert to JSON representation
  Map<String, dynamic> toJson() => {
        'sensorData': sensorData,
        'keyEvent': keyEvent.toJson(),
      };

  /// Create from JSON representation
  factory NearPressPositionData.fromJson(Map<String, dynamic> json) {
    // Parse sensor data array
    final List<dynamic> sensorDataJson = json['sensorData'] ?? [];
    final List<double> sensorData =
        sensorDataJson.map((e) => (e as num).toDouble()).toList();

    // Ensure we have exactly numPoints elements, pad with zeros if needed
    while (sensorData.length < numPoints) {
      sensorData.add(0.0);
    }
    if (sensorData.length > numPoints) {
      sensorData.removeRange(numPoints, sensorData.length);
    }

    // Parse key event
    final KeyEvent keyEvent = KeyEvent.fromJson(
      json['keyEvent'] as Map<String, dynamic>? ?? {},
    );

    return NearPressPositionData(
      sensorData: sensorData,
      keyEvent: keyEvent,
    );
  }

  @override
  String toString() =>
      'NearPressPositionData(keyEvent: $keyEvent, sensorData: [${sensorData.length} points])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NearPressPositionData &&
          runtimeType == other.runtimeType &&
          _listEquals(sensorData, other.sensorData) &&
          keyEvent == other.keyEvent;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(sensorData),
        keyEvent,
      );

  /// Helper method to compare two lists
  static bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
