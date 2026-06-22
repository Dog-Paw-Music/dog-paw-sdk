// ignore_for_file: constant_identifier_names

/// Base data types supported by the endpoint system
enum DataType {
  /// Single floating-point value
  float,

  /// 2D vector of floats
  float2,

  /// 3D vector of floats
  float3,

  /// 4D vector of floats
  float4,

  /// Single integer value
  int_,

  /// 2D vector of ints
  int2,

  /// Boolean toggle state
  toggle,

  /// Momentary button press
  momentary,

  /// Enumerated value selection
  enum_,

  /// Packed 32-bit color value
  color,

  /// Real-time audio data
  audioStream,

  /// Key press event data
  keyPress,

  /// Proximity/near-press detection
  nearPress,

  /// Raw sensor data
  rawSensors,

  /// Musical note control data
  noteControl,

  /// MIDI message data
  midiMessage,

  /// LED control message
  ledMessage,

  /// Key position data
  keyPosition,

  /// Voice events like on, off, stolen, restored
  voiceMessage,

  /// One current scalar value for one logical voice output lane
  voiceOutputValue,

  /// One current scalar value for one global output lane
  globalOutputValue,

  /// DPP editor message: tagged param/note payload for low-rate editor control
  dppEditorMessage,

  /// User-defined custom type, for use with file backed endpoints (cannot be used wtih queue or continuous endpoints)
  custom,

  /// Downsampled stereo audio snapshot: sample_count (uint64) + left[256] + right[256] floats
  scopeBuffer,
}

/// Index types for organizing data by different dimensions
enum IndexType {
  /// Single value (no indexing)
  none,

  /// Indexed by key position on grid
  key,

  /// Indexed by synthesis voice number
  voice,

  // /// User-defined indexing scheme (not supported yet)
  // custom,
}

/// Base class for index specifications with dimension information
sealed class IndexSpec {
  const IndexSpec();

  /// Get the IndexType enum value for this spec
  IndexType get type;

  /// Get the total count of indexed elements
  int get count;

  /// Convert to JSON representation
  Map<String, dynamic> toJson();

  /// Create from JSON representation
  factory IndexSpec.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'key':
        return IndexSpecKey.fromJson(json);
      case 'voice':
        return IndexSpecVoice.fromJson(json);
      default:
        return const IndexSpecNone();
    }
  }
}

/// No indexing - single value
class IndexSpecNone extends IndexSpec {
  const IndexSpecNone();

  @override
  IndexType get type => IndexType.none;

  @override
  int get count => 1;

  @override
  Map<String, dynamic> toJson() => {'type': 'none'};

  @override
  bool operator ==(Object other) => other is IndexSpecNone;

  @override
  int get hashCode => 0;
}

/// Key indexing with grid dimensions
class IndexSpecKey extends IndexSpec {
  /// Number of columns in key grid
  final int width;

  /// Number of rows in key grid
  final int height;

  const IndexSpecKey(this.width, this.height);

  @override
  IndexType get type => IndexType.key;

  @override
  int get count => width * height;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'key',
        'width': width,
        'height': height,
      };

  factory IndexSpecKey.fromJson(Map<String, dynamic> json) {
    return IndexSpecKey(
      json['width'] as int? ?? 8,
      json['height'] as int? ?? 8,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IndexSpecKey && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Voice indexing with voice count
class IndexSpecVoice extends IndexSpec {
  /// Number of synthesis voices
  final int numVoices;

  const IndexSpecVoice(this.numVoices);

  @override
  IndexType get type => IndexType.voice;

  @override
  int get count => numVoices;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'voice',
        'num_voices': numVoices,
      };

  factory IndexSpecVoice.fromJson(Map<String, dynamic> json) {
    return IndexSpecVoice(json['num_voices'] as int? ?? 16);
  }

  @override
  bool operator ==(Object other) =>
      other is IndexSpecVoice && other.numVoices == numVoices;

  @override
  int get hashCode => numVoices.hashCode;
}

/// Endpoint direction for data flow
enum EndpointDirection {
  /// Receives data from other endpoints
  input,

  /// Sends data to other endpoints
  output,

  /// Can both send and receive data (for instance, an encoder)
  bidirectional,
}

/// Priority levels affecting processing and latency
enum Priority {
  /// <1ms - Critical audio/control data
  realtime,

  /// <10ms - Responsive UI interactions
  high,

  /// <100ms - General parameter changes
  normal,

  /// <1s - State persistence, discovery
  background,
}

/// Endpoint category for determining how data flows
enum EndpointCategory {
  /// Discrete messages via DogPawProducer/Consumer (default)
  messageQueue,

  /// Continuous data streams
  continuous,

  /// Real-time audio streams
  audioStream,

  /// Real-time JACK MIDI streams
  jackMidiStream,

  /// Large data payloads via atomic file swaps
  fileBacked,
}

/// Connection mapping types for value transformation
enum MappingType {
  /// Direct linear mapping
  linear,

  /// Logarithmic curve mapping
  logarithmic,

  /// Discrete lookup table
  lookupTable,

  /// Smooth bezier curve
  bezierCurve,

  /// Mathematical expression
  expression,

  /// User-defined mapping function
  custom,
}

/// Reference types for dynamic data resolution
enum ReferenceType {
  /// Reference by specific name
  name,

  /// System-wide current selection
  current,

  /// Inline data provided directly
  inline,
}

/// Key state enumeration matching DPQueue.hpp KeyMsg states
enum KeyState {
  /// Key is at rest (not pressed)
  rest,

  /// Key is activated (detected but not fully pressed)
  activated,

  /// Key is fully pressed
  pressed,
}
