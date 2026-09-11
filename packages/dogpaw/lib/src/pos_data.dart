import 'dart:typed_data';

import 'app_logger.dart';

/// One key's processed position triple from BladeHW `key_position`.
///
/// Wire layout matches C++ `DPCommon::PosTriple`: three little-endian floats
/// `(vertical, bend, rawHorizontal)`.
class PosData {
  /// Vertical / depth position for the key.
  final double vertical;

  /// Playable bend already corrected on the blade (`[-1, 1]`).
  final double bend;

  /// Geometric horizontal tilt before blend/curve (`[-1, 1]`).
  final double rawHorizontal;

  /// Purpose:
  ///     Construct one key-position sample for JSON, FFI, and UI consumers.
  /// Parameters:
  ///     vertical: Depth / vertical sample.
  ///     bend: Pre-corrected playable bend in `[-1, 1]`.
  ///     rawHorizontal: Geometric horizontal in `[-1, 1]`.
  /// Return value:
  ///     Immutable `PosData` instance.
  /// Requirements:
  ///     Callers should supply values from BladeHW or a matching simulator.
  /// Guarantees:
  ///     Fields are stored exactly as provided (no clamping here).
  /// Invariants:
  ///     Slot order remains vertical, bend, rawHorizontal.
  const PosData({
    required this.vertical,
    required this.bend,
    required this.rawHorizontal,
  });

  /// Purpose:
  ///     Encode this sample as a JSON map for debug/logging paths.
  /// Parameters:
  ///     None.
  /// Return value:
  ///     Map with keys `vertical`, `bend`, and `rawHorizontal`.
  /// Requirements:
  ///     None.
  /// Guarantees:
  ///     Emits keys `vertical`, `bend`, and `rawHorizontal` only.
  /// Invariants:
  ///     Field meanings match the wire triple.
  Map<String, dynamic> toJson() => {
        'vertical': vertical,
        'bend': bend,
        'rawHorizontal': rawHorizontal,
      };

  /// Purpose:
  ///     Reconstruct a sample from a JSON map.
  /// Parameters:
  ///     json: Map that may contain `vertical`, `bend`, and `rawHorizontal`.
  /// Return value:
  ///     `PosData` with missing keys defaulted to `0.0`.
  /// Requirements:
  ///     Present numeric values must be coercible via Dart map access.
  /// Guarantees:
  ///     Never throws for missing keys.
  /// Invariants:
  ///     Unknown keys are ignored.
  factory PosData.fromJson(Map<String, dynamic> json) => PosData(
        vertical: (json['vertical'] as num?)?.toDouble() ?? 0.0,
        bend: (json['bend'] as num?)?.toDouble() ?? 0.0,
        rawHorizontal: (json['rawHorizontal'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  String toString() =>
      'PosData(vertical: $vertical, bend: $bend, rawHorizontal: $rawHorizontal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PosData &&
          runtimeType == other.runtimeType &&
          vertical == other.vertical &&
          bend == other.bend &&
          rawHorizontal == other.rawHorizontal;

  @override
  int get hashCode => Object.hash(vertical, bend, rawHorizontal);
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

  /// Purpose:
  ///     Read one key's `(vertical, bend, rawHorizontal)` triple from the
  ///     shared-memory-style byte buffer.
  /// Parameters:
  ///     col: Grid column in `0..7`.
  ///     row: Grid row in `0..7`.
  /// Return value:
  ///     Decoded `PosData`, or zeros when the index/bytes are invalid.
  /// Requirements:
  ///     Buffer should contain 64 packed triples (768 bytes) for a full grid.
  /// Guarantees:
  ///     Out-of-range access logs a warning and returns a zero triple.
  /// Invariants:
  ///     Float offsets are 0 / 4 / 8 within each 12-byte triple.
  PosData getPos(int col, int row) {
    if (col < 0 || col >= _numBlades || row < 0 || row >= _keysPerBlade) {
      AppLogger.warning(
          'KeyPositionBuffer: Invalid key position access: col=$col, row=$row');
      return const PosData(vertical: 0.0, bend: 0.0, rawHorizontal: 0.0);
    }

    final offset = _getKeyedBufferOffset(col, row);
    final byteOffset = offset * _posTripleSize;

    if (byteOffset + _posTripleSize > _bytes.length) {
      AppLogger.warning(
          'KeyPositionBuffer: Invalid key position access: col=$col, row=$row, byteOffset=$byteOffset, _bytes.length=${_bytes.length}');
      return const PosData(vertical: 0.0, bend: 0.0, rawHorizontal: 0.0);
    }

    final bd = ByteData.sublistView(_bytes);
    final vert = bd.getFloat32(byteOffset, Endian.little);
    final bend = bd.getFloat32(byteOffset + 4, Endian.little);
    final rawHorizontal = bd.getFloat32(byteOffset + 8, Endian.little);

    return PosData(
      vertical: vert,
      bend: bend,
      rawHorizontal: rawHorizontal,
    );
  }

  /// Calculate offset in the buffer (matches C++ KeyGridUtility::getKeyedBufferOffset)
  int _getKeyedBufferOffset(int col, int row) {
    // Reverse logic from hardware mapping
    int bladeIdx = _numBlades - 1 - col;
    int keyIdx = _keysPerBlade - 1 - row;
    return keyIdx + _keysPerBlade * bladeIdx;
  }
}
