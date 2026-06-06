/// Numeric range specification
class Range {
  /// Minimum value in the range
  final double min;

  /// Maximum value in the range
  final double max;

  /// Default constructor with range 0.0 to 1.0
  const Range({this.min = 0.0, this.max = 1.0});

  /// Constructor with explicit min and max values
  const Range.fromValues(this.min, this.max);

  /// Check if a value is within this range
  ///
  /// [value] - The value to check
  /// Returns true if the value is within the range (inclusive)
  bool contains(double value) => value >= min && value <= max;

  /// Clamp a value to this range
  ///
  /// [value] - The value to clamp
  /// Returns the value clamped to the range bounds
  double clamp(double value) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Convert to JSON representation
  Map<String, dynamic> toJson() => {
        'min': min,
        'max': max,
      };

  /// Create from JSON representation
  factory Range.fromJson(Map<String, dynamic> json) => Range(
        min: json['min']?.toDouble() ?? 0.0,
        max: json['max']?.toDouble() ?? 1.0,
      );

  @override
  String toString() => 'Range(min: $min, max: $max)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Range &&
          runtimeType == other.runtimeType &&
          min == other.min &&
          max == other.max;

  @override
  int get hashCode => min.hashCode ^ max.hashCode;
}
