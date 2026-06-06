// ignore_for_file: camel_case_types

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import '../app_logger.dart';
import 'dart:io';

// Type definitions matching C++ DataType enum (order must match dogpaw_bridge.h / EndpointData.hpp)
class DPPBDataType {
  static const int float = 0;
  static const int float2 = 1;
  static const int float3 = 2;
  static const int float4 = 3;
  static const int int_ = 4;
  static const int int2 = 5;
  static const int toggle = 6;
  static const int momentary = 7;
  static const int enumVal = 8;
  static const int audioStream = 9;
  static const int keyPress = 10;
  static const int nearPress = 11;
  static const int rawSensors = 12;
  static const int noteControl = 13;
  static const int midiMessage = 14;
  static const int ledMessage = 15;
  static const int keyPosition = 16;
  static const int voiceMessage = 17;
  static const int voiceOutputValue = 18;
  static const int globalOutputValue = 19;
  static const int dppParamQueue = 20;
  static const int custom = 21;
  static const int scopeBuffer = 22;
}

class DPPBIndexType {
  static const int none = 0;
  static const int key = 1;
  static const int voice = 2;
  // static const int custom = 3;
}

// C function signatures
typedef DppbSharedWriterCreateC = Pointer<Void> Function(
    Pointer<Utf8> name, Int32 size, Pointer<Utf8> namespacePrefix);
typedef DppbSharedWriterCreateDart = Pointer<Void> Function(
    Pointer<Utf8> name, int size, Pointer<Utf8> namespacePrefix);

typedef DppbSharedReaderCreateC = Pointer<Void> Function(
    Pointer<Utf8> name, Pointer<Utf8> namespacePrefix);
typedef DppbSharedReaderCreateDart = Pointer<Void> Function(
    Pointer<Utf8> name, Pointer<Utf8> namespacePrefix);

typedef DppbSharedWriteC = Bool Function(
    Pointer<Void> handle, Pointer<Void> data, Int32 size);
typedef DppbSharedWriteDart = bool Function(
    Pointer<Void> handle, Pointer<Void> data, int size);

typedef DppbSharedReadC = Bool Function(
    Pointer<Void> handle, Pointer<Void> outData, Int32 size);
typedef DppbSharedReadDart = bool Function(
    Pointer<Void> handle, Pointer<Void> outData, int size);

typedef DppbSharedDestroyC = Void Function(Pointer<Void> handle);
typedef DppbSharedDestroyDart = void Function(Pointer<Void> handle);

typedef DppbSharedWriterAdjustBufferSizeC = Bool Function(
    Pointer<Void> handle, Int32 deltaBufferSize);
typedef DppbSharedWriterAdjustBufferSizeDart = bool Function(
    Pointer<Void> handle, int deltaBufferSize);

typedef DppbProducerCreateC = Pointer<Void> Function(Pointer<Utf8> queueName,
    Pointer<Utf8> socketName, Int32 dataTypeIdx, Int32 indexTypeIdx);
typedef DppbProducerCreateDart = Pointer<Void> Function(Pointer<Utf8> queueName,
    Pointer<Utf8> socketName, int dataTypeIdx, int indexTypeIdx);

typedef DppbProducerEnqueueC = Int32 Function(
    Pointer<Void> handle, Pointer<Void> data);
typedef DppbProducerEnqueueDart = int Function(
    Pointer<Void> handle, Pointer<Void> data);

typedef DppbConsumerCreateC = Pointer<Void> Function(Pointer<Utf8> queueName,
    Pointer<Utf8> socketName, Int32 dataTypeIdx, Int32 indexTypeIdx);
typedef DppbConsumerCreateDart = Pointer<Void> Function(Pointer<Utf8> queueName,
    Pointer<Utf8> socketName, int dataTypeIdx, int indexTypeIdx);

typedef DppbConsumerPollC = Int32 Function(
    Pointer<Void> handle, Pointer<Void> outBuffer, Int32 maxSize);
typedef DppbConsumerPollDart = int Function(
    Pointer<Void> handle, Pointer<Void> outBuffer, int maxSize);

typedef DppbEndpointDestroyC = Void Function(Pointer<Void> handle);
typedef DppbEndpointDestroyDart = void Function(Pointer<Void> handle);

typedef DppbGetDataSizeC = Int32 Function(
    Int32 dataTypeIdx, Int32 indexTypeIdx, Int32 indexDim1, Int32 indexDim2);
typedef DppbGetDataSizeDart = int Function(
    int dataTypeIdx, int indexTypeIdx, int indexDim1, int indexDim2);

//=============================================================================
// SERVER DETECTION
// Used by: DogPawEntity, Test Infrastructure
//=============================================================================

typedef DppbCheckServerRunningC = Int32 Function(Pointer<Utf8> portFilePath);
typedef DppbCheckServerRunningDart = int Function(Pointer<Utf8> portFilePath);

typedef DppbWaitForServerC = Int32 Function(
    Pointer<Utf8> portFilePath, Int32 timeoutMs);
typedef DppbWaitForServerDart = int Function(
    Pointer<Utf8> portFilePath, int timeoutMs);

//=============================================================================
// PROCESS MANAGEMENT
// Used by: Test Infrastructure
//=============================================================================

typedef DppbSpawnWithDeathSignalC = Int32 Function(Pointer<Utf8> program,
    Pointer<Pointer<Utf8>> argv, Int32 deathSignal, Pointer<Utf8> logPath);
typedef DppbSpawnWithDeathSignalDart = int Function(Pointer<Utf8> program,
    Pointer<Pointer<Utf8>> argv, int deathSignal, Pointer<Utf8> logPath);

typedef DppbKillProcessC = Int32 Function(Int32 pid, Int32 signalNum);
typedef DppbKillProcessDart = int Function(int pid, int signalNum);

typedef DppbWaitProcessC = Int32 Function(Int32 pid, Int32 timeoutMs);
typedef DppbWaitProcessDart = int Function(int pid, int timeoutMs);

typedef DppbIsProcessRunningC = Int32 Function(Int32 pid);
typedef DppbIsProcessRunningDart = int Function(int pid);

//=============================================================================
// NATIVE DOGPAWENTITY BRIDGE
// Used by: Phase 2 migration (Dart facade over C++ DogPawEntity)
//=============================================================================

typedef DppbInitializeDartApiC = Int64 Function(
    Pointer<Void> initializeApiData);
typedef DppbInitializeDartApiDart = int Function(
    Pointer<Void> initializeApiData);

typedef DppbDpeCreateC = Pointer<Void> Function(
  Pointer<Utf8> entityName,
  Pointer<Utf8> serverUrl,
  Int32 timeoutMs,
);
typedef DppbDpeCreateDart = Pointer<Void> Function(
  Pointer<Utf8> entityName,
  Pointer<Utf8> serverUrl,
  int timeoutMs,
);

typedef DppbDpeDestroyC = Void Function(Pointer<Void> handle);
typedef DppbDpeDestroyDart = void Function(Pointer<Void> handle);

typedef DppbDpeSetEventPortC = Bool Function(Pointer<Void> handle, Int64 port);
typedef DppbDpeSetEventPortDart = bool Function(Pointer<Void> handle, int port);

typedef DppbDpeConnectAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeConnectAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeCompleteConnectionStartC = Bool Function(
  Pointer<Void> handle,
  Int32 readyMessageType,
);
typedef DppbDpeCompleteConnectionStartDart = bool Function(
  Pointer<Void> handle,
  int readyMessageType,
);

typedef DppbDpeDisconnectC = Void Function(Pointer<Void> handle);
typedef DppbDpeDisconnectDart = void Function(Pointer<Void> handle);

typedef DppbDpeIsConnectedC = Bool Function(Pointer<Void> handle);
typedef DppbDpeIsConnectedDart = bool Function(Pointer<Void> handle);

typedef DppbDpeSubscribeEntityLifecycleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> entityName,
  Bool sendImmediately,
);
typedef DppbDpeSubscribeEntityLifecycleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> entityName,
  bool sendImmediately,
);

typedef DppbDpeUnsubscribeEntityLifecycleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> entityName,
);
typedef DppbDpeUnsubscribeEntityLifecycleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> entityName,
);

typedef DppbDpeSetThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> themeJson,
);
typedef DppbDpeSetThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> themeJson,
);

typedef DppbDpeCreateThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> themeJson,
  Bool autoSuffix,
);
typedef DppbDpeCreateThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> themeJson,
  bool autoSuffix,
);

typedef DppbDpeUpdateThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> themeJson,
);
typedef DppbDpeUpdateThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> themeJson,
);

typedef DppbDpeReadThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeDeleteThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeDeleteThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeSetCurrentThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeSetCurrentThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeReadCurrentThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadCurrentThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeRemoveCurrentThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeRemoveCurrentThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeListThemesAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeListThemesAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);
typedef DppbDpeSubscribeThemesAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
  Bool sendImmediately,
);
typedef DppbDpeSubscribeThemesAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
  bool sendImmediately,
);
typedef DppbDpeUnsubscribeThemesAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeUnsubscribeThemesAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeSubscribeCurrentThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Bool includeResolved,
  Bool includeSpec,
  Bool sendImmediately,
);
typedef DppbDpeSubscribeCurrentThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  bool includeResolved,
  bool includeSpec,
  bool sendImmediately,
);
typedef DppbDpeUnsubscribeCurrentThemeAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeUnsubscribeCurrentThemeAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeSetScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> scaleJson,
);
typedef DppbDpeSetScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> scaleJson,
);

typedef DppbDpeCreateScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> scaleJson,
  Bool autoSuffix,
);
typedef DppbDpeCreateScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> scaleJson,
  bool autoSuffix,
);

typedef DppbDpeUpdateScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> scaleJson,
);
typedef DppbDpeUpdateScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> scaleJson,
);

typedef DppbDpeReadScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeDeleteScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeDeleteScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeSetCurrentScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeSetCurrentScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeReadCurrentScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadCurrentScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeRemoveCurrentScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeRemoveCurrentScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeListScalesAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeListScalesAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeSetLayoutAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> layoutJson,
);
typedef DppbDpeSetLayoutAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> layoutJson,
);

typedef DppbDpeCreateLayoutAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> layoutJson,
  Bool autoSuffix,
);
typedef DppbDpeCreateLayoutAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> layoutJson,
  bool autoSuffix,
);

typedef DppbDpeUpdateLayoutAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> layoutJson,
);
typedef DppbDpeUpdateLayoutAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> layoutJson,
);

typedef DppbDpeReadLayoutAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadLayoutAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeDeleteLayoutAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeDeleteLayoutAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeListLayoutsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeListLayoutsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeSetKVAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> kvJson,
);
typedef DppbDpeSetKVAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> kvJson,
);

typedef DppbDpeCreateKVAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> kvJson,
);
typedef DppbDpeCreateKVAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> kvJson,
);

typedef DppbDpeUpdateKVAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> kvJson,
);
typedef DppbDpeUpdateKVAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> kvJson,
);

typedef DppbDpeReadKVAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadKVAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeDeleteKVAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeDeleteKVAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeListKVsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeListKVsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeCreateEndpointAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> endpointJson,
  Bool autoSuffix,
);
typedef DppbDpeCreateEndpointAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> endpointJson,
  bool autoSuffix,
);

typedef DppbDpeUpdateEndpointAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> endpointJson,
);
typedef DppbDpeUpdateEndpointAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> endpointJson,
);

typedef DppbDpeSetEndpointAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> endpointJson,
);
typedef DppbDpeSetEndpointAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> endpointJson,
);

typedef DppbDpeReadEndpointAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadEndpointAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeDeleteEndpointAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
);
typedef DppbDpeDeleteEndpointAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
);

typedef DppbDpeSearchEndpointsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> criteriaJson,
);
typedef DppbDpeSearchEndpointsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> criteriaJson,
);

typedef DppbDpeSubscribeEndpointsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
  Bool sendImmediately,
);
typedef DppbDpeSubscribeEndpointsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
  bool sendImmediately,
);

typedef DppbDpeUnsubscribeEndpointsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeUnsubscribeEndpointsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeLocalEndpointWriteC = Bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Void> data,
  Int32 size,
  Bool immediate,
);
typedef DppbDpeLocalEndpointWriteDart = bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Void> data,
  int size,
  bool immediate,
);

typedef DppbDpeLocalEndpointGetConnectionCountC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
);
typedef DppbDpeLocalEndpointGetConnectionCountDart = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
);

typedef DppbDpeLocalEndpointGetConnectionNameC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Int32 index,
  Pointer<Utf8> outName,
  Int32 maxSize,
);
typedef DppbDpeLocalEndpointGetConnectionNameDart = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  int index,
  Pointer<Utf8> outName,
  int maxSize,
);

typedef DppbDpeLocalEndpointGetConnectionShapeC = Bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Utf8> connectionName,
  Pointer<Int32> outIndexType,
  Pointer<Int32> outIndexDim1,
  Pointer<Int32> outIndexDim2,
  Pointer<Int32> outPayloadSize,
);
typedef DppbDpeLocalEndpointGetConnectionShapeDart = bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Utf8> connectionName,
  Pointer<Int32> outIndexType,
  Pointer<Int32> outIndexDim1,
  Pointer<Int32> outIndexDim2,
  Pointer<Int32> outPayloadSize,
);

typedef DppbDpeLocalEndpointPollConnectionC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Utf8> connectionName,
  Pointer<Void> outData,
  Int32 maxSize,
);
typedef DppbDpeLocalEndpointPollConnectionDart = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Utf8> connectionName,
  Pointer<Void> outData,
  int maxSize,
);

typedef DppbDpeLocalEndpointReadFileBackedC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Utf8> connectionName,
  Pointer<Void> outData,
  Int32 maxSize,
);
typedef DppbDpeLocalEndpointReadFileBackedDart = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Utf8> connectionName,
  Pointer<Void> outData,
  int maxSize,
);

typedef DppbDpeLocalEndpointPollFileBackedC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Utf8> connectionName,
  Pointer<Void> outData,
  Int32 maxSize,
);
typedef DppbDpeLocalEndpointPollFileBackedDart = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> endpointName,
  Pointer<Utf8> connectionName,
  Pointer<Void> outData,
  int maxSize,
);

typedef DppbDpeCreateConnectionRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> connectionRequestJson,
);
typedef DppbDpeCreateConnectionRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> connectionRequestJson,
);

typedef DppbDpeSetConnectionRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> connectionRequestJson,
);
typedef DppbDpeSetConnectionRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> connectionRequestJson,
);

typedef DppbDpeUpdateConnectionRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> connectionRequestJson,
);
typedef DppbDpeUpdateConnectionRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> connectionRequestJson,
);

typedef DppbDpeReadConnectionRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadConnectionRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeDeleteConnectionRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeDeleteConnectionRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeListConnectionRequestsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeListConnectionRequestsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeCreateFollowRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> followRequestJson,
);
typedef DppbDpeCreateFollowRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> followRequestJson,
);

typedef DppbDpeSetFollowRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> followRequestJson,
);
typedef DppbDpeSetFollowRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> followRequestJson,
);

typedef DppbDpeUpdateFollowRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> followRequestJson,
);
typedef DppbDpeUpdateFollowRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> followRequestJson,
);

typedef DppbDpeReadFollowRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadFollowRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeDeleteFollowRequestAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeDeleteFollowRequestAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeListFollowRequestsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeListFollowRequestsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeReadConnectionAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadConnectionAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeListConnectionsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeListConnectionsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  bool includeResolved,
  bool includeSpec,
);

typedef DppbDpeSubscribeScalesAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
  Bool sendImmediately,
);
typedef DppbDpeSubscribeScalesAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
  bool sendImmediately,
);
typedef DppbDpeUnsubscribeScalesAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeUnsubscribeScalesAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeSubscribeCurrentScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Bool includeResolved,
  Bool includeSpec,
  Bool sendImmediately,
);
typedef DppbDpeSubscribeCurrentScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  bool includeResolved,
  bool includeSpec,
  bool sendImmediately,
);
typedef DppbDpeUnsubscribeCurrentScaleAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeUnsubscribeCurrentScaleAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeSubscribeLayoutsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
  Bool sendImmediately,
);
typedef DppbDpeSubscribeLayoutsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
  bool sendImmediately,
);
typedef DppbDpeUnsubscribeLayoutsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeUnsubscribeLayoutsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> name,
  Pointer<Utf8> namespaceSelectorJson,
);

// Layout stack
typedef DppbDpeAddLayoutStackEntryAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> layoutRefJson,
  Bool hasIndex,
  Int32 index,
);
typedef DppbDpeAddLayoutStackEntryAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> layoutRefJson,
  bool hasIndex,
  int index,
);
typedef DppbDpeRemoveLayoutStackEntryAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> entryId,
);
typedef DppbDpeRemoveLayoutStackEntryAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> entryId,
);
typedef DppbDpeMoveLayoutStackEntryAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> entryId,
  Int32 newIndex,
);
typedef DppbDpeMoveLayoutStackEntryAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> entryId,
  int newIndex,
);
typedef DppbDpeReadLayoutStackAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Bool includeResolved,
  Bool includeSpec,
);
typedef DppbDpeReadLayoutStackAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  bool includeResolved,
  bool includeSpec,
);
typedef DppbDpeSubscribeLayoutStackAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Bool includeResolved,
  Bool includeSpec,
  Bool sendImmediately,
);
typedef DppbDpeSubscribeLayoutStackAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  bool includeResolved,
  bool includeSpec,
  bool sendImmediately,
);
typedef DppbDpeUnsubscribeLayoutStackAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeUnsubscribeLayoutStackAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeSubscribeKVAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> key,
  Pointer<Utf8> namespaceSelectorJson,
  Bool includeResolved,
  Bool includeSpec,
  Bool sendImmediately,
);
typedef DppbDpeSubscribeKVAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> key,
  Pointer<Utf8> namespaceSelectorJson,
  bool includeResolved,
  bool includeSpec,
  bool sendImmediately,
);
typedef DppbDpeUnsubscribeKVAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> key,
  Pointer<Utf8> namespaceSelectorJson,
);
typedef DppbDpeUnsubscribeKVAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> key,
  Pointer<Utf8> namespaceSelectorJson,
);

typedef DppbDpeSendDirectMessageAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> targetEntity,
  Pointer<Utf8> messageJson,
);
typedef DppbDpeSendDirectMessageAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> targetEntity,
  Pointer<Utf8> messageJson,
);

typedef DppbDpeSendCommandAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> targetEntity,
  Pointer<Utf8> command,
  Pointer<Utf8> paramsJson,
  Int32 timeoutMs,
  Bool waitForCompletion,
  Pointer<Utf8> deliveryPolicyJson,
);
typedef DppbDpeSendCommandAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> targetEntity,
  Pointer<Utf8> command,
  Pointer<Utf8> paramsJson,
  int timeoutMs,
  bool waitForCompletion,
  Pointer<Utf8> deliveryPolicyJson,
);

typedef DppbDpeSendCommandResponseC = Bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> targetEntity,
  Pointer<Utf8> commandId,
  Bool success,
  Pointer<Utf8> resultJson,
  Pointer<Utf8> errorMessage,
);
typedef DppbDpeSendCommandResponseDart = bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> targetEntity,
  Pointer<Utf8> commandId,
  bool success,
  Pointer<Utf8> resultJson,
  Pointer<Utf8> errorMessage,
);

typedef DppbDpeSendCommandAcceptedC = Bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> targetEntity,
  Pointer<Utf8> commandId,
);
typedef DppbDpeSendCommandAcceptedDart = bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> targetEntity,
  Pointer<Utf8> commandId,
);

typedef DppbDpeCompletePresetRequestC = Bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> serverRequestId,
  Bool success,
  Pointer<Utf8> errorMessage,
);
typedef DppbDpeCompletePresetRequestDart = bool Function(
  Pointer<Void> handle,
  Pointer<Utf8> serverRequestId,
  bool success,
  Pointer<Utf8> errorMessage,
);

typedef DppbDpeSaveGlobalStateAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> presetName,
);
typedef DppbDpeSaveGlobalStateAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> presetName,
);

typedef DppbDpeLoadGlobalStateAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> presetName,
);
typedef DppbDpeLoadGlobalStateAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> presetName,
);

typedef DppbDpeLogAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> message,
);
typedef DppbDpeLogAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> message,
);

typedef DppbDpeStartLogSectionAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> sectionTitle,
);
typedef DppbDpeStartLogSectionAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> sectionTitle,
);

typedef DppbDpeFlushLogSectionAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeFlushLogSectionAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeEndLogSectionAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Bool flush,
);
typedef DppbDpeEndLogSectionAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  bool flush,
);

typedef DppbDpeGetSystemInfoAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeGetSystemInfoAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeListAppsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeListAppsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeListRunningEntitiesAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeListRunningEntitiesAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

typedef DppbDpeLaunchAppAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> appName,
  Pointer<Utf8> launchMetadataJson,
);
typedef DppbDpeLaunchAppAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> appName,
  Pointer<Utf8> launchMetadataJson,
);

typedef DppbDpeStopAppAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
  Pointer<Utf8> appName,
);
typedef DppbDpeStopAppAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
  Pointer<Utf8> appName,
);

typedef DppbDpeKillAllAppsAsyncC = Bool Function(
  Pointer<Void> handle,
  Int64 requestId,
);
typedef DppbDpeKillAllAppsAsyncDart = bool Function(
  Pointer<Void> handle,
  int requestId,
);

//=============================================================================
// SIGNAL CONSTANTS
// Linux signal numbers for use with process management functions
//=============================================================================

class DPPBSignal {
  static const int sigterm = 15;
  static const int sigkill = 9;
  static const int sigint = 2;
}

/// Resolve the bundle-local bridge library path for one built Linux app.
///
/// Purpose:
/// Encodes the installed-app contract that each Flutter bundle carries its own
/// `libdogpaw_bridge.so` beside the main executable in the bundle `lib/`
/// directory.
///
/// Parameters:
/// - [resolvedExecutablePath]: Absolute or relative path to the running app
///   executable.
///
/// Return value:
/// - Expected bundle-local bridge library path.
///
/// Requirements/Preconditions:
/// - [resolvedExecutablePath] should point at the Flutter app executable.
///
/// Guarantees/Postconditions:
/// - No filesystem state is modified.
///
/// Invariants:
/// - The returned path always ends in `lib/libdogpaw_bridge.so`.
String resolveBundleAdjacentBridgeLibraryPath({
  required String resolvedExecutablePath,
}) {
  final String executableDirectory = path.dirname(
    path.absolute(resolvedExecutablePath),
  );
  return path.join(
    executableDirectory,
    'lib',
    'libdogpaw_bridge.so',
  );
}

/// Read one environment variable from the live process environment.
///
/// Purpose:
/// Lets bridge loading consult values written via [DogPawBridge.setEnv], which
/// updates libc's process environment after Dart snapshots
/// [Platform.environment].
///
/// Parameters:
/// - [key]: Environment variable name to read.
///
/// Return value:
/// - Current non-empty value, or `null` when unset.
///
/// Requirements/Preconditions:
/// - [key] is a non-empty environment variable name.
///
/// Guarantees/Postconditions:
/// - No filesystem state is modified.
///
/// Invariants:
/// - Reads the live process environment rather than Dart's startup snapshot.
String? _readProcessEnvironmentValue(String key) {
  final getenvFunc = DynamicLibrary.process().lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('getenv');
  final Pointer<Utf8> keyPtr = key.toNativeUtf8();
  try {
    final Pointer<Utf8> valuePtr = getenvFunc(keyPtr);
    if (valuePtr.address == 0) {
      return null;
    }
    final String value = valuePtr.toDartString();
    return value.isEmpty ? null : value;
  } finally {
    malloc.free(keyPtr);
  }
}

/// Resolve the dogpaw bridge shared library for the current runtime.
///
/// Purpose:
/// Implements the supported public loading contract: explicit environment
/// override first, then a bundle-local packaged library for installed Flutter
/// apps.
///
/// Parameters:
/// - [environment]: Optional environment map used by tests. Defaults to
///   [Platform.environment].
/// - [resolvedExecutablePath]: Optional executable path used by tests. Defaults
///   to [Platform.resolvedExecutable].
///
/// Return value:
/// - Absolute or explicit path to the bridge library that should be opened.
///
/// Requirements/Preconditions:
/// - Either `DOGPAW_BRIDGE_LIB` is set, or the running app bundle includes
///   `lib/libdogpaw_bridge.so`.
///
/// Guarantees/Postconditions:
/// - No filesystem state is modified.
///
/// Invariants:
/// - Repository-layout and machine-specific fallback paths are never consulted.
String resolveBridgeLibraryPath({
  Map<String, String>? environment,
  String? resolvedExecutablePath,
}) {
  final String? explicitPath = environment != null
      ? environment['DOGPAW_BRIDGE_LIB']
      : _readProcessEnvironmentValue('DOGPAW_BRIDGE_LIB');
  if (explicitPath != null && explicitPath.isNotEmpty) {
    return explicitPath;
  }

  final String packagedPath = resolveBundleAdjacentBridgeLibraryPath(
    resolvedExecutablePath:
        resolvedExecutablePath ?? Platform.resolvedExecutable,
  );
  if (File(packagedPath).existsSync()) {
    return packagedPath;
  }

  throw StateError(
    'Could not resolve Dog Paw native bridge library. Set DOGPAW_BRIDGE_LIB '
    'or package libdogpaw_bridge.so in the app bundle lib directory.',
  );
}

class DogPawBridge {
  static DogPawBridge? _instance;
  static bool _dpeApiInitialized = false;
  late DynamicLibrary _lib;

  // Function pointers
  late DppbSharedWriterCreateDart sharedWriterCreate;
  late DppbSharedReaderCreateDart sharedReaderCreate;
  late DppbSharedWriteDart sharedWrite;
  late DppbSharedReadDart sharedRead;
  late DppbSharedDestroyDart sharedDestroy;
  late DppbSharedWriterAdjustBufferSizeDart sharedWriterAdjustBufferSize;

  late DppbProducerCreateDart producerCreate;
  late DppbProducerEnqueueDart producerEnqueue;
  late DppbConsumerCreateDart consumerCreate;
  late DppbConsumerPollDart consumerPoll;
  late DppbEndpointDestroyDart endpointDestroy;

  late DppbGetDataSizeDart getDataSize;

  // Server detection
  late DppbCheckServerRunningDart checkServerRunning;
  late DppbWaitForServerDart waitForServer;

  // Process management
  late DppbSpawnWithDeathSignalDart spawnWithDeathSignal;
  late DppbKillProcessDart killProcess;
  late DppbWaitProcessDart waitProcess;
  late DppbIsProcessRunningDart isProcessRunning;

  // Native DogPawEntity bridge
  late DppbInitializeDartApiDart initializeDartApi;
  late DppbDpeCreateDart dpeCreate;
  late DppbDpeDestroyDart dpeDestroy;
  late DppbDpeSetEventPortDart dpeSetEventPort;
  late DppbDpeConnectAsyncDart dpeConnectAsync;
  late DppbDpeCompleteConnectionStartDart dpeCompleteConnectionStart;
  late DppbDpeDisconnectDart dpeDisconnect;
  late DppbDpeIsConnectedDart dpeIsConnected;
  late DppbDpeSubscribeEntityLifecycleAsyncDart
      dpeSubscribeEntityLifecycleAsync;
  late DppbDpeUnsubscribeEntityLifecycleAsyncDart
      dpeUnsubscribeEntityLifecycleAsync;
  late DppbDpeSetThemeAsyncDart dpeSetThemeAsync;
  late DppbDpeCreateThemeAsyncDart dpeCreateThemeAsync;
  late DppbDpeUpdateThemeAsyncDart dpeUpdateThemeAsync;
  late DppbDpeReadThemeAsyncDart dpeReadThemeAsync;
  late DppbDpeDeleteThemeAsyncDart dpeDeleteThemeAsync;
  late DppbDpeSetCurrentThemeAsyncDart dpeSetCurrentThemeAsync;
  late DppbDpeReadCurrentThemeAsyncDart dpeReadCurrentThemeAsync;
  late DppbDpeRemoveCurrentThemeAsyncDart dpeRemoveCurrentThemeAsync;
  late DppbDpeListThemesAsyncDart dpeListThemesAsync;
  late DppbDpeSubscribeThemesAsyncDart dpeSubscribeThemesAsync;
  late DppbDpeUnsubscribeThemesAsyncDart dpeUnsubscribeThemesAsync;
  late DppbDpeSubscribeCurrentThemeAsyncDart dpeSubscribeCurrentThemeAsync;
  late DppbDpeUnsubscribeCurrentThemeAsyncDart dpeUnsubscribeCurrentThemeAsync;
  late DppbDpeSetScaleAsyncDart dpeSetScaleAsync;
  late DppbDpeCreateScaleAsyncDart dpeCreateScaleAsync;
  late DppbDpeUpdateScaleAsyncDart dpeUpdateScaleAsync;
  late DppbDpeReadScaleAsyncDart dpeReadScaleAsync;
  late DppbDpeDeleteScaleAsyncDart dpeDeleteScaleAsync;
  late DppbDpeSetCurrentScaleAsyncDart dpeSetCurrentScaleAsync;
  late DppbDpeReadCurrentScaleAsyncDart dpeReadCurrentScaleAsync;
  late DppbDpeRemoveCurrentScaleAsyncDart dpeRemoveCurrentScaleAsync;
  late DppbDpeListScalesAsyncDart dpeListScalesAsync;
  late DppbDpeSetLayoutAsyncDart dpeSetLayoutAsync;
  late DppbDpeCreateLayoutAsyncDart dpeCreateLayoutAsync;
  late DppbDpeUpdateLayoutAsyncDart dpeUpdateLayoutAsync;
  late DppbDpeReadLayoutAsyncDart dpeReadLayoutAsync;
  late DppbDpeDeleteLayoutAsyncDart dpeDeleteLayoutAsync;
  late DppbDpeListLayoutsAsyncDart dpeListLayoutsAsync;
  late DppbDpeSetKVAsyncDart dpeSetKVAsync;
  late DppbDpeCreateKVAsyncDart dpeCreateKVAsync;
  late DppbDpeUpdateKVAsyncDart dpeUpdateKVAsync;
  late DppbDpeReadKVAsyncDart dpeReadKVAsync;
  late DppbDpeDeleteKVAsyncDart dpeDeleteKVAsync;
  late DppbDpeListKVsAsyncDart dpeListKVsAsync;
  late DppbDpeCreateEndpointAsyncDart dpeCreateEndpointAsync;
  late DppbDpeUpdateEndpointAsyncDart dpeUpdateEndpointAsync;
  late DppbDpeSetEndpointAsyncDart dpeSetEndpointAsync;
  late DppbDpeReadEndpointAsyncDart dpeReadEndpointAsync;
  late DppbDpeDeleteEndpointAsyncDart dpeDeleteEndpointAsync;
  late DppbDpeSearchEndpointsAsyncDart dpeSearchEndpointsAsync;
  late DppbDpeSubscribeEndpointsAsyncDart dpeSubscribeEndpointsAsync;
  late DppbDpeUnsubscribeEndpointsAsyncDart dpeUnsubscribeEndpointsAsync;
  late DppbDpeLocalEndpointWriteDart dpeLocalEndpointWrite;
  late DppbDpeLocalEndpointGetConnectionCountDart
      dpeLocalEndpointGetConnectionCount;
  late DppbDpeLocalEndpointGetConnectionNameDart
      dpeLocalEndpointGetConnectionName;
  late DppbDpeLocalEndpointGetConnectionShapeDart
      dpeLocalEndpointGetConnectionShape;
  late DppbDpeLocalEndpointPollConnectionDart dpeLocalEndpointPollConnection;
  late DppbDpeLocalEndpointReadFileBackedDart dpeLocalEndpointReadFileBacked;
  late DppbDpeLocalEndpointPollFileBackedDart dpeLocalEndpointPollFileBacked;
  late DppbDpeCreateConnectionRequestAsyncDart dpeCreateConnectionRequestAsync;
  late DppbDpeSetConnectionRequestAsyncDart dpeSetConnectionRequestAsync;
  late DppbDpeUpdateConnectionRequestAsyncDart dpeUpdateConnectionRequestAsync;
  late DppbDpeReadConnectionRequestAsyncDart dpeReadConnectionRequestAsync;
  late DppbDpeDeleteConnectionRequestAsyncDart dpeDeleteConnectionRequestAsync;
  late DppbDpeListConnectionRequestsAsyncDart dpeListConnectionRequestsAsync;
  late DppbDpeCreateFollowRequestAsyncDart dpeCreateFollowRequestAsync;
  late DppbDpeSetFollowRequestAsyncDart dpeSetFollowRequestAsync;
  late DppbDpeUpdateFollowRequestAsyncDart dpeUpdateFollowRequestAsync;
  late DppbDpeReadFollowRequestAsyncDart dpeReadFollowRequestAsync;
  late DppbDpeDeleteFollowRequestAsyncDart dpeDeleteFollowRequestAsync;
  late DppbDpeListFollowRequestsAsyncDart dpeListFollowRequestsAsync;
  late DppbDpeReadConnectionAsyncDart dpeReadConnectionAsync;
  late DppbDpeListConnectionsAsyncDart dpeListConnectionsAsync;
  late DppbDpeSubscribeScalesAsyncDart dpeSubscribeScalesAsync;
  late DppbDpeUnsubscribeScalesAsyncDart dpeUnsubscribeScalesAsync;
  late DppbDpeSubscribeCurrentScaleAsyncDart dpeSubscribeCurrentScaleAsync;
  late DppbDpeUnsubscribeCurrentScaleAsyncDart dpeUnsubscribeCurrentScaleAsync;
  late DppbDpeSubscribeLayoutsAsyncDart dpeSubscribeLayoutsAsync;
  late DppbDpeUnsubscribeLayoutsAsyncDart dpeUnsubscribeLayoutsAsync;
  late DppbDpeAddLayoutStackEntryAsyncDart dpeAddLayoutStackEntryAsync;
  late DppbDpeRemoveLayoutStackEntryAsyncDart dpeRemoveLayoutStackEntryAsync;
  late DppbDpeMoveLayoutStackEntryAsyncDart dpeMoveLayoutStackEntryAsync;
  late DppbDpeReadLayoutStackAsyncDart dpeReadLayoutStackAsync;
  late DppbDpeSubscribeLayoutStackAsyncDart dpeSubscribeLayoutStackAsync;
  late DppbDpeUnsubscribeLayoutStackAsyncDart dpeUnsubscribeLayoutStackAsync;
  late DppbDpeSubscribeKVAsyncDart dpeSubscribeKVAsync;
  late DppbDpeUnsubscribeKVAsyncDart dpeUnsubscribeKVAsync;
  late DppbDpeSendDirectMessageAsyncDart dpeSendDirectMessageAsync;
  late DppbDpeSendCommandAsyncDart dpeSendCommandAsync;
  late DppbDpeSendCommandResponseDart dpeSendCommandResponse;
  late DppbDpeSendCommandAcceptedDart dpeSendCommandAccepted;
  late DppbDpeCompletePresetRequestDart dpeCompletePresetRequest;
  late DppbDpeSaveGlobalStateAsyncDart dpeSaveGlobalStateAsync;
  late DppbDpeLoadGlobalStateAsyncDart dpeLoadGlobalStateAsync;
  late DppbDpeLogAsyncDart dpeLogAsync;
  late DppbDpeStartLogSectionAsyncDart dpeStartLogSectionAsync;
  late DppbDpeFlushLogSectionAsyncDart dpeFlushLogSectionAsync;
  late DppbDpeEndLogSectionAsyncDart dpeEndLogSectionAsync;
  late DppbDpeGetSystemInfoAsyncDart dpeGetSystemInfoAsync;
  late DppbDpeListAppsAsyncDart dpeListAppsAsync;
  late DppbDpeListRunningEntitiesAsyncDart dpeListRunningEntitiesAsync;
  late DppbDpeLaunchAppAsyncDart dpeLaunchAppAsync;
  late DppbDpeStopAppAsyncDart dpeStopAppAsync;
  late DppbDpeKillAllAppsAsyncDart dpeKillAllAppsAsync;

  factory DogPawBridge() {
    _instance ??= DogPawBridge._internal();
    return _instance!;
  }

  DogPawBridge._internal() {
    final String libPath = resolveBridgeLibraryPath();
    if (Platform.environment['DPE_FFI_TRACE'] == '1') {
      AppLogger.info(
        'DPE_FFI: DogPawBridge opening "$libPath"',
        'DPE_FFI',
      );
    }

    _lib = DynamicLibrary.open(libPath);
    if (Platform.environment['DPE_FFI_TRACE'] == '1') {
      AppLogger.info(
          'DPE_FFI: DogPawBridge native library open succeeded', 'DPE_FFI');
    }

    // Bind functions
    sharedWriterCreate = _lib.lookupFunction<DppbSharedWriterCreateC,
        DppbSharedWriterCreateDart>('dppb_shared_writer_create');
    sharedReaderCreate = _lib.lookupFunction<DppbSharedReaderCreateC,
        DppbSharedReaderCreateDart>('dppb_shared_reader_create');
    sharedWrite = _lib.lookupFunction<DppbSharedWriteC, DppbSharedWriteDart>(
        'dppb_shared_write');
    sharedRead = _lib.lookupFunction<DppbSharedReadC, DppbSharedReadDart>(
        'dppb_shared_read');
    sharedDestroy =
        _lib.lookupFunction<DppbSharedDestroyC, DppbSharedDestroyDart>(
            'dppb_shared_destroy');
    sharedWriterAdjustBufferSize = _lib.lookupFunction<
            DppbSharedWriterAdjustBufferSizeC,
            DppbSharedWriterAdjustBufferSizeDart>(
        'dppb_shared_writer_adjust_buffer_size');

    producerCreate =
        _lib.lookupFunction<DppbProducerCreateC, DppbProducerCreateDart>(
            'dppb_producer_create');
    producerEnqueue =
        _lib.lookupFunction<DppbProducerEnqueueC, DppbProducerEnqueueDart>(
            'dppb_producer_enqueue');
    consumerCreate =
        _lib.lookupFunction<DppbConsumerCreateC, DppbConsumerCreateDart>(
            'dppb_consumer_create');
    consumerPoll = _lib.lookupFunction<DppbConsumerPollC, DppbConsumerPollDart>(
        'dppb_consumer_poll');
    endpointDestroy =
        _lib.lookupFunction<DppbEndpointDestroyC, DppbEndpointDestroyDart>(
            'dppb_endpoint_destroy');

    getDataSize = _lib.lookupFunction<DppbGetDataSizeC, DppbGetDataSizeDart>(
        'dppb_get_data_size');

    // Server detection
    checkServerRunning = _lib.lookupFunction<DppbCheckServerRunningC,
        DppbCheckServerRunningDart>('dppb_check_server_running');
    waitForServer =
        _lib.lookupFunction<DppbWaitForServerC, DppbWaitForServerDart>(
            'dppb_wait_for_server');

    // Process management
    spawnWithDeathSignal = _lib.lookupFunction<DppbSpawnWithDeathSignalC,
        DppbSpawnWithDeathSignalDart>('dppb_spawn_with_death_signal');
    killProcess = _lib.lookupFunction<DppbKillProcessC, DppbKillProcessDart>(
        'dppb_kill_process');
    waitProcess = _lib.lookupFunction<DppbWaitProcessC, DppbWaitProcessDart>(
        'dppb_wait_process');
    isProcessRunning =
        _lib.lookupFunction<DppbIsProcessRunningC, DppbIsProcessRunningDart>(
            'dppb_is_process_running');

    // Native DogPawEntity bridge
    initializeDartApi =
        _lib.lookupFunction<DppbInitializeDartApiC, DppbInitializeDartApiDart>(
            'dppb_initialize_dart_api');
    dpeCreate = _lib
        .lookupFunction<DppbDpeCreateC, DppbDpeCreateDart>('dppb_dpe_create');
    dpeDestroy = _lib.lookupFunction<DppbDpeDestroyC, DppbDpeDestroyDart>(
        'dppb_dpe_destroy');
    dpeSetEventPort =
        _lib.lookupFunction<DppbDpeSetEventPortC, DppbDpeSetEventPortDart>(
            'dppb_dpe_set_event_port');
    dpeConnectAsync =
        _lib.lookupFunction<DppbDpeConnectAsyncC, DppbDpeConnectAsyncDart>(
            'dppb_dpe_connect_async');
    dpeCompleteConnectionStart = _lib.lookupFunction<
            DppbDpeCompleteConnectionStartC,
            DppbDpeCompleteConnectionStartDart>(
        'dppb_dpe_complete_connection_start');
    dpeDisconnect =
        _lib.lookupFunction<DppbDpeDisconnectC, DppbDpeDisconnectDart>(
            'dppb_dpe_disconnect');
    dpeIsConnected =
        _lib.lookupFunction<DppbDpeIsConnectedC, DppbDpeIsConnectedDart>(
            'dppb_dpe_is_connected');
    dpeSubscribeEntityLifecycleAsync = _lib.lookupFunction<
            DppbDpeSubscribeEntityLifecycleAsyncC,
            DppbDpeSubscribeEntityLifecycleAsyncDart>(
        'dppb_dpe_subscribe_entity_lifecycle_async');
    dpeUnsubscribeEntityLifecycleAsync = _lib.lookupFunction<
            DppbDpeUnsubscribeEntityLifecycleAsyncC,
            DppbDpeUnsubscribeEntityLifecycleAsyncDart>(
        'dppb_dpe_unsubscribe_entity_lifecycle_async');
    dpeSetThemeAsync =
        _lib.lookupFunction<DppbDpeSetThemeAsyncC, DppbDpeSetThemeAsyncDart>(
            'dppb_dpe_set_theme_async');
    dpeCreateThemeAsync = _lib.lookupFunction<DppbDpeCreateThemeAsyncC,
        DppbDpeCreateThemeAsyncDart>('dppb_dpe_create_theme_async');
    dpeUpdateThemeAsync = _lib.lookupFunction<DppbDpeUpdateThemeAsyncC,
        DppbDpeUpdateThemeAsyncDart>('dppb_dpe_update_theme_async');
    dpeReadThemeAsync =
        _lib.lookupFunction<DppbDpeReadThemeAsyncC, DppbDpeReadThemeAsyncDart>(
            'dppb_dpe_read_theme_async');
    dpeDeleteThemeAsync = _lib.lookupFunction<DppbDpeDeleteThemeAsyncC,
        DppbDpeDeleteThemeAsyncDart>('dppb_dpe_delete_theme_async');
    dpeSetCurrentThemeAsync = _lib.lookupFunction<DppbDpeSetCurrentThemeAsyncC,
        DppbDpeSetCurrentThemeAsyncDart>('dppb_dpe_set_current_theme_async');
    dpeReadCurrentThemeAsync = _lib.lookupFunction<
        DppbDpeReadCurrentThemeAsyncC,
        DppbDpeReadCurrentThemeAsyncDart>('dppb_dpe_read_current_theme_async');
    dpeRemoveCurrentThemeAsync = _lib.lookupFunction<
            DppbDpeRemoveCurrentThemeAsyncC,
            DppbDpeRemoveCurrentThemeAsyncDart>(
        'dppb_dpe_remove_current_theme_async');
    dpeListThemesAsync = _lib.lookupFunction<DppbDpeListThemesAsyncC,
        DppbDpeListThemesAsyncDart>('dppb_dpe_list_themes_async');
    dpeSubscribeThemesAsync = _lib.lookupFunction<DppbDpeSubscribeThemesAsyncC,
        DppbDpeSubscribeThemesAsyncDart>('dppb_dpe_subscribe_themes_async');
    dpeUnsubscribeThemesAsync = _lib.lookupFunction<
        DppbDpeUnsubscribeThemesAsyncC,
        DppbDpeUnsubscribeThemesAsyncDart>('dppb_dpe_unsubscribe_themes_async');
    dpeSubscribeCurrentThemeAsync = _lib.lookupFunction<
            DppbDpeSubscribeCurrentThemeAsyncC,
            DppbDpeSubscribeCurrentThemeAsyncDart>(
        'dppb_dpe_subscribe_current_theme_async');
    dpeUnsubscribeCurrentThemeAsync = _lib.lookupFunction<
            DppbDpeUnsubscribeCurrentThemeAsyncC,
            DppbDpeUnsubscribeCurrentThemeAsyncDart>(
        'dppb_dpe_unsubscribe_current_theme_async');
    dpeSetScaleAsync =
        _lib.lookupFunction<DppbDpeSetScaleAsyncC, DppbDpeSetScaleAsyncDart>(
            'dppb_dpe_set_scale_async');
    dpeCreateScaleAsync = _lib.lookupFunction<DppbDpeCreateScaleAsyncC,
        DppbDpeCreateScaleAsyncDart>('dppb_dpe_create_scale_async');
    dpeUpdateScaleAsync = _lib.lookupFunction<DppbDpeUpdateScaleAsyncC,
        DppbDpeUpdateScaleAsyncDart>('dppb_dpe_update_scale_async');
    dpeReadScaleAsync =
        _lib.lookupFunction<DppbDpeReadScaleAsyncC, DppbDpeReadScaleAsyncDart>(
            'dppb_dpe_read_scale_async');
    dpeDeleteScaleAsync = _lib.lookupFunction<DppbDpeDeleteScaleAsyncC,
        DppbDpeDeleteScaleAsyncDart>('dppb_dpe_delete_scale_async');
    dpeSetCurrentScaleAsync = _lib.lookupFunction<DppbDpeSetCurrentScaleAsyncC,
        DppbDpeSetCurrentScaleAsyncDart>('dppb_dpe_set_current_scale_async');
    dpeReadCurrentScaleAsync = _lib.lookupFunction<
        DppbDpeReadCurrentScaleAsyncC,
        DppbDpeReadCurrentScaleAsyncDart>('dppb_dpe_read_current_scale_async');
    dpeRemoveCurrentScaleAsync = _lib.lookupFunction<
            DppbDpeRemoveCurrentScaleAsyncC,
            DppbDpeRemoveCurrentScaleAsyncDart>(
        'dppb_dpe_remove_current_scale_async');
    dpeListScalesAsync = _lib.lookupFunction<DppbDpeListScalesAsyncC,
        DppbDpeListScalesAsyncDart>('dppb_dpe_list_scales_async');
    dpeSetLayoutAsync =
        _lib.lookupFunction<DppbDpeSetLayoutAsyncC, DppbDpeSetLayoutAsyncDart>(
            'dppb_dpe_set_layout_async');
    dpeCreateLayoutAsync = _lib.lookupFunction<DppbDpeCreateLayoutAsyncC,
        DppbDpeCreateLayoutAsyncDart>('dppb_dpe_create_layout_async');
    dpeUpdateLayoutAsync = _lib.lookupFunction<DppbDpeUpdateLayoutAsyncC,
        DppbDpeUpdateLayoutAsyncDart>('dppb_dpe_update_layout_async');
    dpeReadLayoutAsync = _lib.lookupFunction<DppbDpeReadLayoutAsyncC,
        DppbDpeReadLayoutAsyncDart>('dppb_dpe_read_layout_async');
    dpeDeleteLayoutAsync = _lib.lookupFunction<DppbDpeDeleteLayoutAsyncC,
        DppbDpeDeleteLayoutAsyncDart>('dppb_dpe_delete_layout_async');
    dpeListLayoutsAsync = _lib.lookupFunction<DppbDpeListLayoutsAsyncC,
        DppbDpeListLayoutsAsyncDart>('dppb_dpe_list_layouts_async');
    dpeSetKVAsync =
        _lib.lookupFunction<DppbDpeSetKVAsyncC, DppbDpeSetKVAsyncDart>(
            'dppb_dpe_set_kv_async');
    dpeCreateKVAsync =
        _lib.lookupFunction<DppbDpeCreateKVAsyncC, DppbDpeCreateKVAsyncDart>(
            'dppb_dpe_create_kv_async');
    dpeUpdateKVAsync =
        _lib.lookupFunction<DppbDpeUpdateKVAsyncC, DppbDpeUpdateKVAsyncDart>(
            'dppb_dpe_update_kv_async');
    dpeReadKVAsync =
        _lib.lookupFunction<DppbDpeReadKVAsyncC, DppbDpeReadKVAsyncDart>(
            'dppb_dpe_read_kv_async');
    dpeDeleteKVAsync =
        _lib.lookupFunction<DppbDpeDeleteKVAsyncC, DppbDpeDeleteKVAsyncDart>(
            'dppb_dpe_delete_kv_async');
    dpeListKVsAsync =
        _lib.lookupFunction<DppbDpeListKVsAsyncC, DppbDpeListKVsAsyncDart>(
            'dppb_dpe_list_kvs_async');
    dpeCreateEndpointAsync = _lib.lookupFunction<DppbDpeCreateEndpointAsyncC,
        DppbDpeCreateEndpointAsyncDart>('dppb_dpe_create_endpoint_async');
    dpeUpdateEndpointAsync = _lib.lookupFunction<DppbDpeUpdateEndpointAsyncC,
        DppbDpeUpdateEndpointAsyncDart>('dppb_dpe_update_endpoint_async');
    dpeSetEndpointAsync = _lib.lookupFunction<DppbDpeSetEndpointAsyncC,
        DppbDpeSetEndpointAsyncDart>('dppb_dpe_set_endpoint_async');
    dpeReadEndpointAsync = _lib.lookupFunction<DppbDpeReadEndpointAsyncC,
        DppbDpeReadEndpointAsyncDart>('dppb_dpe_read_endpoint_async');
    dpeDeleteEndpointAsync = _lib.lookupFunction<DppbDpeDeleteEndpointAsyncC,
        DppbDpeDeleteEndpointAsyncDart>('dppb_dpe_delete_endpoint_async');
    dpeSearchEndpointsAsync = _lib.lookupFunction<DppbDpeSearchEndpointsAsyncC,
        DppbDpeSearchEndpointsAsyncDart>('dppb_dpe_search_endpoints_async');
    dpeSubscribeEndpointsAsync = _lib.lookupFunction<
            DppbDpeSubscribeEndpointsAsyncC,
            DppbDpeSubscribeEndpointsAsyncDart>(
        'dppb_dpe_subscribe_endpoints_async');
    dpeUnsubscribeEndpointsAsync = _lib.lookupFunction<
            DppbDpeUnsubscribeEndpointsAsyncC,
            DppbDpeUnsubscribeEndpointsAsyncDart>(
        'dppb_dpe_unsubscribe_endpoints_async');
    dpeLocalEndpointWrite = _lib.lookupFunction<DppbDpeLocalEndpointWriteC,
        DppbDpeLocalEndpointWriteDart>('dppb_dpe_local_endpoint_write');
    dpeLocalEndpointGetConnectionCount = _lib.lookupFunction<
            DppbDpeLocalEndpointGetConnectionCountC,
            DppbDpeLocalEndpointGetConnectionCountDart>(
        'dppb_dpe_local_endpoint_get_connection_count');
    dpeLocalEndpointGetConnectionName = _lib.lookupFunction<
            DppbDpeLocalEndpointGetConnectionNameC,
            DppbDpeLocalEndpointGetConnectionNameDart>(
        'dppb_dpe_local_endpoint_get_connection_name');
    dpeLocalEndpointGetConnectionShape = _lib.lookupFunction<
            DppbDpeLocalEndpointGetConnectionShapeC,
            DppbDpeLocalEndpointGetConnectionShapeDart>(
        'dppb_dpe_local_endpoint_get_connection_shape');
    dpeLocalEndpointPollConnection = _lib.lookupFunction<
            DppbDpeLocalEndpointPollConnectionC,
            DppbDpeLocalEndpointPollConnectionDart>(
        'dppb_dpe_local_endpoint_poll_connection');
    dpeLocalEndpointReadFileBacked = _lib.lookupFunction<
            DppbDpeLocalEndpointReadFileBackedC,
            DppbDpeLocalEndpointReadFileBackedDart>(
        'dppb_dpe_local_endpoint_read_file_backed');
    dpeLocalEndpointPollFileBacked = _lib.lookupFunction<
            DppbDpeLocalEndpointPollFileBackedC,
            DppbDpeLocalEndpointPollFileBackedDart>(
        'dppb_dpe_local_endpoint_poll_file_backed');
    dpeCreateConnectionRequestAsync = _lib.lookupFunction<
            DppbDpeCreateConnectionRequestAsyncC,
            DppbDpeCreateConnectionRequestAsyncDart>(
        'dppb_dpe_create_connection_request_async');
    dpeSetConnectionRequestAsync = _lib.lookupFunction<
            DppbDpeSetConnectionRequestAsyncC,
            DppbDpeSetConnectionRequestAsyncDart>(
        'dppb_dpe_set_connection_request_async');
    dpeUpdateConnectionRequestAsync = _lib.lookupFunction<
            DppbDpeUpdateConnectionRequestAsyncC,
            DppbDpeUpdateConnectionRequestAsyncDart>(
        'dppb_dpe_update_connection_request_async');
    dpeReadConnectionRequestAsync = _lib.lookupFunction<
            DppbDpeReadConnectionRequestAsyncC,
            DppbDpeReadConnectionRequestAsyncDart>(
        'dppb_dpe_read_connection_request_async');
    dpeDeleteConnectionRequestAsync = _lib.lookupFunction<
            DppbDpeDeleteConnectionRequestAsyncC,
            DppbDpeDeleteConnectionRequestAsyncDart>(
        'dppb_dpe_delete_connection_request_async');
    dpeListConnectionRequestsAsync = _lib.lookupFunction<
            DppbDpeListConnectionRequestsAsyncC,
            DppbDpeListConnectionRequestsAsyncDart>(
        'dppb_dpe_list_connection_requests_async');
    dpeCreateFollowRequestAsync = _lib.lookupFunction<
            DppbDpeCreateFollowRequestAsyncC,
            DppbDpeCreateFollowRequestAsyncDart>(
        'dppb_dpe_create_follow_request_async');
    dpeSetFollowRequestAsync = _lib.lookupFunction<
        DppbDpeSetFollowRequestAsyncC,
        DppbDpeSetFollowRequestAsyncDart>('dppb_dpe_set_follow_request_async');
    dpeUpdateFollowRequestAsync = _lib.lookupFunction<
            DppbDpeUpdateFollowRequestAsyncC,
            DppbDpeUpdateFollowRequestAsyncDart>(
        'dppb_dpe_update_follow_request_async');
    dpeReadFollowRequestAsync = _lib.lookupFunction<
            DppbDpeReadFollowRequestAsyncC, DppbDpeReadFollowRequestAsyncDart>(
        'dppb_dpe_read_follow_request_async');
    dpeDeleteFollowRequestAsync = _lib.lookupFunction<
            DppbDpeDeleteFollowRequestAsyncC,
            DppbDpeDeleteFollowRequestAsyncDart>(
        'dppb_dpe_delete_follow_request_async');
    dpeListFollowRequestsAsync = _lib.lookupFunction<
            DppbDpeListFollowRequestsAsyncC,
            DppbDpeListFollowRequestsAsyncDart>(
        'dppb_dpe_list_follow_requests_async');
    dpeReadConnectionAsync = _lib.lookupFunction<DppbDpeReadConnectionAsyncC,
        DppbDpeReadConnectionAsyncDart>('dppb_dpe_read_connection_async');
    dpeListConnectionsAsync = _lib.lookupFunction<DppbDpeListConnectionsAsyncC,
        DppbDpeListConnectionsAsyncDart>('dppb_dpe_list_connections_async');
    dpeSubscribeScalesAsync = _lib.lookupFunction<DppbDpeSubscribeScalesAsyncC,
        DppbDpeSubscribeScalesAsyncDart>('dppb_dpe_subscribe_scales_async');
    dpeUnsubscribeScalesAsync = _lib.lookupFunction<
        DppbDpeUnsubscribeScalesAsyncC,
        DppbDpeUnsubscribeScalesAsyncDart>('dppb_dpe_unsubscribe_scales_async');
    dpeSubscribeCurrentScaleAsync = _lib.lookupFunction<
            DppbDpeSubscribeCurrentScaleAsyncC,
            DppbDpeSubscribeCurrentScaleAsyncDart>(
        'dppb_dpe_subscribe_current_scale_async');
    dpeUnsubscribeCurrentScaleAsync = _lib.lookupFunction<
            DppbDpeUnsubscribeCurrentScaleAsyncC,
            DppbDpeUnsubscribeCurrentScaleAsyncDart>(
        'dppb_dpe_unsubscribe_current_scale_async');
    dpeSubscribeLayoutsAsync = _lib.lookupFunction<
        DppbDpeSubscribeLayoutsAsyncC,
        DppbDpeSubscribeLayoutsAsyncDart>('dppb_dpe_subscribe_layouts_async');
    dpeUnsubscribeLayoutsAsync = _lib.lookupFunction<
            DppbDpeUnsubscribeLayoutsAsyncC,
            DppbDpeUnsubscribeLayoutsAsyncDart>(
        'dppb_dpe_unsubscribe_layouts_async');
    dpeAddLayoutStackEntryAsync = _lib.lookupFunction<
            DppbDpeAddLayoutStackEntryAsyncC,
            DppbDpeAddLayoutStackEntryAsyncDart>(
        'dppb_dpe_add_layout_stack_entry_async');
    dpeRemoveLayoutStackEntryAsync = _lib.lookupFunction<
            DppbDpeRemoveLayoutStackEntryAsyncC,
            DppbDpeRemoveLayoutStackEntryAsyncDart>(
        'dppb_dpe_remove_layout_stack_entry_async');
    dpeMoveLayoutStackEntryAsync = _lib.lookupFunction<
            DppbDpeMoveLayoutStackEntryAsyncC,
            DppbDpeMoveLayoutStackEntryAsyncDart>(
        'dppb_dpe_move_layout_stack_entry_async');
    dpeReadLayoutStackAsync = _lib.lookupFunction<DppbDpeReadLayoutStackAsyncC,
        DppbDpeReadLayoutStackAsyncDart>('dppb_dpe_read_layout_stack_async');
    dpeSubscribeLayoutStackAsync = _lib.lookupFunction<
            DppbDpeSubscribeLayoutStackAsyncC,
            DppbDpeSubscribeLayoutStackAsyncDart>(
        'dppb_dpe_subscribe_layout_stack_async');
    dpeUnsubscribeLayoutStackAsync = _lib.lookupFunction<
            DppbDpeUnsubscribeLayoutStackAsyncC,
            DppbDpeUnsubscribeLayoutStackAsyncDart>(
        'dppb_dpe_unsubscribe_layout_stack_async');
    dpeSubscribeKVAsync = _lib.lookupFunction<DppbDpeSubscribeKVAsyncC,
        DppbDpeSubscribeKVAsyncDart>('dppb_dpe_subscribe_kv_async');
    dpeUnsubscribeKVAsync = _lib.lookupFunction<DppbDpeUnsubscribeKVAsyncC,
        DppbDpeUnsubscribeKVAsyncDart>('dppb_dpe_unsubscribe_kv_async');
    dpeSendDirectMessageAsync = _lib.lookupFunction<
            DppbDpeSendDirectMessageAsyncC, DppbDpeSendDirectMessageAsyncDart>(
        'dppb_dpe_send_direct_message_async');
    dpeSendCommandAsync = _lib.lookupFunction<DppbDpeSendCommandAsyncC,
        DppbDpeSendCommandAsyncDart>('dppb_dpe_send_command_async');
    dpeSendCommandResponse = _lib.lookupFunction<DppbDpeSendCommandResponseC,
        DppbDpeSendCommandResponseDart>('dppb_dpe_send_command_response');
    dpeSendCommandAccepted = _lib.lookupFunction<DppbDpeSendCommandAcceptedC,
        DppbDpeSendCommandAcceptedDart>('dppb_dpe_send_command_accepted');
    dpeCompletePresetRequest = _lib.lookupFunction<
        DppbDpeCompletePresetRequestC,
        DppbDpeCompletePresetRequestDart>('dppb_dpe_complete_preset_request');
    dpeSaveGlobalStateAsync = _lib.lookupFunction<DppbDpeSaveGlobalStateAsyncC,
        DppbDpeSaveGlobalStateAsyncDart>('dppb_dpe_save_global_state_async');
    dpeLoadGlobalStateAsync = _lib.lookupFunction<DppbDpeLoadGlobalStateAsyncC,
        DppbDpeLoadGlobalStateAsyncDart>('dppb_dpe_load_global_state_async');
    dpeLogAsync = _lib.lookupFunction<DppbDpeLogAsyncC, DppbDpeLogAsyncDart>(
        'dppb_dpe_log_async');
    dpeStartLogSectionAsync = _lib.lookupFunction<DppbDpeStartLogSectionAsyncC,
        DppbDpeStartLogSectionAsyncDart>('dppb_dpe_start_log_section_async');
    dpeFlushLogSectionAsync = _lib.lookupFunction<DppbDpeFlushLogSectionAsyncC,
        DppbDpeFlushLogSectionAsyncDart>('dppb_dpe_flush_log_section_async');
    dpeEndLogSectionAsync = _lib.lookupFunction<DppbDpeEndLogSectionAsyncC,
        DppbDpeEndLogSectionAsyncDart>('dppb_dpe_end_log_section_async');
    dpeGetSystemInfoAsync = _lib.lookupFunction<DppbDpeGetSystemInfoAsyncC,
        DppbDpeGetSystemInfoAsyncDart>('dppb_dpe_get_system_info_async');
    dpeListAppsAsync =
        _lib.lookupFunction<DppbDpeListAppsAsyncC, DppbDpeListAppsAsyncDart>(
            'dppb_dpe_list_apps_async');
    dpeListRunningEntitiesAsync = _lib.lookupFunction<
        DppbDpeListRunningEntitiesAsyncC,
        DppbDpeListRunningEntitiesAsyncDart>(
      'dppb_dpe_list_running_entities_async',
    );
    dpeLaunchAppAsync =
        _lib.lookupFunction<DppbDpeLaunchAppAsyncC, DppbDpeLaunchAppAsyncDart>(
            'dppb_dpe_launch_app_async');
    dpeStopAppAsync =
        _lib.lookupFunction<DppbDpeStopAppAsyncC, DppbDpeStopAppAsyncDart>(
            'dppb_dpe_stop_app_async');
    dpeKillAllAppsAsync = _lib.lookupFunction<DppbDpeKillAllAppsAsyncC,
        DppbDpeKillAllAppsAsyncDart>('dppb_dpe_kill_all_apps_async');

    if (!_dpeApiInitialized) {
      final int initResult = initializeDartApi(NativeApi.initializeApiDLData);
      if (initResult != 0) {
        throw StateError(
            'Failed to initialize dogpaw_bridge Dart API: $initResult');
      }
      _dpeApiInitialized = true;
    }
  }

  //===========================================================================
  // High-level wrappers that handle memory management
  //===========================================================================

  /// Check if Epiphany server is running
  /// Returns: port number (>0) if running, 0 if not running, -1 on file error, -2 on lock error
  int checkServerRunningManaged(String portFilePath) {
    final pathPtr = portFilePath.toNativeUtf8();
    try {
      return checkServerRunning(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Wait for server to become ready
  /// Returns: port number (>0) if ready, 0 on timeout, -1 on error
  int waitForServerManaged(String portFilePath, int timeoutMs) {
    final pathPtr = portFilePath.toNativeUtf8();
    try {
      return waitForServer(pathPtr, timeoutMs);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Spawn process with PR_SET_PDEATHSIG
  /// argv should NOT include null terminator, it will be added automatically
  /// logPath: if provided, stdout/stderr are redirected to this file (reduces test output)
  /// Returns: child PID (>0) on success, -1 on fork error, -2 on exec error
  int spawnWithDeathSignalManaged(
      String program, List<String> argv, int deathSignal,
      {String? logPath}) {
    final programPtr = program.toNativeUtf8();
    final logPathPtr = logPath?.toNativeUtf8();

    // Allocate array of pointers (argv.length + 1 for null terminator)
    final argvPtr = malloc<Pointer<Utf8>>(argv.length + 1);

    // Convert each argument to Utf8 and store pointer
    final argPtrs = <Pointer<Utf8>>[];
    try {
      for (int i = 0; i < argv.length; i++) {
        final argPtr = argv[i].toNativeUtf8();
        argPtrs.add(argPtr);
        argvPtr[i] = argPtr;
      }
      // Null terminator
      argvPtr[argv.length] = nullptr;

      return spawnWithDeathSignal(
          programPtr, argvPtr, deathSignal, logPathPtr ?? nullptr);
    } finally {
      // Free all allocated strings
      malloc.free(programPtr);
      if (logPathPtr != null) {
        malloc.free(logPathPtr);
      }
      for (var argPtr in argPtrs) {
        malloc.free(argPtr);
      }
      malloc.free(argvPtr);
    }
  }

  /// Send signal to process
  /// Returns: 0 on success, -1 on error
  int killProcessManaged(int pid, int signalNum) {
    return killProcess(pid, signalNum);
  }

  /// Wait for process to exit with timeout
  /// Returns: exit status (>=0) if exited, -1 on error, -2 on timeout
  int waitProcessManaged(int pid, int timeoutMs) {
    return waitProcess(pid, timeoutMs);
  }

  /// Check if process is still running
  /// Returns: 1 if running, 0 if not running, -1 on error
  int isProcessRunningManaged(int pid) {
    return isProcessRunning(pid);
  }

  /// Create a native-backed DogPawEntity bridge handle.
  ///
  /// Purpose:
  /// Allocates a bridge-owned C++ DogPawEntity instance that Dart can drive via
  /// async request/result envelopes.
  ///
  /// Parameters:
  /// - [entityName]: `String` entity name to pass to the native DogPawEntity.
  /// - [serverUrl]: `String` websocket URL used by the native DogPawEntity.
  /// - [timeoutMs]: `int` default request timeout in milliseconds.
  ///
  /// Return value:
  /// - `Pointer<Void>` opaque native handle. `nullptr` indicates creation
  ///   failure.
  ///
  /// Requirements/Preconditions:
  /// - [entityName] must be non-empty.
  /// - [timeoutMs] must be zero or positive.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the returned handle owns a live native DogPawEntity bridge.
  ///
  /// Invariants:
  /// - The returned handle must later be released with [dpeDestroyManaged].
  Pointer<Void> dpeCreateManaged(
    String entityName, {
    String serverUrl = 'ws://localhost:8080',
    int timeoutMs = 5000,
  }) {
    final Pointer<Utf8> entityNamePtr = entityName.toNativeUtf8();
    final Pointer<Utf8> serverUrlPtr = serverUrl.toNativeUtf8();
    try {
      return dpeCreate(entityNamePtr, serverUrlPtr, timeoutMs);
    } finally {
      malloc.free(entityNamePtr);
      malloc.free(serverUrlPtr);
    }
  }

  /// Destroy a native-backed DogPawEntity bridge handle.
  ///
  /// Purpose:
  /// Releases the native wrapper and its owned C++ DogPawEntity instance.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` opaque handle returned by
  ///   [dpeCreateManaged].
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is either `nullptr` or a live bridge handle.
  ///
  /// Guarantees/Postconditions:
  /// - If [handle] was live, its native resources are released.
  ///
  /// Invariants:
  /// - Calling with `nullptr` is a no-op.
  void dpeDestroyManaged(Pointer<Void> handle) {
    dpeDestroy(handle);
  }

  /// Register the Dart event port used by the native DPE bridge.
  ///
  /// Purpose:
  /// Gives the native bridge a port it can post async result and error
  /// envelopes to.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [port]: `int` native port id from a `ReceivePort`.
  ///
  /// Return value:
  /// - `bool` indicating whether the port was stored successfully.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle.
  /// - [port] refers to an open `ReceivePort`.
  ///
  /// Guarantees/Postconditions:
  /// - On success, future native async events target [port].
  ///
  /// Invariants:
  /// - This method does not launch any request by itself.
  bool dpeSetEventPortManaged(Pointer<Void> handle, int port) {
    return dpeSetEventPort(handle, port);
  }

  /// Launch an asynchronous native connect request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::connect()` flow and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id used to resolve the
  ///   matching completer.
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final connect result will arrive asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeConnectAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeConnectAsync(handle, requestId);
  }

  /// Complete the pending native connection start handle.
  ///
  /// Purpose:
  /// Mirrors the public DogPawEntity ready-handle contract on top of the native
  /// bridge.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [readyMessageType]: `int` enum value where `0` means ready and `1`
  ///   means error.
  ///
  /// Return value:
  /// - `bool` indicating whether a pending native connection-start handle was
  ///   present and completed.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the stored native ready handle is consumed.
  ///
  /// Invariants:
  /// - Repeated completion attempts after success return `false`.
  bool dpeCompleteConnectionStartManaged(
    Pointer<Void> handle,
    int readyMessageType,
  ) {
    return dpeCompleteConnectionStart(handle, readyMessageType);
  }

  /// Disconnect the native-backed DogPawEntity immediately.
  ///
  /// Purpose:
  /// Exposes the native `disconnect()` call to Dart.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  ///
  /// Return value:
  /// - None.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is either `nullptr` or a live bridge handle.
  ///
  /// Guarantees/Postconditions:
  /// - If connected, the native entity is disconnected.
  ///
  /// Invariants:
  /// - Calling with `nullptr` is a no-op.
  void dpeDisconnectManaged(Pointer<Void> handle) {
    dpeDisconnect(handle);
  }

  /// Read the native-backed connection state synchronously.
  ///
  /// Purpose:
  /// Returns the native DogPawEntity's current connected flag for lifecycle
  /// assertions.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  ///
  /// Return value:
  /// - `bool` indicating whether the native entity reports connected.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is either `nullptr` or a live bridge handle.
  ///
  /// Guarantees/Postconditions:
  /// - Returns the current native connection state snapshot.
  ///
  /// Invariants:
  /// - Calling with `nullptr` returns `false`.
  bool dpeIsConnectedManaged(Pointer<Void> handle) {
    return dpeIsConnected(handle);
  }

  /// Launch an asynchronous native `subscribeToEntityLifecycle()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::subscribeToEntityLifecycle()` call and
  /// resolves it later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [entityName]: optional `String` entity filter, or `null` for all
  ///   entities.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final subscribe-entity-lifecycle result arrives
  ///   asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSubscribeEntityLifecycleAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? entityName,
    required bool sendImmediately,
  }) {
    final Pointer<Utf8> entityNamePtr =
        entityName != null ? entityName.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeSubscribeEntityLifecycleAsync(
        handle,
        requestId,
        entityNamePtr,
        sendImmediately,
      );
    } finally {
      if (entityName != null) {
        malloc.free(entityNamePtr);
      }
    }
  }

  /// Launch an asynchronous native `unsubscribeFromEntityLifecycle()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::unsubscribeFromEntityLifecycle()` call and
  /// resolves it later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [entityName]: optional `String` entity filter, or `null` for the
  ///   all-entities subscription.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final unsubscribe-entity-lifecycle result arrives
  ///   asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUnsubscribeEntityLifecycleAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? entityName,
  }) {
    final Pointer<Utf8> entityNamePtr =
        entityName != null ? entityName.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeUnsubscribeEntityLifecycleAsync(
        handle,
        requestId,
        entityNamePtr,
      );
    } finally {
      if (entityName != null) {
        malloc.free(entityNamePtr);
      }
    }
  }

  /// Launch an asynchronous native direct-message send.
  ///
  /// Purpose:
  /// Starts the native direct-message path and resolves it later via the
  /// registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [targetEntity]: `String` entity id to address.
  /// - [messageJson]: `String` JSON payload for the message.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSendDirectMessageAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String targetEntity,
    String messageJson,
  ) {
    final Pointer<Utf8> targetPtr = targetEntity.toNativeUtf8();
    final Pointer<Utf8> messagePtr = messageJson.toNativeUtf8();
    try {
      return dpeSendDirectMessageAsync(
        handle,
        requestId,
        targetPtr,
        messagePtr,
      );
    } finally {
      malloc.free(targetPtr);
      malloc.free(messagePtr);
    }
  }

  /// Launch an asynchronous native command send.
  ///
  /// Purpose:
  /// Starts the native command send and resolves it later via the registered
  /// Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [targetEntity]: `String` entity id to address.
  /// - [command]: `String` command name.
  /// - [paramsJson]: `String` JSON encoding of command parameters.
  /// - [timeoutMs]: `int` timeout in milliseconds.
  /// - [waitForCompletion]: `bool` forwarded to the native request.
  /// - [deliveryPolicyJson]: optional `String` JSON for delivery policy, or
  ///   `null` to omit.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final command result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSendCommandAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String targetEntity,
    String command,
    String paramsJson, {
    required int timeoutMs,
    required bool waitForCompletion,
    String? deliveryPolicyJson,
  }) {
    final Pointer<Utf8> targetPtr = targetEntity.toNativeUtf8();
    final Pointer<Utf8> commandPtr = command.toNativeUtf8();
    final Pointer<Utf8> paramsPtr = paramsJson.toNativeUtf8();
    final Pointer<Utf8> deliveryPtr = deliveryPolicyJson != null
        ? deliveryPolicyJson.toNativeUtf8()
        : nullptr.cast<Utf8>();
    try {
      return dpeSendCommandAsync(
        handle,
        requestId,
        targetPtr,
        commandPtr,
        paramsPtr,
        timeoutMs,
        waitForCompletion,
        deliveryPtr,
      );
    } finally {
      malloc.free(targetPtr);
      malloc.free(commandPtr);
      malloc.free(paramsPtr);
      if (deliveryPolicyJson != null) {
        malloc.free(deliveryPtr);
      }
    }
  }

  /// Send a native command response (synchronous bridge call).
  ///
  /// Purpose:
  /// Forwards a command completion to the native bridge for delivery to the
  /// target entity.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [targetEntity]: `String` entity id to address.
  /// - [commandId]: `String` id of the command being answered.
  /// - [success]: `bool` outcome flag.
  /// - [resultJson]: `String` JSON result body.
  /// - [errorMessage]: `String` error text when [success] is false; may be
  ///   empty.
  ///
  /// Return value:
  /// - `bool` indicating whether the native call succeeded.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native bridge accepts the response for delivery.
  ///
  /// Invariants:
  /// - Does not block on remote completion beyond native queueing work.
  bool dpeSendCommandResponseManaged(
    Pointer<Void> handle,
    String targetEntity,
    String commandId, {
    required bool success,
    required String resultJson,
    String errorMessage = '',
  }) {
    final Pointer<Utf8> targetPtr = targetEntity.toNativeUtf8();
    final Pointer<Utf8> commandIdPtr = commandId.toNativeUtf8();
    final Pointer<Utf8> resultPtr = resultJson.toNativeUtf8();
    final Pointer<Utf8> errorPtr = errorMessage.toNativeUtf8();
    try {
      return dpeSendCommandResponse(
        handle,
        targetPtr,
        commandIdPtr,
        success,
        resultPtr,
        errorPtr,
      );
    } finally {
      malloc.free(targetPtr);
      malloc.free(commandIdPtr);
      malloc.free(resultPtr);
      malloc.free(errorPtr);
    }
  }

  /// Send a native command-accepted notification (synchronous bridge call).
  ///
  /// Purpose:
  /// Notifies the native bridge that a command was accepted by this entity.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [targetEntity]: `String` entity id to address.
  /// - [commandId]: `String` id of the accepted command.
  ///
  /// Return value:
  /// - `bool` indicating whether the native call succeeded.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native bridge records acceptance for delivery.
  ///
  /// Invariants:
  /// - Does not block on remote completion beyond native queueing work.
  bool dpeSendCommandAcceptedManaged(
    Pointer<Void> handle,
    String targetEntity,
    String commandId,
  ) {
    final Pointer<Utf8> targetPtr = targetEntity.toNativeUtf8();
    final Pointer<Utf8> commandIdPtr = commandId.toNativeUtf8();
    try {
      return dpeSendCommandAccepted(handle, targetPtr, commandIdPtr);
    } finally {
      malloc.free(targetPtr);
      malloc.free(commandIdPtr);
    }
  }

  /// Complete a deferred native preset request (synchronous bridge call).
  ///
  /// Purpose:
  /// Forwards the final success or failure state for a preset request that was
  /// previously delivered to Dart through the native event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [serverRequestId]: `String` preset request correlation id.
  /// - [success]: `bool` outcome flag.
  /// - [errorMessage]: `String` error text when [success] is false; may be
  ///   empty.
  ///
  /// Return value:
  /// - `bool` indicating whether the native call succeeded.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the native bridge accepts the preset completion for delivery.
  ///
  /// Invariants:
  /// - Does not allocate a Dart async request id.
  bool dpeCompletePresetRequestManaged(
    Pointer<Void> handle,
    String serverRequestId, {
    required bool success,
    String errorMessage = '',
  }) {
    final Pointer<Utf8> serverRequestIdPtr = serverRequestId.toNativeUtf8();
    final Pointer<Utf8> errorPtr = errorMessage.toNativeUtf8();
    try {
      return dpeCompletePresetRequest(
        handle,
        serverRequestIdPtr,
        success,
        errorPtr,
      );
    } finally {
      malloc.free(serverRequestIdPtr);
      malloc.free(errorPtr);
    }
  }

  /// Launch an asynchronous native `saveGlobalState()` request.
  ///
  /// Purpose:
  /// Starts the native preset-save flow and resolves it later via the
  /// registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [presetName]: `String` preset name to save.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final save result arrives asynchronously via the event
  ///   port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSaveGlobalStateAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String presetName,
  ) {
    final Pointer<Utf8> presetNamePtr = presetName.toNativeUtf8();
    try {
      return dpeSaveGlobalStateAsync(handle, requestId, presetNamePtr);
    } finally {
      malloc.free(presetNamePtr);
    }
  }

  /// Launch an asynchronous native `loadGlobalState()` request.
  ///
  /// Purpose:
  /// Starts the native preset-load flow and resolves it later via the
  /// registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [presetName]: `String` preset name to load.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final load result arrives asynchronously via the event
  ///   port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeLoadGlobalStateAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String presetName,
  ) {
    final Pointer<Utf8> presetNamePtr = presetName.toNativeUtf8();
    try {
      return dpeLoadGlobalStateAsync(handle, requestId, presetNamePtr);
    } finally {
      malloc.free(presetNamePtr);
    }
  }

  /// Launch an asynchronous native `log()` request.
  ///
  /// Purpose:
  /// Starts the native utility-log flow and resolves it later via the
  /// registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [message]: `String` log text to forward to Epiphany.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final log result arrives asynchronously via the event
  ///   port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeLogAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String message,
  ) {
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      return dpeLogAsync(handle, requestId, messagePtr);
    } finally {
      malloc.free(messagePtr);
    }
  }

  /// Launch an asynchronous native `startLogSection()` request.
  ///
  /// Purpose:
  /// Starts one buffered Epiphany log section and resolves it later via the
  /// registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [sectionTitle]: `String` optional section label.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeStartLogSectionAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String sectionTitle,
  ) {
    final Pointer<Utf8> sectionTitlePtr = sectionTitle.toNativeUtf8();
    try {
      return dpeStartLogSectionAsync(handle, requestId, sectionTitlePtr);
    } finally {
      malloc.free(sectionTitlePtr);
    }
  }

  /// Launch an asynchronous native `flushLogSection()` request.
  ///
  /// Purpose:
  /// Flushes the current buffered Epiphany log section and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeFlushLogSectionAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeFlushLogSectionAsync(handle, requestId);
  }

  /// Launch an asynchronous native `endLogSection()` request.
  ///
  /// Purpose:
  /// Ends the current buffered Epiphany log section and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [flush]: `bool` controlling whether buffered logs are printed.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeEndLogSectionAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    bool flush,
  ) {
    return dpeEndLogSectionAsync(handle, requestId, flush);
  }

  /// Launch an asynchronous native `getSystemInfo()` request.
  ///
  /// Purpose:
  /// Starts the native system-info flow and resolves it later via the
  /// registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeGetSystemInfoAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeGetSystemInfoAsync(handle, requestId);
  }

  /// Launch an asynchronous native `listApps()` request.
  ///
  /// Purpose:
  /// Starts the native app-list flow and resolves it later via the registered
  /// Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeListAppsAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeListAppsAsync(handle, requestId);
  }

  /// Launch an asynchronous native `listRunningEntities()` request.
  ///
  /// Purpose:
  /// Starts the native runtime-entity list flow and resolves it later via the
  /// registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeListRunningEntitiesAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeListRunningEntitiesAsync(handle, requestId);
  }

  /// Launch an asynchronous native `launchApp()` request.
  ///
  /// Purpose:
  /// Starts the native app-launch flow and resolves it later via the registered
  /// Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [appName]: `String` app name to launch.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeLaunchAppAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String appName, {
    String? launchMetadataJson,
  }) {
    final Pointer<Utf8> appNamePtr = appName.toNativeUtf8();
    final Pointer<Utf8> metadataPtr = launchMetadataJson != null
        ? launchMetadataJson.toNativeUtf8()
        : nullptr.cast<Utf8>();
    try {
      return dpeLaunchAppAsync(handle, requestId, appNamePtr, metadataPtr);
    } finally {
      malloc.free(appNamePtr);
      if (launchMetadataJson != null) {
        malloc.free(metadataPtr);
      }
    }
  }

  /// Launch an asynchronous native `stopApp()` request.
  ///
  /// Purpose:
  /// Starts the native app-stop flow and resolves it later via the registered
  /// Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [appName]: `String` app name to stop.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeStopAppAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String appName,
  ) {
    final Pointer<Utf8> appNamePtr = appName.toNativeUtf8();
    try {
      return dpeStopAppAsync(handle, requestId, appNamePtr);
    } finally {
      malloc.free(appNamePtr);
    }
  }

  /// Launch an asynchronous native `killAllApps()` request.
  ///
  /// Purpose:
  /// Starts the native app-kill-all flow and resolves it later via the
  /// registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final result arrives asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeKillAllAppsAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeKillAllAppsAsync(handle, requestId);
  }

  /// Launch an asynchronous native `setTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::setTheme()` call and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [themeJson]: `String` JSON encoding of a `Theme`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [themeJson] contains valid `Theme` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final set-theme result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSetThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String themeJson,
  ) {
    final Pointer<Utf8> themeJsonPtr = themeJson.toNativeUtf8();
    try {
      return dpeSetThemeAsync(handle, requestId, themeJsonPtr);
    } finally {
      malloc.free(themeJsonPtr);
    }
  }

  /// Launch an asynchronous native `createTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::createTheme()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [themeJson]: `String` JSON encoding of a `Theme`.
  /// - [autoSuffix]: `bool` forwarded to the native create request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [themeJson] contains valid `Theme` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final create-theme result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeCreateThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String themeJson, {
    bool autoSuffix = false,
  }) {
    final Pointer<Utf8> themeJsonPtr = themeJson.toNativeUtf8();
    try {
      return dpeCreateThemeAsync(handle, requestId, themeJsonPtr, autoSuffix);
    } finally {
      malloc.free(themeJsonPtr);
    }
  }

  /// Launch an asynchronous native `updateTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::updateTheme()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [themeJson]: `String` JSON encoding of a `Theme`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [themeJson] contains valid `Theme` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final update-theme result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUpdateThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String themeJson,
  ) {
    final Pointer<Utf8> themeJsonPtr = themeJson.toNativeUtf8();
    try {
      return dpeUpdateThemeAsync(handle, requestId, themeJsonPtr);
    } finally {
      malloc.free(themeJsonPtr);
    }
  }

  /// Launch an asynchronous native `readTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::readTheme()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` theme name to read.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final read-theme result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeReadThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeReadThemeAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `deleteTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::deleteTheme()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` theme name to delete.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final delete-theme result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeDeleteThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson,
  ) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeDeleteThemeAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `setCurrentTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::setCurrentTheme()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` theme name to set current.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final set-current-theme result arrives asynchronously
  ///   via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSetCurrentThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson,
  ) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeSetCurrentThemeAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `readCurrentTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::readCurrentTheme()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final read-current-theme result arrives asynchronously
  ///   via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeReadCurrentThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    return dpeReadCurrentThemeAsync(
      handle,
      requestId,
      includeResolved,
      includeSpec,
    );
  }

  /// Launch an asynchronous native `removeCurrentTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::removeCurrentTheme()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final remove-current-theme result arrives asynchronously
  ///   via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeRemoveCurrentThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeRemoveCurrentThemeAsync(handle, requestId);
  }

  /// Launch an asynchronous native `listThemes()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::listThemes()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` passed through to the native request.
  /// - [includeSpec]: `bool` passed through to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final list-themes result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeListThemesAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeListThemesAsync(
        handle,
        requestId,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `subscribeToThemes()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::subscribeToThemes()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: optional `String` theme name to watch, or `null` for all themes.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final subscribe-themes result arrives asynchronously via
  ///   the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSubscribeThemesAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? name,
    required String namespaceSelectorJson,
    required bool includeResolved,
    required bool includeSpec,
    required bool sendImmediately,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> namePtr =
        name != null ? name.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeSubscribeThemesAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
        sendImmediately,
      );
    } finally {
      if (name != null) {
        malloc.free(namePtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `unsubscribeFromThemes()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::unsubscribeFromThemes()` call and resolves
  /// it later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: optional `String` theme name to stop watching, or `null` for all
  ///   themes.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final unsubscribe-themes result arrives asynchronously
  ///   via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUnsubscribeThemesAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? name,
    required String namespaceSelectorJson,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> namePtr =
        name != null ? name.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeUnsubscribeThemesAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      if (name != null) {
        malloc.free(namePtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `subscribeToCurrentTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::subscribeToCurrentTheme()` call and
  /// resolves it later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final subscribe-current-theme result arrives
  ///   asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSubscribeCurrentThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    required bool includeResolved,
    required bool includeSpec,
    required bool sendImmediately,
  }) {
    return dpeSubscribeCurrentThemeAsync(
      handle,
      requestId,
      includeResolved,
      includeSpec,
      sendImmediately,
    );
  }

  /// Launch an asynchronous native `unsubscribeFromCurrentTheme()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::unsubscribeFromCurrentTheme()` call and
  /// resolves it later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final unsubscribe-current-theme result arrives
  ///   asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUnsubscribeCurrentThemeAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeUnsubscribeCurrentThemeAsync(handle, requestId);
  }

  /// Launch an asynchronous native `setScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::setScale()` call and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [scaleJson]: `String` JSON encoding of a `Scale`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [scaleJson] contains valid `Scale` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final set-scale result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSetScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String scaleJson,
  ) {
    final Pointer<Utf8> scaleJsonPtr = scaleJson.toNativeUtf8();
    try {
      return dpeSetScaleAsync(handle, requestId, scaleJsonPtr);
    } finally {
      malloc.free(scaleJsonPtr);
    }
  }

  /// Launch an asynchronous native `createScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::createScale()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [scaleJson]: `String` JSON encoding of a `Scale`.
  /// - [autoSuffix]: `bool` forwarded to the native create request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [scaleJson] contains valid `Scale` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final create-scale result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeCreateScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String scaleJson, {
    bool autoSuffix = false,
  }) {
    final Pointer<Utf8> scaleJsonPtr = scaleJson.toNativeUtf8();
    try {
      return dpeCreateScaleAsync(handle, requestId, scaleJsonPtr, autoSuffix);
    } finally {
      malloc.free(scaleJsonPtr);
    }
  }

  /// Launch an asynchronous native `updateScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::updateScale()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [scaleJson]: `String` JSON encoding of a `Scale`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [scaleJson] contains valid `Scale` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final update-scale result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUpdateScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String scaleJson,
  ) {
    final Pointer<Utf8> scaleJsonPtr = scaleJson.toNativeUtf8();
    try {
      return dpeUpdateScaleAsync(handle, requestId, scaleJsonPtr);
    } finally {
      malloc.free(scaleJsonPtr);
    }
  }

  /// Launch an asynchronous native `readScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::readScale()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` scale name to read.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final read-scale result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeReadScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeReadScaleAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `deleteScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::deleteScale()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` scale name to delete.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final delete-scale result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeDeleteScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson,
  ) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeDeleteScaleAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `setCurrentScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::setCurrentScale()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` scale name to set current.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final set-current-scale result arrives asynchronously
  ///   via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSetCurrentScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson,
  ) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeSetCurrentScaleAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `readCurrentScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::readCurrentScale()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final read-current-scale result arrives asynchronously
  ///   via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeReadCurrentScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    return dpeReadCurrentScaleAsync(
      handle,
      requestId,
      includeResolved,
      includeSpec,
    );
  }

  /// Launch an asynchronous native `removeCurrentScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::removeCurrentScale()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final remove-current-scale result arrives asynchronously
  ///   via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeRemoveCurrentScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeRemoveCurrentScaleAsync(handle, requestId);
  }

  /// Launch an asynchronous native `listScales()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::listScales()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id used to resolve the
  ///   matching completer.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` passed through to the native request.
  /// - [includeSpec]: `bool` passed through to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final list result arrives asynchronously via the event
  ///   port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeListScalesAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeListScalesAsync(
        handle,
        requestId,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `setLayout()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::setLayout()` call and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [layoutJson]: `String` JSON encoding of a `Layout`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [layoutJson] contains valid `Layout` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final set-layout result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSetLayoutAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String layoutJson,
  ) {
    final Pointer<Utf8> layoutJsonPtr = layoutJson.toNativeUtf8();
    try {
      return dpeSetLayoutAsync(handle, requestId, layoutJsonPtr);
    } finally {
      malloc.free(layoutJsonPtr);
    }
  }

  /// Launch an asynchronous native `createLayout()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::createLayout()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [layoutJson]: `String` JSON encoding of a `Layout`.
  /// - [autoSuffix]: `bool` forwarded to the native create request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [layoutJson] contains valid `Layout` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final create-layout result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeCreateLayoutAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String layoutJson, {
    bool autoSuffix = false,
  }) {
    final Pointer<Utf8> layoutJsonPtr = layoutJson.toNativeUtf8();
    try {
      return dpeCreateLayoutAsync(handle, requestId, layoutJsonPtr, autoSuffix);
    } finally {
      malloc.free(layoutJsonPtr);
    }
  }

  /// Launch an asynchronous native `updateLayout()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::updateLayout()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [layoutJson]: `String` JSON encoding of a `Layout`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [layoutJson] contains valid `Layout` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final update-layout result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUpdateLayoutAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String layoutJson,
  ) {
    final Pointer<Utf8> layoutJsonPtr = layoutJson.toNativeUtf8();
    try {
      return dpeUpdateLayoutAsync(handle, requestId, layoutJsonPtr);
    } finally {
      malloc.free(layoutJsonPtr);
    }
  }

  /// Launch an asynchronous native `readLayout()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::readLayout()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` layout name to read.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final read-layout result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeReadLayoutAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeReadLayoutAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `deleteLayout()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::deleteLayout()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` layout name to delete.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final delete-layout result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeDeleteLayoutAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson,
  ) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeDeleteLayoutAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `listLayouts()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::listLayouts()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` passed through to the native request.
  /// - [includeSpec]: `bool` passed through to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final list-layouts result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeListLayoutsAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeListLayoutsAsync(
        handle,
        requestId,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `setKV()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::setKV()` call and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [kvJson]: `String` JSON encoding of a `KV`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [kvJson] contains valid `KV` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final set-kv result arrives asynchronously via the event
  ///   port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSetKVAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String kvJson,
  ) {
    final Pointer<Utf8> kvJsonPtr = kvJson.toNativeUtf8();
    try {
      return dpeSetKVAsync(handle, requestId, kvJsonPtr);
    } finally {
      malloc.free(kvJsonPtr);
    }
  }

  /// Launch an asynchronous native `createKV()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::createKV()` call and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [kvJson]: `String` JSON encoding of a `KV`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [kvJson] contains valid `KV` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final create-kv result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeCreateKVAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String kvJson,
  ) {
    final Pointer<Utf8> kvJsonPtr = kvJson.toNativeUtf8();
    try {
      return dpeCreateKVAsync(handle, requestId, kvJsonPtr);
    } finally {
      malloc.free(kvJsonPtr);
    }
  }

  /// Launch an asynchronous native `updateKV()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::updateKV()` call and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [kvJson]: `String` JSON encoding of a `KV`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [kvJson] contains valid `KV` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final update-kv result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUpdateKVAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String kvJson,
  ) {
    final Pointer<Utf8> kvJsonPtr = kvJson.toNativeUtf8();
    try {
      return dpeUpdateKVAsync(handle, requestId, kvJsonPtr);
    } finally {
      malloc.free(kvJsonPtr);
    }
  }

  /// Launch an asynchronous native `readKV()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::readKV()` call and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` KV name to read.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final read-kv result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeReadKVAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeReadKVAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `deleteKV()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::deleteKV()` call and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` KV name to delete.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final delete-kv result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeDeleteKVAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson,
  ) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeDeleteKVAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `listKVs()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::listKVs()` call and resolves it later via
  /// the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` passed through to the native request.
  /// - [includeSpec]: `bool` passed through to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final list-kvs result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeListKVsAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeListKVsAsync(
        handle,
        requestId,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `createEndpoint()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::createEndpoint()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [endpointJson]: `String` JSON encoding of an `Endpoint`.
  /// - [autoSuffix]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [endpointJson] contains valid `Endpoint` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final create-endpoint result arrives asynchronously via
  ///   the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeCreateEndpointAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String endpointJson, {
    required bool autoSuffix,
  }) {
    final Pointer<Utf8> endpointJsonPtr = endpointJson.toNativeUtf8();
    try {
      return dpeCreateEndpointAsync(
        handle,
        requestId,
        endpointJsonPtr,
        autoSuffix,
      );
    } finally {
      malloc.free(endpointJsonPtr);
    }
  }

  /// Launch an asynchronous native `updateEndpoint()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::updateEndpoint()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [endpointJson]: `String` JSON encoding of an `Endpoint`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [endpointJson] contains valid `Endpoint` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final update-endpoint result arrives asynchronously via
  ///   the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUpdateEndpointAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String endpointJson,
  ) {
    final Pointer<Utf8> endpointJsonPtr = endpointJson.toNativeUtf8();
    try {
      return dpeUpdateEndpointAsync(handle, requestId, endpointJsonPtr);
    } finally {
      malloc.free(endpointJsonPtr);
    }
  }

  /// Launch an asynchronous native `setEndpoint()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::setEndpoint()` call and resolves it later
  /// via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [endpointJson]: `String` JSON encoding of an `Endpoint`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [endpointJson] contains valid `Endpoint` JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final set-endpoint result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSetEndpointAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String endpointJson,
  ) {
    final Pointer<Utf8> endpointJsonPtr = endpointJson.toNativeUtf8();
    try {
      return dpeSetEndpointAsync(handle, requestId, endpointJsonPtr);
    } finally {
      malloc.free(endpointJsonPtr);
    }
  }

  /// Launch an asynchronous native `readEndpoint()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::readEndpoint()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` endpoint name to read.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final read-endpoint result arrives asynchronously via
  ///   the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeReadEndpointAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeReadEndpointAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `deleteEndpoint()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::deleteEndpoint()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: `String` endpoint name to delete.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final delete-endpoint result arrives asynchronously via
  ///   the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeDeleteEndpointAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
  ) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    try {
      return dpeDeleteEndpointAsync(handle, requestId, namePtr);
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Launch an asynchronous native `searchEndpoints()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::searchEndpoints()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [criteriaJson]: `String` JSON encoding of `SearchCriteria`.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [criteriaJson] contains valid search criteria JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final search-endpoints result arrives asynchronously via
  ///   the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSearchEndpointsAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String criteriaJson,
  ) {
    final Pointer<Utf8> criteriaJsonPtr = criteriaJson.toNativeUtf8();
    try {
      return dpeSearchEndpointsAsync(handle, requestId, criteriaJsonPtr);
    } finally {
      malloc.free(criteriaJsonPtr);
    }
  }

  /// Launch an asynchronous native `createConnectionRequest()` request.
  ///
  /// Purpose:
  /// Starts `DogPawEntity::createConnectionRequest()` and completes via the
  /// registered event port.
  ///
  /// Parameters:
  /// - [handle]: native bridge handle.
  /// - [requestId]: Dart bridge request id.
  /// - [connectionRequestJson]: JSON for one `ConnectionRequest`.
  ///
  /// Return value: whether the native worker was started.
  ///
  /// Requirements/Preconditions: live handle; event port registered.
  ///
  /// Guarantees/Postconditions: result posted asynchronously.
  ///
  /// Invariants: caller isolate not blocked on Epiphany.
  bool dpeCreateConnectionRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String connectionRequestJson,
  ) {
    final Pointer<Utf8> ptr = connectionRequestJson.toNativeUtf8();
    try {
      return dpeCreateConnectionRequestAsync(handle, requestId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Launch an asynchronous native `setConnectionRequest()` request.
  ///
  /// Purpose:
  /// Starts `DogPawEntity::setConnectionRequest()`; completes via event port.
  ///
  /// Parameters:
  /// - [connectionRequestJson]: JSON for one `ConnectionRequest`.
  ///
  /// Return value: whether the native worker was started.
  ///
  /// Requirements/Preconditions: live handle; event port registered.
  ///
  /// Guarantees/Postconditions: result posted asynchronously.
  ///
  /// Invariants: caller isolate not blocked on Epiphany.
  bool dpeSetConnectionRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String connectionRequestJson,
  ) {
    final Pointer<Utf8> ptr = connectionRequestJson.toNativeUtf8();
    try {
      return dpeSetConnectionRequestAsync(handle, requestId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Launch an asynchronous native `updateConnectionRequest()` request.
  ///
  /// Purpose:
  /// Starts `DogPawEntity::updateConnectionRequest()`; completes via event port.
  ///
  /// Parameters:
  /// - [connectionRequestJson]: JSON for one `ConnectionRequest`.
  ///
  /// Return value: whether the native worker was started.
  ///
  /// Requirements/Preconditions: live handle; event port registered.
  ///
  /// Guarantees/Postconditions: result posted asynchronously.
  ///
  /// Invariants: caller isolate not blocked on Epiphany.
  bool dpeUpdateConnectionRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String connectionRequestJson,
  ) {
    final Pointer<Utf8> ptr = connectionRequestJson.toNativeUtf8();
    try {
      return dpeUpdateConnectionRequestAsync(handle, requestId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Launch an asynchronous native `readConnectionRequest()` request.
  ///
  /// Purpose:
  /// Starts `DogPawEntity::readConnectionRequest()`; typed payload in result.
  ///
  /// Return value: whether the native worker was started.
  ///
  /// Requirements/Preconditions: valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions: result posted asynchronously.
  ///
  /// Invariants: caller isolate not blocked on Epiphany.
  bool dpeReadConnectionRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> nsPtr = namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeReadConnectionRequestAsync(
        handle,
        requestId,
        namePtr,
        nsPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(nsPtr);
    }
  }

  /// Launch an asynchronous native `deleteConnectionRequest()` request.
  ///
  /// Purpose:
  /// Starts `DogPawEntity::deleteConnectionRequest()` for [name] in the given
  /// namespace scope.
  ///
  /// Return value: whether the native worker was started.
  ///
  /// Requirements/Preconditions: valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions: result posted asynchronously.
  ///
  /// Invariants: caller isolate not blocked on Epiphany.
  bool dpeDeleteConnectionRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson,
  ) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> nsPtr = namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeDeleteConnectionRequestAsync(
        handle,
        requestId,
        namePtr,
        nsPtr,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(nsPtr);
    }
  }

  /// Launch an asynchronous native `listConnectionRequests()` request.
  ///
  /// Purpose:
  /// Starts `DogPawEntity::listConnectionRequests()`; list in result payload.
  ///
  /// Return value: whether the native worker was started.
  ///
  /// Requirements/Preconditions: valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions: result posted asynchronously.
  ///
  /// Invariants: caller isolate not blocked on Epiphany.
  bool dpeListConnectionRequestsAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> nsPtr = namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeListConnectionRequestsAsync(
        handle,
        requestId,
        nsPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(nsPtr);
    }
  }

  /// Launch an asynchronous native `createFollowRequest()` request.
  ///
  /// Purpose: starts `DogPawEntity::createFollowRequest()`.
  ///
  /// Return value: whether the native worker was started.
  bool dpeCreateFollowRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String followRequestJson,
  ) {
    final Pointer<Utf8> ptr = followRequestJson.toNativeUtf8();
    try {
      return dpeCreateFollowRequestAsync(handle, requestId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Launch an asynchronous native `setFollowRequest()` request.
  ///
  /// Purpose: starts `DogPawEntity::setFollowRequest()`.
  ///
  /// Return value: whether the native worker was started.
  bool dpeSetFollowRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String followRequestJson,
  ) {
    final Pointer<Utf8> ptr = followRequestJson.toNativeUtf8();
    try {
      return dpeSetFollowRequestAsync(handle, requestId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Launch an asynchronous native `updateFollowRequest()` request.
  ///
  /// Purpose: starts `DogPawEntity::updateFollowRequest()`.
  ///
  /// Return value: whether the native worker was started.
  bool dpeUpdateFollowRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String followRequestJson,
  ) {
    final Pointer<Utf8> ptr = followRequestJson.toNativeUtf8();
    try {
      return dpeUpdateFollowRequestAsync(handle, requestId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Launch an asynchronous native `readFollowRequest()` request.
  ///
  /// Purpose: starts `DogPawEntity::readFollowRequest()`; optional item in
  /// result.
  ///
  /// Return value: whether the native worker was started.
  bool dpeReadFollowRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> nsPtr = namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeReadFollowRequestAsync(
        handle,
        requestId,
        namePtr,
        nsPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(nsPtr);
    }
  }

  /// Launch an asynchronous native `deleteFollowRequest()` request.
  ///
  /// Purpose: starts `DogPawEntity::deleteFollowRequest()`.
  ///
  /// Return value: whether the native worker was started.
  bool dpeDeleteFollowRequestAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name,
    String namespaceSelectorJson,
  ) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> nsPtr = namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeDeleteFollowRequestAsync(
        handle,
        requestId,
        namePtr,
        nsPtr,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(nsPtr);
    }
  }

  /// Launch an asynchronous native `listFollowRequests()` request.
  ///
  /// Purpose: starts `DogPawEntity::listFollowRequests()`.
  ///
  /// Return value: whether the native worker was started.
  bool dpeListFollowRequestsAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String namespaceSelectorJson, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> nsPtr = namespaceSelectorJson.toNativeUtf8();
    try {
      return dpeListFollowRequestsAsync(
        handle,
        requestId,
        nsPtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(nsPtr);
    }
  }

  /// Launch an asynchronous native `readConnection()` request.
  ///
  /// Purpose:
  /// Starts `DogPawEntity::readConnection()`; C++ applies global namespace on
  /// the wire.
  ///
  /// Return value: whether the native worker was started.
  bool dpeReadConnectionAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String name, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    try {
      return dpeReadConnectionAsync(
        handle,
        requestId,
        namePtr,
        includeResolved,
        includeSpec,
      );
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Launch an asynchronous native `listConnections()` request.
  ///
  /// Purpose:
  /// Starts `DogPawEntity::listConnections()`; C++ applies global namespace on
  /// the wire.
  ///
  /// Return value: whether the native worker was started.
  bool dpeListConnectionsAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    return dpeListConnectionsAsync(
      handle,
      requestId,
      includeResolved,
      includeSpec,
    );
  }

  /// Launch an asynchronous native `subscribeToScales()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::subscribeToScales()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: optional `String` scale name to watch, or `null` for all scales.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final subscribe-scales result arrives asynchronously via
  ///   the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSubscribeScalesAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? name,
    required String namespaceSelectorJson,
    required bool includeResolved,
    required bool includeSpec,
    required bool sendImmediately,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> namePtr =
        name != null ? name.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeSubscribeScalesAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
        sendImmediately,
      );
    } finally {
      if (name != null) {
        malloc.free(namePtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `unsubscribeFromScales()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::unsubscribeFromScales()` call and
  /// resolves it later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: optional `String` scale name to stop watching, or `null` for all
  ///   scales.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final unsubscribe-scales result arrives asynchronously
  ///   via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUnsubscribeScalesAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? name,
    required String namespaceSelectorJson,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> namePtr =
        name != null ? name.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeUnsubscribeScalesAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      if (name != null) {
        malloc.free(namePtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `subscribeToCurrentScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::subscribeToCurrentScale()` call and
  /// resolves it later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final subscribe-current-scale result arrives
  ///   asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSubscribeCurrentScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    required bool includeResolved,
    required bool includeSpec,
    required bool sendImmediately,
  }) {
    return dpeSubscribeCurrentScaleAsync(
      handle,
      requestId,
      includeResolved,
      includeSpec,
      sendImmediately,
    );
  }

  /// Launch an asynchronous native `unsubscribeFromCurrentScale()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::unsubscribeFromCurrentScale()` call and
  /// resolves it later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final unsubscribe-current-scale result arrives
  ///   asynchronously via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUnsubscribeCurrentScaleAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeUnsubscribeCurrentScaleAsync(handle, requestId);
  }

  /// Launch an asynchronous native `subscribeToLayouts()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::subscribeToLayouts()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: optional `String` layout name to watch, or `null` for all
  ///   layouts.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final subscribe-layouts result arrives asynchronously via
  ///   the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSubscribeLayoutsAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? name,
    required String namespaceSelectorJson,
    required bool includeResolved,
    required bool includeSpec,
    required bool sendImmediately,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> namePtr =
        name != null ? name.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeSubscribeLayoutsAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
        sendImmediately,
      );
    } finally {
      if (name != null) {
        malloc.free(namePtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `unsubscribeFromLayouts()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::unsubscribeFromLayouts()` call and
  /// resolves it later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [name]: optional `String` layout name to stop watching, or `null` for
  ///   all layouts.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final unsubscribe-layouts result arrives asynchronously
  ///   via the event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUnsubscribeLayoutsAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? name,
    required String namespaceSelectorJson,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> namePtr =
        name != null ? name.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeUnsubscribeLayoutsAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      if (name != null) {
        malloc.free(namePtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `addLayoutStackEntry()` request.
  bool dpeAddLayoutStackEntryAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String layoutRefJson, {
    int? index,
  }) {
    final Pointer<Utf8> layoutRefPtr = layoutRefJson.toNativeUtf8();
    try {
      return dpeAddLayoutStackEntryAsync(
        handle,
        requestId,
        layoutRefPtr,
        index != null,
        index ?? 0,
      );
    } finally {
      malloc.free(layoutRefPtr);
    }
  }

  /// Launch an asynchronous native `removeLayoutStackEntry()` request.
  bool dpeRemoveLayoutStackEntryAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String entryId,
  ) {
    final Pointer<Utf8> entryIdPtr = entryId.toNativeUtf8();
    try {
      return dpeRemoveLayoutStackEntryAsync(handle, requestId, entryIdPtr);
    } finally {
      malloc.free(entryIdPtr);
    }
  }

  /// Launch an asynchronous native `moveLayoutStackEntry()` request.
  bool dpeMoveLayoutStackEntryAsyncManaged(
    Pointer<Void> handle,
    int requestId,
    String entryId,
    int newIndex,
  ) {
    final Pointer<Utf8> entryIdPtr = entryId.toNativeUtf8();
    try {
      return dpeMoveLayoutStackEntryAsync(
        handle,
        requestId,
        entryIdPtr,
        newIndex,
      );
    } finally {
      malloc.free(entryIdPtr);
    }
  }

  /// Launch an asynchronous native `readLayoutStack()` request.
  bool dpeReadLayoutStackAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    required bool includeResolved,
    required bool includeSpec,
  }) {
    return dpeReadLayoutStackAsync(
      handle,
      requestId,
      includeResolved,
      includeSpec,
    );
  }

  /// Launch an asynchronous native `subscribeToLayoutStack()` request.
  bool dpeSubscribeLayoutStackAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    required bool includeResolved,
    required bool includeSpec,
    required bool sendImmediately,
  }) {
    return dpeSubscribeLayoutStackAsync(
      handle,
      requestId,
      includeResolved,
      includeSpec,
      sendImmediately,
    );
  }

  /// Launch an asynchronous native `unsubscribeFromLayoutStack()` request.
  bool dpeUnsubscribeLayoutStackAsyncManaged(
    Pointer<Void> handle,
    int requestId,
  ) {
    return dpeUnsubscribeLayoutStackAsync(handle, requestId);
  }

  /// Launch an asynchronous native `subscribeToKV()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::subscribeToKV()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [key]: optional `String` KV key to watch, or `null` for all keys.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  /// - [includeResolved]: `bool` forwarded to the native request.
  /// - [includeSpec]: `bool` forwarded to the native request.
  /// - [sendImmediately]: `bool` forwarded to the native request.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final subscribe-kv result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeSubscribeKVAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? key,
    required String namespaceSelectorJson,
    required bool includeResolved,
    required bool includeSpec,
    required bool sendImmediately,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> keyPtr =
        key != null ? key.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeSubscribeKVAsync(
        handle,
        requestId,
        keyPtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
        sendImmediately,
      );
    } finally {
      if (key != null) {
        malloc.free(keyPtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `unsubscribeFromKV()` request.
  ///
  /// Purpose:
  /// Starts the native `DogPawEntity::unsubscribeFromKV()` call and resolves it
  /// later via the registered Dart event port.
  ///
  /// Parameters:
  /// - [handle]: `Pointer<Void>` native bridge handle.
  /// - [requestId]: `int` Dart-side bridge request id.
  /// - [key]: optional `String` KV key to stop watching, or `null` for all keys.
  /// - [namespaceSelectorJson]: `String` JSON encoding of a namespace selector.
  ///
  /// Return value:
  /// - `bool` indicating whether the native request was launched.
  ///
  /// Requirements/Preconditions:
  /// - [handle] is a live bridge handle with an event port already registered.
  /// - [namespaceSelectorJson] contains valid namespace-selector JSON.
  ///
  /// Guarantees/Postconditions:
  /// - On success, the final unsubscribe-kv result arrives asynchronously via the
  ///   event port.
  ///
  /// Invariants:
  /// - The Dart isolate thread is not blocked waiting for the server response.
  bool dpeUnsubscribeKVAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? key,
    required String namespaceSelectorJson,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> keyPtr =
        key != null ? key.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeUnsubscribeKVAsync(
        handle,
        requestId,
        keyPtr,
        namespaceSelectorPtr,
      );
    } finally {
      if (key != null) {
        malloc.free(keyPtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `subscribeToEndpoints()` request.
  ///
  /// Returns whether the native request was launched successfully.
  bool dpeSubscribeEndpointsAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? name,
    required String namespaceSelectorJson,
    required bool includeResolved,
    required bool includeSpec,
    required bool sendImmediately,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> namePtr =
        name != null ? name.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeSubscribeEndpointsAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
        includeResolved,
        includeSpec,
        sendImmediately,
      );
    } finally {
      if (name != null) {
        malloc.free(namePtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Launch an asynchronous native `unsubscribeFromEndpoints()` request.
  ///
  /// Returns whether the native request was launched successfully.
  bool dpeUnsubscribeEndpointsAsyncManaged(
    Pointer<Void> handle,
    int requestId, {
    String? name,
    required String namespaceSelectorJson,
  }) {
    final Pointer<Utf8> namespaceSelectorPtr =
        namespaceSelectorJson.toNativeUtf8();
    final Pointer<Utf8> namePtr =
        name != null ? name.toNativeUtf8() : nullptr.cast<Utf8>();
    try {
      return dpeUnsubscribeEndpointsAsync(
        handle,
        requestId,
        namePtr,
        namespaceSelectorPtr,
      );
    } finally {
      if (name != null) {
        malloc.free(namePtr);
      }
      malloc.free(namespaceSelectorPtr);
    }
  }

  /// Write serialized bytes through a native-owned local endpoint.
  ///
  /// [endpointName] identifies the owned endpoint within the current entity.
  /// [data] points at serialized endpoint payload bytes.
  /// [size] is the number of readable bytes at [data].
  /// [immediate] controls message-queue flush behavior.
  ///
  /// Returns true when the native endpoint accepted the payload.
  bool dpeLocalEndpointWriteManaged(
    Pointer<Void> handle, {
    required String endpointName,
    required Pointer<Void> data,
    required int size,
    required bool immediate,
  }) {
    final Pointer<Utf8> endpointNamePtr = endpointName.toNativeUtf8();
    try {
      return dpeLocalEndpointWrite(
        handle,
        endpointNamePtr,
        data,
        size,
        immediate,
      );
    } finally {
      malloc.free(endpointNamePtr);
    }
  }

  /// Count realized native input connections for one local endpoint.
  ///
  /// Returns a non-negative count on success, or -1 on error.
  int dpeLocalEndpointGetConnectionCountManaged(
    Pointer<Void> handle, {
    required String endpointName,
  }) {
    final Pointer<Utf8> endpointNamePtr = endpointName.toNativeUtf8();
    try {
      return dpeLocalEndpointGetConnectionCount(handle, endpointNamePtr);
    } finally {
      malloc.free(endpointNamePtr);
    }
  }

  /// Read one realized connection name from the native endpoint runtime.
  ///
  /// Returns the required buffer size including the null terminator, or -1 on
  /// error. When [outName] is non-null and [maxSize] is large enough, the name
  /// is written to the provided buffer.
  int dpeLocalEndpointGetConnectionNameManaged(
    Pointer<Void> handle, {
    required String endpointName,
    required int index,
    Pointer<Utf8>? outName,
    required int maxSize,
  }) {
    final Pointer<Utf8> endpointNamePtr = endpointName.toNativeUtf8();
    try {
      return dpeLocalEndpointGetConnectionName(
        handle,
        endpointNamePtr,
        index,
        outName ?? nullptr.cast<Utf8>(),
        maxSize,
      );
    } finally {
      malloc.free(endpointNamePtr);
    }
  }

  /// Query the current payload shape for one realized native input connection.
  ///
  /// Returns true on success and fills the provided output pointers.
  bool dpeLocalEndpointGetConnectionShapeManaged(
    Pointer<Void> handle, {
    required String endpointName,
    required String connectionName,
    required Pointer<Int32> outIndexType,
    required Pointer<Int32> outIndexDim1,
    required Pointer<Int32> outIndexDim2,
    required Pointer<Int32> outPayloadSize,
  }) {
    final Pointer<Utf8> endpointNamePtr = endpointName.toNativeUtf8();
    final Pointer<Utf8> connectionNamePtr = connectionName.toNativeUtf8();
    try {
      return dpeLocalEndpointGetConnectionShape(
        handle,
        endpointNamePtr,
        connectionNamePtr,
        outIndexType,
        outIndexDim1,
        outIndexDim2,
        outPayloadSize,
      );
    } finally {
      malloc.free(endpointNamePtr);
      malloc.free(connectionNamePtr);
    }
  }

  /// Poll one realized native input connection into a caller-owned buffer.
  ///
  /// Returns bytes written to [outData], `0` when no payload is available, or
  /// `-1` on error.
  int dpeLocalEndpointPollConnectionManaged(
    Pointer<Void> handle, {
    required String endpointName,
    required String connectionName,
    required Pointer<Void> outData,
    required int maxSize,
  }) {
    final Pointer<Utf8> endpointNamePtr = endpointName.toNativeUtf8();
    final Pointer<Utf8> connectionNamePtr = connectionName.toNativeUtf8();
    try {
      return dpeLocalEndpointPollConnection(
        handle,
        endpointNamePtr,
        connectionNamePtr,
        outData,
        maxSize,
      );
    } finally {
      malloc.free(endpointNamePtr);
      malloc.free(connectionNamePtr);
    }
  }

  /// Read one realized native file-backed connection into a caller-owned
  /// buffer, or query the required size when [outData] is null.
  ///
  /// Returns a positive byte count on success, `0` when no readable contents
  /// are available, or `-1` on error.
  int dpeLocalEndpointReadFileBackedManaged(
    Pointer<Void> handle, {
    required String endpointName,
    required String connectionName,
    Pointer<Void>? outData,
    required int maxSize,
  }) {
    final Pointer<Utf8> endpointNamePtr = endpointName.toNativeUtf8();
    final Pointer<Utf8> connectionNamePtr = connectionName.toNativeUtf8();
    try {
      return dpeLocalEndpointReadFileBacked(
        handle,
        endpointNamePtr,
        connectionNamePtr,
        outData ?? nullptr,
        maxSize,
      );
    } finally {
      malloc.free(endpointNamePtr);
      malloc.free(connectionNamePtr);
    }
  }

  /// Poll one realized native file-backed connection and read the changed file
  /// contents into a caller-owned buffer, or query the required size when
  /// [outData] is null.
  ///
  /// Returns a positive byte count when a change was observed and read
  /// successfully, `0` when no change is available, or `-1` on error.
  int dpeLocalEndpointPollFileBackedManaged(
    Pointer<Void> handle, {
    required String endpointName,
    required String connectionName,
    Pointer<Void>? outData,
    required int maxSize,
  }) {
    final Pointer<Utf8> endpointNamePtr = endpointName.toNativeUtf8();
    final Pointer<Utf8> connectionNamePtr = connectionName.toNativeUtf8();
    try {
      return dpeLocalEndpointPollFileBacked(
        handle,
        endpointNamePtr,
        connectionNamePtr,
        outData ?? nullptr,
        maxSize,
      );
    } finally {
      malloc.free(endpointNamePtr);
      malloc.free(connectionNamePtr);
    }
  }

  //===========================================================================
  // ENVIRONMENT VARIABLE MANIPULATION
  // Uses libc setenv() via DynamicLibrary.process() — no custom C code needed.
  // This modifies the real process environment, so child processes inherit
  // the changes. Dart's Platform.environment is a snapshot and won't reflect
  // these changes — use DogPawEntity static overrides for in-process access.
  //===========================================================================

  /// Set an environment variable in the process environment.
  /// Child processes (e.g. Epiphany spawned via spawnWithDeathSignal) will
  /// inherit this value. Does NOT affect Dart's Platform.environment snapshot.
  ///
  /// [key] - Environment variable name (e.g. "DOGPAW_RUNTIME_DIR")
  /// [value] - Value to set
  /// [overwrite] - If true (default), overwrites existing values
  ///
  /// Returns 0 on success, -1 on error.
  static int setEnv(String key, String value, {bool overwrite = true}) {
    final setenvFunc = DynamicLibrary.process().lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)>('setenv');

    final keyPtr = key.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    try {
      return setenvFunc(keyPtr, valuePtr, overwrite ? 1 : 0);
    } finally {
      malloc.free(keyPtr);
      malloc.free(valuePtr);
    }
  }
}
