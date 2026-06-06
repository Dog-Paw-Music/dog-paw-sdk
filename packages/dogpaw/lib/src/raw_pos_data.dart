class RawPosData {
  final int v1;
  final int v2;

  const RawPosData({
    required this.v1,
    required this.v2,
  });

  Map<String, dynamic> toJson() => {'v1': v1, 'v2': v2};

  /// Create from JSON representation
  factory RawPosData.fromJson(Map<String, dynamic> json) => RawPosData(
        v1: json['v1'] ?? 0,
        v2: json['v2'] ?? 0,
      );

  @override
  String toString() => 'RawPosData(v1: $v1, v2: $v2)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawPosData &&
          runtimeType == other.runtimeType &&
          v1 == other.v1 &&
          v2 == other.v2;

  @override
  int get hashCode => Object.hash(v1, v2);
}
