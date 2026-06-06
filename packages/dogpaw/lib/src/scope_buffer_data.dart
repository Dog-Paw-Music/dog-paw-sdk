/// Immutable snapshot of waveform stereo audio from a `SCOPE_BUFFER` endpoint.
///
/// Layout (binary): `sample_count` (uint64, 8 bytes) + `sample_rate_hz`
/// (uint32, 4 bytes) + `frames_per_payload` (uint32, 4 bytes) +
/// `left_buffer[max]` (float) + `right_buffer[max]` (float).
/// Used by the oscilloscope visualizer and any consumer of `SCOPE_BUFFER`
/// endpoints.
class ScopeBufferData {
  /// Monotonically increasing count of valid emitted samples for this stream.
  final int sampleCount;

  /// Sample rate represented inside this payload.
  final int sampleRateHz;

  /// Number of valid frames in `leftSamples` and `rightSamples`.
  final int framesPerPayload;

  /// Left channel samples, chronological order (oldest at index 0).
  final List<double> leftSamples;

  /// Right channel samples, same convention.
  final List<double> rightSamples;

  const ScopeBufferData({
    required this.sampleCount,
    required this.sampleRateHz,
    required this.framesPerPayload,
    required this.leftSamples,
    required this.rightSamples,
  });

  static const int maxSamplesPerChannel = 2048;
}
