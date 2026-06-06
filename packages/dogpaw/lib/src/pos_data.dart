import 'dart:typed_data';

import 'app_logger.dart';

class PosData {
  final double vertical;
  final double horizontal;
  final double horizBlendAmt;

  const PosData(
      {required this.vertical,
      required this.horizontal,
      required this.horizBlendAmt});

  Map<String, dynamic> toJson() => {
        'vertical': vertical,
        'horizontal': horizontal,
        'horizBlendAmt': horizBlendAmt
      };

  /// Create from JSON representation
  factory PosData.fromJson(Map<String, dynamic> json) => PosData(
      vertical: json['vertical'] ?? 0.0,
      horizontal: json['horizontal'] ?? 0.0,
      horizBlendAmt: json['horizBlendAmt'] ?? 0.0);

  @override
  String toString() =>
      'PosData(vertical: $vertical, horizontal: $horizontal, horizBlendAmt: $horizBlendAmt)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PosData &&
          runtimeType == other.runtimeType &&
          vertical == other.vertical &&
          horizontal == other.horizontal &&
          horizBlendAmt == other.horizBlendAmt;

  @override
  int get hashCode => Object.hash(vertical, horizontal, horizBlendAmt);
}

/// Buffer containing position data for all keys (8x8 grid)
/// Matches C++ KeyPosBuffer structure
class KeyPositionBuffer {
  final Uint8List _bytes;

  // Constants for 8x8 grid
  static const int _numBlades = 8;
  static const int _keysPerBlade = 8;
  static const int _posTripleSize = 12; // 3 * 4 bytes (float)

  KeyPositionBuffer(this._bytes);

  /// Get position data for a specific column and row
  PosData getPos(int col, int row) {
    if (col < 0 || col >= _numBlades || row < 0 || row >= _keysPerBlade) {
      AppLogger.warning(
          'KeyPositionBuffer: Invalid key position access: col=$col, row=$row');
      return const PosData(vertical: 0.0, horizontal: 0.0, horizBlendAmt: 0.0);
    }

    final offset = _getKeyedBufferOffset(col, row);
    final byteOffset = offset * _posTripleSize;

    if (byteOffset + _posTripleSize > _bytes.length) {
      AppLogger.warning(
          'KeyPositionBuffer: Invalid key position access: col=$col, row=$row, byteOffset=$byteOffset, _bytes.length=${_bytes.length}');
      return const PosData(vertical: 0.0, horizontal: 0.0, horizBlendAmt: 0.0);
    }

    final bd = ByteData.sublistView(_bytes);
    final vert = bd.getFloat32(byteOffset, Endian.little);
    final horiz = bd.getFloat32(byteOffset + 4, Endian.little);
    final blend = bd.getFloat32(byteOffset + 8, Endian.little);

    return PosData(vertical: vert, horizontal: horiz, horizBlendAmt: blend);
  }

  /// Calculate offset in the buffer (matches C++ KeyGridUtility::getKeyedBufferOffset)
  int _getKeyedBufferOffset(int col, int row) {
    // Reverse logic from hardware mapping
    int bladeIdx = _numBlades - 1 - col;
    int keyIdx = _keysPerBlade - 1 - row;
    return keyIdx + _keysPerBlade * bladeIdx;
  }
}
