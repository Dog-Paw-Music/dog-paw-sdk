/// Knob data containing values for 6 knobs
///
/// This class represents the current state of all 6 hardware knobs,
/// with each knob value being a floating-point number typically in the range [0.0, 1.0].
class KnobData {
  /// Array of 6 knob values
  final List<double> values;

  /// Constructor with all 6 knob values
  KnobData({
    required this.values,
  }) : assert(values.length == 6, 'KnobData must contain exactly 6 values');

  /// Constructor from individual values
  KnobData.fromValues(
    double knob0,
    double knob1,
    double knob2,
    double knob3,
    double knob4,
    double knob5,
  ) : values = [knob0, knob1, knob2, knob3, knob4, knob5];

  /// Get value for a specific knob (0-5)
  double getKnobValue(int knobIndex) {
    if (knobIndex < 0 || knobIndex >= 6) {
      throw RangeError('Knob index must be between 0 and 5, got $knobIndex');
    }
    return values[knobIndex];
  }

  /// Convert to JSON representation
  Map<String, dynamic> toJson() => {
        'values': values,
      };

  /// Create from JSON representation
  factory KnobData.fromJson(Map<String, dynamic> json) {
    final valuesList = json['values'] as List<dynamic>?;
    if (valuesList == null || valuesList.length != 6) {
      throw ArgumentError('KnobData JSON must contain exactly 6 values');
    }
    return KnobData(
      values: valuesList.map((v) => (v as num).toDouble()).toList(),
    );
  }

  @override
  String toString() => 'KnobData(values: $values)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KnobData &&
          runtimeType == other.runtimeType &&
          _listEquals(values, other.values);

  @override
  int get hashCode => Object.hashAll(values);
}

/// Helper function to compare lists for equality
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
