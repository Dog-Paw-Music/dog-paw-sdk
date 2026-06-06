/// Modulation parameters for connections
class ModulationConfig {
  /// Modulation depth (0.0 to 1.0)
  final double amount;

  /// Invert the modulation signal
  final bool inverted;

  /// Use bipolar (-1 to +1) instead of unipolar (0 to 1)
  final bool bipolar;

  /// Default constructor
  const ModulationConfig({
    this.amount = 1.0,
    this.inverted = false,
    this.bipolar = false,
  });

  /// Convert to JSON representation
  Map<String, dynamic> toJson() => {
        'amount': amount,
        'inverted': inverted,
        'bipolar': bipolar,
      };

  /// Create from JSON representation
  factory ModulationConfig.fromJson(Map<String, dynamic> json) =>
      ModulationConfig(
        amount: json['amount']?.toDouble() ?? 1.0,
        inverted: json['inverted'] ?? false,
        bipolar: json['bipolar'] ?? false,
      );

  @override
  String toString() =>
      'ModulationConfig(amount: $amount, inverted: $inverted, bipolar: $bipolar)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModulationConfig &&
          runtimeType == other.runtimeType &&
          amount == other.amount &&
          inverted == other.inverted &&
          bipolar == other.bipolar;

  @override
  int get hashCode => Object.hash(amount, inverted, bipolar);
}
