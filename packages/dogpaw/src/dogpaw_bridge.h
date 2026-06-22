#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

//=============================================================================
// CONTINUOUS (Shared Data)
// Used by: DogPawEntity endpoints with CONTINUOUS category
//=============================================================================

// Create a shared data writer
void *dppb_shared_writer_create(const char *name, int size, const char *namespace_prefix);

// Create a shared data reader
void *dppb_shared_reader_create(const char *name, const char *namespace_prefix);

// Write data to shared memory
bool dppb_shared_write(void *handle, const void *data, int size);

// Read data from shared memory
// Returns true if successful
bool dppb_shared_read(void *handle, void *out_data, int size);

// Destroy shared writer/reader
void dppb_shared_destroy(void *handle);

// Adjust buffer size for shared writer (delta can be positive or negative)
// Only valid for writer handles, returns false for readers or on error
bool dppb_shared_writer_adjust_buffer_size(void *handle, int delta_buffer_size);

//=============================================================================
// MESSAGE QUEUES (Discrete)
// Used by: DogPawEntity endpoints with MESSAGE_QUEUE category
//=============================================================================

// Data types matching C++ DataType enum (order must match EndpointData.hpp)
enum {
  DPPB_TYPE_FLOAT = 0,
  DPPB_TYPE_FLOAT2,
  DPPB_TYPE_FLOAT3,
  DPPB_TYPE_FLOAT4,
  DPPB_TYPE_INT,
  DPPB_TYPE_INT2,
  DPPB_TYPE_TOGGLE,
  DPPB_TYPE_MOMENTARY,
  DPPB_TYPE_ENUM,
  DPPB_TYPE_COLOR,
  DPPB_TYPE_AUDIO_STREAM,
  DPPB_TYPE_KEY_PRESS,
  DPPB_TYPE_NEAR_PRESS,
  DPPB_TYPE_RAW_SENSORS,
  DPPB_TYPE_NOTE_CONTROL,
  DPPB_TYPE_MIDI_MESSAGE,
  DPPB_TYPE_LED_MESSAGE,
  DPPB_TYPE_KEY_POSITION,
  DPPB_TYPE_VOICE_MESSAGE,
  DPPB_TYPE_VOICE_OUTPUT_VALUE,
  DPPB_TYPE_GLOBAL_OUTPUT_VALUE,
  DPPB_TYPE_DPP_EDITOR_MESSAGE,
  DPPB_TYPE_CUSTOM,
  DPPB_TYPE_SCOPE_BUFFER
};

// Index types matching C++ IndexType enum
enum { DPPB_INDEX_NONE = 0, DPPB_INDEX_KEY, DPPB_INDEX_VOICE, DPPB_INDEX_CUSTOM };

// Create a producer
void *dppb_producer_create(const char *queue_name, const char *socket_name, int data_type_idx, int index_type_idx);

// Enqueue data
// Returns number of consumers notified (>=0), or negative for errors:
//   -1: not connected to shared memory
//   -3: invalid handle
int dppb_producer_enqueue(void *handle, const void *data);

// Create a consumer
void *dppb_consumer_create(const char *queue_name, const char *socket_name, int data_type_idx, int index_type_idx);

// Poll for data
// Returns number of bytes read (0 if no data)
// max_size is the size of the out_buffer
int dppb_consumer_poll(void *handle, void *out_buffer, int max_size);

// Destroy producer/consumer
void dppb_endpoint_destroy(void *handle);

//=============================================================================
// UTILITIES
// Used by: Internal calculations for data sizes
//=============================================================================

// Get the size of the data structure for a given type index with dimensions
// For KEY index: dim1=width, dim2=height
// For VOICE index: dim1=numVoices, dim2=unused
// For NONE index: dimensions ignored
int dppb_get_data_size(int data_type_idx, int index_type_idx, int index_dim1, int index_dim2);

//=============================================================================
// SERVER DETECTION (flock-based)
// Used by: DogPawEntity (connection), Test Infrastructure (server lifecycle)
//=============================================================================

// Check if Epiphany server is running by testing flock on port file
// Returns: port number (>0) if running, 0 if not running, -1 on file error, -2 on lock error
int dppb_check_server_running(const char *port_file_path);

// Wait for server to become ready (polls with flock check)
// Returns: port number (>0) if ready, 0 on timeout, -1 on error
int dppb_wait_for_server(const char *port_file_path, int timeout_ms);

//=============================================================================
// PROCESS MANAGEMENT
// Used by: Test Infrastructure (spawning Epiphany with auto-cleanup)
//=============================================================================

// Spawn process with PR_SET_PDEATHSIG so it auto-terminates when parent dies
// argv must be null-terminated array, argv[0] should be program name
// log_path: if not NULL, stdout/stderr are redirected to this file (matching C++ test behavior)
// Returns: child PID (>0) on success, -1 on fork error, -2 on exec error
int dppb_spawn_with_death_signal(const char *program, const char **argv, int death_signal, const char *log_path);

// Send signal to process
// Returns: 0 on success, -1 on error
int dppb_kill_process(int pid, int signal_num);

// Wait for process to exit with timeout
// Returns: exit status (>=0) if exited, -1 on error, -2 on timeout
int dppb_wait_process(int pid, int timeout_ms);

// Check if process is still running
// Returns: 1 if running, 0 if not running, -1 on error
int dppb_is_process_running(int pid);

//=============================================================================
// SIGNAL CONSTANTS
// Linux signal numbers for use with process management functions
//=============================================================================

#define DPPB_SIGTERM 15
#define DPPB_SIGKILL 9
#define DPPB_SIGINT 2

//=============================================================================
// NATIVE DOGPAWENTITY BRIDGE
// Used by: Phase 2 Dart->C++ DogPawEntity migration
//=============================================================================

/**
 * @brief Initialize the dynamically linked Dart API for async native posting.
 *
 * Purpose:
 * Binds the `dart_api_dl.h` function table so this bridge library can post
 * asynchronous request results and error events back to Dart.
 *
 * @param initialize_api_data Opaque pointer from `NativeApi.initializeApiDLData`.
 * @return `0` on success, non-zero on initialization failure.
 *
 * @pre `initialize_api_data` came from the currently running Dart VM.
 * @post On success, `_DL` API functions such as `Dart_PostCObject_DL` are ready
 *   for use.
 * @invariant This function does not create or destroy any DogPawEntity bridge
 *   handles.
 */
int64_t dppb_initialize_dart_api(void* initialize_api_data);

/**
 * @brief Create a native-backed DogPawEntity bridge wrapper.
 *
 * Purpose:
 * Allocates a wrapper that owns a real C++ `dogpaw::DogPawEntity` instance and
 * exposes it through an opaque C handle for Dart FFI.
 *
 * @param entity_name UTF-8 entity name for the wrapped DogPawEntity.
 * @param server_url UTF-8 websocket URL, or null to use the default localhost
 *   endpoint with runtime port discovery.
 * @param timeout_ms Default native request timeout in milliseconds.
 * @return Opaque handle pointer on success, or null on failure.
 *
 * @pre `entity_name` points to a valid null-terminated UTF-8 string.
 * @pre `timeout_ms` is zero or positive.
 * @post On success, the returned handle owns a live native DogPawEntity bridge.
 * @invariant The returned handle must eventually be released with
 *   `dppb_dpe_destroy()`.
 */
void* dppb_dpe_create(const char* entity_name, const char* server_url, int32_t timeout_ms);

/**
 * @brief Destroy a native-backed DogPawEntity bridge wrapper.
 *
 * Purpose:
 * Releases the wrapped C++ entity, joins request waiter threads, and frees the
 * opaque handle allocated by `dppb_dpe_create()`.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @return None.
 *
 * @pre `handle` is either null or a live handle created by
 *   `dppb_dpe_create()`.
 * @post If `handle` was live, its resources are released.
 * @invariant Calling with null is a no-op.
 */
void dppb_dpe_destroy(void* handle);

/**
 * @brief Register the Dart event port used for async bridge envelopes.
 *
 * Purpose:
 * Stores the Dart `ReceivePort` handle that should receive request-result and
 * error envelopes emitted by the native bridge.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param port Native Dart port identifier from a `ReceivePort`.
 * @return `true` if the port was stored successfully, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle.
 * @pre `port` refers to an open Dart `ReceivePort`.
 * @post On success, future async native events target `port`.
 * @invariant This function does not connect the entity or launch any request.
 */
bool dppb_dpe_set_event_port(void* handle, int64_t port);

/**
 * @brief Launch an asynchronous native-backed connect request.
 *
 * Purpose:
 * Starts the wrapped C++ `connect()` flow on a native waiter thread and later
 * posts the final result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param auto_reconnect Whether the wrapped C++ entity should auto-reconnect.
 * @return `true` if the connect worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async connect result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the server
 *   response.
 */
bool dppb_dpe_connect_async(void* handle, int64_t request_id);

/**
 * @brief Complete the pending native connection-start handle.
 *
 * Purpose:
 * Mirrors the existing ready-handle contract by letting Dart explicitly tell
 * the wrapped C++ entity to send either `READY` or `ERROR`.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param ready_message_type Integer enum value where `0` means ready and `1`
 *   means error.
 * @return `true` if a pending connection-start handle existed and was
 *   completed, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle.
 * @post On success, the stored pending connection-start handle is consumed and
 *   its ready/error message is sent once.
 * @invariant Completing the handle clears the stored pending ready state.
 */
bool dppb_dpe_complete_connection_start(void* handle, int32_t ready_message_type);

/**
 * @brief Disconnect the wrapped native DogPawEntity immediately.
 *
 * Purpose:
 * Exposes the native `disconnect()` call through the bridge.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @return None.
 *
 * @pre `handle` is either null or a live bridge handle.
 * @post If connected, the wrapped native entity is disconnected and pending
 *   native requests are cancelled by the underlying C++ implementation.
 * @invariant Calling with null is a no-op.
 */
void dppb_dpe_disconnect(void* handle);

/**
 * @brief Query the wrapped native connection state synchronously.
 *
 * Purpose:
 * Returns the wrapped C++ entity's current `isConnected()` value for Dart-side
 * lifecycle assertions.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @return `true` if the wrapped entity currently reports connected, otherwise
 *   `false`.
 *
 * @pre `handle` is either null or a live bridge handle.
 * @post Returns the current native connection state snapshot.
 * @invariant Calling with null returns `false`.
 */
bool dppb_dpe_is_connected(void* handle);

/**
 * @brief Launch an asynchronous native-backed `subscribeToEntityLifecycle()`
 * request.
 *
 * Purpose:
 * Registers a native entity-lifecycle subscription through the wrapped C++
 * `subscribeToEntityLifecycle()` API and posts the success/error result back to
 * Dart. Subsequent entity lifecycle notifications are posted separately on the
 * same event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param entity_name Optional entity name filter, or null for all entities.
 * @param send_immediately Whether currently connected matching entities should
 *   be emitted immediately after subscribing.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async subscribe-entity-lifecycle result will be posted
 *   to Dart.
 * @post Later entity lifecycle notifications may be posted until unsubscribed
 *   or destroyed.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_subscribe_entity_lifecycle_async(void* handle,
                                               int64_t request_id,
                                               const char* entity_name,
                                               bool send_immediately);

/**
 * @brief Launch an asynchronous native-backed
 * `unsubscribeFromEntityLifecycle()` request.
 *
 * Purpose:
 * Removes a native entity-lifecycle subscription through the wrapped C++
 * `unsubscribeFromEntityLifecycle()` API and posts the success/error result
 * back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param entity_name Optional entity name filter, or null for the all-entities
 *   subscription.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async unsubscribe-entity-lifecycle result will be
 *   posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_unsubscribe_entity_lifecycle_async(void* handle,
                                                 int64_t request_id,
                                                 const char* entity_name);

/**
 * @brief Launch an asynchronous native-backed `sendDirectMessage()` request.
 *
 * Purpose:
 * Routes one direct message through the wrapped C++ `sendDirectMessage()` API
 * and posts the success/error result back to Dart through the registered event
 * port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param target_entity UTF-8 target entity name.
 * @param message_json JSON string encoding the message payload object.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `target_entity` points to a non-empty UTF-8 string.
 * @pre `message_json` contains valid JSON object text.
 * @post On success, one async direct-message send result will be posted to
 *   Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_send_direct_message_async(void* handle,
                                        int64_t request_id,
                                        const char* target_entity,
                                        const char* message_json);

/**
 * @brief Launch an asynchronous native-backed `sendCommand()` request.
 *
 * Purpose:
 * Routes one command through the wrapped C++ `sendCommand()` API, posts any
 * intermediate accepted notifications back to Dart, and finally posts the
 * completed/error result through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used both for accepted events
 *   and the final result envelope.
 * @param target_entity UTF-8 target entity name.
 * @param command UTF-8 command name.
 * @param params_json JSON string encoding the command params object.
 * @param timeout_ms Timeout in milliseconds for the underlying C++ command
 *   request.
 * @param wait_for_completion Whether the native command should wait for a
 *   completed/error response instead of returning on routing success.
 * @param delivery_policy_json Optional JSON string encoding a command delivery
 *   policy, or null for default routing.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `target_entity` and `command` point to non-empty UTF-8 strings.
 * @pre `params_json` contains valid JSON object text.
 * @pre `timeout_ms` is zero or positive.
 * @post On success, one async command result will be posted to Dart.
 * @post If the target acknowledges with `accepted`, a separate accepted event
 *   may be posted before the final result.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_send_command_async(void* handle,
                                 int64_t request_id,
                                 const char* target_entity,
                                 const char* command,
                                 const char* params_json,
                                 int32_t timeout_ms,
                                 bool wait_for_completion,
                                 const char* delivery_policy_json);

/**
 * @brief Send a native-backed `sendCommandResponse()` message immediately.
 *
 * Purpose:
 * Forwards a completed/error command response through the wrapped C++
 * `sendCommandResponse()` API without waiting for a server acknowledgement.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param target_entity UTF-8 entity name that originally sent the command.
 * @param command_id UTF-8 command correlation id from the incoming command.
 * @param success Whether the command completed successfully.
 * @param result_json Optional JSON string encoding the result payload object, or
 *   null for `{}`.
 * @param error_message Optional UTF-8 error message, or null for empty.
 * @return `true` if the response was forwarded to the wrapped C++ entity,
 *   otherwise `false`.
 *
 * @pre `handle` is a live bridge handle.
 * @pre `target_entity` and `command_id` point to non-empty UTF-8 strings.
 * @pre `result_json`, when non-null, contains valid JSON object text.
 * @post On success, the wrapped C++ entity has attempted to send the response.
 * @invariant This helper does not allocate a Dart-side async request id.
 */
bool dppb_dpe_send_command_response(void* handle,
                                    const char* target_entity,
                                    const char* command_id,
                                    bool success,
                                    const char* result_json,
                                    const char* error_message);

/**
 * @brief Send a native-backed `sendCommandAccepted()` message immediately.
 *
 * Purpose:
 * Forwards an accepted acknowledgement through the wrapped C++
 * `sendCommandAccepted()` API without waiting for a server acknowledgement.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param target_entity UTF-8 entity name that originally sent the command.
 * @param command_id UTF-8 command correlation id from the incoming command.
 * @return `true` if the accepted message was forwarded to the wrapped C++
 *   entity, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle.
 * @pre `target_entity` and `command_id` point to non-empty UTF-8 strings.
 * @post On success, the wrapped C++ entity has attempted to send the accepted
 *   message.
 * @invariant This helper does not allocate a Dart-side async request id.
 */
bool dppb_dpe_send_command_accepted(void* handle,
                                    const char* target_entity,
                                    const char* command_id);

/**
 * @brief Complete one deferred native-backed preset request immediately.
 *
 * Purpose:
 * Forwards the final success/error result for a preset request that was
 * previously deferred by the wrapped C++ `setPresetRequestCallback()` flow.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param server_request_id UTF-8 preset request correlation id from Epiphany.
 * @param success Whether the preset request finished successfully.
 * @param error_message Optional UTF-8 error message, or null for empty.
 * @return `true` if the completion was forwarded to the wrapped C++ entity,
 *   otherwise `false`.
 *
 * @pre `handle` is a live bridge handle.
 * @pre `server_request_id` points to a non-empty UTF-8 string.
 * @post On success, the wrapped C++ entity has attempted to complete the preset
 *   request exactly once.
 * @invariant This helper does not allocate a Dart-side async request id.
 */
bool dppb_dpe_complete_preset_request(void* handle,
                                      const char* server_request_id,
                                      bool success,
                                      const char* error_message);

/**
 * @brief Launch the native dispatcher-order probe used by bridge integration
 * tests.
 *
 * Purpose:
 * Starts a bridge-local synthetic event scenario that integration tests use to
 * distinguish direct multi-threaded Dart posting from a single dispatcher
 * queue.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @return `true` if the probe worker threads were launched successfully,
 *   otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, synthetic debug-probe events will be posted back to Dart.
 * @invariant This helper is intended only for bridge integration tests.
 */
bool dppb_dpe_debug_run_dispatcher_order_probe(void* handle);

/**
 * @brief Run the native shutdown-drain probe used by bridge integration tests.
 *
 * Purpose:
 * Exercises native bridge shutdown while a synthetic event should already
 * belong to the bridge, letting integration tests verify whether teardown
 * drains accepted work before returning.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @return `true` if the probe ran successfully, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, the bridge shutdown path has completed before return.
 * @invariant This helper is intended only for bridge integration tests.
 */
bool dppb_dpe_debug_run_shutdown_drain_probe(void* handle);

/**
 * @brief Launch an asynchronous native-backed `saveGlobalState()` request.
 *
 * Purpose:
 * Routes a preset-save request through the wrapped C++ `saveGlobalState()` API
 * and posts the final success/error result back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param preset_name UTF-8 preset name to save.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `preset_name` points to a valid preset name string.
 * @post On success, one async save-global-state result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_save_global_state_async(void* handle,
                                      int64_t request_id,
                                      const char* preset_name);

/**
 * @brief Launch an asynchronous native-backed `loadGlobalState()` request.
 *
 * Purpose:
 * Routes a preset-load request through the wrapped C++ `loadGlobalState()` API
 * and posts the final success/error result back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param preset_name UTF-8 preset name to load.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `preset_name` points to a valid preset name string.
 * @post On success, one async load-global-state result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_load_global_state_async(void* handle,
                                      int64_t request_id,
                                      const char* preset_name);

/**
 * @brief Launch an asynchronous native-backed `log()` request.
 *
 * Purpose:
 * Routes a utility log message through the wrapped C++ `log()` API and posts
 * the final success/error result back to Dart through the registered event
 * port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param message UTF-8 log message to forward to Epiphany.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_log_async(void* handle, int64_t request_id, const char* message);

/**
 * @brief Launch an asynchronous native-backed `startLogSection()` request.
 *
 * Purpose:
 * Routes a buffered-log-section start request through the wrapped C++
 * `startLogSection()` API and posts the final success/error result back to
 * Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param section_title UTF-8 optional section title string.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_start_log_section_async(void* handle,
                                      int64_t request_id,
                                      const char* section_title);

/**
 * @brief Launch an asynchronous native-backed `flushLogSection()` request.
 *
 * Purpose:
 * Routes a buffered-log-section flush request through the wrapped C++
 * `flushLogSection()` API and posts the final success/error result back to Dart
 * through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_flush_log_section_async(void* handle, int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `endLogSection()` request.
 *
 * Purpose:
 * Routes a buffered-log-section end request through the wrapped C++
 * `endLogSection()` API and posts the final success/error result back to Dart
 * through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param flush Whether buffered logs should be printed before ending the
 *   section.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_end_log_section_async(void* handle,
                                    int64_t request_id,
                                    bool flush);

/**
 * @brief Launch an asynchronous native-backed `getSystemInfo()` request.
 *
 * Purpose:
 * Routes a system-info request through the wrapped C++ `getSystemInfo()` API
 * and posts the final success/error result back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_get_system_info_async(void* handle, int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `listApps()` request.
 *
 * Purpose:
 * Routes an app-list request through the wrapped C++ `listApps()` API and posts
 * Epiphany's launcher-owned app metadata back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_list_apps_async(void* handle, int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `listRunningEntities()` request.
 *
 * Purpose:
 * Routes a runtime-entity-list request through the wrapped C++
 * `listRunningEntities()` API and posts the currently running entity metadata
 * back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_list_running_entities_async(void* handle, int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `launchApp()` request.
 *
 * Purpose:
 * Routes an app-launch request through the wrapped C++ `launchApp()` API and
 * posts the runtime entity name (or error) back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param app_name UTF-8 app template name.
 * @param launch_metadata_json Optional UTF-8 JSON object to pass as launch
 *   metadata. Pass `nullptr` or an empty string to launch without metadata.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * On success, the `result` payload contains `entityName` with the runtime
 * entity name assigned by Epiphany (singleton apps: stable manifest name;
 * multi-instance apps: generated per-instance name).
 */
bool dppb_dpe_launch_app_async(void* handle,
                               int64_t request_id,
                               const char* app_name,
                               const char* launch_metadata_json);

/**
 * @brief Launch an asynchronous native-backed `stopApp()` request.
 *
 * Purpose:
 * Routes an app-stop request through the wrapped C++ `stopApp()` API and posts
 * the final success/error result back to Dart through the registered event
 * port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param app_name UTF-8 app name string.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_stop_app_async(void* handle,
                             int64_t request_id,
                             const char* app_name);

/**
 * @brief Launch an asynchronous native-backed `killAllApps()` request.
 *
 * Purpose:
 * Routes an app-kill-all request through the wrapped C++ `killAllApps()` API
 * and posts the final success/error result back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_kill_all_apps_async(void* handle, int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `setTheme()` request.
 *
 * Purpose:
 * Stores a theme through the wrapped C++ `setTheme()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param theme_json JSON string encoding one Dog Paw `Theme`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `theme_json` contains valid Dog Paw `Theme` JSON.
 * @post On success, one async set-theme result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_set_theme_async(void* handle, int64_t request_id, const char* theme_json);

/**
 * @brief Launch an asynchronous native-backed `createTheme()` request.
 *
 * Purpose:
 * Creates a theme through the wrapped C++ `createTheme()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param theme_json JSON string encoding one Dog Paw `Theme`.
 * @param auto_suffix Whether the wrapped C++ API should auto-suffix duplicate
 *   names.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `theme_json` contains valid Dog Paw `Theme` JSON.
 * @post On success, one async create-theme result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_create_theme_async(void* handle, int64_t request_id, const char* theme_json, bool auto_suffix);

/**
 * @brief Launch an asynchronous native-backed `updateTheme()` request.
 *
 * Purpose:
 * Updates a theme through the wrapped C++ `updateTheme()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param theme_json JSON string encoding one Dog Paw `Theme`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `theme_json` contains valid Dog Paw `Theme` JSON.
 * @post On success, one async update-theme result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_update_theme_async(void* handle, int64_t request_id, const char* theme_json);

/**
 * @brief Launch an asynchronous native-backed `readTheme()` request.
 *
 * Purpose:
 * Reads one theme through the wrapped C++ `readTheme()` API and posts the
 * typed result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Theme name to read.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid theme name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async read-theme result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_read_theme_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `deleteTheme()` request.
 *
 * Purpose:
 * Deletes one theme through the wrapped C++ `deleteTheme()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Theme name to delete.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid theme name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async delete-theme result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_delete_theme_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `setCurrentTheme()` request.
 *
 * Purpose:
 * Pushes one theme onto the current-theme stack through the wrapped C++
 * `setCurrentTheme()` API and posts the success/error result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Theme name to set current.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid theme name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async set-current-theme result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_set_current_theme_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `readCurrentTheme()` request.
 *
 * Purpose:
 * Reads the top of the current-theme stack through the wrapped C++
 * `readCurrentTheme()` API and posts the typed result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async read-current-theme result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_read_current_theme_async(
    void* handle,
    int64_t request_id,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `removeCurrentTheme()` request.
 *
 * Purpose:
 * Pops the current-theme stack through the wrapped C++ `removeCurrentTheme()`
 * API and posts the success/error result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async remove-current-theme result will be posted to
 *   Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_remove_current_theme_async(void* handle, int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `listThemes()` request.
 *
 * Purpose:
 * Executes the wrapped C++ `listThemes()` implementation on a native waiter
 * thread and posts the final typed result back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the list worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async list-themes result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_list_themes_async(
    void* handle,
    int64_t request_id,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `subscribeToThemes()` request.
 *
 * Purpose:
 * Registers a native theme subscription through the wrapped C++
 * `subscribeToThemes()` API and posts the success/error result back to Dart.
 * Subsequent theme notifications are posted separately on the same event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Optional theme name to watch, or null for all themes.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @param send_immediately Whether the current matching theme should be emitted
 *   immediately after subscribing.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async subscribe-themes result will be posted to Dart.
 * @post Later native theme notifications may be posted until unsubscribed or
 *   destroyed.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_subscribe_themes_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec,
    bool send_immediately);

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromThemes()`
 * request.
 *
 * Purpose:
 * Removes a native theme subscription through the wrapped C++
 * `unsubscribeFromThemes()` API and posts the success/error result back to
 * Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Optional theme name to stop watching, or null for all themes.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async unsubscribe-themes result will be posted to
 *   Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_unsubscribe_themes_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `subscribeToCurrentTheme()`
 * request.
 *
 * Purpose:
 * Registers a native current-theme subscription through the wrapped C++
 * `subscribeToCurrentTheme()` API and posts the success/error result back to
 * Dart. Subsequent current-theme notifications are posted separately on the
 * same event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @param send_immediately Whether the current theme should be emitted
 *   immediately after subscribing.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async subscribe-current-theme result will be posted to
 *   Dart.
 * @post Later native current-theme notifications may be posted until
 *   unsubscribed or destroyed.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_subscribe_current_theme_async(
    void* handle,
    int64_t request_id,
    bool include_resolved,
    bool include_spec,
    bool send_immediately);

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromCurrentTheme()`
 * request.
 *
 * Purpose:
 * Removes a native current-theme subscription through the wrapped C++
 * `unsubscribeFromCurrentTheme()` API and posts the success/error result back
 * to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async unsubscribe-current-theme result will be posted
 *   to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_unsubscribe_current_theme_async(void* handle, int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `setScale()` request.
 *
 * Purpose:
 * Stores a scale through the wrapped C++ `setScale()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param scale_json JSON string encoding one Dog Paw `Scale`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `scale_json` contains valid Dog Paw `Scale` JSON.
 * @post On success, one async set-scale result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_set_scale_async(void* handle, int64_t request_id, const char* scale_json);

/**
 * @brief Launch an asynchronous native-backed `createScale()` request.
 *
 * Purpose:
 * Creates a scale through the wrapped C++ `createScale()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param scale_json JSON string encoding one Dog Paw `Scale`.
 * @param auto_suffix Whether the wrapped C++ API should auto-suffix duplicate
 *   names.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `scale_json` contains valid Dog Paw `Scale` JSON.
 * @post On success, one async create-scale result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_create_scale_async(void* handle, int64_t request_id, const char* scale_json, bool auto_suffix);

/**
 * @brief Launch an asynchronous native-backed `updateScale()` request.
 *
 * Purpose:
 * Updates a scale through the wrapped C++ `updateScale()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param scale_json JSON string encoding one Dog Paw `Scale`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `scale_json` contains valid Dog Paw `Scale` JSON.
 * @post On success, one async update-scale result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_update_scale_async(void* handle, int64_t request_id, const char* scale_json);

/**
 * @brief Launch an asynchronous native-backed `readScale()` request.
 *
 * Purpose:
 * Reads one scale through the wrapped C++ `readScale()` API and posts the
 * typed result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Scale name to read.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid scale name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async read-scale result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_read_scale_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `deleteScale()` request.
 *
 * Purpose:
 * Deletes one scale through the wrapped C++ `deleteScale()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Scale name to delete.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid scale name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async delete-scale result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_delete_scale_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `setCurrentScale()` request.
 *
 * Purpose:
 * Pushes one scale onto the current-scale stack through the wrapped C++
 * `setCurrentScale()` API and posts the success/error result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Scale name to set current.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid scale name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async set-current-scale result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_set_current_scale_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `readCurrentScale()` request.
 *
 * Purpose:
 * Reads the top of the current-scale stack through the wrapped C++
 * `readCurrentScale()` API and posts the typed result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async read-current-scale result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_read_current_scale_async(
    void* handle,
    int64_t request_id,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `removeCurrentScale()` request.
 *
 * Purpose:
 * Pops the current-scale stack through the wrapped C++ `removeCurrentScale()`
 * API and posts the success/error result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async remove-current-scale result will be posted to
 *   Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_remove_current_scale_async(void* handle, int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `listScales()` request.
 *
 * Purpose:
 * Executes the wrapped C++ `listScales()` implementation on a native waiter
 * thread and posts the final typed result back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the list worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async list-scales result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_list_scales_async(
    void* handle,
    int64_t request_id,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `setLayout()` request.
 *
 * Purpose:
 * Stores a layout through the wrapped C++ `setLayout()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param layout_json JSON string encoding one Dog Paw `Layout`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `layout_json` contains valid Dog Paw `Layout` JSON.
 * @post On success, one async set-layout result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_set_layout_async(void* handle, int64_t request_id, const char* layout_json);

/**
 * @brief Launch an asynchronous native-backed `createLayout()` request.
 *
 * Purpose:
 * Creates a layout through the wrapped C++ `createLayout()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param layout_json JSON string encoding one Dog Paw `Layout`.
 * @param auto_suffix Whether the wrapped C++ API should auto-suffix duplicate
 *   names.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `layout_json` contains valid Dog Paw `Layout` JSON.
 * @post On success, one async create-layout result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_create_layout_async(void* handle, int64_t request_id, const char* layout_json, bool auto_suffix);

/**
 * @brief Launch an asynchronous native-backed `updateLayout()` request.
 *
 * Purpose:
 * Updates a layout through the wrapped C++ `updateLayout()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param layout_json JSON string encoding one Dog Paw `Layout`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `layout_json` contains valid Dog Paw `Layout` JSON.
 * @post On success, one async update-layout result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_update_layout_async(void* handle, int64_t request_id, const char* layout_json);

/**
 * @brief Launch an asynchronous native-backed `readLayout()` request.
 *
 * Purpose:
 * Reads one layout through the wrapped C++ `readLayout()` API and posts the
 * typed result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Layout name to read.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid layout name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async read-layout result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_read_layout_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `deleteLayout()` request.
 *
 * Purpose:
 * Deletes one layout through the wrapped C++ `deleteLayout()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Layout name to delete.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid layout name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async delete-layout result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_delete_layout_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `listLayouts()` request.
 *
 * Purpose:
 * Executes the wrapped C++ `listLayouts()` implementation on a native waiter
 * thread and posts the final typed result back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the list worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async list-layouts result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_list_layouts_async(
    void* handle,
    int64_t request_id,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `setKV()` request.
 *
 * Purpose:
 * Stores one KV through the wrapped C++ `setKV()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param kv_json JSON string encoding one Dog Paw `KV`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `kv_json` contains valid Dog Paw `KV` JSON.
 * @post On success, one async set-kv result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_set_kv_async(void* handle, int64_t request_id, const char* kv_json);

/**
 * @brief Launch an asynchronous native-backed `createKV()` request.
 *
 * Purpose:
 * Creates one KV through the wrapped C++ `createKV()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param kv_json JSON string encoding one Dog Paw `KV`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `kv_json` contains valid Dog Paw `KV` JSON.
 * @post On success, one async create-kv result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_create_kv_async(void* handle, int64_t request_id, const char* kv_json);

/**
 * @brief Launch an asynchronous native-backed `updateKV()` request.
 *
 * Purpose:
 * Updates one KV through the wrapped C++ `updateKV()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param kv_json JSON string encoding one Dog Paw `KV`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `kv_json` contains valid Dog Paw `KV` JSON.
 * @post On success, one async update-kv result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_update_kv_async(void* handle, int64_t request_id, const char* kv_json);

/**
 * @brief Launch an asynchronous native-backed `readKV()` request.
 *
 * Purpose:
 * Reads one KV through the wrapped C++ `readKV()` API and posts the
 * typed result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name KV name to read.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid KV name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async read-kv result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_read_kv_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `deleteKV()` request.
 *
 * Purpose:
 * Deletes one KV through the wrapped C++ `deleteKV()` API and posts the
 * success/error result back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name KV name to delete.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid KV name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async delete-kv result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_delete_kv_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `listKVs()` request.
 *
 * Purpose:
 * Executes the wrapped C++ `listKVs()` implementation on a native waiter
 * thread and posts the final typed result back to Dart through the registered
 * event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the list worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async list-kvs result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_list_kvs_async(
    void* handle,
    int64_t request_id,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `createEndpoint()` request.
 *
 * Purpose:
 * Creates an endpoint through the wrapped C++ `createEndpoint()` API and
 * posts the typed `Endpoint` result back to Dart through the registered event
 * port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param endpoint_json JSON string encoding one Dog Paw `Endpoint`.
 * @param auto_suffix Whether the wrapped C++ API should auto-suffix duplicate
 *   names.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `endpoint_json` contains valid Dog Paw `Endpoint` JSON.
 * @post On success, one async create-endpoint result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_create_endpoint_async(void* handle,
                                    int64_t request_id,
                                    const char* endpoint_json,
                                    bool auto_suffix);

/**
 * @brief Launch an asynchronous native-backed `updateEndpoint()` request.
 *
 * Purpose:
 * Updates an endpoint through the wrapped C++ `updateEndpoint()` API and
 * posts the typed `Endpoint` result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param endpoint_json JSON string encoding one Dog Paw `Endpoint`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `endpoint_json` contains valid Dog Paw `Endpoint` JSON.
 * @post On success, one async update-endpoint result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_update_endpoint_async(void* handle,
                                    int64_t request_id,
                                    const char* endpoint_json);

/**
 * @brief Launch an asynchronous native-backed `setEndpoint()` request.
 *
 * Purpose:
 * Stores an endpoint through the wrapped C++ `setEndpoint()` API and posts the
 * typed `Endpoint` result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param endpoint_json JSON string encoding one Dog Paw `Endpoint`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `endpoint_json` contains valid Dog Paw `Endpoint` JSON.
 * @post On success, one async set-endpoint result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_set_endpoint_async(void* handle,
                                 int64_t request_id,
                                 const char* endpoint_json);

/**
 * @brief Launch an asynchronous native-backed `readEndpoint()` request.
 *
 * Purpose:
 * Reads one endpoint through the wrapped C++ `readEndpoint()` API and posts the
 * typed result (or absent endpoint) back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Endpoint name to read.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid endpoint name string.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async read-endpoint result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_read_endpoint_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `deleteEndpoint()` request.
 *
 * Purpose:
 * Deletes one endpoint by name through the wrapped C++ `deleteEndpoint()` API
 * (which applies the current-entity namespace on the native side) and posts
 * the success/error result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Endpoint name to delete.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `name` points to a valid endpoint name string.
 * @post On success, one async delete-endpoint result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_delete_endpoint_async(void* handle,
                                    int64_t request_id,
                                    const char* name);

/**
 * @brief Launch an asynchronous native-backed `searchEndpoints()` request.
 *
 * Purpose:
 * Searches endpoints using criteria parsed from JSON and posts the typed list
 * back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param criteria_json JSON string encoding Dog Paw `SearchCriteria`.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `criteria_json` contains valid `SearchCriteria` JSON.
 * @post On success, one async search-endpoints result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_search_endpoints_async(void* handle,
                                     int64_t request_id,
                                     const char* criteria_json);

/**
 * @brief Launch an asynchronous native-backed `subscribeToEndpoints()`
 * request.
 *
 * Purpose:
 * Registers an endpoint subscription through the wrapped C++ DogPawEntity and
 * posts both the subscription result and later endpoint notifications back to
 * Dart on the bridge event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Optional endpoint name to watch, or null for all endpoints in the
 *   selected namespace.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @param send_immediately Whether matching current endpoints should be emitted
 *   immediately after subscribing.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async subscribe-endpoints result will be posted to
 *   Dart.
 * @post Later native endpoint notifications may be posted until unsubscribed or
 *   destroyed.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_subscribe_endpoints_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec,
    bool send_immediately);

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromEndpoints()`
 * request.
 *
 * Purpose:
 * Removes an endpoint subscription through the wrapped C++ DogPawEntity and
 * posts the success/error result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Optional endpoint name to stop watching, or null for all
 *   endpoints in the selected namespace.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async unsubscribe-endpoints result will be posted to
 *   Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_unsubscribe_endpoints_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Write one already-serialized payload through a native-owned local
 * endpoint.
 *
 * Purpose:
 * Uses the wrapped C++ `DogPawEntity`'s live endpoint registry so Dart can send
 * endpoint runtime data without reconstructing queue/shared-memory handles.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param endpoint_name Owned endpoint name in the current entity namespace.
 * @param data Serialized payload bytes matching the endpoint's current wire
 *   format.
 * @param size Number of bytes available at `data`.
 * @param immediate Whether message-queue writes should flush immediately.
 * @return `true` when the native endpoint accepted the payload, otherwise
 * `false`.
 *
 * @pre `handle` is a live bridge handle.
 * @pre `endpoint_name` points to a valid null-terminated UTF-8 string.
 * @pre `data` points to at least `size` readable bytes when `size > 0`.
 * @post On success, the payload has been forwarded to the native endpoint's
 * runtime transport.
 * @invariant This function performs no JSON encoding or metadata mutation.
 */
bool dppb_dpe_local_endpoint_write(
    void* handle,
    const char* endpoint_name,
    const void* data,
    int32_t size,
    bool immediate);

/**
 * @brief Count realized input connections for one native-owned local endpoint.
 *
 * Purpose:
 * Lets Dart enumerate native-managed input connections when polling without
 * maintaining its own connection map.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param endpoint_name Owned endpoint name in the current entity namespace.
 * @return Non-negative connection count on success, or `-1` on error.
 *
 * @pre `handle` is a live bridge handle.
 * @pre `endpoint_name` points to a valid null-terminated UTF-8 string.
 * @post Endpoint state is unchanged.
 * @invariant Returned count reflects native runtime state at the time of the
 * call.
 */
int32_t dppb_dpe_local_endpoint_get_connection_count(
    void* handle,
    const char* endpoint_name);

/**
 * @brief Read one realized connection name by index for a native-owned local
 * endpoint.
 *
 * Purpose:
 * Exposes the current native connection enumeration to Dart without requiring a
 * separate subscription-maintained cache.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param endpoint_name Owned endpoint name in the current entity namespace.
 * @param index Zero-based connection index.
 * @param out_name Writable UTF-8 buffer, or null to query the required size.
 * @param max_size Capacity of `out_name` in bytes including the terminator.
 * @return Required byte count including the terminator on success, or `-1` on
 * error.
 *
 * @pre `handle` is a live bridge handle.
 * @pre `endpoint_name` points to a valid null-terminated UTF-8 string.
 * @pre When `out_name` is non-null, it points to at least `max_size` writable
 * bytes.
 * @post When `out_name` is non-null and large enough, it contains a
 * null-terminated UTF-8 connection name.
 * @invariant Endpoint state is unchanged.
 */
int32_t dppb_dpe_local_endpoint_get_connection_name(
    void* handle,
    const char* endpoint_name,
    int32_t index,
    char* out_name,
    int32_t max_size);

/**
 * @brief Query the current payload shape for one realized native input
 * connection.
 *
 * Purpose:
 * Provides the connection-specific index dimensions and byte size that Dart
 * needs before polling native-managed endpoint data.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param endpoint_name Owned endpoint name in the current entity namespace.
 * @param connection_name Realized connection name returned by
 *   `dppb_dpe_local_endpoint_get_connection_name()`.
 * @param out_index_type Output pointer receiving the DPPB index type enum.
 * @param out_index_dim1 Output pointer receiving the first index dimension.
 * @param out_index_dim2 Output pointer receiving the second index dimension.
 * @param out_payload_size Output pointer receiving the serialized payload size
 *   in bytes.
 * @return `true` on success, otherwise `false`.
 *
 * @pre All pointer arguments are non-null and writable where applicable.
 * @post Output pointers contain the native connection's current payload shape.
 * @invariant Endpoint state is unchanged.
 */
bool dppb_dpe_local_endpoint_get_connection_shape(
    void* handle,
    const char* endpoint_name,
    const char* connection_name,
    int32_t* out_index_type,
    int32_t* out_index_dim1,
    int32_t* out_index_dim2,
    int32_t* out_payload_size);

/**
 * @brief Poll one realized native input connection into a caller-owned buffer.
 *
 * Purpose:
 * Reads one payload from the wrapped C++ endpoint runtime using the native
 * connection state already maintained by `DogPawEntity`.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param endpoint_name Owned endpoint name in the current entity namespace.
 * @param connection_name Realized connection name to poll.
 * @param out_data Writable byte buffer that receives the serialized payload.
 * @param max_size Capacity of `out_data` in bytes.
 * @return Number of bytes written to `out_data`, or `0` when no payload was
 * available, or `-1` on error.
 *
 * @pre `handle`, `endpoint_name`, `connection_name`, and `out_data` are valid
 * pointers.
 * @pre `max_size` is large enough for the connection's payload shape reported
 * by `dppb_dpe_local_endpoint_get_connection_shape()`.
 * @post On success, `out_data` contains one serialized endpoint payload.
 * @invariant Endpoint metadata is unchanged by polling.
 */
int32_t dppb_dpe_local_endpoint_poll_connection(
    void* handle,
    const char* endpoint_name,
    const char* connection_name,
    void* out_data,
    int32_t max_size);

/**
 * @brief Read one native-owned local endpoint's retained-state snapshot as
 * JSON.
 *
 * Purpose:
 * Gives Dart direct access to the native endpoint runtime's retained-state
 * snapshot without rebuilding that state in the wrapper layer.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param endpoint_name Owned endpoint name in the current entity namespace.
 * @param out_json Writable UTF-8 buffer that receives snapshot JSON, or null to
 *   query the required size.
 * @param max_size Capacity of `out_json` in bytes including the terminator.
 * @return Required byte count including the terminator on success, or `-1` on
 *   error.
 *
 * @pre `handle` is a live bridge handle.
 * @pre `endpoint_name` points to a valid null-terminated UTF-8 string.
 * @pre When `out_json` is non-null, it points to at least `max_size` writable
 * bytes.
 * @post When `out_json` is non-null and large enough, it contains one
 * null-terminated UTF-8 JSON object matching `EndpointRetainedStateSnapshot`.
 * @invariant Endpoint metadata and runtime state are unchanged by this read.
 */
int32_t dppb_dpe_local_endpoint_get_retained_state_json(
    void* handle,
    const char* endpoint_name,
    char* out_json,
    int32_t max_size);

/**
 * @brief Adopt one retained-state snapshot into a native-owned local stateful
 * input endpoint.
 *
 * Purpose:
 * Exposes the wrapped C++ `Endpoint::adoptRetainedStateSnapshot()` primitive so
 * the Dart facade can commit accepted state through the same native runtime
 * path used by C++ owners.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param endpoint_name Owned endpoint name in the current entity namespace.
 * @param snapshot_json UTF-8 JSON object matching
 *   `EndpointRetainedStateSnapshot`.
 * @param publish_matched_output Whether a linked matched output should publish
 *   the committed state immediately.
 * @param sender_info_json Optional UTF-8 JSON object describing
 *   `EndpointSenderInfo`, or null/empty when no sender identity should be
 *   attached.
 * @return `true` when the snapshot was adopted successfully, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle.
 * @pre `endpoint_name` and `snapshot_json` point to valid null-terminated UTF-8
 * strings.
 * @pre When `sender_info_json` is non-null and non-empty, it encodes an object
 * with `name` and `target` fields compatible with the native sender contract.
 * @post On success, the endpoint's retained state matches `snapshot_json`.
 * @post When `publish_matched_output` is `true`, a linked matched output
 * publishes the committed state through the normal native path.
 * @invariant This function does not mutate authored endpoint metadata.
 */
bool dppb_dpe_local_endpoint_adopt_retained_state_json(
    void* handle,
    const char* endpoint_name,
    const char* snapshot_json,
    bool publish_matched_output,
    const char* sender_info_json);

/**
 * @brief Read the current bytes for one realized native file-backed input
 * connection.
 *
 * Purpose:
 * Exposes the wrapped C++ `Endpoint::readFileBacked()` behavior to Dart while
 * keeping the native runtime as the source of truth for connection state.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param endpoint_name Owned endpoint name in the current entity namespace.
 * @param connection_name Realized connection name to read.
 * @param out_data Writable byte buffer that receives the file contents, or null
 *   to query the required size.
 * @param max_size Capacity of `out_data` in bytes.
 * @return Positive byte count on success, `0` when no readable contents are
 * available, or `-1` on error. When `out_data` is null or `max_size <= 0`, a
 * positive return value reports the required buffer size.
 *
 * @pre `handle`, `endpoint_name`, and `connection_name` are valid pointers.
 * @pre When `out_data` is non-null, it points to at least `max_size` writable
 * bytes.
 * @post On success, `out_data` contains the current file contents when a
 * writable buffer was provided.
 * @invariant Endpoint metadata is unchanged by this read.
 */
int32_t dppb_dpe_local_endpoint_read_file_backed(
    void* handle,
    const char* endpoint_name,
    const char* connection_name,
    void* out_data,
    int32_t max_size);

/**
 * @brief Poll one realized native file-backed input connection for a change and
 * read the resulting file contents.
 *
 * Purpose:
 * Mirrors the existing Dart `pollFileBacked()` semantics by first checking the
 * native notification queue and only then reading the file contents if a change
 * was observed.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param endpoint_name Owned endpoint name in the current entity namespace.
 * @param connection_name Realized connection name to poll.
 * @param out_data Writable byte buffer that receives the file contents, or null
 *   to query the required size after a detected change.
 * @param max_size Capacity of `out_data` in bytes.
 * @return Positive byte count when a change was observed and read
 * successfully, `0` when no change was available, or `-1` on error. When
 * `out_data` is null or `max_size <= 0`, a positive return value reports the
 * required buffer size for the changed contents.
 *
 * @pre `handle`, `endpoint_name`, and `connection_name` are valid pointers.
 * @pre When `out_data` is non-null, it points to at least `max_size` writable
 * bytes.
 * @post On success, `out_data` contains the latest file contents when a
 * writable buffer was provided.
 * @invariant Endpoint metadata is unchanged by polling.
 */
int32_t dppb_dpe_local_endpoint_poll_file_backed(
    void* handle,
    const char* endpoint_name,
    const char* connection_name,
    void* out_data,
    int32_t max_size);

/**
 * @brief Launch an asynchronous native-backed `createConnectionRequest()`
 * request.
 *
 * Purpose:
 * Forwards JSON to the wrapped C++ `createConnectionRequest()` and posts the
 * operation result to Dart.
 */
bool dppb_dpe_create_connection_request_async(void* handle,
                                              int64_t request_id,
                                              const char* connection_request_json);

/**
 * @brief Launch an asynchronous native-backed `setConnectionRequest()`
 * request.
 */
bool dppb_dpe_set_connection_request_async(void* handle,
                                           int64_t request_id,
                                           const char* connection_request_json);

/**
 * @brief Launch an asynchronous native-backed `updateConnectionRequest()`
 * request.
 */
bool dppb_dpe_update_connection_request_async(void* handle,
                                              int64_t request_id,
                                              const char* connection_request_json);

/**
 * @brief Launch an asynchronous native-backed `readConnectionRequest()`
 * request.
 */
bool dppb_dpe_read_connection_request_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `deleteConnectionRequest()`
 * request.
 */
bool dppb_dpe_delete_connection_request_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `listConnectionRequests()`
 * request.
 */
bool dppb_dpe_list_connection_requests_async(
    void* handle,
    int64_t request_id,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `createFollowRequest()`
 * request.
 */
bool dppb_dpe_create_follow_request_async(void* handle,
                                          int64_t request_id,
                                          const char* follow_request_json);

/**
 * @brief Launch an asynchronous native-backed `setFollowRequest()` request.
 */
bool dppb_dpe_set_follow_request_async(void* handle,
                                       int64_t request_id,
                                       const char* follow_request_json);

/**
 * @brief Launch an asynchronous native-backed `updateFollowRequest()`
 * request.
 */
bool dppb_dpe_update_follow_request_async(void* handle,
                                          int64_t request_id,
                                          const char* follow_request_json);

/**
 * @brief Launch an asynchronous native-backed `readFollowRequest()` request.
 */
bool dppb_dpe_read_follow_request_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `deleteFollowRequest()`
 * request.
 */
bool dppb_dpe_delete_follow_request_async(void* handle,
                                          int64_t request_id,
                                          const char* name,
                                          const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `listFollowRequests()` request.
 */
bool dppb_dpe_list_follow_requests_async(
    void* handle,
    int64_t request_id,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `readConnection()` request.
 *
 * Purpose:
 * Reads one realized connection; the wrapped C++ API uses global namespace
 * semantics on the wire.
 */
bool dppb_dpe_read_connection_async(void* handle,
                                    int64_t request_id,
                                    const char* name,
                                    bool include_resolved,
                                    bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `listConnections()` request.
 *
 * Purpose:
 * Lists realized connections; the wrapped C++ API uses global namespace
 * semantics on the wire.
 */
bool dppb_dpe_list_connections_async(void* handle,
                                     int64_t request_id,
                                     bool include_resolved,
                                     bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `subscribeToScales()` request.
 *
 * Purpose:
 * Registers a native scale subscription through the wrapped C++
 * `subscribeToScales()` API and posts the success/error result back to Dart.
 * Subsequent scale notifications are posted separately on the same event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Optional scale name to watch, or null for all scales.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @param send_immediately Whether the current matching scale should be emitted
 *   immediately after subscribing.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async subscribe-scales result will be posted to Dart.
 * @post Later native scale notifications may be posted until unsubscribed or
 *   destroyed.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_subscribe_scales_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec,
    bool send_immediately);

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromScales()`
 * request.
 *
 * Purpose:
 * Removes a native scale subscription through the wrapped C++
 * `unsubscribeFromScales()` API and posts the success/error result back to
 * Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Optional scale name to stop watching, or null for all scales.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async unsubscribe-scales result will be posted to
 *   Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_unsubscribe_scales_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `subscribeToCurrentScale()`
 * request.
 *
 * Purpose:
 * Registers a native current-scale subscription through the wrapped C++
 * `subscribeToCurrentScale()` API and posts the success/error result back to
 * Dart. Subsequent current-scale notifications are posted separately on the
 * same event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @param send_immediately Whether the current scale should be emitted
 *   immediately after subscribing.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async subscribe-current-scale result will be posted to
 *   Dart.
 * @post Later native current-scale notifications may be posted until
 *   unsubscribed or destroyed.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_subscribe_current_scale_async(
    void* handle,
    int64_t request_id,
    bool include_resolved,
    bool include_spec,
    bool send_immediately);

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromCurrentScale()`
 * request.
 *
 * Purpose:
 * Removes a native current-scale subscription through the wrapped C++
 * `unsubscribeFromCurrentScale()` API and posts the success/error result back
 * to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @post On success, one async unsubscribe-current-scale result will be posted
 *   to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_unsubscribe_current_scale_async(void* handle, int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `subscribeToLayouts()` request.
 *
 * Purpose:
 * Registers a native layout subscription through the wrapped C++
 * `subscribeToLayouts()` API and posts the success/error result back to Dart.
 * Subsequent layout notifications are posted separately on the same event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Optional layout name to watch, or null for all layouts.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @param send_immediately Whether the current matching layout should be emitted
 *   immediately after subscribing.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async subscribe-layouts result will be posted to Dart.
 * @post Later native layout notifications may be posted until unsubscribed or
 *   destroyed.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_subscribe_layouts_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec,
    bool send_immediately);

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromLayouts()`
 * request.
 *
 * Purpose:
 * Removes a native layout subscription through the wrapped C++
 * `unsubscribeFromLayouts()` API and posts the success/error result back to
 * Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param name Optional layout name to stop watching, or null for all layouts.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async unsubscribe-layouts result will be posted to
 *   Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_unsubscribe_layouts_async(
    void* handle,
    int64_t request_id,
    const char* name,
    const char* namespace_selector_json);

/**
 * @brief Launch an asynchronous native-backed `addLayoutStackEntry()` request.
 *
 * Purpose:
 * Adds a layout reference to the persistent layout stack and posts the new
 * entry id (or error) back to Dart through the registered event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id.
 * @param layout_ref_json UTF-8 JSON object with the DataItemRefByName describing
 *   the layout to reference.
 * @param has_index Whether a specific insert index was supplied.
 * @param index Insert position (only meaningful when `has_index` is true).
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * On success, the `result` payload contains `entryId` with the new stack
 * entry's stable id.
 */
bool dppb_dpe_add_layout_stack_entry_async(void* handle,
                                           int64_t request_id,
                                           const char* layout_ref_json,
                                           bool has_index,
                                           int32_t index);

/**
 * @brief Launch an asynchronous native-backed `removeLayoutStackEntry()` request.
 *
 * @param handle Opaque bridge handle.
 * @param request_id Dart-side bridge request id.
 * @param entry_id UTF-8 stable entry id returned by a prior add/read.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_remove_layout_stack_entry_async(void* handle,
                                              int64_t request_id,
                                              const char* entry_id);

/**
 * @brief Launch an asynchronous native-backed `moveLayoutStackEntry()` request.
 *
 * @param handle Opaque bridge handle.
 * @param request_id Dart-side bridge request id.
 * @param entry_id UTF-8 stable entry id.
 * @param new_index Destination zero-based index.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_move_layout_stack_entry_async(void* handle,
                                            int64_t request_id,
                                            const char* entry_id,
                                            int32_t new_index);

/**
 * @brief Launch an asynchronous native-backed `readLayoutStack()` request.
 *
 * @param handle Opaque bridge handle.
 * @param request_id Dart-side bridge request id.
 * @param include_resolved Whether to include the composed resolved layout.
 * @param include_spec Whether to include spec data in the resolved layout.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * On success, the `result` payload contains `layoutStack` — the full snapshot
 * as JSON: `layoutStackEntries` array and an optional `resolvedLayout`.
 */
bool dppb_dpe_read_layout_stack_async(void* handle,
                                      int64_t request_id,
                                      bool include_resolved,
                                      bool include_spec);

/**
 * @brief Launch an asynchronous native-backed `subscribeToLayoutStack()`
 * request.
 *
 * Purpose:
 * Registers a native layout-stack subscription. Subsequent stack notifications
 * are posted as subscription notification events on the same event port with
 * topic `layout_stack/notification` and payload field `layoutStack`.
 *
 * @param handle Opaque bridge handle.
 * @param request_id Dart-side bridge request id.
 * @param include_resolved Whether notifications include the composed layout.
 * @param include_spec Whether notifications include spec data.
 * @param send_immediately Whether to receive the current snapshot immediately.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_subscribe_layout_stack_async(void* handle,
                                           int64_t request_id,
                                           bool include_resolved,
                                           bool include_spec,
                                           bool send_immediately);

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromLayoutStack()`
 * request.
 *
 * @param handle Opaque bridge handle.
 * @param request_id Dart-side bridge request id.
 * @return `true` if the worker thread was launched, otherwise `false`.
 */
bool dppb_dpe_unsubscribe_layout_stack_async(void* handle,
                                             int64_t request_id);

/**
 * @brief Launch an asynchronous native-backed `subscribeToKV()` request.
 *
 * Purpose:
 * Registers a native KV subscription through the wrapped C++ `subscribeToKV()`
 * API and posts the success/error result back to Dart. Subsequent KV
 * notifications are posted separately on the same event port.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param key Optional KV key to watch, or null for all keys.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @param include_resolved Whether resolved data should be requested.
 * @param include_spec Whether spec data should be requested.
 * @param send_immediately Whether the current matching KV should be emitted
 *   immediately after subscribing.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async subscribe-kv result will be posted to Dart.
 * @post Later native KV notifications may be posted until unsubscribed or
 *   destroyed.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_subscribe_kv_async(
    void* handle,
    int64_t request_id,
    const char* key,
    const char* namespace_selector_json,
    bool include_resolved,
    bool include_spec,
    bool send_immediately);

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromKV()` request.
 *
 * Purpose:
 * Removes a native KV subscription through the wrapped C++
 * `unsubscribeFromKV()` API and posts the success/error result back to Dart.
 *
 * @param handle Opaque bridge handle returned by `dppb_dpe_create()`.
 * @param request_id Dart-side bridge request id used to resolve the matching
 *   Dart completer.
 * @param key Optional KV key to stop watching, or null for all keys.
 * @param namespace_selector_json JSON string encoding a Dog Paw namespace
 *   selector.
 * @return `true` if the worker thread was launched, otherwise `false`.
 *
 * @pre `handle` is a live bridge handle with an event port already registered.
 * @pre `namespace_selector_json` contains valid namespace-selector JSON.
 * @post On success, one async unsubscribe-kv result will be posted to Dart.
 * @invariant The calling Dart isolate is not blocked waiting for the Epiphany
 *   response.
 */
bool dppb_dpe_unsubscribe_kv_async(
    void* handle,
    int64_t request_id,
    const char* key,
    const char* namespace_selector_json);

#ifdef __cplusplus
}
#endif
