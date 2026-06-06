import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'native_bridge.dart';
import '../data_types.dart';
import '../app_logger.dart';

/// Wraps native endpoint handles and buffer management
class NativeMemoryHandle {
  final DogPawBridge _bridge = DogPawBridge();
  
  Pointer<Void>? _handle;
  Pointer<Void>? _buffer;
  int _bufferSize = 0;
  
  bool get isValid => _handle != null;
  
  // Type metadata
  late final int _dataTypeIdx;
  late final int _indexTypeIdx;
  late final int _indexDim1;
  late final int _indexDim2;
  late final bool _isOutput;
  late final bool _isContinuous;
  
  NativeMemoryHandle({
    required DataType dataType,
    required IndexSpec indexSpec,
    required bool isOutput,
    required bool isContinuous,
  }) {
    _dataTypeIdx = _mapDataType(dataType);
    _indexTypeIdx = _mapIndexType(indexSpec.type);
    
    // Extract dimensions from IndexSpec
    if (indexSpec is IndexSpecKey) {
      _indexDim1 = indexSpec.width;
      _indexDim2 = indexSpec.height;
    } else if (indexSpec is IndexSpecVoice) {
      _indexDim1 = indexSpec.numVoices;
      _indexDim2 = 0; // Unused for voice
    } else {
      _indexDim1 = 0;
      _indexDim2 = 0;
    }
    
    _isOutput = isOutput;
    _isContinuous = isContinuous;
    
    // Calculate size with actual dimensions
    _bufferSize = _bridge.getDataSize(_dataTypeIdx, _indexTypeIdx, _indexDim1, _indexDim2);
    if (_bufferSize > 0) {
      _buffer = calloc<Uint8>(_bufferSize).cast<Void>();
    }
  }
  
  /// Initialize the native handle with fully-resolved paths from the server
  ///
  /// All resource paths/names are computed by Epiphany and sent to clients.
  /// Clients pass them through without modification.
  ///
  /// @param queueShmName Full shm_open path for DPQueue (e.g., "/ep_default_dp_seed_queue")
  /// @param socketPath Full filesystem path for DPQueue socket
  /// @param sharedDataName Logical SharedData name (SharedData adds its own prefix)
  /// @param shmNamespacePrefix Namespace prefix for SharedData (e.g., "ep_default_")
  void initialize({
    String? queueShmName,
    String? socketPath,
    String? sharedDataName,
    String? shmNamespacePrefix,
  }) {
    if (_handle != null) return; // Already initialized
    
    if (_isContinuous) {
      if (sharedDataName == null) return;
      final namePtr = sharedDataName.toNativeUtf8();
      final prefixPtr = (shmNamespacePrefix ?? '').toNativeUtf8();
      try {
        if (_isOutput) {
          _handle = _bridge.sharedWriterCreate(namePtr, _bufferSize, prefixPtr);
        } else {
          _handle = _bridge.sharedReaderCreate(namePtr, prefixPtr);
        }
      } finally {
        calloc.free(namePtr);
        calloc.free(prefixPtr);
      }
    } else {
      // Message Queue -- paths are fully resolved by the server
      if (queueShmName == null || socketPath == null) return;
      final qPtr = queueShmName.toNativeUtf8();
      final sPtr = socketPath.toNativeUtf8();
      try {
        if (_isOutput) {
          _handle = _bridge.producerCreate(qPtr, sPtr, _dataTypeIdx, _indexTypeIdx);
        } else {
          _handle = _bridge.consumerCreate(qPtr, sPtr, _dataTypeIdx, _indexTypeIdx);
        }
      } finally {
        calloc.free(qPtr);
        calloc.free(sPtr);
      }
    }
    
    if (!isValid) {
      AppLogger.error('NativeMemoryHandle initialized failed. Valid? $isValid');
    }
  }
  
  void dispose() {
    if (_handle != null) {
      if (_isContinuous) {
        _bridge.sharedDestroy(_handle!);
      } else {
        _bridge.endpointDestroy(_handle!);
      }
      _handle = null;
    }
    if (_buffer != null) {
      calloc.free(_buffer!);
      _buffer = null;
    }
  }
  
  /// Adjust buffer size for shared writer (only for output continuous endpoints)
  /// delta can be positive or negative
  /// Returns true on success, false on failure or if not a writer
  bool adjustBufferSize(int delta) {
    if (!_isOutput || !_isContinuous || _handle == null) {
      AppLogger.debug('adjustBufferSize: Precondition failed - isOutput: $_isOutput, isContinuous: $_isContinuous, handle null: ${_handle == null}');
      return false;
    }
    
    AppLogger.debug('adjustBufferSize: Before - handle: $_handle, _buffer: $_buffer, _bufferSize: $_bufferSize, delta: $delta');
    
    try {
      final success = _bridge.sharedWriterAdjustBufferSize(_handle!, delta);
      if (success) {
        final newBufferSize = _bufferSize + delta;
        AppLogger.debug('adjustBufferSize: C++ call succeeded, reallocating Dart buffer from $_bufferSize to $newBufferSize');
        
        // Reallocate the Dart-side staging buffer to match the new size
        // The C++ side has already resized the shared memory in-place
        if (_buffer != null) {
          calloc.free(_buffer!);
          AppLogger.debug('adjustBufferSize: Freed old buffer');
        }
        _buffer = calloc<Uint8>(newBufferSize).cast<Void>();
        _bufferSize = newBufferSize;
        
        AppLogger.info('Adjusted buffer size by $delta, new size: $_bufferSize, new buffer: $_buffer');
      } else {
        AppLogger.error('adjustBufferSize: C++ call returned false');
      }
      return success;
    } catch (e) {
      AppLogger.error('Failed to adjust buffer size: $e');
      return false;
    }
  }
  
  // Write methods
  bool writeBytes(Uint8List data) {
    if (_handle == null || !_isOutput || _buffer == null) return false;
    
    // Copy data to native buffer
    final len = data.length > _bufferSize ? _bufferSize : data.length;
    final bufferBytes = _buffer!.cast<Uint8>().asTypedList(_bufferSize);
    
    // Debug: Check if we have size mismatch
    if (data.length != _bufferSize) {
      AppLogger.warning('WARNING: Data size mismatch! data.length=${data.length}, _bufferSize=$_bufferSize, will copy $len bytes');
    }
    
    bufferBytes.setRange(0, len, data);

    if (_isContinuous) {
      return _bridge.sharedWrite(_handle!, _buffer!, len);
    } else {
      int result = _bridge.producerEnqueue(_handle!, _buffer!);
      if (result < 0) {
        String errorMsg;
        switch (result) {
          case -1:
            errorMsg = "Not connected to shared memory";
            break;
          case -3:
            errorMsg = "Invalid handle";
            break;
          default:
            errorMsg = "Unknown error ($result)";
        }
        AppLogger.warning('NativeMemoryHandle.write: producerEnqueue failed: $errorMsg');
        return false;
      }
      if (result == 0) {
        AppLogger.warning('NativeMemoryHandle.write: producerEnqueue returned 0, no consumers notified');
      }
      // AppLogger.debug('NativeMemoryHandle.write: Successfully enqueued to $result consumer(s)');
      return true;
    }
  }
  
    // Read methods (Poll)
  Uint8List? poll() {
    if (_handle == null) {
      AppLogger.debug('DEBUG: NativeMemoryHandle.poll() - _handle is null');
      return null;
    }
    if (_isOutput) {
      AppLogger.debug('DEBUG: NativeMemoryHandle.poll() - _isOutput is true');
      return null;
    }
    if (_buffer == null) {
      AppLogger.debug('DEBUG: NativeMemoryHandle.poll() - _buffer is null');
      return null;
    }
    
    int bytesRead = 0;
    if (_isContinuous) {
      // For shared data, we just read the current state
      // The bridge returns true if success
      // AppLogger.debug('DEBUG: NativeMemoryHandle.poll() - calling sharedRead');
      if (_bridge.sharedRead(_handle!, _buffer!, _bufferSize)) {
        bytesRead = _bufferSize;
      }
    } else {
      // For message queue, returns bytes read
      // AppLogger.debug('DEBUG: NativeMemoryHandle.poll() - calling consumerPoll with bufferSize=$_bufferSize');
      bytesRead = _bridge.consumerPoll(_handle!, _buffer!, _bufferSize);
      // AppLogger.
      //debug('DEBUG: NativeMemoryHandle.poll() - consumerPoll returned bytesRead=$bytesRead');
    }
    
    if (bytesRead > 0) {
      // Return a copy of the data
      final bufferBytes = _buffer!.cast<Uint8>().asTypedList(bytesRead);
      return Uint8List.fromList(bufferBytes);
    }
    return null;
  }
  
  // Helper to get buffer for direct modification (unsafe but fast)
  Pointer<Void>? get rawBuffer => _buffer;
  int get bufferSize => _bufferSize;
  
  // Expose IndexSpec information for deserialization
  IndexSpec getIndexSpec() {
    if (_indexTypeIdx == DPPBIndexType.key) {
      return IndexSpecKey(_indexDim1, _indexDim2);
    } else if (_indexTypeIdx == DPPBIndexType.voice) {
      return IndexSpecVoice(_indexDim1);
    } else {
      return const IndexSpecNone();
    }
  }
  
  bool get isContinuous => _isContinuous;
  
  // Mappers
  int _mapDataType(DataType type) {
    switch (type) {
      case DataType.float: return DPPBDataType.float;
      case DataType.float2: return DPPBDataType.float2;
      case DataType.float3: return DPPBDataType.float3;
      case DataType.float4: return DPPBDataType.float4;
      case DataType.int_: return DPPBDataType.int_;
      case DataType.int2: return DPPBDataType.int2;
      case DataType.toggle: return DPPBDataType.toggle;
      case DataType.momentary: return DPPBDataType.momentary;
      case DataType.enum_: return DPPBDataType.enumVal;
      case DataType.audioStream: return DPPBDataType.audioStream;
      case DataType.keyPress: return DPPBDataType.keyPress;
      case DataType.nearPress: return DPPBDataType.nearPress;
      case DataType.rawSensors: return DPPBDataType.rawSensors;
      case DataType.noteControl: return DPPBDataType.noteControl;
      case DataType.midiMessage: return DPPBDataType.midiMessage;
      case DataType.ledMessage: return DPPBDataType.ledMessage;
      case DataType.keyPosition: return DPPBDataType.keyPosition;
      case DataType.voiceMessage: return DPPBDataType.voiceMessage;
      case DataType.voiceOutputValue: return DPPBDataType.voiceOutputValue;
      case DataType.globalOutputValue: return DPPBDataType.globalOutputValue;
      case DataType.dppParamQueue: return DPPBDataType.dppParamQueue;
      case DataType.custom: return DPPBDataType.custom;
      case DataType.scopeBuffer: return DPPBDataType.scopeBuffer;
    }
  }
  
  int _mapIndexType(IndexType type) {
    switch (type) {
      case IndexType.none: return DPPBIndexType.none;
      case IndexType.key: return DPPBIndexType.key;
      case IndexType.voice: return DPPBIndexType.voice;
      // case IndexType.custom: return DPPBIndexType.custom;
    }
  }
}

