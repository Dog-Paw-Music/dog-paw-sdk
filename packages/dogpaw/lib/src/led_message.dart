import 'dart:math';
import 'dart:typed_data';

import 'json_constants.dart';

/// Enumerates the currently supported LED wire commands from `ledControlTypes.hpp`.
enum LedCommand {
  none(0),
  solidKey(1),
  modGlobal(2),
  keyAnimWave(3),
  keyAnimTwinkle(4),
  keyAnimHighlight(5),
  keyAnimCancel(6),
  keyAnimHighlightMask(7),
  keyAnimSpreadHighlight(8),
  keyAnimParamUpdate(9),
  keyAnimColorUpdate(10),
  sideAnimLrHighlight(11),
  sideAnimParamUpdate(12),
  sideAnimColorUpdate(13),
  lifecycleSync(14),
  keyAnimPulse(15),
  sideAnimPulse(16),
  keyAnimRainbowWave(17),
  keyAnimPulseWave(18);

  /// Purpose: Bind each enum member to the exact 16-bit on-wire value.
  ///
  /// Parameters:
  /// - [wireValue]: native `LED_CMD_*` integer from `ledControlTypes.hpp`.
  ///
  /// Return value:
  /// - None. This is an enum constructor.
  ///
  /// Requirements/Preconditions:
  /// - [wireValue] must match the native command contract.
  ///
  /// Guarantees/Postconditions:
  /// - `wireValue` remains stable for each enum member.
  ///
  /// Invariants:
  /// - The mapping is one-to-one with the current native LED command set.
  const LedCommand(this.wireValue);

  /// Exact 16-bit command value used on the LED wire.
  final int wireValue;

  /// Purpose: Resolve one raw wire command into a typed enum when known.
  ///
  /// Parameters:
  /// - [wireValue]: 16-bit command value read from one wire record.
  ///
  /// Return value:
  /// - Matching [LedCommand], or `null` when the command is unknown locally.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returns `null` instead of throwing for unknown future commands.
  ///
  /// Invariants:
  /// - Does not mutate global or instance state.
  static LedCommand? fromWireValue(int wireValue) {
    for (final LedCommand command in LedCommand.values) {
      if (command.wireValue == wireValue) {
        return command;
      }
    }
    return null;
  }
}

/// Shared LED wire constants and byte helpers for `DataType.ledMessage`.
abstract final class LedWire {
  static const int size = 32;
  static const int schemaV1 = 1;
  static const int payloadBytes = 29;

  static const int cmdSolidKey = 1;
  static const int cmdModGlobal = 2;
  static const int cmdKeyAnimWave = 3;
  static const int cmdKeyAnimTwinkle = 4;
  static const int cmdKeyAnimHighlight = 5;
  static const int cmdKeyAnimCancel = 6;
  static const int cmdKeyAnimHighlightMask = 7;
  static const int cmdKeyAnimSpreadHighlight = 8;
  static const int cmdKeyAnimParamUpdate = 9;
  static const int cmdKeyAnimColorUpdate = 10;
  static const int cmdSideAnimLrHighlight = 11;
  static const int cmdSideAnimParamUpdate = 12;
  static const int cmdSideAnimColorUpdate = 13;
  static const int cmdLifecycleSync = 14;
  static const int cmdKeyAnimPulse = 15;
  static const int cmdSideAnimPulse = 16;
  static const int cmdKeyAnimRainbowWave = 17;
  static const int cmdKeyAnimPulseWave = 18;

  static const int solidFlagOverride = 0x01;
  static const int syncFlagStart = 0x01;
  static const int syncFlagEnd = 0x02;
  static const int syncMaxIdsPerChunk = 10;

  static const int animParamSpreadHighlightSpread = 0;
  static const int animParamSpreadHighlightShape = 1;
  static const int animParamSpreadHighlightLr = 2;
  static const int animParamKeyPulseHz = 0;
  static const int animParamSidePulseHz = 0;
  static const int animParamLrHighlightLr = 0;

  /// Purpose: Pack one key-grid coordinate into the shared LED key-id format.
  ///
  /// Parameters:
  /// - [col]: key column; only the low three bits are used.
  /// - [row]: key row; only the low three bits are used.
  ///
  /// Return value:
  /// - Packed key-id byte matching the native SPI/shadow-grid convention.
  ///
  /// Requirements/Preconditions:
  /// - Callers should pass logical 0..7 grid coordinates.
  ///
  /// Guarantees/Postconditions:
  /// - Higher bits are masked off to match the native contract.
  ///
  /// Invariants:
  /// - No external state is mutated.
  static int packKeyColRow(int col, int row) => ((col & 7) << 3) | (row & 7);

  /// Purpose: Unpack one shared LED key-id byte into `(column, row)`.
  ///
  /// Parameters:
  /// - [keyId]: packed key identifier from the LED wire record.
  ///
  /// Return value:
  /// - Dart record containing `(column, row)`.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returned values are masked into the native 0..7 key-grid range.
  ///
  /// Invariants:
  /// - No external state is mutated.
  static (int, int) unpackKeyColRow(int keyId) =>
      (((keyId >> 3) & 7), (keyId & 7));

  /// Bit index for [cmdKeyAnimHighlightMask] key masks using the shadow-grid convention.
  static int keyMaskBitIndex(int col, int row) => (col & 7) * 8 + (row & 7);

  /// Purpose: Pack one ARGB color into the native AARRGGBB integer format.
  ///
  /// Parameters:
  /// - [a]: alpha channel 0..255.
  /// - [r]: red channel 0..255.
  /// - [g]: green channel 0..255.
  /// - [b]: blue channel 0..255.
  ///
  /// Return value:
  /// - Packed 32-bit color value.
  ///
  /// Requirements/Preconditions:
  /// - Channel values should be byte-sized; higher bits are masked off.
  ///
  /// Guarantees/Postconditions:
  /// - The return value matches the native AARRGGBB layout.
  ///
  /// Invariants:
  /// - No external state is mutated.
  static int packArgb(int a, int r, int g, int b) =>
      ((a & 0xff) << 24) |
      ((r & 0xff) << 16) |
      ((g & 0xff) << 8) |
      (b & 0xff);

  /// Extracts the alpha channel from one packed ARGB color.
  static int argbAlpha(int argb) => (argb >> 24) & 0xff;

  /// Extracts the red channel from one packed ARGB color.
  static int argbRed(int argb) => (argb >> 16) & 0xff;

  /// Extracts the green channel from one packed ARGB color.
  static int argbGreen(int argb) => (argb >> 8) & 0xff;

  /// Extracts the blue channel from one packed ARGB color.
  static int argbBlue(int argb) => argb & 0xff;

  /// Purpose: Read one unsigned 64-bit little-endian integer from the LED payload.
  ///
  /// Parameters:
  /// - [data]: source LED wire bytes.
  /// - [offset]: starting byte offset.
  ///
  /// Return value:
  /// - Decoded unsigned 64-bit integer as a Dart [int].
  ///
  /// Requirements/Preconditions:
  /// - `[offset, offset + 8)` is readable within [data].
  ///
  /// Guarantees/Postconditions:
  /// - Decodes using little-endian byte order.
  ///
  /// Invariants:
  /// - No external state is mutated.
  static int readU64Le(ByteData data, int offset) {
    int value = 0;
    for (int index = 0; index < 8; index++) {
      value |= data.getUint8(offset + index) << (8 * index);
    }
    return value;
  }

  /// Purpose: Write one unsigned 64-bit little-endian integer into the LED payload.
  ///
  /// Parameters:
  /// - [data]: destination LED wire bytes.
  /// - [offset]: starting byte offset.
  /// - [value]: integer value whose low 64 bits should be written.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - `[offset, offset + 8)` is writable within [data].
  ///
  /// Guarantees/Postconditions:
  /// - Writes using little-endian byte order.
  ///
  /// Invariants:
  /// - Only the addressed 8-byte window is modified.
  static void writeU64Le(ByteData data, int offset, int value) {
    for (int index = 0; index < 8; index++) {
      data.setUint8(offset + index, (value >> (8 * index)) & 0xff);
    }
  }

  /// Purpose: Copy one arbitrary [ByteData] view into a fixed-width LED record.
  ///
  /// Parameters:
  /// - [source]: source bytes to normalize.
  ///
  /// Return value:
  /// - Fresh [ByteData] of length [size] with source bytes copied in and any
  ///   remaining bytes zero-filled.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - The returned record is always exactly [size] bytes long.
  ///
  /// Invariants:
  /// - Does not mutate [source].
  static ByteData normalize(ByteData source) {
    final ByteData normalized = ByteData(size);
    final Uint8List sourceBytes = source.buffer.asUint8List(
      source.offsetInBytes,
      source.lengthInBytes,
    );
    final int copyLength = min(size, sourceBytes.length);
    for (int index = 0; index < copyLength; index++) {
      normalized.setUint8(index, sourceBytes[index]);
    }
    return normalized;
  }
}

/// Assigns 16-bit animation instance ids from a random base.
class LedClientAnimIdAllocator {
  /// Purpose: Create one allocator for one logical LED producer.
  ///
  /// Parameters:
  /// - [base]: optional starting ID; masked to 16 bits when supplied.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Chooses a random 16-bit base when [base] is omitted.
  ///
  /// Invariants:
  /// - IDs advance by one modulo 16 bits.
  LedClientAnimIdAllocator([int? base])
      : base = (base ?? Random().nextInt(65536)) & 0xffff;

  /// Random or caller-supplied base for this allocator.
  final int base;
  int _seq = 0;

  /// Purpose: Return the next sender-local animation ID.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Next 16-bit animation instance ID.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returns `(base + seq) mod 65536`.
  ///
  /// Invariants:
  /// - Advances internal sequence state by exactly one.
  int next() {
    final int value = (base + (_seq & 0xffff)) & 0xffff;
    _seq++;
    return value;
  }
}

/// Base type for one 32-byte LED wire record on a message-queue endpoint.
abstract class LEDMessage {
  /// Base constructor for typed LED message subclasses.
  const LEDMessage._();

  /// Purpose: Preserve the legacy solid-key constructor as the default public entrypoint.
  ///
  /// Parameters:
  /// - [column], [row]: key coordinate for the solid-key command.
  /// - [red], [green], [blue], [alpha]: RGBA channels.
  /// - [info]: legacy JSON-only metadata field retained for compatibility.
  /// - [modifierLayer]: non-zero means "write override solid" on the wire.
  /// - [timestamp]: legacy app-side metadata field retained for compatibility.
  ///
  /// Return value:
  /// - One [SolidKeyLEDMessage].
  ///
  /// Requirements/Preconditions:
  /// - Intended only for the solid-key command family.
  ///
  /// Guarantees/Postconditions:
  /// - Produces a message compatible with the old `LEDMessage(...)` constructor.
  ///
  /// Invariants:
  /// - Does not expose any extra retained-animation semantics.
  factory LEDMessage({
    required int column,
    required int row,
    required int red,
    required int green,
    required int blue,
    int alpha,
    int info,
    int modifierLayer,
    int timestamp,
  }) = SolidKeyLEDMessage.legacy;

  /// Purpose: Decode one 32-byte LED wire record into the best matching typed message.
  ///
  /// Parameters:
  /// - [data]: source LED wire bytes.
  ///
  /// Return value:
  /// - Known typed [LEDMessage] subclass when the command is recognized.
  /// - [UnknownLEDMessage] when the command or schema is not recognized locally.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Preserves the original wire bytes even for unknown commands.
  ///
  /// Invariants:
  /// - Never throws for unknown command values.
  factory LEDMessage.fromWireByteData(ByteData data) {
    final ByteData normalized = LedWire.normalize(data);
    final int schemaVersion = normalized.getUint8(0);
    final int wireCommand = normalized.getUint16(1, Endian.little);
    if (schemaVersion != LedWire.schemaV1) {
      return UnknownLEDMessage._(normalized);
    }

    switch (LedCommand.fromWireValue(wireCommand)) {
      case LedCommand.solidKey:
        return SolidKeyLEDMessage.fromWireByteData(normalized);
      case LedCommand.modGlobal:
        return ModGlobalLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimWave:
        return KeyWaveLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimTwinkle:
        return KeyTwinkleLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimHighlight:
        return KeyHighlightLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimCancel:
        return AnimationCancelLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimHighlightMask:
        return KeyHighlightMaskLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimSpreadHighlight:
        return SpreadHighlightLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimParamUpdate:
        return AnimationParamUpdateLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimColorUpdate:
        return AnimationColorUpdateLEDMessage.fromWireByteData(normalized);
      case LedCommand.sideAnimLrHighlight:
        return LrHighlightLEDMessage.fromWireByteData(normalized);
      case LedCommand.sideAnimParamUpdate:
        return SideAnimationParamUpdateLEDMessage.fromWireByteData(normalized);
      case LedCommand.sideAnimColorUpdate:
        return SideAnimationColorUpdateLEDMessage.fromWireByteData(normalized);
      case LedCommand.lifecycleSync:
        return LifecycleSyncLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimPulse:
        return KeyPulseLEDMessage.fromWireByteData(normalized);
      case LedCommand.sideAnimPulse:
        return SidePulseLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimRainbowWave:
        return RainbowWaveLEDMessage.fromWireByteData(normalized);
      case LedCommand.keyAnimPulseWave:
        return PulseWaveLEDMessage.fromWireByteData(normalized);
      case LedCommand.none:
      case null:
        return UnknownLEDMessage._(normalized);
    }
  }

  /// Purpose: Decode one legacy JSON solid-key payload.
  ///
  /// Parameters:
  /// - [json]: JSON map shaped like the historical solid-key Dart API.
  ///
  /// Return value:
  /// - One [SolidKeyLEDMessage] using the supplied fields.
  ///
  /// Requirements/Preconditions:
  /// - Intended for legacy solid-key JSON only.
  ///
  /// Guarantees/Postconditions:
  /// - Preserves the old JSON-to-solid-message behavior.
  ///
  /// Invariants:
  /// - Does not attempt to infer other command families from JSON.
  factory LEDMessage.fromJson(Map<String, dynamic> json) =>
      SolidKeyLEDMessage.legacy(
        column: json[JsonFields.COLUMN] ?? 0,
        row: json[JsonFields.ROW] ?? 0,
        red: json[JsonFields.RED] ?? 0,
        green: json[JsonFields.GREEN] ?? 0,
        blue: json[JsonFields.BLUE] ?? 0,
        alpha: json[JsonFields.ALPHA] ?? 255,
        info: json[JsonFields.INFO] ?? 0,
        modifierLayer: json[JsonFields.MODIFIER_LAYER] ?? 0,
        timestamp: json[JsonFields.TIMESTAMP] ?? 0,
      );

  /// Current schema version written by this message.
  int get schemaVersion;

  /// Typed command when the record is known locally, otherwise `null`.
  LedCommand? get command;

  /// Raw 16-bit wire command value.
  int get wireCommand;

  /// Purpose: Encode this message into the fixed-width LED wire format.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Fresh [ByteData] of length [LedWire.size].
  ///
  /// Requirements/Preconditions:
  /// - Message fields satisfy the command-specific LED wire contract.
  ///
  /// Guarantees/Postconditions:
  /// - Returned bytes are safe to enqueue on `DataType.ledMessage`.
  ///
  /// Invariants:
  /// - Does not mutate message state.
  ByteData toWireByteData();

  /// Purpose: Encode this message into a detached byte list copy.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Fresh [Uint8List] copy of the wire record.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Returned list is not aliased with internal storage.
  ///
  /// Invariants:
  /// - Does not mutate message state.
  Uint8List toWireBytes() => Uint8List.fromList(
        toWireByteData().buffer.asUint8List(),
      );

  /// Purpose: Convert this message into a JSON-like debugging map.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - JSON-safe map containing generic wire metadata.
  ///
  /// Requirements/Preconditions:
  /// - None.
  ///
  /// Guarantees/Postconditions:
  /// - Known command families may override this for richer structured output.
  ///
  /// Invariants:
  /// - Does not mutate message state.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'command': wireCommand,
        'wireBytes': toWireBytes(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! LEDMessage || runtimeType != other.runtimeType) {
      return false;
    }
    final Uint8List lhs = toWireBytes();
    final Uint8List rhs = other.toWireBytes();
    if (lhs.length != rhs.length) {
      return false;
    }
    for (int index = 0; index < lhs.length; index++) {
      if (lhs[index] != rhs[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    int hash = runtimeType.hashCode;
    for (final int byte in toWireBytes()) {
      hash = (hash * 31) ^ byte;
    }
    return hash;
  }
}

/// Base class for known schema-v1 messages.
abstract class KnownLEDMessage extends LEDMessage {
  const KnownLEDMessage() : super._();

  @override
  int get schemaVersion => LedWire.schemaV1;

  @override
  int get wireCommand => command!.wireValue;

  /// Purpose: Create one zeroed wire record with this message's command header.
  ///
  /// Parameters:
  /// - None.
  ///
  /// Return value:
  /// - Mutable [ByteData] initialized with schema and command bytes.
  ///
  /// Requirements/Preconditions:
  /// - [command] is non-null for known messages.
  ///
  /// Guarantees/Postconditions:
  /// - Payload bytes start zero-filled.
  ///
  /// Invariants:
  /// - Returns a fresh detached buffer on every call.
  ByteData buildBaseWireData() {
    final ByteData data = ByteData(LedWire.size);
    data.setUint8(0, schemaVersion);
    data.setUint16(1, wireCommand, Endian.little);
    return data;
  }
}

/// Preserves unknown or future LED commands without losing their wire bytes.
class UnknownLEDMessage extends LEDMessage {
  /// Purpose: Preserve one unrecognized LED wire record.
  ///
  /// Parameters:
  /// - [data]: normalized 32-byte LED wire record.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [data] should already be normalized to [LedWire.size].
  ///
  /// Guarantees/Postconditions:
  /// - Future `toWireByteData()` calls return the same bytes.
  ///
  /// Invariants:
  /// - This object never interprets payload semantics beyond header accessors.
  UnknownLEDMessage._(ByteData data)
      : _data = LedWire.normalize(data),
        super._();

  final ByteData _data;

  @override
  int get schemaVersion => _data.getUint8(0);

  @override
  LedCommand? get command =>
      LedCommand.fromWireValue(_data.getUint16(1, Endian.little));

  @override
  int get wireCommand => _data.getUint16(1, Endian.little);

  @override
  ByteData toWireByteData() => LedWire.normalize(_data);
}

/// Legacy solid-key message plus the typed modern solid-key builder.
class SolidKeyLEDMessage extends KnownLEDMessage {
  /// Purpose: Create one typed solid-key LED message from packed ARGB data.
  ///
  /// Parameters:
  /// - [column], [row]: key coordinate to paint.
  /// - [colorArgb]: packed AARRGGBB solid color.
  /// - [asOverride]: whether the solid should write the override layer.
  /// - [info], [timestamp]: legacy compatibility metadata retained for callers.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Intended only for `LED_CMD_SOLID_KEY`.
  ///
  /// Guarantees/Postconditions:
  /// - `modifierLayer` becomes `1` when [asOverride] is true, else `0`.
  ///
  /// Invariants:
  /// - The payload remains compatible with the historical Dart LED constructor.
  SolidKeyLEDMessage({
    required this.column,
    required this.row,
    required this.colorArgb,
    bool asOverride = true,
    this.info = 1 | (1 << 3) | (1 << 4),
    this.timestamp = 0,
  }) : modifierLayer = asOverride ? 1 : 0;

  /// Purpose: Preserve the historical RGBA-based Dart constructor surface.
  ///
  /// Parameters:
  /// - [column], [row]: key coordinate.
  /// - [red], [green], [blue], [alpha]: RGBA channels.
  /// - [info], [modifierLayer], [timestamp]: legacy compatibility fields.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - Intended only for the solid-key command family.
  ///
  /// Guarantees/Postconditions:
  /// - `colorArgb` is packed using the native AARRGGBB contract.
  ///
  /// Invariants:
  /// - Any non-zero [modifierLayer] means the wire override flag is set.
  SolidKeyLEDMessage.legacy({
    required this.column,
    required this.row,
    required int red,
    required int green,
    required int blue,
    int alpha = 255,
    this.info = 1 | (1 << 3) | (1 << 4),
    this.modifierLayer = 0,
    this.timestamp = 0,
  }) : colorArgb = LedWire.packArgb(alpha, red, green, blue);

  /// Purpose: Decode one schema-v1 solid-key wire record.
  ///
  /// Parameters:
  /// - [data]: normalized solid-key wire bytes.
  ///
  /// Return value:
  /// - One [SolidKeyLEDMessage].
  ///
  /// Requirements/Preconditions:
  /// - [data] carries `LED_CMD_SOLID_KEY`.
  ///
  /// Guarantees/Postconditions:
  /// - Override flag is mapped onto `modifierLayer` as `1` or `0`.
  ///
  /// Invariants:
  /// - Legacy JSON metadata is reset to its default compatible values.
  factory SolidKeyLEDMessage.fromWireByteData(ByteData data) {
    final (int column, int row) =
        LedWire.unpackKeyColRow(data.getUint8(3));
    final int colorArgb = data.getUint32(4, Endian.little);
    final bool asOverride =
        (data.getUint8(8) & LedWire.solidFlagOverride) != 0;
    return SolidKeyLEDMessage(
      column: column,
      row: row,
      colorArgb: colorArgb,
      asOverride: asOverride,
    );
  }

  final int column;
  final int row;
  final int colorArgb;
  final int info;
  final int modifierLayer;
  final int timestamp;

  bool get asOverride => modifierLayer != 0;
  int get alpha => LedWire.argbAlpha(colorArgb);
  int get red => LedWire.argbRed(colorArgb);
  int get green => LedWire.argbGreen(colorArgb);
  int get blue => LedWire.argbBlue(colorArgb);

  @override
  LedCommand get command => LedCommand.solidKey;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint8(3, LedWire.packKeyColRow(column, row));
    data.setUint32(4, colorArgb, Endian.little);
    data.setUint8(8, asOverride ? LedWire.solidFlagOverride : 0);
    return data;
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        JsonFields.COLUMN: column,
        JsonFields.ROW: row,
        JsonFields.RED: red,
        JsonFields.GREEN: green,
        JsonFields.BLUE: blue,
        JsonFields.ALPHA: alpha,
        JsonFields.INFO: info,
        JsonFields.MODIFIER_LAYER: modifierLayer,
        JsonFields.TIMESTAMP: timestamp,
      };

  @override
  String toString() =>
      'SolidKeyLEDMessage(column: $column, row: $row, colorArgb: 0x${colorArgb.toRadixString(16).padLeft(8, '0')})';
}

/// Global solid-color modifier layer command.
class ModGlobalLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_MOD_GLOBAL` message.
  const ModGlobalLEDMessage({required this.colorArgb});

  /// Decodes one `LED_CMD_MOD_GLOBAL` wire record.
  factory ModGlobalLEDMessage.fromWireByteData(ByteData data) =>
      ModGlobalLEDMessage(
        colorArgb: data.getUint32(3, Endian.little),
      );

  final int colorArgb;

  @override
  LedCommand get command => LedCommand.modGlobal;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint32(3, colorArgb, Endian.little);
    return data;
  }
}

/// One non-retained wave animation create command.
class KeyWaveLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_WAVE` message.
  const KeyWaveLEDMessage({
    required this.colorArgb,
    required this.originKeyId,
    required this.durationFrames,
  });

  /// Decodes one `LED_CMD_KEY_ANIM_WAVE` wire record.
  factory KeyWaveLEDMessage.fromWireByteData(ByteData data) =>
      KeyWaveLEDMessage(
        colorArgb: data.getUint32(3, Endian.little),
        originKeyId: data.getUint8(7),
        durationFrames: data.getUint16(8, Endian.little),
      );

  final int colorArgb;
  final int originKeyId;
  final int durationFrames;

  @override
  LedCommand get command => LedCommand.keyAnimWave;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint32(3, colorArgb, Endian.little);
    data.setUint8(7, originKeyId & 0xff);
    data.setUint16(8, durationFrames & 0xffff, Endian.little);
    return data;
  }
}

/// One non-retained twinkle animation create command.
class KeyTwinkleLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_TWINKLE` message.
  const KeyTwinkleLEDMessage({
    required this.centerKeyId,
    required this.durationFrames,
    required this.seed,
  });

  /// Decodes one `LED_CMD_KEY_ANIM_TWINKLE` wire record.
  factory KeyTwinkleLEDMessage.fromWireByteData(ByteData data) =>
      KeyTwinkleLEDMessage(
        centerKeyId: data.getUint8(3),
        durationFrames: data.getUint16(4, Endian.little),
        seed: data.getUint16(6, Endian.little),
      );

  final int centerKeyId;
  final int durationFrames;
  final int seed;

  @override
  LedCommand get command => LedCommand.keyAnimTwinkle;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint8(3, centerKeyId & 0xff);
    data.setUint16(4, durationFrames & 0xffff, Endian.little);
    data.setUint16(6, seed & 0xffff, Endian.little);
    return data;
  }
}

/// One retained single-key highlight create command.
class KeyHighlightLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_HIGHLIGHT` message.
  const KeyHighlightLEDMessage({
    required this.column,
    required this.row,
    required this.colorArgb,
    required this.clientInstanceId,
  });

  /// Decodes one `LED_CMD_KEY_ANIM_HIGHLIGHT` wire record.
  factory KeyHighlightLEDMessage.fromWireByteData(ByteData data) {
    final (int column, int row) =
        LedWire.unpackKeyColRow(data.getUint8(3));
    return KeyHighlightLEDMessage(
      column: column,
      row: row,
      colorArgb: data.getUint32(4, Endian.little),
      clientInstanceId: data.getUint16(8, Endian.little),
    );
  }

  final int column;
  final int row;
  final int colorArgb;
  final int clientInstanceId;

  @override
  LedCommand get command => LedCommand.keyAnimHighlight;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint8(3, LedWire.packKeyColRow(column, row));
    data.setUint32(4, colorArgb, Endian.little);
    data.setUint16(8, clientInstanceId & 0xffff, Endian.little);
    return data;
  }
}

/// One retained animation cancel command shared across retained families.
class AnimationCancelLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_CANCEL` message.
  const AnimationCancelLEDMessage({required this.clientInstanceId});

  /// Decodes one `LED_CMD_KEY_ANIM_CANCEL` wire record.
  factory AnimationCancelLEDMessage.fromWireByteData(ByteData data) =>
      AnimationCancelLEDMessage(
        clientInstanceId: data.getUint16(3, Endian.little),
      );

  final int clientInstanceId;

  @override
  LedCommand get command => LedCommand.keyAnimCancel;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint16(3, clientInstanceId & 0xffff, Endian.little);
    return data;
  }
}

/// One retained multi-key highlight create command.
class KeyHighlightMaskLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_HIGHLIGHT_MASK` message.
  const KeyHighlightMaskLEDMessage({
    required this.colorArgb,
    required this.keyMask,
    required this.clientInstanceId,
  });

  /// Decodes one `LED_CMD_KEY_ANIM_HIGHLIGHT_MASK` wire record.
  factory KeyHighlightMaskLEDMessage.fromWireByteData(ByteData data) =>
      KeyHighlightMaskLEDMessage(
        colorArgb: data.getUint32(3, Endian.little),
        keyMask: LedWire.readU64Le(data, 7),
        clientInstanceId: data.getUint16(15, Endian.little),
      );

  final int colorArgb;
  final int keyMask;
  final int clientInstanceId;

  @override
  LedCommand get command => LedCommand.keyAnimHighlightMask;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint32(3, colorArgb, Endian.little);
    LedWire.writeU64Le(data, 7, keyMask);
    data.setUint16(15, clientInstanceId & 0xffff, Endian.little);
    return data;
  }
}

/// One retained spread-highlight create command.
class SpreadHighlightLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_SPREAD_HIGHLIGHT` message.
  const SpreadHighlightLEDMessage({
    required this.column,
    required this.row,
    required this.colorArgb,
    required this.spread,
    required this.shape,
    required this.clientInstanceId,
  });

  /// Decodes one `LED_CMD_KEY_ANIM_SPREAD_HIGHLIGHT` wire record.
  factory SpreadHighlightLEDMessage.fromWireByteData(ByteData data) {
    final (int column, int row) =
        LedWire.unpackKeyColRow(data.getUint8(3));
    return SpreadHighlightLEDMessage(
      column: column,
      row: row,
      colorArgb: data.getUint32(4, Endian.little),
      clientInstanceId: data.getUint16(8, Endian.little),
      spread: data.getFloat32(10, Endian.little),
      shape: data.getFloat32(14, Endian.little),
    );
  }

  final int column;
  final int row;
  final int colorArgb;
  final double spread;
  final double shape;
  final int clientInstanceId;

  @override
  LedCommand get command => LedCommand.keyAnimSpreadHighlight;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint8(3, LedWire.packKeyColRow(column, row));
    data.setUint32(4, colorArgb, Endian.little);
    data.setUint16(8, clientInstanceId & 0xffff, Endian.little);
    data.setFloat32(10, spread, Endian.little);
    data.setFloat32(14, shape, Endian.little);
    return data;
  }
}

/// One retained per-key LR-highlight create command.
class LrHighlightLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_SIDE_ANIM_LR_HIGHLIGHT` message.
  const LrHighlightLEDMessage({
    required this.column,
    required this.row,
    required this.colorArgb,
    required this.lr,
    required this.clientInstanceId,
  });

  /// Decodes one `LED_CMD_SIDE_ANIM_LR_HIGHLIGHT` wire record.
  factory LrHighlightLEDMessage.fromWireByteData(ByteData data) {
    final (int column, int row) =
        LedWire.unpackKeyColRow(data.getUint8(3));
    return LrHighlightLEDMessage(
      column: column,
      row: row,
      colorArgb: data.getUint32(4, Endian.little),
      clientInstanceId: data.getUint16(8, Endian.little),
      lr: data.getFloat32(10, Endian.little),
    );
  }

  final int column;
  final int row;
  final int colorArgb;
  final double lr;
  final int clientInstanceId;

  @override
  LedCommand get command => LedCommand.sideAnimLrHighlight;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint8(3, LedWire.packKeyColRow(column, row));
    data.setUint32(4, colorArgb, Endian.little);
    data.setUint16(8, clientInstanceId & 0xffff, Endian.little);
    data.setFloat32(10, lr, Endian.little);
    return data;
  }
}

/// One retained key-pulse create command.
class KeyPulseLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_PULSE` message.
  const KeyPulseLEDMessage({
    required this.colorArgb,
    required this.colorArgbB,
    required this.keyMask,
    required this.clientInstanceId,
  });

  /// Decodes one `LED_CMD_KEY_ANIM_PULSE` wire record.
  factory KeyPulseLEDMessage.fromWireByteData(ByteData data) =>
      KeyPulseLEDMessage(
        colorArgb: data.getUint32(3, Endian.little),
        colorArgbB: data.getUint32(7, Endian.little),
        keyMask: LedWire.readU64Le(data, 11),
        clientInstanceId: data.getUint16(19, Endian.little),
      );

  final int colorArgb;
  final int colorArgbB;
  final int keyMask;
  final int clientInstanceId;

  @override
  LedCommand get command => LedCommand.keyAnimPulse;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint32(3, colorArgb, Endian.little);
    data.setUint32(7, colorArgbB, Endian.little);
    LedWire.writeU64Le(data, 11, keyMask);
    data.setUint16(19, clientInstanceId & 0xffff, Endian.little);
    return data;
  }
}

/// One retained side-pulse create command.
class SidePulseLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_SIDE_ANIM_PULSE` message.
  const SidePulseLEDMessage({
    required this.colorArgb,
    required this.colorArgbB,
    required this.keyMask,
    required this.clientInstanceId,
  });

  /// Decodes one `LED_CMD_SIDE_ANIM_PULSE` wire record.
  factory SidePulseLEDMessage.fromWireByteData(ByteData data) =>
      SidePulseLEDMessage(
        colorArgb: data.getUint32(3, Endian.little),
        colorArgbB: data.getUint32(7, Endian.little),
        keyMask: LedWire.readU64Le(data, 11),
        clientInstanceId: data.getUint16(19, Endian.little),
      );

  final int colorArgb;
  final int colorArgbB;
  final int keyMask;
  final int clientInstanceId;

  @override
  LedCommand get command => LedCommand.sideAnimPulse;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint32(3, colorArgb, Endian.little);
    data.setUint32(7, colorArgbB, Endian.little);
    LedWire.writeU64Le(data, 11, keyMask);
    data.setUint16(19, clientInstanceId & 0xffff, Endian.little);
    return data;
  }
}

/// One retained rainbow-wave create command.
class RainbowWaveLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_RAINBOW_WAVE` message.
  const RainbowWaveLEDMessage({required this.clientInstanceId});

  /// Decodes one `LED_CMD_KEY_ANIM_RAINBOW_WAVE` wire record.
  factory RainbowWaveLEDMessage.fromWireByteData(ByteData data) =>
      RainbowWaveLEDMessage(
        clientInstanceId: data.getUint16(3, Endian.little),
      );

  final int clientInstanceId;

  @override
  LedCommand get command => LedCommand.keyAnimRainbowWave;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint16(3, clientInstanceId & 0xffff, Endian.little);
    return data;
  }
}

/// One retained pulse-wave create command.
class PulseWaveLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_PULSE_WAVE` message.
  const PulseWaveLEDMessage({
    required this.basePulseHz,
    required this.deltaPulseHz,
    required this.clientInstanceId,
  });

  /// Decodes one `LED_CMD_KEY_ANIM_PULSE_WAVE` wire record.
  factory PulseWaveLEDMessage.fromWireByteData(ByteData data) =>
      PulseWaveLEDMessage(
        clientInstanceId: data.getUint16(3, Endian.little),
        basePulseHz: data.getFloat32(5, Endian.little),
        deltaPulseHz: data.getFloat32(9, Endian.little),
      );

  final double basePulseHz;
  final double deltaPulseHz;
  final int clientInstanceId;

  @override
  LedCommand get command => LedCommand.keyAnimPulseWave;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint16(3, clientInstanceId & 0xffff, Endian.little);
    data.setFloat32(5, basePulseHz, Endian.little);
    data.setFloat32(9, deltaPulseHz, Endian.little);
    return data;
  }
}

/// One generic retained key-animation parameter update command.
class AnimationParamUpdateLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_PARAM_UPDATE` message.
  const AnimationParamUpdateLEDMessage({
    required this.clientInstanceId,
    required this.paramIndex,
    required this.value,
  });

  /// Decodes one `LED_CMD_KEY_ANIM_PARAM_UPDATE` wire record.
  factory AnimationParamUpdateLEDMessage.fromWireByteData(ByteData data) =>
      AnimationParamUpdateLEDMessage(
        clientInstanceId: data.getUint16(3, Endian.little),
        paramIndex: data.getUint8(5),
        value: data.getFloat32(6, Endian.little),
      );

  final int clientInstanceId;
  final int paramIndex;
  final double value;

  @override
  LedCommand get command => LedCommand.keyAnimParamUpdate;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint16(3, clientInstanceId & 0xffff, Endian.little);
    data.setUint8(5, paramIndex & 0xff);
    data.setFloat32(6, value, Endian.little);
    return data;
  }
}

/// One generic retained key-animation color update command.
class AnimationColorUpdateLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_KEY_ANIM_COLOR_UPDATE` message.
  const AnimationColorUpdateLEDMessage({
    required this.clientInstanceId,
    required this.colorArgb,
    this.colorArgbB = 0,
  });

  /// Decodes one `LED_CMD_KEY_ANIM_COLOR_UPDATE` wire record.
  factory AnimationColorUpdateLEDMessage.fromWireByteData(ByteData data) =>
      AnimationColorUpdateLEDMessage(
        clientInstanceId: data.getUint16(3, Endian.little),
        colorArgb: data.getUint32(5, Endian.little),
        colorArgbB: data.getUint32(9, Endian.little),
      );

  final int clientInstanceId;
  final int colorArgb;
  final int colorArgbB;

  @override
  LedCommand get command => LedCommand.keyAnimColorUpdate;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint16(3, clientInstanceId & 0xffff, Endian.little);
    data.setUint32(5, colorArgb, Endian.little);
    data.setUint32(9, colorArgbB, Endian.little);
    return data;
  }
}

/// One generic retained side-animation parameter update command.
class SideAnimationParamUpdateLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_SIDE_ANIM_PARAM_UPDATE` message.
  const SideAnimationParamUpdateLEDMessage({
    required this.clientInstanceId,
    required this.paramIndex,
    required this.value,
  });

  /// Decodes one `LED_CMD_SIDE_ANIM_PARAM_UPDATE` wire record.
  factory SideAnimationParamUpdateLEDMessage.fromWireByteData(ByteData data) =>
      SideAnimationParamUpdateLEDMessage(
        clientInstanceId: data.getUint16(3, Endian.little),
        paramIndex: data.getUint8(5),
        value: data.getFloat32(6, Endian.little),
      );

  final int clientInstanceId;
  final int paramIndex;
  final double value;

  @override
  LedCommand get command => LedCommand.sideAnimParamUpdate;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint16(3, clientInstanceId & 0xffff, Endian.little);
    data.setUint8(5, paramIndex & 0xff);
    data.setFloat32(6, value, Endian.little);
    return data;
  }
}

/// One generic retained side-animation color update command.
class SideAnimationColorUpdateLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_SIDE_ANIM_COLOR_UPDATE` message.
  const SideAnimationColorUpdateLEDMessage({
    required this.clientInstanceId,
    required this.colorArgb,
    this.colorArgbB = 0,
  });

  /// Decodes one `LED_CMD_SIDE_ANIM_COLOR_UPDATE` wire record.
  factory SideAnimationColorUpdateLEDMessage.fromWireByteData(ByteData data) =>
      SideAnimationColorUpdateLEDMessage(
        clientInstanceId: data.getUint16(3, Endian.little),
        colorArgb: data.getUint32(5, Endian.little),
        colorArgbB: data.getUint32(9, Endian.little),
      );

  final int clientInstanceId;
  final int colorArgb;
  final int colorArgbB;

  @override
  LedCommand get command => LedCommand.sideAnimColorUpdate;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    data.setUint16(3, clientInstanceId & 0xffff, Endian.little);
    data.setUint32(5, colorArgb, Endian.little);
    data.setUint32(9, colorArgbB, Endian.little);
    return data;
  }
}

/// One ids-only lifecycle sync chunk used for retained-animation drift repair.
class LifecycleSyncLEDMessage extends KnownLEDMessage {
  /// Creates one `LED_CMD_LIFECYCLE_SYNC` chunk.
  LifecycleSyncLEDMessage({
    required this.syncSequence,
    required this.chunkIndex,
    required this.chunkCount,
    required this.isStart,
    required this.isEnd,
    required List<int> activeAnimationIds,
  }) : activeAnimationIds = List<int>.unmodifiable(activeAnimationIds);

  /// Decodes one `LED_CMD_LIFECYCLE_SYNC` wire record.
  factory LifecycleSyncLEDMessage.fromWireByteData(ByteData data) {
    final int idCount = data.getUint8(10);
    final List<int> ids = <int>[];
    final int boundedCount = min(idCount, LedWire.syncMaxIdsPerChunk);
    for (int index = 0; index < boundedCount; index++) {
      ids.add(data.getUint16(11 + (index * 2), Endian.little));
    }
    final int flags = data.getUint8(9);
    return LifecycleSyncLEDMessage(
      syncSequence: data.getUint32(3, Endian.little),
      chunkIndex: data.getUint8(7),
      chunkCount: data.getUint8(8),
      isStart: (flags & LedWire.syncFlagStart) != 0,
      isEnd: (flags & LedWire.syncFlagEnd) != 0,
      activeAnimationIds: ids,
    );
  }

  final int syncSequence;
  final int chunkIndex;
  final int chunkCount;
  final bool isStart;
  final bool isEnd;
  final List<int> activeAnimationIds;

  @override
  LedCommand get command => LedCommand.lifecycleSync;

  @override
  ByteData toWireByteData() {
    final ByteData data = buildBaseWireData();
    final int boundedCount = min(activeAnimationIds.length, LedWire.syncMaxIdsPerChunk);
    data.setUint32(3, syncSequence, Endian.little);
    data.setUint8(7, chunkIndex & 0xff);
    data.setUint8(8, chunkCount & 0xff);
    data.setUint8(
      9,
      (isStart ? LedWire.syncFlagStart : 0) |
          (isEnd ? LedWire.syncFlagEnd : 0),
    );
    data.setUint8(10, boundedCount);
    for (int index = 0; index < boundedCount; index++) {
      data.setUint16(
        11 + (index * 2),
        activeAnimationIds[index] & 0xffff,
        Endian.little,
      );
    }
    return data;
  }
}
