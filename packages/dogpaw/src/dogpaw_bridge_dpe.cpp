#include "dogpaw_bridge.h"

// Define VERBOSITY to 0 to silence logging if headers depend on it
#ifndef VERBOSITY
#define VERBOSITY 0
#endif

#include "DogPawEntity.hpp"
#include "LayoutJsonFfiNormalize.hpp"
#include "dart_api_dl.h"
#include "logging/AppLogger.hpp"
#include <cstring>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace JF = epiphany::JsonFields;

/**
 * @brief Native wrapper state for one Dart-owned DogPawEntity bridge instance.
 *
 * Purpose:
 * Owns the real C++ `dogpaw::DogPawEntity`, stores the pending connection-start
 * handle needed for explicit ready completion, tracks the Dart port used for
 * async notifications, and keeps waiter threads alive until request futures
 * complete.
 *
 * @param entityName The logical entity name this client connects as.
 * @param serverUrl The websocket endpoint to use when constructing the C++ entity.
 * @param timeoutMs Default request timeout for the C++ entity in milliseconds.
 * @return Constructed instances own a ready-to-use C++ `DogPawEntity`.
 *
 * @pre `entityName` must be a valid Dog Paw entity name.
 * @pre `timeoutMs` must be non-negative.
 * @post The wrapped C++ entity exists for the lifetime of this bridge state.
 * @post `shutdown()` disconnects, clears pending ready state, and joins waiter
 *   threads before destruction completes.
 * @invariant Access to mutable state is guarded by `mutex`.
 * @invariant Async waiter threads are joined before the bridge object is destroyed.
 */
struct NativeDogPawEntityBridge {
  /**
   * @brief Construct bridge state around a real C++ DogPawEntity.
   *
   * Purpose:
   * Creates the underlying C++ entity with quiet websocket logging and installs
   * the native-to-Dart error callback bridge.
   *
   * @param entityName Native entity name used by the wrapped C++ DogPawEntity.
   * @param serverUrl Websocket URL passed through to the wrapped entity.
   * @param timeoutMs Default request timeout for the wrapped entity.
   * @return Constructed bridge state.
   *
   * @pre `timeoutMs` is zero or positive.
   * @post `entity` is non-null and points at a valid C++ DogPawEntity.
   * @invariant The constructor does not register a Dart event port.
   */
  NativeDogPawEntityBridge(const std::string& entityName,
                           const std::string& serverUrl,
                           const int32_t timeoutMs)
      : entity(std::make_unique<dogpaw::DogPawEntity>(
            entityName,
            dogpaw::DogPawEntity::PrintVerbosity::NONE,
            dogpaw::DogPawEntity::PrintVerbosity::NONE,
            serverUrl,
            std::chrono::milliseconds(timeoutMs))) {}

  /**
   * @brief Destroy the bridge state after orderly shutdown.
   *
   * Purpose:
   * Ensures the wrapped entity disconnects and all waiter threads finish before
   * the bridge memory is released.
   *
   * @param None.
   * @return None.
   *
   * @pre None.
   * @post The entity is disconnected and waiter threads are joined.
   * @invariant Destruction is idempotent through the `destroying` flag.
   */
  ~NativeDogPawEntityBridge() { shutdown(); }

  /**
   * @brief Disconnect the wrapped entity and join all waiter threads.
   *
   * Purpose:
   * Provides a single place for native teardown so both explicit destroy and
   * normal C++ destruction follow the same rules.
   *
   * @param None.
   * @return None.
   *
   * @pre None.
   * @post No waiter threads remain joinable and no pending ready handle is left
   *   unsignaled.
   * @invariant After this returns once, subsequent calls are no-ops.
   */
  void shutdown();

  std::mutex mutex;
  std::unique_ptr<dogpaw::DogPawEntity> entity;
  std::optional<dogpaw::ConnectionStartHandle> pendingConnectionStartHandle;
  std::vector<std::thread> requestThreads;
  Dart_Port_DL eventPort = ILLEGAL_PORT;
  bool destroying = false;
};

/**
 * @brief Convert a nullable C string to a std::string with a fallback value.
 *
 * Purpose:
 * Normalizes C ABI string inputs so the bridge code can use standard C++
 * strings without repeated null checks.
 *
 * @param value Nullable UTF-8 C string from the FFI boundary.
 * @param fallback Value to return when `value` is null.
 * @return Normalized std::string.
 *
 * @pre `value` is either null or points to a valid null-terminated UTF-8 string.
 * @post Returned string contains the input text or the fallback.
 * @invariant This helper never mutates the input.
 */
std::string string_or_fallback(const char* value, const std::string& fallback) {
  return (value != nullptr) ? std::string(value) : fallback;
}

/**
 * @brief Post one JSON event envelope to Dart through the registered port.
 *
 * Purpose:
 * Implements the native-to-Dart async routing boundary used by the migration.
 * The payload is serialized to a JSON string so Dart can inspect and dispatch
 * it without sharing native object layouts.
 *
 * @param bridge Bridge state whose Dart event port should receive the event.
 * @param eventJson JSON envelope to serialize and post.
 * @return true when Dart accepted the message for delivery, otherwise false.
 *
 * @pre `Dart_InitializeApiDL()` already succeeded.
 * @pre `eventJson` contains a serializable JSON object.
 * @post On success, one string message is queued for Dart.
 * @invariant This helper does not mutate the bridge state.
 */
bool post_bridge_event(NativeDogPawEntityBridge* bridge,
                       const nlohmann::json& eventJson) {
  Dart_Port_DL eventPort = ILLEGAL_PORT;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || bridge->eventPort == ILLEGAL_PORT) {
      return false;
    }
    eventPort = bridge->eventPort;
  }

  std::string eventString = eventJson.dump();
  Dart_CObject dartMessage;
  dartMessage.type = Dart_CObject_kString;
  dartMessage.value.as_string = const_cast<char*>(eventString.c_str());
  return Dart_PostCObject_DL(eventPort, &dartMessage);
}

/**
 * @brief Build the standard request-result envelope posted back to Dart.
 *
 * Purpose:
 * Keeps the bridge's response shape uniform so the Dart wrapper can resolve its
 * own pending completers without method-specific transport code.
 *
 * @param requestId Dart-side bridge request id.
 * @param methodName Logical method name for debugging and dispatch.
 * @param success Whether the native request completed successfully.
 * @param error Error message when `success` is false, otherwise empty.
 * @param resultJson Optional JSON payload returned by the native operation.
 * @return JSON event envelope ready for posting to Dart.
 *
 * @pre `methodName` is non-empty.
 * @post Returned JSON contains `eventType`, `requestId`, `method`, `success`,
 *   `error`, and `result`.
 * @invariant The returned object is self-contained and does not reference
 *   native memory.
 */
nlohmann::json make_request_result_event(const int64_t requestId,
                                         const std::string& methodName,
                                         const bool success,
                                         const std::string& error,
                                         const nlohmann::json& resultJson =
                                             nlohmann::json::object()) {
  return nlohmann::json{
      {JF::EVENT_TYPE, "requestResult"},
      {JF::REQUEST_ID, requestId},
      {JF::METHOD, methodName},
      {JF::SUCCESS, success},
      {JF::ERROR, error},
      {JF::RESULT, resultJson},
  };
}

/**
 * @brief Build the standard native error event envelope.
 *
 * Purpose:
 * Routes asynchronous C++ error callbacks into Dart using the same event port
 * channel as request results.
 *
 * @param message Error text originating from the wrapped C++ entity.
 * @return JSON error event envelope.
 *
 * @pre `message` is valid UTF-8 or plain ASCII.
 * @post Returned JSON contains the normalized error event shape.
 * @invariant The returned object is independent of the input string storage.
 */
nlohmann::json make_error_event(const std::string& message) {
  return nlohmann::json{
      {JF::EVENT_TYPE, "error"},
      {JF::MESSAGE, message},
  };
}

/**
 * @brief Build one subscription-notification envelope posted back to Dart.
 *
 * Purpose:
 * Mirrors the shape of websocket notifications closely enough that the Dart
 * client can reuse the existing subscription-matching logic on top of the
 * native event port.
 *
 * @param topic Notification topic associated with the subscription family.
 * @param notificationType Native notification type such as create/update/delete.
 * @param itemRef Typed item reference identifying the changed item.
 * @param valueField JSON field name that stores the changed item payload.
 * @param valueJson Serialized JSON payload for the changed item.
 * @return JSON event envelope ready for posting to Dart.
 *
 * @pre `topic` and `valueField` are non-empty.
 * @post Returned JSON contains `eventType`, `topic`, and a `result` payload
 *   that includes item-ref fields, `notificationType`, and the typed item JSON.
 * @invariant The returned object is self-contained and does not reference
 *   native memory.
 */
nlohmann::json make_subscription_notification_event(
    const std::string& topic,
    const std::string& notificationType,
    const dogpaw::DataItemRefByName& itemRef,
    const std::string& valueField,
    const nlohmann::json& valueJson) {
  nlohmann::json resultJson = itemRef.toJson();
  resultJson[JF::NOTIFICATION_TYPE] = notificationType;
  resultJson[valueField] = valueJson;
  return nlohmann::json{
      {JF::EVENT_TYPE, "subscriptionNotification"},
      {JF::TOPIC, topic},
      {JF::RESULT, resultJson},
  };
}

nlohmann::json make_endpoint_runtime_notification_event(
    const std::string& notificationType,
    const dogpaw::DataItemRefByName& itemRef,
    const nlohmann::json& connectionJson) {
  nlohmann::json resultJson = itemRef.toJson();
  resultJson[JF::NOTIFICATION_TYPE] = notificationType;
  resultJson["connection"] = connectionJson;
  return nlohmann::json{
      {JF::EVENT_TYPE, "subscriptionNotification"},
      {JF::TOPIC, epiphany::Topics::ENDPOINT_NOTIFICATION},
      {JF::RESULT, resultJson},
  };
}

/**
 * @brief Build one entity-lifecycle notification envelope posted back to Dart.
 *
 * Purpose:
 * Mirrors the websocket `entity/notification` payload closely enough that the
 * Dart native client can dispatch entity-connected and entity-disconnected
 * callbacks without reintroducing websocket transport.
 *
 * @param notificationType Notification type such as entity_connected.
 * @param entityName Entity name carried by the native callback.
 * @return JSON event envelope ready for posting to Dart.
 *
 * @pre `notificationType` and `entityName` are non-empty.
 * @post Returned JSON contains `eventType`, `topic`, and a `result` payload
 *   with `notificationType` and `entityName`.
 * @invariant The returned object is self-contained and does not reference
 *   native memory.
 */
nlohmann::json make_entity_lifecycle_notification_event(
    const std::string& notificationType,
    const std::string& entityName) {
  return nlohmann::json{
      {JF::EVENT_TYPE, "entityLifecycleNotification"},
      {JF::TOPIC, epiphany::Topics::ENTITY_NOTIFICATION},
      {JF::RESULT,
       nlohmann::json{
           {JF::NOTIFICATION_TYPE, notificationType},
           {JF::ENTITY_NAME, entityName},
       }},
  };
}

/**
 * @brief Build one direct-message envelope posted back to Dart.
 *
 * Purpose:
 * Mirrors the websocket direct-message payload so the Dart native client can
 * reuse the same callback shape without a websocket transport.
 *
 * @param senderEntity Entity name that sent the message.
 * @param messageJson JSON payload carried by the direct message.
 * @return JSON event envelope ready for posting to Dart.
 *
 * @pre `senderEntity` is non-empty.
 * @post Returned JSON contains `eventType`, `topic`, and a `result` payload
 *   with `senderEntity` and `message`.
 * @invariant The returned object is self-contained and does not reference
 *   native memory.
 */
nlohmann::json make_direct_message_event(const std::string& senderEntity,
                                         const nlohmann::json& messageJson) {
  return nlohmann::json{
      {JF::EVENT_TYPE, "directMessage"},
      {JF::TOPIC, epiphany::Topics::ENTITY_DIRECT_MESSAGE},
      {JF::RESULT,
       nlohmann::json{
           {JF::SENDER_ENTITY, senderEntity},
           {JF::MESSAGE, messageJson},
       }},
  };
}

/**
 * @brief Build one incoming-command envelope posted back to Dart.
 *
 * Purpose:
 * Mirrors the websocket command payload so the Dart native client can dispatch
 * command handlers and later send accepted/completed responses through FFI.
 *
 * @param senderEntity Entity name that sent the command.
 * @param command Command name.
 * @param paramsJson JSON params object carried by the command.
 * @param commandId Command correlation id.
 * @return JSON event envelope ready for posting to Dart.
 *
 * @pre `senderEntity`, `command`, and `commandId` are valid UTF-8 strings.
 * @post Returned JSON contains `eventType`, `topic`, and a `result` payload
 *   with sender, command, params, and command id.
 * @invariant The returned object is self-contained and does not reference
 *   native memory.
 */
nlohmann::json make_incoming_command_event(const std::string& senderEntity,
                                           const std::string& command,
                                           const nlohmann::json& paramsJson,
                                           const std::string& commandId) {
  return nlohmann::json{
      {JF::EVENT_TYPE, "incomingCommand"},
      {JF::TOPIC, epiphany::Topics::ENTITY_COMMAND},
      {JF::RESULT,
       nlohmann::json{
           {JF::SENDER_ENTITY, senderEntity},
           {JF::COMMAND, command},
           {JF::PARAMS, paramsJson},
           {JF::COMMAND_ID, commandId},
       }},
  };
}

/**
 * @brief Build one command-accepted envelope posted back to Dart.
 *
 * Purpose:
 * Bridges the native C++ `onAccepted` callback into Dart while preserving the
 * request id of the originating `sendCommand()` call.
 *
 * @param requestId Dart-side bridge request id for the original send-command
 *   request.
 * @param resultJson JSON result payload from the accepted response.
 * @return JSON event envelope ready for posting to Dart.
 *
 * @pre `requestId` identifies a pending Dart send-command request.
 * @post Returned JSON contains `eventType`, `requestId`, and `result`.
 * @invariant The returned object is self-contained and does not reference
 *   native memory.
 */
nlohmann::json make_command_accepted_event(const int64_t requestId,
                                           const nlohmann::json& resultJson) {
  return nlohmann::json{
      {JF::EVENT_TYPE, "commandAccepted"},
      {JF::REQUEST_ID, requestId},
      {JF::RESULT, resultJson},
  };
}

/**
 * @brief Build one preset-request envelope posted back to Dart.
 *
 * Purpose:
 * Mirrors the websocket preset-request payload so the Dart native client can
 * preserve the existing async preset callback contract while the C++ bridge
 * always defers server completion until Dart explicitly finishes or auto-
 * completes the request.
 *
 * @param contentJson JSON payload received on the preset-request topic.
 * @return JSON event envelope ready for posting to Dart.
 *
 * @pre `contentJson` is the preset-request message body from Epiphany.
 * @post Returned JSON contains `eventType`, `topic`, and the raw preset request
 *   content in `result`.
 * @invariant The returned object is self-contained and does not reference
 *   native memory.
 */
nlohmann::json make_preset_request_event(const nlohmann::json& contentJson) {
  return nlohmann::json{
      {JF::EVENT_TYPE, "presetRequest"},
      {JF::TOPIC, epiphany::Topics::PRESET_REQUEST},
      {JF::RESULT, contentJson},
  };
}

/**
 * @brief Parse a JSON namespace-selector string into the C++ typed selector.
 *
 * Purpose:
 * Reuses the existing C++ namespace parsing rules so Dart does not need to
 * learn any native-only selector format.
 *
 * @param namespaceSelectorJson UTF-8 JSON string matching Dog Paw namespace
 * selector JSON.
 * @return Parsed typed namespace selector.
 *
 * @pre `namespaceSelectorJson` points to a valid JSON object string.
 * @post Returned selector matches the encoded namespace-selector fields.
 * @invariant Parsing does not mutate the source string.
 */
dogpaw::NamespaceSelector parse_namespace_selector_json(
    const char* namespaceSelectorJson) {
  const std::string selectorJsonString =
      string_or_fallback(namespaceSelectorJson, "{\"type\":\"CURRENT_ENTITY\"}");
  const nlohmann::json selectorJson = nlohmann::json::parse(selectorJsonString);
  return dogpaw::NamespaceSelector::fromJson(selectorJson);
}

/**
 * @brief Parse one JSON object string into a standalone `nlohmann::json`.
 *
 * Purpose:
 * Reuses the bridge's JSON parsing flow for direct messages, command params,
 * and command result payloads without duplicating schema-specific helpers.
 *
 * @param jsonText UTF-8 JSON string encoding an object, or null for `{}`.
 * @return Parsed JSON object.
 *
 * @pre `jsonText`, when non-null, points to valid JSON object text.
 * @post Returned JSON is an object value suitable for Dog Paw message payloads.
 * @invariant Parsing does not mutate the source string.
 */
nlohmann::json parse_json_object(const char* jsonText) {
  const std::string jsonString = string_or_fallback(jsonText, "{}");
  const nlohmann::json parsedJson = nlohmann::json::parse(jsonString);
  if (!parsedJson.is_object()) {
    throw std::runtime_error("Expected JSON object payload.");
  }
  return parsedJson;
}

/**
 * @brief Parse one Dog Paw scale JSON string into a typed C++ `Scale`.
 *
 * Purpose:
 * Reuses the existing typed `Scale::fromJson()` parser so the bridge does not
 * duplicate scale-schema knowledge.
 *
 * @param scaleJson UTF-8 JSON string encoding one Dog Paw `Scale`.
 * @return Parsed `Scale` on success, or `nullptr` if parsing fails.
 *
 * @pre `scaleJson` points to a valid JSON object string.
 * @post Returned pointer owns the parsed `Scale` instance when parsing
 *   succeeds.
 * @invariant Parsing does not mutate the source string.
 */
std::unique_ptr<dogpaw::Scale> parse_scale_json(const char* scaleJson) {
  const std::string scaleJsonString = string_or_fallback(scaleJson, "{}");
  const nlohmann::json parsedScaleJson = nlohmann::json::parse(scaleJsonString);
  return dogpaw::Scale::fromJson(parsedScaleJson);
}

/**
 * @brief Parse one Dog Paw theme JSON string into a typed C++ `Theme`.
 *
 * Purpose:
 * Reuses the existing typed `Theme::fromJson()` parser so the bridge does not
 * duplicate theme-schema knowledge.
 *
 * @param themeJson UTF-8 JSON string encoding one Dog Paw `Theme`.
 * @return Parsed `Theme` on success, or `nullptr` if parsing fails.
 *
 * @pre `themeJson` points to a valid JSON object string.
 * @post Returned pointer owns the parsed `Theme` instance when parsing
 *   succeeds.
 * @invariant Parsing does not mutate the source string.
 */
std::unique_ptr<dogpaw::Theme> parse_theme_json(const char* themeJson) {
  const std::string themeJsonString = string_or_fallback(themeJson, "{}");
  const nlohmann::json parsedThemeJson = nlohmann::json::parse(themeJsonString);
  return dogpaw::Theme::fromJson(parsedThemeJson);
}

/**
 * @brief Parse one Dog Paw layout JSON string into a typed C++ `Layout`.
 *
 * Purpose:
 * Reuses the existing typed `Layout::fromJson()` parser so the bridge does not
 * duplicate layout-schema knowledge.
 *
 * @param layoutJson UTF-8 JSON string encoding one Dog Paw `Layout`.
 * @return Parsed `Layout` on success, or `nullptr` if parsing fails.
 *
 * @pre `layoutJson` points to a valid JSON object string.
 * @post Returned pointer owns the parsed `Layout` instance when parsing
 *   succeeds.
 * @invariant Parsing does not mutate the source string.
 */
std::unique_ptr<dogpaw::Layout> parse_layout_json(const char* layoutJson) {
  const std::string layoutJsonString = string_or_fallback(layoutJson, "{}");
  nlohmann::json parsedLayoutJson = nlohmann::json::parse(layoutJsonString);
  dogpaw::normalizeLayoutJsonFromDartFfiPayload(parsedLayoutJson);
  return dogpaw::Layout::fromJson(parsedLayoutJson);
}

/**
 * @brief Parse one Dog Paw KV JSON string into a typed C++ `KV`.
 *
 * Purpose:
 * Reuses the existing typed `KV::fromJson()` parser so the bridge does not
 * duplicate KV-schema knowledge.
 *
 * @param kvJson UTF-8 JSON string encoding one Dog Paw `KV`.
 * @return Parsed `KV` on success, or `nullptr` if parsing fails.
 *
 * @pre `kvJson` points to a valid JSON object string.
 * @post Returned pointer owns the parsed `KV` instance when parsing succeeds.
 * @invariant Parsing does not mutate the source string.
 */
std::unique_ptr<dogpaw::KV> parse_kv_json(const char* kvJson) {
  const std::string kvJsonString = string_or_fallback(kvJson, "{}");
  const nlohmann::json parsedKvJson = nlohmann::json::parse(kvJsonString);
  return dogpaw::KV::fromJson(parsedKvJson);
}

/**
 * @brief Parse one Dog Paw endpoint JSON string into a typed C++ `Endpoint`.
 *
 * Purpose:
 * Reuses `Endpoint::fromJson()` so the bridge does not duplicate
 * endpoint-schema knowledge.
 *
 * @param endpointJson UTF-8 JSON string encoding one Dog Paw `Endpoint`.
 * @return Parsed `Endpoint` on success, or `nullptr` if parsing fails.
 *
 * @pre `endpointJson` points to a valid JSON object string.
 * @post Returned pointer owns the parsed `Endpoint` when parsing succeeds.
 * @invariant Parsing does not mutate the source string.
 */
std::unique_ptr<dogpaw::Endpoint> parse_endpoint_json(const char* endpointJson) {
  const std::string endpointJsonString = string_or_fallback(endpointJson, "{}");
  const nlohmann::json parsedEndpointJson =
      nlohmann::json::parse(endpointJsonString);
  return dogpaw::Endpoint::fromJson(parsedEndpointJson, false);
}

/**
 * @brief Serialize one C++ endpoint for the Dart bridge with resolved transport
 * metadata preserved.
 *
 * Purpose:
 * Extends the generic endpoint JSON representation with the `sharedMemory`
 * object that Dart uses to build local runtime handles for owned endpoints.
 *
 * @param endpoint Fully populated endpoint returned by the C++ DogPawEntity.
 * @return JSON object containing standard endpoint data plus resolved transport
 * resource names when they are available.
 *
 * @pre `endpoint` refers to a valid C++ endpoint instance.
 * @post Returned JSON can be decoded by Dart `EndpointInfo.fromJson()`.
 * @post Resolved queue/shared-data/JACK/file fields are emitted under
 * `sharedMemory` when present.
 * @invariant This helper does not mutate `endpoint`.
 */
nlohmann::json serialize_endpoint_for_dart(const dogpaw::Endpoint& endpoint) {
  nlohmann::json endpointJson = endpoint.toJson();
  nlohmann::json sharedMemoryJson = nlohmann::json::object();

  const std::optional<std::string> queueShmName = endpoint.getQueueShmName();
  if (queueShmName.has_value()) {
    sharedMemoryJson[JF::QUEUE_SHM_NAME] = queueShmName.value();
  }

  const std::optional<std::string> socketPath = endpoint.getSocketPath();
  if (socketPath.has_value()) {
    sharedMemoryJson[JF::SOCKET_PATH] = socketPath.value();
  }

  const std::optional<std::string> sharedDataName =
      endpoint.getSharedDataName();
  if (sharedDataName.has_value()) {
    sharedMemoryJson[JF::SHARED_DATA_NAME] = sharedDataName.value();
  }

  const std::optional<std::string> shmNamespacePrefix =
      endpoint.getShmNamespacePrefix();
  if (shmNamespacePrefix.has_value()) {
    sharedMemoryJson[JF::SHM_NAMESPACE_PREFIX] = shmNamespacePrefix.value();
  }

  const std::optional<std::string> jackPortName = endpoint.getJackPortName();
  if (jackPortName.has_value()) {
    sharedMemoryJson[JF::JACK_PORT_NAME] = jackPortName.value();
  }

  const std::optional<std::string> filePath = endpoint.getFilePath();
  if (filePath.has_value()) {
    sharedMemoryJson[JF::FILE_PATH] = filePath.value();
  }

  if (!sharedMemoryJson.empty()) {
    endpointJson["sharedMemory"] = sharedMemoryJson;
  }

  return endpointJson;
}

/**
 * @brief Resolve one native-owned local endpoint by current-entity name.
 *
 * Purpose:
 * Reuses the wrapped C++ `DogPawEntity`'s live owned-endpoint map so runtime
 * bridge calls operate on the same endpoint instances that already receive
 * native connection and index-spec updates.
 *
 * @param bridge Native bridge wrapper containing the live C++ entity.
 * @param endpointName Owned endpoint name in the current entity namespace.
 * @return Shared endpoint pointer on success, or null when the endpoint is not
 * currently available.
 *
 * @pre `bridge` is non-null.
 * @pre `endpointName` is non-empty.
 * @post Endpoint state is unchanged.
 * @invariant Access is serialized through the wrapped `DogPawEntity`.
 */
std::shared_ptr<dogpaw::Endpoint> resolve_local_endpoint(
    NativeDogPawEntityBridge* bridge,
    const std::string& endpointName) {
  if (bridge == nullptr || endpointName.empty()) {
    return nullptr;
  }

  std::lock_guard<std::mutex> lock(bridge->mutex);
  if (bridge->destroying || bridge->entity == nullptr) {
    return nullptr;
  }

  return bridge->entity->getEndpoint(endpointName);
}

/**
 * @brief Map one Dog Paw base data type to the bridge's integer enum.
 *
 * Purpose:
 * Converts native `dogpaw::DataType` values into the stable C ABI enum used by
 * `dppb_get_data_size()`.
 *
 * @param dataType Native Dog Paw base data type.
 * @return Matching `DPPB_TYPE_*` constant, or `-1` when unsupported.
 *
 * @pre None.
 * @post Endpoint state is unchanged.
 * @invariant Mapping order must stay aligned with `dogpaw_bridge.h`.
 */
int bridge_data_type_index(const dogpaw::DataType dataType) {
  switch (dataType) {
    case dogpaw::DataType::FLOAT:
      return DPPB_TYPE_FLOAT;
    case dogpaw::DataType::FLOAT2:
      return DPPB_TYPE_FLOAT2;
    case dogpaw::DataType::FLOAT3:
      return DPPB_TYPE_FLOAT3;
    case dogpaw::DataType::FLOAT4:
      return DPPB_TYPE_FLOAT4;
    case dogpaw::DataType::INT:
      return DPPB_TYPE_INT;
    case dogpaw::DataType::INT2:
      return DPPB_TYPE_INT2;
    case dogpaw::DataType::TOGGLE:
      return DPPB_TYPE_TOGGLE;
    case dogpaw::DataType::MOMENTARY:
      return DPPB_TYPE_MOMENTARY;
    case dogpaw::DataType::ENUM:
      return DPPB_TYPE_ENUM;
    case dogpaw::DataType::AUDIO_STREAM:
      return DPPB_TYPE_AUDIO_STREAM;
    case dogpaw::DataType::KEY_PRESS:
      return DPPB_TYPE_KEY_PRESS;
    case dogpaw::DataType::NEAR_PRESS:
      return DPPB_TYPE_NEAR_PRESS;
    case dogpaw::DataType::RAW_SENSORS:
      return DPPB_TYPE_RAW_SENSORS;
    case dogpaw::DataType::NOTE_CONTROL:
      return DPPB_TYPE_NOTE_CONTROL;
    case dogpaw::DataType::MIDI_MESSAGE:
      return DPPB_TYPE_MIDI_MESSAGE;
    case dogpaw::DataType::LED_MESSAGE:
      return DPPB_TYPE_LED_MESSAGE;
    case dogpaw::DataType::KEY_POSITION:
      return DPPB_TYPE_KEY_POSITION;
    case dogpaw::DataType::VOICE_MESSAGE:
      return DPPB_TYPE_VOICE_MESSAGE;
    case dogpaw::DataType::VOICE_OUTPUT_VALUE:
      return DPPB_TYPE_VOICE_OUTPUT_VALUE;
    case dogpaw::DataType::GLOBAL_OUTPUT_VALUE:
      return DPPB_TYPE_GLOBAL_OUTPUT_VALUE;
    case dogpaw::DataType::DPP_PARAM_QUEUE:
      return DPPB_TYPE_DPP_PARAM_QUEUE;
    case dogpaw::DataType::CUSTOM:
      return DPPB_TYPE_CUSTOM;
    case dogpaw::DataType::SCOPE_BUFFER:
      return DPPB_TYPE_SCOPE_BUFFER;
  }

  return -1;
}

/**
 * @brief Convert one native `IndexSpec` into bridge enum fields.
 *
 * Purpose:
 * Normalizes connection-specific payload shape metadata for the Dart FFI layer.
 *
 * @param indexSpec Native endpoint index specification.
 * @param outIndexType Output bridge enum receiving the normalized index type.
 * @param outIndexDim1 Output first index dimension.
 * @param outIndexDim2 Output second index dimension.
 * @return `true` when the spec was converted successfully, otherwise `false`.
 *
 * @pre Output pointers are non-null.
 * @post Output fields describe the same index shape as `indexSpec`.
 * @invariant Conversion is pure and does not mutate endpoint state.
 */
bool fill_index_shape_fields(const dogpaw::IndexSpec& indexSpec,
                             int32_t* outIndexType,
                             int32_t* outIndexDim1,
                             int32_t* outIndexDim2) {
  if (outIndexType == nullptr || outIndexDim1 == nullptr ||
      outIndexDim2 == nullptr) {
    return false;
  }

  if (std::holds_alternative<dogpaw::IndexTypeNone>(indexSpec)) {
    *outIndexType = DPPB_INDEX_NONE;
    *outIndexDim1 = 0;
    *outIndexDim2 = 0;
    return true;
  }

  if (std::holds_alternative<dogpaw::KeyIndexSpec>(indexSpec)) {
    const dogpaw::KeyIndexSpec& keySpec =
        std::get<dogpaw::KeyIndexSpec>(indexSpec);
    *outIndexType = DPPB_INDEX_KEY;
    *outIndexDim1 = keySpec.width;
    *outIndexDim2 = keySpec.height;
    return true;
  }

  if (std::holds_alternative<dogpaw::VoiceIndexSpec>(indexSpec)) {
    const dogpaw::VoiceIndexSpec& voiceSpec =
        std::get<dogpaw::VoiceIndexSpec>(indexSpec);
    *outIndexType = DPPB_INDEX_VOICE;
    *outIndexDim1 = voiceSpec.numVoices;
    *outIndexDim2 = 0;
    return true;
  }

  return false;
}

/**
 * @brief Copy one native file-backed connection's current bytes into a
 * caller-owned buffer.
 *
 * Purpose:
 * Centralizes the native `poll` then `read` flow used by the file-backed local
 * endpoint bridge helpers so Dart can query required sizes and retrieve bytes
 * without keeping its own file-path cache.
 *
 * @param endpoint Resolved native-owned endpoint.
 * @param connectionName Realized connection identifier for this input endpoint.
 * @param requireNotification Whether a file-backed notification must be
 *   observed before reading the file.
 * @param outData Writable output buffer, or null to query required size only.
 * @param maxSize Capacity of `outData` in bytes.
 * @return Positive byte count on success, `0` when no notification was
 * observed, or `-1` on error.
 *
 * @pre `endpoint` is non-null and represents an input FILE_BACKED endpoint.
 * @pre `connectionName` is non-empty.
 * @post When successful and `outData` is large enough, it contains the current
 *   file contents for [connectionName].
 * @invariant Endpoint metadata is unchanged by this helper.
 */
int32_t copy_file_backed_connection_bytes(
    const std::shared_ptr<dogpaw::Endpoint>& endpoint,
    const std::string& connectionName,
    const bool requireNotification,
    void* outData,
    const int32_t maxSize) {
  if (endpoint == nullptr || connectionName.empty()) {
    return -1;
  }

  try {
    if (requireNotification) {
      bool sawNotification = false;
      const bool pollSuccess = endpoint->pollMessageQueue(
          connectionName,
          [&sawNotification]([[maybe_unused]] const void* notificationData) {
            sawNotification = true;
          });
      if (!pollSuccess) {
        return -1;
      }
      if (!sawNotification) {
        return 0;
      }
    }

    std::vector<uint8_t> payloadBytes;
    const bool readSuccess = endpoint->readFileBacked(
        [&payloadBytes](const void* source, const size_t size) {
          const uint8_t* typedSource = static_cast<const uint8_t*>(source);
          payloadBytes.assign(typedSource, typedSource + size);
        },
        std::optional<std::string>(connectionName));
    if (!readSuccess) {
      return -1;
    }

    const int32_t requiredSize = static_cast<int32_t>(payloadBytes.size());
    if (outData == nullptr || maxSize <= 0) {
      return requiredSize;
    }
    if (maxSize < requiredSize) {
      return requiredSize;
    }
    if (requiredSize > 0) {
      std::memcpy(outData, payloadBytes.data(), static_cast<size_t>(requiredSize));
    }
    return requiredSize;
  } catch (...) {
    return -1;
  }
}

nlohmann::json index_spec_to_json(const dogpaw::IndexSpec& indexSpec) {
  if (std::holds_alternative<dogpaw::IndexTypeNone>(indexSpec)) {
    return nlohmann::json{{"type", "none"}};
  }

  if (std::holds_alternative<dogpaw::KeyIndexSpec>(indexSpec)) {
    const dogpaw::KeyIndexSpec& keySpec =
        std::get<dogpaw::KeyIndexSpec>(indexSpec);
    return nlohmann::json{
        {"type", "key"},
        {"width", keySpec.width},
        {"height", keySpec.height},
    };
  }

  const dogpaw::VoiceIndexSpec& voiceSpec =
      std::get<dogpaw::VoiceIndexSpec>(indexSpec);
  return nlohmann::json{
      {"type", "voice"},
      {"num_voices", voiceSpec.numVoices},
  };
}

/**
 * @brief Parse Dog Paw `SearchCriteria` JSON into a typed C++ value.
 *
 * Purpose:
 * Reuses `SearchCriteria::fromJson()` so the bridge does not duplicate search
 * schema knowledge.
 *
 * @param criteriaJson UTF-8 JSON string encoding `SearchCriteria`.
 * @return Parsed criteria on success, or `nullptr` if parsing fails.
 *
 * @pre `criteriaJson` points to valid JSON object text.
 * @invariant Parsing does not mutate the source string.
 */
std::unique_ptr<dogpaw::SearchCriteria> parse_search_criteria_json(
    const char* criteriaJson) {
  const std::string criteriaString = string_or_fallback(criteriaJson, "{}");
  const nlohmann::json parsedCriteriaJson =
      nlohmann::json::parse(criteriaString);
  return dogpaw::SearchCriteria::fromJson(parsedCriteriaJson);
}

/**
 * @brief Parse one Dog Paw `ConnectionRequest` JSON string.
 *
 * Purpose:
 * Reuses `ConnectionRequest::fromJson()` so the bridge does not duplicate
 * schema knowledge.
 *
 * @param jsonUtf8 UTF-8 JSON object text for one `ConnectionRequest`.
 * @return Parsed request on success, or `nullptr` if parsing fails.
 */
std::unique_ptr<dogpaw::ConnectionRequest> parse_connection_request_json(
    const char* jsonUtf8) {
  const std::string jsonString = string_or_fallback(jsonUtf8, "{}");
  const nlohmann::json parsedJson = nlohmann::json::parse(jsonString);
  return dogpaw::ConnectionRequest::fromJson(parsedJson, false);
}

/**
 * @brief Parse one Dog Paw `FollowRequest` JSON string.
 *
 * Purpose:
 * Reuses `FollowRequest::fromJson()` so the bridge does not duplicate schema
 * knowledge.
 *
 * @param jsonUtf8 UTF-8 JSON object text for one `FollowRequest`.
 * @return Parsed request on success, or `nullptr` if parsing fails.
 */
std::unique_ptr<dogpaw::FollowRequest> parse_follow_request_json(
    const char* jsonUtf8) {
  const std::string jsonString = string_or_fallback(jsonUtf8, "{}");
  const nlohmann::json parsedJson = nlohmann::json::parse(jsonString);
  return dogpaw::FollowRequest::fromJson(parsedJson, false);
}

/**
 * @brief Store one launched request worker thread on the bridge.
 *
 * Purpose:
 * Centralizes the "join immediately if already destroying, otherwise retain"
 * rule shared by all async bridge requests.
 *
 * @param bridge Native bridge state that owns request worker threads.
 * @param requestThread Newly launched worker thread for one async request.
 * @return `true` when the thread was stored successfully, otherwise `false`.
 *
 * @pre `requestThread` is joinable.
 * @post On success, `bridge` owns the worker thread until shutdown.
 * @invariant If the bridge is already destroying, the thread is joined before
 *   this helper returns.
 */
bool store_request_thread(NativeDogPawEntityBridge* bridge,
                          std::thread&& requestThread) {
  std::lock_guard<std::mutex> lock(bridge->mutex);
  if (bridge->destroying) {
    if (requestThread.joinable()) {
      requestThread.join();
    }
    return false;
  }
  bridge->requestThreads.push_back(std::move(requestThread));
  return true;
}

void NativeDogPawEntityBridge::shutdown() {
  std::vector<std::thread> requestThreadsToJoin;
  std::optional<dogpaw::ConnectionStartHandle> pendingHandleToClose;
  dogpaw::DogPawEntity* entityToDisconnect = nullptr;

  {
    std::lock_guard<std::mutex> lock(mutex);
    if (destroying) {
      return;
    }
    destroying = true;
    pendingHandleToClose = std::move(pendingConnectionStartHandle);
    pendingConnectionStartHandle.reset();
    requestThreadsToJoin = std::move(requestThreads);
    entityToDisconnect = entity.get();
  }

  if (pendingHandleToClose.has_value()) {
    pendingHandleToClose->setReadyMessage(
        dogpaw::ConnectionStartHandleMessageType::ERROR);
    pendingHandleToClose->sendReadyMessage();
  }

  if (entityToDisconnect != nullptr) {
    entityToDisconnect->disconnect();
  }

  for (std::thread& requestThread : requestThreadsToJoin) {
    if (requestThread.joinable()) {
      requestThread.join();
    }
  }

  std::lock_guard<std::mutex> lock(mutex);
  entity.reset();
  eventPort = ILLEGAL_PORT;
}

extern "C" {

/**
 * @brief Initialize the dynamically linked Dart API for async native posting.
 */
int64_t dppb_initialize_dart_api(void* initialize_api_data) {
  return Dart_InitializeApiDL(initialize_api_data);
}

/**
 * @brief Create a native-backed DogPawEntity bridge wrapper.
 */
void* dppb_dpe_create(const char* entity_name,
                      const char* server_url,
                      const int32_t timeout_ms) {
  if (entity_name == nullptr || timeout_ms < 0) {
    return nullptr;
  }

  try {
    auto* bridge = new NativeDogPawEntityBridge(
        entity_name,
        string_or_fallback(server_url, "ws://localhost:8080"),
        timeout_ms);
    bridge->entity->setErrorCallback(
        [bridge](const std::string& errorMessage) {
          post_bridge_event(bridge, make_error_event(errorMessage));
        });
    bridge->entity->setDirectMessageCallback(
        [bridge](const std::string& senderEntity, nlohmann::json&& message) {
          post_bridge_event(
              bridge,
              make_direct_message_event(senderEntity, message));
        });
    bridge->entity->setEndpointConnectionAddedCallback(
        [bridge](const std::string& localEndpointName,
                 const std::string& connectionName,
                 const dogpaw::DataItemRefByName& peerEndpointRef) {
          const dogpaw::DataItemRefByName localEndpointRef(
              localEndpointName,
              dogpaw::NamespaceSelector::specificEntity(
                  bridge->entity->getEntityName()));
          nlohmann::json connectionJson = nlohmann::json::object();
          connectionJson[JF::NAME] = connectionName;
          connectionJson["target"] = peerEndpointRef.toJson();
          post_bridge_event(
              bridge,
              make_endpoint_runtime_notification_event(
                  "endpoint_connection_added",
                  localEndpointRef,
                  connectionJson));
        });
    bridge->entity->setEndpointConnectionRemovedCallback(
        [bridge](const std::string& localEndpointName,
                 const std::string& connectionName,
                 const dogpaw::DataItemRefByName& peerEndpointRef) {
          const dogpaw::DataItemRefByName localEndpointRef(
              localEndpointName,
              dogpaw::NamespaceSelector::specificEntity(
                  bridge->entity->getEntityName()));
          nlohmann::json connectionJson = nlohmann::json::object();
          connectionJson[JF::NAME] = connectionName;
          connectionJson["target"] = peerEndpointRef.toJson();
          post_bridge_event(
              bridge,
              make_endpoint_runtime_notification_event(
                  "endpoint_connection_removed",
                  localEndpointRef,
                  connectionJson));
        });
    bridge->entity->setEndpointConnectionIndexSpecChangedCallback(
        [bridge](const std::string& localEndpointName,
                 const std::string& connectionName,
                 const dogpaw::DataItemRefByName& peerEndpointRef,
                 const dogpaw::IndexSpec& newIndexSpec) {
          const dogpaw::DataItemRefByName localEndpointRef(
              localEndpointName,
              dogpaw::NamespaceSelector::specificEntity(
                  bridge->entity->getEntityName()));
          nlohmann::json connectionJson = nlohmann::json::object();
          connectionJson[JF::NAME] = connectionName;
          connectionJson["target"] = peerEndpointRef.toJson();
          connectionJson[JF::INDEX_SPEC] = index_spec_to_json(newIndexSpec);
          post_bridge_event(
              bridge,
              make_endpoint_runtime_notification_event(
                  "endpoint_index_spec_changed",
                  localEndpointRef,
                  connectionJson));
        });
    bridge->entity->setCommandCallback(
        [bridge](const std::string& senderEntity,
                 const std::string& command,
                 nlohmann::json&& params,
                 const std::string& commandId) {
          post_bridge_event(
              bridge,
              make_incoming_command_event(senderEntity, command, params, commandId));
        });
    bridge->entity->setPresetRequestCallback(
        [bridge](const std::string& serverRequestId, nlohmann::json&& content) {
          const bool posted = post_bridge_event(
              bridge,
              make_preset_request_event(content));
          if (!posted) {
            AppLogger::warning(
                "dppb_dpe_create: Failed to forward preset request to Dart; "
                "completing with error for serverRequestId: " + serverRequestId);
            bridge->entity->completePresetRequest(
                serverRequestId,
                false,
                "Failed to deliver preset request to Dart.");
          }
          return false;
        });
    return bridge;
  } catch (const std::exception& exception) {
    AppLogger::error("dppb_dpe_create: Failed to create native DogPawEntity bridge: " +
                     std::string(exception.what()));
    return nullptr;
  } catch (...) {
    AppLogger::error(
        "dppb_dpe_create: Failed to create native DogPawEntity bridge with unknown exception");
    return nullptr;
  }
}

/**
 * @brief Destroy a native-backed DogPawEntity bridge wrapper.
 */
void dppb_dpe_destroy(void* handle) {
  if (handle == nullptr) {
    return;
  }
  delete static_cast<NativeDogPawEntityBridge*>(handle);
}

/**
 * @brief Store the Dart event port used for async request results and errors.
 */
bool dppb_dpe_set_event_port(void* handle, const int64_t port) {
  if (handle == nullptr || port == ILLEGAL_PORT) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::lock_guard<std::mutex> lock(bridge->mutex);
  if (bridge->destroying) {
    return false;
  }
  bridge->eventPort = port;
  return true;
}

/**
 * @brief Launch an asynchronous native-backed connect request.
 */
bool dppb_dpe_connect_async(void* handle, const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::ConnectionStartHandleResult connectResult =
              bridge->entity->connect();
          if (connectResult.success) {
            {
              std::lock_guard<std::mutex> lock(bridge->mutex);
              if (!bridge->destroying) {
                bridge->pendingConnectionStartHandle =
                    std::move(connectResult.value);
              }
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id, "connect", true, "", nlohmann::json::object()));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "connect",
                    false,
                    connectResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "connect",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Complete the pending native connection-start handle.
 */
bool dppb_dpe_complete_connection_start(void* handle,
                                        const int32_t ready_message_type) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::optional<dogpaw::ConnectionStartHandle> pendingHandle;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || !bridge->pendingConnectionStartHandle.has_value()) {
      return false;
    }
    pendingHandle = std::move(bridge->pendingConnectionStartHandle);
    bridge->pendingConnectionStartHandle.reset();
  }

  if (ready_message_type == 1) {
    pendingHandle->setReadyMessage(
        dogpaw::ConnectionStartHandleMessageType::ERROR);
  } else {
    pendingHandle->setReadyMessage(
        dogpaw::ConnectionStartHandleMessageType::READY);
  }
  pendingHandle->sendReadyMessage();
  return true;
}

/**
 * @brief Disconnect the wrapped native DogPawEntity immediately.
 */
void dppb_dpe_disconnect(void* handle) {
  if (handle == nullptr) {
    return;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::optional<dogpaw::ConnectionStartHandle> pendingHandleToClose;
  dogpaw::DogPawEntity* entityToDisconnect = nullptr;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->entity == nullptr) {
      return;
    }
    pendingHandleToClose = std::move(bridge->pendingConnectionStartHandle);
    bridge->pendingConnectionStartHandle.reset();
    entityToDisconnect = bridge->entity.get();
  }

  if (pendingHandleToClose.has_value()) {
    pendingHandleToClose->setReadyMessage(
        dogpaw::ConnectionStartHandleMessageType::ERROR);
    pendingHandleToClose->sendReadyMessage();
  }

  entityToDisconnect->disconnect();
}

/**
 * @brief Query whether the wrapped C++ entity currently reports connected.
 */
bool dppb_dpe_is_connected(void* handle) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::lock_guard<std::mutex> lock(bridge->mutex);
  if (bridge->destroying || bridge->entity == nullptr) {
    return false;
  }
  return bridge->entity->isConnected();
}

/**
 * @brief Launch an asynchronous native-backed `subscribeToEntityLifecycle()`
 * request.
 */
bool dppb_dpe_subscribe_entity_lifecycle_async(void* handle,
                                               const int64_t request_id,
                                               const char* entity_name,
                                               const bool send_immediately) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::optional<std::string> watchEntityName =
      (entity_name != nullptr) ? std::optional<std::string>(std::string(entity_name))
                               : std::nullopt;
  std::thread requestThread(
      [bridge, request_id, watchEntityName, send_immediately]() mutable {
        try {
          dogpaw::OperationResult subscribeResult =
              bridge->entity
                  ->subscribeToEntityLifecycle(
                      dogpaw::EntityLifecycleCallback(
                          [bridge](const std::string& notificationType,
                                   const std::string& entityName) {
                            post_bridge_event(
                                bridge,
                                make_entity_lifecycle_notification_event(
                                    notificationType, entityName));
                          }),
                      watchEntityName,
                      send_immediately)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToEntityLifecycle",
                  subscribeResult.success,
                  subscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToEntityLifecycle",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed
 * `unsubscribeFromEntityLifecycle()` request.
 */
bool dppb_dpe_unsubscribe_entity_lifecycle_async(void* handle,
                                                 const int64_t request_id,
                                                 const char* entity_name) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::optional<std::string> watchEntityName =
      (entity_name != nullptr) ? std::optional<std::string>(std::string(entity_name))
                               : std::nullopt;
  std::thread requestThread(
      [bridge, request_id, watchEntityName]() mutable {
        try {
          dogpaw::OperationResult unsubscribeResult =
              bridge->entity->unsubscribeFromEntityLifecycle(watchEntityName)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromEntityLifecycle",
                  unsubscribeResult.success,
                  unsubscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromEntityLifecycle",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `sendDirectMessage()` request.
 */
bool dppb_dpe_send_direct_message_async(void* handle,
                                        const int64_t request_id,
                                        const char* target_entity,
                                        const char* message_json) {
  if (handle == nullptr || target_entity == nullptr || message_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  nlohmann::json messageJson;
  try {
    messageJson = parse_json_object(message_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "sendDirectMessage",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::string targetEntity(target_entity);
  std::thread requestThread([bridge, request_id, targetEntity, messageJson]() mutable {
    try {
      dogpaw::OperationResult sendResult =
          bridge->entity->sendDirectMessage(targetEntity, messageJson).get();
      post_bridge_event(
          bridge,
          make_request_result_event(
              request_id,
              "sendDirectMessage",
              sendResult.success,
              sendResult.error,
              nlohmann::json::object()));
    } catch (const std::exception& exception) {
      post_bridge_event(
          bridge,
          make_request_result_event(
              request_id,
              "sendDirectMessage",
              false,
              exception.what(),
              nlohmann::json::object()));
    }
  });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `sendCommand()` request.
 */
bool dppb_dpe_send_command_async(void* handle,
                                 const int64_t request_id,
                                 const char* target_entity,
                                 const char* command,
                                 const char* params_json,
                                 const int32_t timeout_ms,
                                 const bool wait_for_completion,
                                 const char* delivery_policy_json) {
  if (handle == nullptr || target_entity == nullptr || command == nullptr ||
      params_json == nullptr || timeout_ms < 0) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  nlohmann::json paramsJson;
  std::optional<dogpaw::CommandDeliveryPolicy> deliveryPolicy = std::nullopt;
  try {
    paramsJson = parse_json_object(params_json);
    if (delivery_policy_json != nullptr) {
      deliveryPolicy = dogpaw::CommandDeliveryPolicy::fromJson(
          parse_json_object(delivery_policy_json));
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "sendCommand",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::string targetEntity(target_entity);
  const std::string commandName(command);
  std::thread requestThread(
      [bridge,
       request_id,
       targetEntity,
       commandName,
       paramsJson,
       timeout_ms,
       wait_for_completion,
       deliveryPolicy]() mutable {
        try {
          dogpaw::OnAcceptedCallback onAccepted = nullptr;
          if (wait_for_completion) {
            onAccepted =
                [bridge, request_id](const nlohmann::json& acceptedResult) {
                  post_bridge_event(
                      bridge,
                      make_command_accepted_event(request_id, acceptedResult));
                };
          }

          dogpaw::CommandResponseResult commandResult =
              bridge->entity
                  ->sendCommand(
                      targetEntity,
                      commandName,
                      paramsJson,
                      std::chrono::milliseconds(timeout_ms),
                      wait_for_completion,
                      onAccepted,
                      deliveryPolicy)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "sendCommand",
                  commandResult.success,
                  commandResult.error,
                  commandResult.result));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "sendCommand",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Send a native-backed `sendCommandResponse()` message immediately.
 */
bool dppb_dpe_send_command_response(void* handle,
                                    const char* target_entity,
                                    const char* command_id,
                                    const bool success,
                                    const char* result_json,
                                    const char* error_message) {
  if (handle == nullptr || target_entity == nullptr || command_id == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  nlohmann::json resultJson;
  try {
    resultJson = parse_json_object(result_json);
  } catch (const std::exception&) {
    return false;
  }

  std::lock_guard<std::mutex> lock(bridge->mutex);
  if (bridge->destroying || bridge->entity == nullptr) {
    return false;
  }
  bridge->entity->sendCommandResponse(
      target_entity,
      command_id,
      success,
      resultJson,
      string_or_fallback(error_message, ""));
  return true;
}

/**
 * @brief Send a native-backed `sendCommandAccepted()` message immediately.
 */
bool dppb_dpe_send_command_accepted(void* handle,
                                    const char* target_entity,
                                    const char* command_id) {
  if (handle == nullptr || target_entity == nullptr || command_id == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::lock_guard<std::mutex> lock(bridge->mutex);
  if (bridge->destroying || bridge->entity == nullptr) {
    return false;
  }
  bridge->entity->sendCommandAccepted(target_entity, command_id);
  return true;
}

/**
 * @brief Complete one deferred preset request immediately through the wrapped
 * C++ DogPawEntity.
 */
bool dppb_dpe_complete_preset_request(void* handle,
                                      const char* server_request_id,
                                      const bool success,
                                      const char* error_message) {
  if (handle == nullptr || server_request_id == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::lock_guard<std::mutex> lock(bridge->mutex);
  if (bridge->destroying || bridge->entity == nullptr) {
    return false;
  }

  bridge->entity->completePresetRequest(
      server_request_id,
      success,
      string_or_fallback(error_message, ""));
  return true;
}

/**
 * @brief Launch an asynchronous native-backed `saveGlobalState()` request.
 */
bool dppb_dpe_save_global_state_async(void* handle,
                                      const int64_t request_id,
                                      const char* preset_name) {
  if (handle == nullptr || preset_name == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string presetName(preset_name);
  std::thread requestThread(
      [bridge, request_id, presetName]() mutable {
        try {
          dogpaw::OperationResult saveResult =
              bridge->entity->saveGlobalState(presetName).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "saveGlobalState",
                  saveResult.success,
                  saveResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "saveGlobalState",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `loadGlobalState()` request.
 */
bool dppb_dpe_load_global_state_async(void* handle,
                                      const int64_t request_id,
                                      const char* preset_name) {
  if (handle == nullptr || preset_name == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string presetName(preset_name);
  std::thread requestThread(
      [bridge, request_id, presetName]() mutable {
        try {
          dogpaw::OperationResult loadResult =
              bridge->entity->loadGlobalState(presetName).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "loadGlobalState",
                  loadResult.success,
                  loadResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "loadGlobalState",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `log()` request.
 */
bool dppb_dpe_log_async(void* handle,
                        const int64_t request_id,
                        const char* message) {
  if (handle == nullptr || message == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string logMessage(message);
  std::thread requestThread(
      [bridge, request_id, logMessage]() mutable {
        try {
          dogpaw::OperationResult logResult =
              bridge->entity->log(logMessage).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "log",
                  logResult.success,
                  logResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "log",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `startLogSection()` request.
 */
bool dppb_dpe_start_log_section_async(void* handle,
                                      const int64_t request_id,
                                      const char* section_title) {
  if (handle == nullptr || section_title == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string sectionTitle(section_title);
  std::thread requestThread(
      [bridge, request_id, sectionTitle]() mutable {
        try {
          dogpaw::OperationResult startResult =
              bridge->entity->startLogSection(sectionTitle).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "startLogSection",
                  startResult.success,
                  startResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "startLogSection",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `flushLogSection()` request.
 */
bool dppb_dpe_flush_log_section_async(void* handle,
                                      const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::OperationResult flushResult =
              bridge->entity->flushLogSection().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "flushLogSection",
                  flushResult.success,
                  flushResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "flushLogSection",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `endLogSection()` request.
 */
bool dppb_dpe_end_log_section_async(void* handle,
                                    const int64_t request_id,
                                    const bool flush) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id, flush]() mutable {
        try {
          dogpaw::OperationResult endResult =
              bridge->entity->endLogSection(flush).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "endLogSection",
                  endResult.success,
                  endResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "endLogSection",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `getSystemInfo()` request.
 */
bool dppb_dpe_get_system_info_async(void* handle,
                                    const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::Result<nlohmann::json> systemInfoResult =
              bridge->entity->getSystemInfo().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "getSystemInfo",
                  systemInfoResult.success,
                  systemInfoResult.error,
                  systemInfoResult.value));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "getSystemInfo",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `listApps()` request.
 */
bool dppb_dpe_list_apps_async(void* handle,
                              const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::Result<nlohmann::json> appListResult =
              bridge->entity->listApps().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listApps",
                  appListResult.success,
                  appListResult.error,
                  appListResult.value));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listApps",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `listRunningEntities()` request.
 */
bool dppb_dpe_list_running_entities_async(void* handle,
                                          const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::Result<nlohmann::json> entityListResult =
              bridge->entity->listRunningEntities().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listRunningEntities",
                  entityListResult.success,
                  entityListResult.error,
                  entityListResult.value));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listRunningEntities",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `launchApp()` request.
 */
bool dppb_dpe_launch_app_async(void* handle,
                               const int64_t request_id,
                               const char* app_name,
                               const char* launch_metadata_json) {
  if (handle == nullptr || app_name == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string appName(app_name);

  std::optional<nlohmann::json> launchMetadata;
  if (launch_metadata_json != nullptr && launch_metadata_json[0] != '\0') {
    try {
      launchMetadata = nlohmann::json::parse(launch_metadata_json);
    } catch (const std::exception& exception) {
      post_bridge_event(
          bridge,
          make_request_result_event(
              request_id,
              "launchApp",
              false,
              std::string("Failed to parse launchMetadata JSON: ") +
                  exception.what(),
              nlohmann::json::object()));
      return true;
    }
  }

  std::thread requestThread(
      [bridge, request_id, appName, launchMetadata]() mutable {
        try {
          dogpaw::Result<std::string> launchResult =
              bridge->entity->launchApp(appName, launchMetadata).get();
          nlohmann::json resultJson = nlohmann::json::object();
          if (launchResult.success) {
            resultJson[JF::ENTITY_NAME] = launchResult.value;
          }
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "launchApp",
                  launchResult.success,
                  launchResult.error,
                  resultJson));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "launchApp",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `stopApp()` request.
 */
bool dppb_dpe_stop_app_async(void* handle,
                             const int64_t request_id,
                             const char* app_name) {
  if (handle == nullptr || app_name == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string appName(app_name);
  std::thread requestThread(
      [bridge, request_id, appName]() mutable {
        try {
          dogpaw::OperationResult stopResult =
              bridge->entity->stopApp(appName).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "stopApp",
                  stopResult.success,
                  stopResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "stopApp",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `killAllApps()` request.
 */
bool dppb_dpe_kill_all_apps_async(void* handle,
                                  const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::StringResult killResult =
              bridge->entity->killAllApps().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "killAllApps",
                  killResult.success,
                  killResult.error,
                  nlohmann::json{{JF::MESSAGE, killResult.value}}));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "killAllApps",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `setTheme()` request.
 */
bool dppb_dpe_set_theme_async(void* handle,
                              const int64_t request_id,
                              const char* theme_json) {
  if (handle == nullptr || theme_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Theme> theme;
  try {
    theme = parse_theme_json(theme_json);
    if (theme == nullptr) {
      throw std::runtime_error("Failed to parse theme JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "setTheme",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, theme = std::move(theme)]() mutable {
        try {
          dogpaw::OperationResult setResult = bridge->entity->setTheme(*theme).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setTheme",
                  setResult.success,
                  setResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `createTheme()` request.
 */
bool dppb_dpe_create_theme_async(void* handle,
                                 const int64_t request_id,
                                 const char* theme_json,
                                 const bool auto_suffix) {
  if (handle == nullptr || theme_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Theme> theme;
  try {
    theme = parse_theme_json(theme_json);
    if (theme == nullptr) {
      throw std::runtime_error("Failed to parse theme JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "createTheme",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, theme = std::move(theme), auto_suffix]() mutable {
        try {
          dogpaw::OperationResult createResult =
              bridge->entity->createTheme(*theme, auto_suffix).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createTheme",
                  createResult.success,
                  createResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `updateTheme()` request.
 */
bool dppb_dpe_update_theme_async(void* handle,
                                 const int64_t request_id,
                                 const char* theme_json) {
  if (handle == nullptr || theme_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Theme> theme;
  try {
    theme = parse_theme_json(theme_json);
    if (theme == nullptr) {
      throw std::runtime_error("Failed to parse theme JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "updateTheme",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, theme = std::move(theme)]() mutable {
        try {
          dogpaw::OperationResult updateResult =
              bridge->entity->updateTheme(*theme).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateTheme",
                  updateResult.success,
                  updateResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readTheme()` request.
 */
bool dppb_dpe_read_theme_async(void* handle,
                               const int64_t request_id,
                               const char* name,
                               const char* namespace_selector_json,
                               const bool include_resolved,
                               const bool include_spec) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "readTheme",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string themeName(name);
  std::thread requestThread(
      [bridge, request_id, themeName, namespaceSelector, include_resolved, include_spec]() mutable {
        try {
          dogpaw::Result<dogpaw::optional<dogpaw::Theme>> readResult =
              bridge->entity->readTheme(
                  themeName, namespaceSelector, include_resolved, include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value.has_value()) {
              resultJson[JF::THEME] = readResult.value->toJson();
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readTheme",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readTheme",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `deleteTheme()` request.
 */
bool dppb_dpe_delete_theme_async(void* handle,
                                 const int64_t request_id,
                                 const char* name,
                                 const char* namespace_selector_json) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "deleteTheme",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string themeName(name);
  std::thread requestThread(
      [bridge, request_id, themeName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult deleteResult =
              bridge->entity->deleteTheme(themeName, namespaceSelector).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteTheme",
                  deleteResult.success,
                  deleteResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `setCurrentTheme()` request.
 */
bool dppb_dpe_set_current_theme_async(void* handle,
                                      const int64_t request_id,
                                      const char* name,
                                      const char* namespace_selector_json) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "setCurrentTheme",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string themeName(name);
  std::thread requestThread(
      [bridge, request_id, themeName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult setCurrentResult =
              bridge->entity->setCurrentTheme(themeName, namespaceSelector).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setCurrentTheme",
                  setCurrentResult.success,
                  setCurrentResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setCurrentTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readCurrentTheme()` request.
 */
bool dppb_dpe_read_current_theme_async(void* handle,
                                       const int64_t request_id,
                                       const bool include_resolved,
                                       const bool include_spec) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id, include_resolved, include_spec]() mutable {
        try {
          dogpaw::Result<dogpaw::optional<dogpaw::Theme>> readResult =
              bridge->entity->readCurrentTheme(include_resolved, include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value.has_value()) {
              resultJson[JF::THEME] = readResult.value->toJson();
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readCurrentTheme",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readCurrentTheme",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readCurrentTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `removeCurrentTheme()` request.
 */
bool dppb_dpe_remove_current_theme_async(void* handle,
                                         const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::OperationResult removeCurrentResult =
              bridge->entity->removeCurrentTheme().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "removeCurrentTheme",
                  removeCurrentResult.success,
                  removeCurrentResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "removeCurrentTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `listThemes()` request.
 */
bool dppb_dpe_list_themes_async(void* handle,
                                const int64_t request_id,
                                const char* namespace_selector_json,
                                const bool include_resolved,
                                const bool include_spec) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id, "listThemes", false, exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::future<dogpaw::Result<std::vector<dogpaw::Theme>>> listFuture;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || bridge->entity == nullptr) {
      return false;
    }
    listFuture = bridge->entity->listThemes(
        namespaceSelector, include_resolved, include_spec);
  }

  std::thread requestThread(
      [bridge, request_id, listFuture = std::move(listFuture)]() mutable {
        try {
          dogpaw::Result<std::vector<dogpaw::Theme>> listResult = listFuture.get();
          if (listResult.success) {
            nlohmann::json themesJson = nlohmann::json::array();
            for (const dogpaw::Theme& theme : listResult.value) {
              themesJson.push_back(theme.toJson());
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listThemes",
                    true,
                    "",
                    nlohmann::json{{JF::THEMES, themesJson}}));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listThemes",
                    false,
                    listResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listThemes",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `subscribeToThemes()` request.
 */
bool dppb_dpe_subscribe_themes_async(void* handle,
                                     const int64_t request_id,
                                     const char* name,
                                     const char* namespace_selector_json,
                                     const bool include_resolved,
                                     const bool include_spec,
                                     const bool send_immediately) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "subscribeToThemes",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> themeName =
      (name != nullptr) ? std::optional<std::string>(std::string(name))
                        : std::nullopt;
  std::thread requestThread(
      [bridge,
       request_id,
       themeName,
       namespaceSelector,
       include_resolved,
       include_spec,
       send_immediately]() mutable {
        try {
          dogpaw::OperationResult subscribeResult =
              bridge->entity
                  ->subscribeToThemes(
                      dogpaw::ThemeChangeCallback([bridge](
                          const std::string& notificationType,
                          const dogpaw::DataItemRefByName& itemRef,
                          const dogpaw::Theme& theme) {
                        post_bridge_event(
                            bridge,
                            make_subscription_notification_event(
                                epiphany::Topics::THEME_NOTIFICATION,
                                notificationType,
                                itemRef,
                                JF::THEME,
                                theme.toJson()));
                      }),
                      themeName,
                      namespaceSelector,
                      include_resolved,
                      include_spec,
                      send_immediately)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToThemes",
                  subscribeResult.success,
                  subscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToThemes",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromThemes()`
 * request.
 */
bool dppb_dpe_unsubscribe_themes_async(void* handle,
                                       const int64_t request_id,
                                       const char* name,
                                       const char* namespace_selector_json) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "unsubscribeFromThemes",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> themeName =
      (name != nullptr) ? std::optional<std::string>(std::string(name))
                        : std::nullopt;
  std::thread requestThread(
      [bridge, request_id, themeName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult unsubscribeResult =
              bridge->entity
                  ->unsubscribeFromThemes(themeName, namespaceSelector)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromThemes",
                  unsubscribeResult.success,
                  unsubscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromThemes",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `subscribeToCurrentTheme()`
 * request.
 */
bool dppb_dpe_subscribe_current_theme_async(void* handle,
                                            const int64_t request_id,
                                            const bool include_resolved,
                                            const bool include_spec,
                                            const bool send_immediately) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge,
       request_id,
       include_resolved,
       include_spec,
       send_immediately]() mutable {
        try {
          dogpaw::OperationResult subscribeResult =
              bridge->entity
                  ->subscribeToCurrentTheme(
                      dogpaw::ThemeChangeCallback([bridge](
                          const std::string& notificationType,
                          const dogpaw::DataItemRefByName& itemRef,
                          const dogpaw::Theme& theme) {
                        post_bridge_event(
                            bridge,
                            make_subscription_notification_event(
                                epiphany::Topics::THEME_NOTIFICATION,
                                notificationType,
                                itemRef,
                                JF::THEME,
                                theme.toJson()));
                      }),
                      include_resolved,
                      include_spec,
                      send_immediately)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToCurrentTheme",
                  subscribeResult.success,
                  subscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToCurrentTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromCurrentTheme()`
 * request.
 */
bool dppb_dpe_unsubscribe_current_theme_async(void* handle,
                                              const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::OperationResult unsubscribeResult =
              bridge->entity->unsubscribeFromCurrentTheme().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromCurrentTheme",
                  unsubscribeResult.success,
                  unsubscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromCurrentTheme",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `setScale()` request.
 */
bool dppb_dpe_set_scale_async(void* handle,
                              const int64_t request_id,
                              const char* scale_json) {
  if (handle == nullptr || scale_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Scale> scale;
  try {
    scale = parse_scale_json(scale_json);
    if (scale == nullptr) {
      throw std::runtime_error("Failed to parse scale JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "setScale",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, scale = std::move(scale)]() mutable {
        try {
          dogpaw::OperationResult setResult = bridge->entity->setScale(*scale).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setScale",
                  setResult.success,
                  setResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `createScale()` request.
 */
bool dppb_dpe_create_scale_async(void* handle,
                                 const int64_t request_id,
                                 const char* scale_json,
                                 const bool auto_suffix) {
  if (handle == nullptr || scale_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Scale> scale;
  try {
    scale = parse_scale_json(scale_json);
    if (scale == nullptr) {
      throw std::runtime_error("Failed to parse scale JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "createScale",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, scale = std::move(scale), auto_suffix]() mutable {
        try {
          dogpaw::OperationResult createResult =
              bridge->entity->createScale(*scale, auto_suffix).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createScale",
                  createResult.success,
                  createResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `updateScale()` request.
 */
bool dppb_dpe_update_scale_async(void* handle,
                                 const int64_t request_id,
                                 const char* scale_json) {
  if (handle == nullptr || scale_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Scale> scale;
  try {
    scale = parse_scale_json(scale_json);
    if (scale == nullptr) {
      throw std::runtime_error("Failed to parse scale JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "updateScale",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, scale = std::move(scale)]() mutable {
        try {
          dogpaw::OperationResult updateResult =
              bridge->entity->updateScale(*scale).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateScale",
                  updateResult.success,
                  updateResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readScale()` request.
 */
bool dppb_dpe_read_scale_async(void* handle,
                               const int64_t request_id,
                               const char* name,
                               const char* namespace_selector_json,
                               const bool include_resolved,
                               const bool include_spec) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "readScale",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string scaleName(name);
  std::thread requestThread(
      [bridge, request_id, scaleName, namespaceSelector, include_resolved, include_spec]() mutable {
        try {
          dogpaw::Result<dogpaw::optional<dogpaw::Scale>> readResult =
              bridge->entity->readScale(
                  scaleName, namespaceSelector, include_resolved, include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value.has_value()) {
              resultJson[JF::SCALE] = readResult.value->toJson();
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readScale",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readScale",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `deleteScale()` request.
 */
bool dppb_dpe_delete_scale_async(void* handle,
                                 const int64_t request_id,
                                 const char* name,
                                 const char* namespace_selector_json) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "deleteScale",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string scaleName(name);
  std::thread requestThread(
      [bridge, request_id, scaleName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult deleteResult =
              bridge->entity->deleteScale(scaleName, namespaceSelector).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteScale",
                  deleteResult.success,
                  deleteResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `setCurrentScale()` request.
 */
bool dppb_dpe_set_current_scale_async(void* handle,
                                      const int64_t request_id,
                                      const char* name,
                                      const char* namespace_selector_json) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "setCurrentScale",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string scaleName(name);
  std::thread requestThread(
      [bridge, request_id, scaleName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult setCurrentResult =
              bridge->entity->setCurrentScale(scaleName, namespaceSelector).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setCurrentScale",
                  setCurrentResult.success,
                  setCurrentResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setCurrentScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readCurrentScale()` request.
 */
bool dppb_dpe_read_current_scale_async(void* handle,
                                       const int64_t request_id,
                                       const bool include_resolved,
                                       const bool include_spec) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id, include_resolved, include_spec]() mutable {
        try {
          dogpaw::Result<dogpaw::optional<dogpaw::Scale>> readResult =
              bridge->entity->readCurrentScale(include_resolved, include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value.has_value()) {
              resultJson[JF::SCALE] = readResult.value->toJson();
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readCurrentScale",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readCurrentScale",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readCurrentScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `removeCurrentScale()` request.
 */
bool dppb_dpe_remove_current_scale_async(void* handle,
                                         const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::OperationResult removeCurrentResult =
              bridge->entity->removeCurrentScale().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "removeCurrentScale",
                  removeCurrentResult.success,
                  removeCurrentResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "removeCurrentScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `listScales()` request.
 */
bool dppb_dpe_list_scales_async(void* handle,
                                const int64_t request_id,
                                const char* namespace_selector_json,
                                const bool include_resolved,
                                const bool include_spec) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id, "listScales", false, exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::future<dogpaw::Result<std::vector<dogpaw::Scale>>> listFuture;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || bridge->entity == nullptr) {
      return false;
    }
    listFuture = bridge->entity->listScales(
        namespaceSelector, include_resolved, include_spec);
  }

  std::thread requestThread(
      [bridge, request_id, listFuture = std::move(listFuture)]() mutable {
        try {
          dogpaw::Result<std::vector<dogpaw::Scale>> listResult = listFuture.get();
          if (listResult.success) {
            nlohmann::json scalesJson = nlohmann::json::array();
            for (const dogpaw::Scale& scale : listResult.value) {
              scalesJson.push_back(scale.toJson());
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listScales",
                    true,
                    "",
                    nlohmann::json{{JF::SCALES, scalesJson}}));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listScales",
                    false,
                    listResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listScales",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `setLayout()` request.
 */
bool dppb_dpe_set_layout_async(void* handle,
                               const int64_t request_id,
                               const char* layout_json) {
  if (handle == nullptr || layout_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Layout> layout;
  try {
    layout = parse_layout_json(layout_json);
    if (layout == nullptr) {
      throw std::runtime_error("Failed to parse layout JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "setLayout",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, layout = std::move(layout)]() mutable {
        try {
          dogpaw::OperationResult setResult = bridge->entity->setLayout(*layout).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setLayout",
                  setResult.success,
                  setResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setLayout",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `createLayout()` request.
 */
bool dppb_dpe_create_layout_async(void* handle,
                                  const int64_t request_id,
                                  const char* layout_json,
                                  const bool auto_suffix) {
  if (handle == nullptr || layout_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Layout> layout;
  try {
    layout = parse_layout_json(layout_json);
    if (layout == nullptr) {
      throw std::runtime_error("Failed to parse layout JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "createLayout",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, layout = std::move(layout), auto_suffix]() mutable {
        try {
          // Always pass addToLayoutStack=false from the bridge. The Dart
          // facade's createLayout composes create + addLayoutStackEntry when
          // addToLayoutStack is requested, so the C++ hybrid behavior would
          // cause a double-add.
          dogpaw::OperationResult createResult =
              bridge->entity
                  ->createLayout(*layout, auto_suffix,
                                 /*addToLayoutStack=*/false)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createLayout",
                  createResult.success,
                  createResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createLayout",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `updateLayout()` request.
 */
bool dppb_dpe_update_layout_async(void* handle,
                                  const int64_t request_id,
                                  const char* layout_json) {
  if (handle == nullptr || layout_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Layout> layout;
  try {
    layout = parse_layout_json(layout_json);
    if (layout == nullptr) {
      throw std::runtime_error("Failed to parse layout JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "updateLayout",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, layout = std::move(layout)]() mutable {
        try {
          dogpaw::OperationResult updateResult =
              bridge->entity->updateLayout(*layout).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateLayout",
                  updateResult.success,
                  updateResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateLayout",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readLayout()` request.
 */
bool dppb_dpe_read_layout_async(void* handle,
                                const int64_t request_id,
                                const char* name,
                                const char* namespace_selector_json,
                                const bool include_resolved,
                                const bool include_spec) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "readLayout",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string layoutName(name);
  std::thread requestThread(
      [bridge, request_id, layoutName, namespaceSelector, include_resolved, include_spec]() mutable {
        try {
          dogpaw::Result<dogpaw::optional<dogpaw::Layout>> readResult =
              bridge->entity->readLayout(
                  layoutName, namespaceSelector, include_resolved, include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value.has_value()) {
              resultJson[JF::LAYOUT] = readResult.value->toJson();
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readLayout",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readLayout",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readLayout",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `deleteLayout()` request.
 */
bool dppb_dpe_delete_layout_async(void* handle,
                                  const int64_t request_id,
                                  const char* name,
                                  const char* namespace_selector_json) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "deleteLayout",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string layoutName(name);
  std::thread requestThread(
      [bridge, request_id, layoutName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult deleteResult =
              bridge->entity->deleteLayout(layoutName, namespaceSelector).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteLayout",
                  deleteResult.success,
                  deleteResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteLayout",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `listLayouts()` request.
 */
bool dppb_dpe_list_layouts_async(void* handle,
                                 const int64_t request_id,
                                 const char* namespace_selector_json,
                                 const bool include_resolved,
                                 const bool include_spec) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id, "listLayouts", false, exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::future<dogpaw::Result<std::vector<dogpaw::Layout>>> listFuture;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || bridge->entity == nullptr) {
      return false;
    }
    listFuture = bridge->entity->listLayouts(
        namespaceSelector, include_resolved, include_spec);
  }

  std::thread requestThread(
      [bridge, request_id, listFuture = std::move(listFuture)]() mutable {
        try {
          dogpaw::Result<std::vector<dogpaw::Layout>> listResult = listFuture.get();
          if (listResult.success) {
            nlohmann::json layoutsJson = nlohmann::json::array();
            for (const dogpaw::Layout& layout : listResult.value) {
              layoutsJson.push_back(layout.toJson());
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listLayouts",
                    true,
                    "",
                    nlohmann::json{{JF::LAYOUTS, layoutsJson}}));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listLayouts",
                    false,
                    listResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listLayouts",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `setKV()` request.
 */
bool dppb_dpe_set_kv_async(void* handle,
                           const int64_t request_id,
                           const char* kv_json) {
  if (handle == nullptr || kv_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::KV> kv;
  try {
    kv = parse_kv_json(kv_json);
    if (kv == nullptr) {
      throw std::runtime_error("Failed to parse KV JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "setKV",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, kv = std::move(kv)]() mutable {
        try {
          dogpaw::OperationResult setResult = bridge->entity->setKV(*kv).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setKV",
                  setResult.success,
                  setResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setKV",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `createKV()` request.
 */
bool dppb_dpe_create_kv_async(void* handle,
                              const int64_t request_id,
                              const char* kv_json) {
  if (handle == nullptr || kv_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::KV> kv;
  try {
    kv = parse_kv_json(kv_json);
    if (kv == nullptr) {
      throw std::runtime_error("Failed to parse KV JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "createKV",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, kv = std::move(kv)]() mutable {
        try {
          dogpaw::OperationResult createResult =
              bridge->entity->createKV(*kv).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createKV",
                  createResult.success,
                  createResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createKV",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `updateKV()` request.
 */
bool dppb_dpe_update_kv_async(void* handle,
                              const int64_t request_id,
                              const char* kv_json) {
  if (handle == nullptr || kv_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::KV> kv;
  try {
    kv = parse_kv_json(kv_json);
    if (kv == nullptr) {
      throw std::runtime_error("Failed to parse KV JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "updateKV",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, kv = std::move(kv)]() mutable {
        try {
          dogpaw::OperationResult updateResult =
              bridge->entity->updateKV(*kv).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateKV",
                  updateResult.success,
                  updateResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateKV",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readKV()` request.
 */
bool dppb_dpe_read_kv_async(void* handle,
                            const int64_t request_id,
                            const char* name,
                            const char* namespace_selector_json,
                            const bool include_resolved,
                            const bool include_spec) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "readKV",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string kvName(name);
  std::thread requestThread(
      [bridge, request_id, kvName, namespaceSelector, include_resolved, include_spec]() mutable {
        try {
          dogpaw::Result<dogpaw::optional<dogpaw::KV>> readResult =
              bridge->entity->readKV(
                  kvName, namespaceSelector, include_resolved, include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value.has_value()) {
              resultJson[JF::KV] = readResult.value->toJson();
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readKV",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readKV",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readKV",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `deleteKV()` request.
 */
bool dppb_dpe_delete_kv_async(void* handle,
                              const int64_t request_id,
                              const char* name,
                              const char* namespace_selector_json) {
  if (handle == nullptr || name == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "deleteKV",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::string kvName(name);
  std::thread requestThread(
      [bridge, request_id, kvName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult deleteResult =
              bridge->entity->deleteKV(kvName, namespaceSelector).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteKV",
                  deleteResult.success,
                  deleteResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteKV",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `listKVs()` request.
 */
bool dppb_dpe_list_kvs_async(void* handle,
                             const int64_t request_id,
                             const char* namespace_selector_json,
                             const bool include_resolved,
                             const bool include_spec) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id, "listKVs", false, exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::future<dogpaw::Result<std::vector<dogpaw::KV>>> listFuture;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || bridge->entity == nullptr) {
      return false;
    }
    listFuture = bridge->entity->listKVs(
        namespaceSelector, include_resolved, include_spec);
  }

  std::thread requestThread(
      [bridge, request_id, listFuture = std::move(listFuture)]() mutable {
        try {
          dogpaw::Result<std::vector<dogpaw::KV>> listResult = listFuture.get();
          if (listResult.success) {
            nlohmann::json kvsJson = nlohmann::json::array();
            for (const dogpaw::KV& kv : listResult.value) {
              kvsJson.push_back(kv.toJson());
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listKVs",
                    true,
                    "",
                    nlohmann::json{{JF::KVS, kvsJson}}));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listKVs",
                    false,
                    listResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listKVs",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `createEndpoint()` request.
 */
bool dppb_dpe_create_endpoint_async(void* handle,
                                    const int64_t request_id,
                                    const char* endpoint_json,
                                    const bool auto_suffix) {
  if (handle == nullptr || endpoint_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Endpoint> endpoint;
  try {
    endpoint = parse_endpoint_json(endpoint_json);
    if (endpoint == nullptr) {
      throw std::runtime_error("Failed to parse endpoint JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "createEndpoint",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, endpoint = std::move(endpoint), auto_suffix]() mutable {
        try {
          dogpaw::Result<std::shared_ptr<dogpaw::Endpoint>> createResult =
              bridge->entity->createEndpoint(*endpoint, auto_suffix).get();
          if (createResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (createResult.value != nullptr) {
              resultJson[JF::ENDPOINT] =
                  serialize_endpoint_for_dart(*createResult.value);
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "createEndpoint",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "createEndpoint",
                    false,
                    createResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createEndpoint",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `updateEndpoint()` request.
 */
bool dppb_dpe_update_endpoint_async(void* handle,
                                    const int64_t request_id,
                                    const char* endpoint_json) {
  if (handle == nullptr || endpoint_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Endpoint> endpoint;
  try {
    endpoint = parse_endpoint_json(endpoint_json);
    if (endpoint == nullptr) {
      throw std::runtime_error("Failed to parse endpoint JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "updateEndpoint",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, endpoint = std::move(endpoint)]() mutable {
        try {
          dogpaw::Result<std::shared_ptr<dogpaw::Endpoint>> updateResult =
              bridge->entity->updateEndpoint(*endpoint).get();
          if (updateResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (updateResult.value != nullptr) {
              resultJson[JF::ENDPOINT] =
                  serialize_endpoint_for_dart(*updateResult.value);
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "updateEndpoint",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "updateEndpoint",
                    false,
                    updateResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateEndpoint",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `setEndpoint()` request.
 */
bool dppb_dpe_set_endpoint_async(void* handle,
                                 const int64_t request_id,
                                 const char* endpoint_json) {
  if (handle == nullptr || endpoint_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::Endpoint> endpoint;
  try {
    endpoint = parse_endpoint_json(endpoint_json);
    if (endpoint == nullptr) {
      throw std::runtime_error("Failed to parse endpoint JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "setEndpoint",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, endpoint = std::move(endpoint)]() mutable {
        try {
          dogpaw::Result<std::shared_ptr<dogpaw::Endpoint>> setResult =
              bridge->entity->setEndpoint(*endpoint).get();
          if (setResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (setResult.value != nullptr) {
              resultJson[JF::ENDPOINT] =
                  serialize_endpoint_for_dart(*setResult.value);
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "setEndpoint",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "setEndpoint",
                    false,
                    setResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setEndpoint",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readEndpoint()` request.
 */
bool dppb_dpe_read_endpoint_async(void* handle,
                                  const int64_t request_id,
                                  const char* name,
                                  const char* namespace_selector_json,
                                  const bool include_resolved,
                                  const bool include_spec) {
  if (handle == nullptr || name == nullptr ||
      namespace_selector_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "readEndpoint",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::string endpointName(name);
  std::thread requestThread(
      [bridge,
       request_id,
       endpointName,
       namespaceSelector,
       include_resolved,
       include_spec]() mutable {
        try {
          dogpaw::Result<std::shared_ptr<dogpaw::Endpoint>> readResult =
              bridge->entity
                  ->readEndpoint(
                      endpointName,
                      namespaceSelector,
                      include_resolved,
                      include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value != nullptr) {
              resultJson[JF::ENDPOINT] =
                  serialize_endpoint_for_dart(*readResult.value);
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readEndpoint",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readEndpoint",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readEndpoint",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `deleteEndpoint()` request.
 */
bool dppb_dpe_delete_endpoint_async(void* handle,
                                    const int64_t request_id,
                                    const char* name) {
  if (handle == nullptr || name == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string endpointName(name);
  std::thread requestThread(
      [bridge, request_id, endpointName]() mutable {
        try {
          dogpaw::OperationResult deleteResult =
              bridge->entity->deleteEndpoint(endpointName).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteEndpoint",
                  deleteResult.success,
                  deleteResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteEndpoint",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `searchEndpoints()` request.
 */
bool dppb_dpe_search_endpoints_async(void* handle,
                                     const int64_t request_id,
                                     const char* criteria_json) {
  if (handle == nullptr || criteria_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::SearchCriteria> criteriaPtr;
  try {
    criteriaPtr = parse_search_criteria_json(criteria_json);
    if (criteriaPtr == nullptr) {
      throw std::runtime_error("Failed to parse search criteria JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "searchEndpoints",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  dogpaw::SearchCriteria criteria = std::move(*criteriaPtr);

  std::future<dogpaw::Result<std::vector<std::shared_ptr<dogpaw::Endpoint>>>>
      searchFuture;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || bridge->entity == nullptr) {
      return false;
    }
    searchFuture = bridge->entity->searchEndpoints(criteria);
  }

  std::thread requestThread(
      [bridge, request_id, searchFuture = std::move(searchFuture)]() mutable {
        try {
          dogpaw::Result<std::vector<std::shared_ptr<dogpaw::Endpoint>>>
              searchResult = searchFuture.get();
          if (searchResult.success) {
            nlohmann::json endpointsJson = nlohmann::json::array();
            for (const std::shared_ptr<dogpaw::Endpoint>& ep :
                 searchResult.value) {
              if (ep != nullptr) {
                endpointsJson.push_back(serialize_endpoint_for_dart(*ep));
              }
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "searchEndpoints",
                    true,
                    "",
                    nlohmann::json{{JF::ENDPOINTS, endpointsJson}}));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "searchEndpoints",
                    false,
                    searchResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "searchEndpoints",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

bool dppb_dpe_subscribe_endpoints_async(void* handle,
                                        const int64_t request_id,
                                        const char* name,
                                        const char* namespace_selector_json,
                                        const bool include_resolved,
                                        const bool include_spec,
                                        const bool send_immediately) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "subscribeToEndpoints",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> endpointName =
      (name != nullptr) ? std::optional<std::string>(std::string(name))
                        : std::nullopt;
  std::thread requestThread(
      [bridge,
       request_id,
       endpointName,
       namespaceSelector,
       include_resolved,
       include_spec,
       send_immediately]() mutable {
        try {
          dogpaw::OperationResult subscribeResult =
              bridge->entity
                  ->subscribeToEndpoints(
                      dogpaw::EndpointChangeCallback([bridge](
                          const std::string& notificationType,
                          const dogpaw::DataItemRefByName& itemRef,
                          const dogpaw::Endpoint& endpoint) {
                        post_bridge_event(
                            bridge,
                            make_subscription_notification_event(
                                epiphany::Topics::ENDPOINT_NOTIFICATION,
                                notificationType,
                                itemRef,
                                JF::ENDPOINT,
                                serialize_endpoint_for_dart(endpoint)));
                      }),
                      endpointName,
                      namespaceSelector,
                      include_resolved,
                      include_spec,
                      send_immediately)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToEndpoints",
                  subscribeResult.success,
                  subscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToEndpoints",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

bool dppb_dpe_unsubscribe_endpoints_async(void* handle,
                                          const int64_t request_id,
                                          const char* name,
                                          const char* namespace_selector_json) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "unsubscribeFromEndpoints",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> endpointName =
      (name != nullptr) ? std::optional<std::string>(std::string(name))
                        : std::nullopt;
  std::thread requestThread(
      [bridge, request_id, endpointName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult unsubscribeResult =
              bridge->entity
                  ->unsubscribeFromEndpoints(endpointName, namespaceSelector)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromEndpoints",
                  unsubscribeResult.success,
                  unsubscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromEndpoints",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

bool dppb_dpe_local_endpoint_write(void* handle,
                                   const char* endpoint_name,
                                   const void* data,
                                   const int32_t size,
                                   const bool immediate) {
  if (handle == nullptr || endpoint_name == nullptr || data == nullptr ||
      size <= 0) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  const std::shared_ptr<dogpaw::Endpoint> endpoint =
      resolve_local_endpoint(bridge, std::string(endpoint_name));
  if (endpoint == nullptr) {
    return false;
  }

  const dogpaw::EndpointSpec& endpointSpec = endpoint->getData();
  if (endpointSpec.direction != dogpaw::EndpointDirection::OUTPUT) {
    return false;
  }

  if (endpointSpec.category == dogpaw::EndpointCategory::MESSAGE_QUEUE) {
    return endpoint->writeToMessageQueue(data, immediate);
  }

  if (endpointSpec.category == dogpaw::EndpointCategory::CONTINUOUS) {
    return endpoint->writeToSharedData(
        [data, size](void* destination, const size_t destinationSize) {
          const size_t copySize =
              std::min(destinationSize, static_cast<size_t>(size));
          std::memcpy(destination, data, copySize);
        });
  }

  if (endpointSpec.category == dogpaw::EndpointCategory::FILE_BACKED) {
    return endpoint->writeFileBacked(data, static_cast<size_t>(size));
  }

  return false;
}

int32_t dppb_dpe_local_endpoint_get_connection_count(void* handle,
                                                     const char* endpoint_name) {
  if (handle == nullptr || endpoint_name == nullptr) {
    return -1;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  const std::shared_ptr<dogpaw::Endpoint> endpoint =
      resolve_local_endpoint(bridge, std::string(endpoint_name));
  if (endpoint == nullptr) {
    return -1;
  }

  try {
    return static_cast<int32_t>(endpoint->getConnections().size());
  } catch (...) {
    return -1;
  }
}

int32_t dppb_dpe_local_endpoint_get_connection_name(void* handle,
                                                    const char* endpoint_name,
                                                    const int32_t index,
                                                    char* out_name,
                                                    const int32_t max_size) {
  if (handle == nullptr || endpoint_name == nullptr || index < 0) {
    return -1;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  const std::shared_ptr<dogpaw::Endpoint> endpoint =
      resolve_local_endpoint(bridge, std::string(endpoint_name));
  if (endpoint == nullptr) {
    return -1;
  }

  try {
    const std::vector<std::string> connectionNames = endpoint->getConnections();
    if (static_cast<size_t>(index) >= connectionNames.size()) {
      return -1;
    }

    const std::string& connectionName = connectionNames[static_cast<size_t>(index)];
    const int32_t requiredSize =
        static_cast<int32_t>(connectionName.size() + 1);
    if (out_name == nullptr || max_size <= 0) {
      return requiredSize;
    }

    if (max_size < requiredSize) {
      return requiredSize;
    }

    std::memcpy(out_name, connectionName.c_str(),
                static_cast<size_t>(requiredSize));
    return requiredSize;
  } catch (...) {
    return -1;
  }
}

bool dppb_dpe_local_endpoint_get_connection_shape(
    void* handle,
    const char* endpoint_name,
    const char* connection_name,
    int32_t* out_index_type,
    int32_t* out_index_dim1,
    int32_t* out_index_dim2,
    int32_t* out_payload_size) {
  if (handle == nullptr || endpoint_name == nullptr ||
      connection_name == nullptr || out_index_type == nullptr ||
      out_index_dim1 == nullptr || out_index_dim2 == nullptr ||
      out_payload_size == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  const std::shared_ptr<dogpaw::Endpoint> endpoint =
      resolve_local_endpoint(bridge, std::string(endpoint_name));
  if (endpoint == nullptr) {
    return false;
  }

  try {
    const dogpaw::EndpointSpec& endpointSpec = endpoint->getData();
    const dogpaw::IndexSpec connectionIndexSpec =
        endpoint->getConnectionIndexSpec(std::string(connection_name));

    if (!fill_index_shape_fields(connectionIndexSpec, out_index_type,
                                 out_index_dim1, out_index_dim2)) {
      return false;
    }

    const int dataTypeIndex =
        bridge_data_type_index(endpointSpec.dataType.baseType);
    if (dataTypeIndex < 0) {
      return false;
    }

    *out_payload_size = dppb_get_data_size(dataTypeIndex, *out_index_type,
                                           *out_index_dim1, *out_index_dim2);
    return *out_payload_size > 0;
  } catch (...) {
    return false;
  }
}

int32_t dppb_dpe_local_endpoint_poll_connection(void* handle,
                                                const char* endpoint_name,
                                                const char* connection_name,
                                                void* out_data,
                                                const int32_t max_size) {
  if (handle == nullptr || endpoint_name == nullptr ||
      connection_name == nullptr || out_data == nullptr || max_size <= 0) {
    return -1;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  const std::shared_ptr<dogpaw::Endpoint> endpoint =
      resolve_local_endpoint(bridge, std::string(endpoint_name));
  if (endpoint == nullptr) {
    return -1;
  }

  const dogpaw::EndpointSpec& endpointSpec = endpoint->getData();
  if (endpointSpec.direction != dogpaw::EndpointDirection::INPUT) {
    return -1;
  }

  int32_t bytesRead = 0;
  const std::string connectionName(connection_name);

  try {
    if (endpointSpec.category == dogpaw::EndpointCategory::MESSAGE_QUEUE) {
      const bool success = endpoint->pollMessageQueue(
          connectionName,
          [&out_data, &bytesRead, max_size](const void* source,
                                            const size_t size) {
            const size_t copySize =
                std::min(static_cast<size_t>(max_size), size);
            std::memcpy(out_data, source, copySize);
            bytesRead = static_cast<int32_t>(copySize);
          });
      return success ? bytesRead : 0;
    }

    if (endpointSpec.category == dogpaw::EndpointCategory::CONTINUOUS) {
      const bool success = endpoint->readFromSharedData(
          connectionName,
          [&out_data, &bytesRead, max_size](const void* source,
                                            const size_t size) {
            const size_t copySize =
                std::min(static_cast<size_t>(max_size), size);
            std::memcpy(out_data, source, copySize);
            bytesRead = static_cast<int32_t>(copySize);
          });
      return success ? bytesRead : 0;
    }
  } catch (...) {
    return -1;
  }

  return -1;
}

int32_t dppb_dpe_local_endpoint_read_file_backed(void* handle,
                                                 const char* endpoint_name,
                                                 const char* connection_name,
                                                 void* out_data,
                                                 const int32_t max_size) {
  if (handle == nullptr || endpoint_name == nullptr ||
      connection_name == nullptr) {
    return -1;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  const std::shared_ptr<dogpaw::Endpoint> endpoint =
      resolve_local_endpoint(bridge, std::string(endpoint_name));
  if (endpoint == nullptr) {
    return -1;
  }

  const dogpaw::EndpointSpec& endpointSpec = endpoint->getData();
  if (endpointSpec.direction != dogpaw::EndpointDirection::INPUT ||
      endpointSpec.category != dogpaw::EndpointCategory::FILE_BACKED) {
    return -1;
  }

  return copy_file_backed_connection_bytes(
      endpoint, std::string(connection_name), false, out_data, max_size);
}

int32_t dppb_dpe_local_endpoint_poll_file_backed(void* handle,
                                                 const char* endpoint_name,
                                                 const char* connection_name,
                                                 void* out_data,
                                                 const int32_t max_size) {
  if (handle == nullptr || endpoint_name == nullptr ||
      connection_name == nullptr) {
    return -1;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  const std::shared_ptr<dogpaw::Endpoint> endpoint =
      resolve_local_endpoint(bridge, std::string(endpoint_name));
  if (endpoint == nullptr) {
    return -1;
  }

  const dogpaw::EndpointSpec& endpointSpec = endpoint->getData();
  if (endpointSpec.direction != dogpaw::EndpointDirection::INPUT ||
      endpointSpec.category != dogpaw::EndpointCategory::FILE_BACKED) {
    return -1;
  }

  return copy_file_backed_connection_bytes(
      endpoint, std::string(connection_name), true, out_data, max_size);
}

/**
 * @brief Launch an asynchronous native-backed `createConnectionRequest()`
 * request.
 */
bool dppb_dpe_create_connection_request_async(
    void* handle,
    const int64_t request_id,
    const char* connection_request_json) {
  if (handle == nullptr || connection_request_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::ConnectionRequest> connectionRequest;
  try {
    connectionRequest = parse_connection_request_json(connection_request_json);
    if (connectionRequest == nullptr) {
      throw std::runtime_error("Failed to parse connection request JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "createConnectionRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, connectionRequest = std::move(connectionRequest)]() mutable {
        try {
          dogpaw::OperationResult opResult =
              bridge->entity->createConnectionRequest(*connectionRequest).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createConnectionRequest",
                  opResult.success,
                  opResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createConnectionRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `setConnectionRequest()`
 * request.
 */
bool dppb_dpe_set_connection_request_async(void* handle,
                                           const int64_t request_id,
                                           const char* connection_request_json) {
  if (handle == nullptr || connection_request_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::ConnectionRequest> connectionRequest;
  try {
    connectionRequest = parse_connection_request_json(connection_request_json);
    if (connectionRequest == nullptr) {
      throw std::runtime_error("Failed to parse connection request JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "setConnectionRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, connectionRequest = std::move(connectionRequest)]() mutable {
        try {
          dogpaw::OperationResult opResult =
              bridge->entity->setConnectionRequest(*connectionRequest).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setConnectionRequest",
                  opResult.success,
                  opResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setConnectionRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `updateConnectionRequest()`
 * request.
 */
bool dppb_dpe_update_connection_request_async(
    void* handle,
    const int64_t request_id,
    const char* connection_request_json) {
  if (handle == nullptr || connection_request_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::ConnectionRequest> connectionRequest;
  try {
    connectionRequest = parse_connection_request_json(connection_request_json);
    if (connectionRequest == nullptr) {
      throw std::runtime_error("Failed to parse connection request JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "updateConnectionRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, connectionRequest = std::move(connectionRequest)]() mutable {
        try {
          dogpaw::OperationResult opResult =
              bridge->entity->updateConnectionRequest(*connectionRequest).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateConnectionRequest",
                  opResult.success,
                  opResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateConnectionRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readConnectionRequest()`
 * request.
 */
bool dppb_dpe_read_connection_request_async(
    void* handle,
    const int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    const bool include_resolved,
    const bool include_spec) {
  if (handle == nullptr || name == nullptr ||
      namespace_selector_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "readConnectionRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::string requestName(name);
  std::thread requestThread(
      [bridge,
       request_id,
       requestName,
       namespaceSelector,
       include_resolved,
       include_spec]() mutable {
        try {
          dogpaw::ConnectionRequestResult readResult =
              bridge->entity
                  ->readConnectionRequest(
                      requestName,
                      namespaceSelector,
                      include_resolved,
                      include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value.has_value()) {
              resultJson[JF::CONNECTION_REQUEST_ITEM] =
                  readResult.value.value().toJson();
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readConnectionRequest",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readConnectionRequest",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readConnectionRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `deleteConnectionRequest()`
 * request.
 */
bool dppb_dpe_delete_connection_request_async(
    void* handle,
    const int64_t request_id,
    const char* name,
    const char* namespace_selector_json) {
  if (handle == nullptr || name == nullptr ||
      namespace_selector_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "deleteConnectionRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::string requestName(name);
  std::thread requestThread(
      [bridge, request_id, requestName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult deleteResult =
              bridge->entity
                  ->deleteConnectionRequest(requestName, namespaceSelector)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteConnectionRequest",
                  deleteResult.success,
                  deleteResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteConnectionRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `listConnectionRequests()`
 * request.
 */
bool dppb_dpe_list_connection_requests_async(
    void* handle,
    const int64_t request_id,
    const char* namespace_selector_json,
    const bool include_resolved,
    const bool include_spec) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "listConnectionRequests",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::future<dogpaw::ConnectionRequestListResult> listFuture;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || bridge->entity == nullptr) {
      return false;
    }
    listFuture = bridge->entity->listConnectionRequests(
        namespaceSelector, include_resolved, include_spec);
  }

  std::thread requestThread(
      [bridge, request_id, listFuture = std::move(listFuture)]() mutable {
        try {
          dogpaw::ConnectionRequestListResult listResult = listFuture.get();
          if (listResult.success) {
            nlohmann::json itemsJson = nlohmann::json::array();
            for (const dogpaw::ConnectionRequest& item : listResult.value) {
              itemsJson.push_back(item.toJson());
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listConnectionRequests",
                    true,
                    "",
                    nlohmann::json{{JF::CONNECTION_REQUESTS, itemsJson}}));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listConnectionRequests",
                    false,
                    listResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listConnectionRequests",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `createFollowRequest()`
 * request.
 */
bool dppb_dpe_create_follow_request_async(void* handle,
                                          const int64_t request_id,
                                          const char* follow_request_json) {
  if (handle == nullptr || follow_request_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::FollowRequest> followRequest;
  try {
    followRequest = parse_follow_request_json(follow_request_json);
    if (followRequest == nullptr) {
      throw std::runtime_error("Failed to parse follow request JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "createFollowRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, followRequest = std::move(followRequest)]() mutable {
        try {
          dogpaw::OperationResult opResult =
              bridge->entity->createFollowRequest(*followRequest).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createFollowRequest",
                  opResult.success,
                  opResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "createFollowRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `setFollowRequest()` request.
 */
bool dppb_dpe_set_follow_request_async(void* handle,
                                       const int64_t request_id,
                                       const char* follow_request_json) {
  if (handle == nullptr || follow_request_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::FollowRequest> followRequest;
  try {
    followRequest = parse_follow_request_json(follow_request_json);
    if (followRequest == nullptr) {
      throw std::runtime_error("Failed to parse follow request JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "setFollowRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, followRequest = std::move(followRequest)]() mutable {
        try {
          dogpaw::OperationResult opResult =
              bridge->entity->setFollowRequest(*followRequest).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setFollowRequest",
                  opResult.success,
                  opResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "setFollowRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `updateFollowRequest()`
 * request.
 */
bool dppb_dpe_update_follow_request_async(void* handle,
                                          const int64_t request_id,
                                          const char* follow_request_json) {
  if (handle == nullptr || follow_request_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::unique_ptr<dogpaw::FollowRequest> followRequest;
  try {
    followRequest = parse_follow_request_json(follow_request_json);
    if (followRequest == nullptr) {
      throw std::runtime_error("Failed to parse follow request JSON");
    }
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "updateFollowRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::thread requestThread(
      [bridge, request_id, followRequest = std::move(followRequest)]() mutable {
        try {
          dogpaw::OperationResult opResult =
              bridge->entity->updateFollowRequest(*followRequest).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateFollowRequest",
                  opResult.success,
                  opResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "updateFollowRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readFollowRequest()` request.
 */
bool dppb_dpe_read_follow_request_async(
    void* handle,
    const int64_t request_id,
    const char* name,
    const char* namespace_selector_json,
    const bool include_resolved,
    const bool include_spec) {
  if (handle == nullptr || name == nullptr ||
      namespace_selector_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "readFollowRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::string requestName(name);
  std::thread requestThread(
      [bridge,
       request_id,
       requestName,
       namespaceSelector,
       include_resolved,
       include_spec]() mutable {
        try {
          dogpaw::FollowRequestResult readResult =
              bridge->entity
                  ->readFollowRequest(
                      requestName,
                      namespaceSelector,
                      include_resolved,
                      include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value.has_value()) {
              resultJson[JF::FOLLOW_REQUEST_ITEM] =
                  readResult.value.value().toJson();
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readFollowRequest",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readFollowRequest",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readFollowRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `deleteFollowRequest()`
 * request.
 */
bool dppb_dpe_delete_follow_request_async(
    void* handle,
    const int64_t request_id,
    const char* name,
    const char* namespace_selector_json) {
  if (handle == nullptr || name == nullptr ||
      namespace_selector_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "deleteFollowRequest",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::string requestName(name);
  std::thread requestThread(
      [bridge, request_id, requestName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult deleteResult =
              bridge->entity
                  ->deleteFollowRequest(requestName, namespaceSelector)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteFollowRequest",
                  deleteResult.success,
                  deleteResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "deleteFollowRequest",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `listFollowRequests()` request.
 */
bool dppb_dpe_list_follow_requests_async(
    void* handle,
    const int64_t request_id,
    const char* namespace_selector_json,
    const bool include_resolved,
    const bool include_spec) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "listFollowRequests",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  std::future<dogpaw::FollowRequestListResult> listFuture;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || bridge->entity == nullptr) {
      return false;
    }
    listFuture = bridge->entity->listFollowRequests(
        namespaceSelector, include_resolved, include_spec);
  }

  std::thread requestThread(
      [bridge, request_id, listFuture = std::move(listFuture)]() mutable {
        try {
          dogpaw::FollowRequestListResult listResult = listFuture.get();
          if (listResult.success) {
            nlohmann::json itemsJson = nlohmann::json::array();
            for (const dogpaw::FollowRequest& item : listResult.value) {
              itemsJson.push_back(item.toJson());
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listFollowRequests",
                    true,
                    "",
                    nlohmann::json{{JF::FOLLOW_REQUESTS, itemsJson}}));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listFollowRequests",
                    false,
                    listResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listFollowRequests",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readConnection()` request.
 */
bool dppb_dpe_read_connection_async(void* handle,
                                    const int64_t request_id,
                                    const char* name,
                                    const bool include_resolved,
                                    const bool include_spec) {
  if (handle == nullptr || name == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string connectionName(name);
  std::thread requestThread(
      [bridge,
       request_id,
       connectionName,
       include_resolved,
       include_spec]() mutable {
        try {
          dogpaw::ConnectionResult readResult =
              bridge->entity
                  ->readConnection(
                      connectionName, include_resolved, include_spec)
                  .get();

          if (readResult.success) {
            nlohmann::json resultJson = nlohmann::json::object();
            if (readResult.value.has_value()) {
              resultJson[JF::CONNECTION] =
                  readResult.value.value().toJson();
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readConnection",
                    true,
                    "",
                    resultJson));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "readConnection",
                    false,
                    readResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readConnection",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `listConnections()` request.
 */
bool dppb_dpe_list_connections_async(void* handle,
                                     const int64_t request_id,
                                     const bool include_resolved,
                                     const bool include_spec) {
  if (handle == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  std::future<dogpaw::ConnectionListResult> listFuture;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    if (bridge->destroying || bridge->entity == nullptr) {
      return false;
    }
    listFuture =
        bridge->entity->listConnections(include_resolved, include_spec);
  }

  std::thread requestThread(
      [bridge, request_id, listFuture = std::move(listFuture)]() mutable {
        try {
          dogpaw::ConnectionListResult listResult = listFuture.get();
          if (listResult.success) {
            nlohmann::json itemsJson = nlohmann::json::array();
            for (const dogpaw::Connection& item : listResult.value) {
              itemsJson.push_back(item.toJson());
            }
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listConnections",
                    true,
                    "",
                    nlohmann::json{{JF::CONNECTIONS, itemsJson}}));
          } else {
            post_bridge_event(
                bridge,
                make_request_result_event(
                    request_id,
                    "listConnections",
                    false,
                    listResult.error,
                    nlohmann::json::object()));
          }
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "listConnections",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `subscribeToScales()` request.
 */
bool dppb_dpe_subscribe_scales_async(void* handle,
                                     const int64_t request_id,
                                     const char* name,
                                     const char* namespace_selector_json,
                                     const bool include_resolved,
                                     const bool include_spec,
                                     const bool send_immediately) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  NativeDogPawEntityBridge* bridge =
      static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "subscribeToScales",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> scaleName =
      (name != nullptr) ? std::optional<std::string>(std::string(name))
                        : std::nullopt;
  std::thread requestThread(
      [bridge,
       request_id,
       scaleName,
       namespaceSelector,
       include_resolved,
       include_spec,
       send_immediately]() mutable {
        try {
          dogpaw::OperationResult subscribeResult =
              bridge->entity
                  ->subscribeToScales(
                      dogpaw::ScaleChangeCallback([bridge](
                          const std::string& notificationType,
                          const dogpaw::DataItemRefByName& itemRef,
                          const dogpaw::Scale& scale) {
                        post_bridge_event(
                            bridge,
                            make_subscription_notification_event(
                                epiphany::Topics::SCALE_NOTIFICATION,
                                notificationType,
                                itemRef,
                                JF::SCALE,
                                scale.toJson()));
                      }),
                      scaleName,
                      namespaceSelector,
                      include_resolved,
                      include_spec,
                      send_immediately)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToScales",
                  subscribeResult.success,
                  subscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToScales",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromScales()`
 * request.
 */
bool dppb_dpe_unsubscribe_scales_async(void* handle,
                                       const int64_t request_id,
                                       const char* name,
                                       const char* namespace_selector_json) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "unsubscribeFromScales",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> scaleName =
      (name != nullptr) ? std::optional<std::string>(std::string(name))
                        : std::nullopt;
  std::thread requestThread(
      [bridge, request_id, scaleName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult unsubscribeResult =
              bridge->entity
                  ->unsubscribeFromScales(scaleName, namespaceSelector)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromScales",
                  unsubscribeResult.success,
                  unsubscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromScales",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `subscribeToCurrentScale()`
 * request.
 */
bool dppb_dpe_subscribe_current_scale_async(void* handle,
                                            const int64_t request_id,
                                            const bool include_resolved,
                                            const bool include_spec,
                                            const bool send_immediately) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge,
       request_id,
       include_resolved,
       include_spec,
       send_immediately]() mutable {
        try {
          dogpaw::OperationResult subscribeResult =
              bridge->entity
                  ->subscribeToCurrentScale(
                      dogpaw::ScaleChangeCallback([bridge](
                          const std::string& notificationType,
                          const dogpaw::DataItemRefByName& itemRef,
                          const dogpaw::Scale& scale) {
                        post_bridge_event(
                            bridge,
                            make_subscription_notification_event(
                                epiphany::Topics::SCALE_NOTIFICATION,
                                notificationType,
                                itemRef,
                                JF::SCALE,
                                scale.toJson()));
                      }),
                      include_resolved,
                      include_spec,
                      send_immediately)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToCurrentScale",
                  subscribeResult.success,
                  subscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToCurrentScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromCurrentScale()`
 * request.
 */
bool dppb_dpe_unsubscribe_current_scale_async(void* handle,
                                              const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::OperationResult unsubscribeResult =
              bridge->entity->unsubscribeFromCurrentScale().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromCurrentScale",
                  unsubscribeResult.success,
                  unsubscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromCurrentScale",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `subscribeToLayouts()` request.
 */
bool dppb_dpe_subscribe_layouts_async(void* handle,
                                      const int64_t request_id,
                                      const char* name,
                                      const char* namespace_selector_json,
                                      const bool include_resolved,
                                      const bool include_spec,
                                      const bool send_immediately) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "subscribeToLayouts",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> layoutName =
      (name != nullptr) ? std::optional<std::string>(std::string(name))
                        : std::nullopt;
  std::thread requestThread(
      [bridge,
       request_id,
       layoutName,
       namespaceSelector,
       include_resolved,
       include_spec,
       send_immediately]() mutable {
        try {
          dogpaw::OperationResult subscribeResult =
              bridge->entity
                  ->subscribeToLayouts(
                      dogpaw::LayoutChangeCallback([bridge](
                          const std::string& notificationType,
                          const dogpaw::DataItemRefByName& itemRef,
                          const dogpaw::Layout& layout) {
                        post_bridge_event(
                            bridge,
                            make_subscription_notification_event(
                                epiphany::Topics::LAYOUT_NOTIFICATION,
                                notificationType,
                                itemRef,
                                JF::LAYOUT,
                                layout.toJson()));
                      }),
                      layoutName,
                      namespaceSelector,
                      include_resolved,
                      include_spec,
                      send_immediately)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToLayouts",
                  subscribeResult.success,
                  subscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToLayouts",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromLayouts()`
 * request.
 */
bool dppb_dpe_unsubscribe_layouts_async(void* handle,
                                        const int64_t request_id,
                                        const char* name,
                                        const char* namespace_selector_json) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "unsubscribeFromLayouts",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> layoutName =
      (name != nullptr) ? std::optional<std::string>(std::string(name))
                        : std::nullopt;
  std::thread requestThread(
      [bridge, request_id, layoutName, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult unsubscribeResult =
              bridge->entity
                  ->unsubscribeFromLayouts(layoutName, namespaceSelector)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromLayouts",
                  unsubscribeResult.success,
                  unsubscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromLayouts",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

// =============================================================================
// Layout stack
// =============================================================================

/**
 * @brief Launch an asynchronous native-backed `addLayoutStackEntry()` request.
 */
bool dppb_dpe_add_layout_stack_entry_async(void* handle,
                                           const int64_t request_id,
                                           const char* layout_ref_json,
                                           const bool has_index,
                                           const int32_t index) {
  if (handle == nullptr || layout_ref_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::DataItemRefByName layoutRef;
  try {
    const nlohmann::json layoutRefJson = nlohmann::json::parse(layout_ref_json);
    std::unique_ptr<dogpaw::DataItemRefByName> parsed =
        dogpaw::DataItemRefByName::fromJson(layoutRefJson);
    if (!parsed) {
      throw std::runtime_error("Failed to parse layoutRef JSON");
    }
    layoutRef = *parsed;
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "addLayoutStackEntry",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<int> optionalIndex =
      has_index ? std::optional<int>(static_cast<int>(index)) : std::nullopt;

  std::thread requestThread(
      [bridge, request_id, layoutRef, optionalIndex]() mutable {
        try {
          dogpaw::Result<std::string> addResult =
              bridge->entity->addLayoutStackEntry(layoutRef, optionalIndex).get();
          nlohmann::json resultJson = nlohmann::json::object();
          if (addResult.success) {
            resultJson[JF::ENTRY_ID] = addResult.value;
          }
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "addLayoutStackEntry",
                  addResult.success,
                  addResult.error,
                  resultJson));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "addLayoutStackEntry",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `removeLayoutStackEntry()` request.
 */
bool dppb_dpe_remove_layout_stack_entry_async(void* handle,
                                              const int64_t request_id,
                                              const char* entry_id) {
  if (handle == nullptr || entry_id == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string entryId(entry_id);
  std::thread requestThread(
      [bridge, request_id, entryId]() mutable {
        try {
          dogpaw::OperationResult removeResult =
              bridge->entity->removeLayoutStackEntry(entryId).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "removeLayoutStackEntry",
                  removeResult.success,
                  removeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "removeLayoutStackEntry",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `moveLayoutStackEntry()` request.
 */
bool dppb_dpe_move_layout_stack_entry_async(void* handle,
                                            const int64_t request_id,
                                            const char* entry_id,
                                            const int32_t new_index) {
  if (handle == nullptr || entry_id == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  const std::string entryId(entry_id);
  const int newIndex = static_cast<int>(new_index);
  std::thread requestThread(
      [bridge, request_id, entryId, newIndex]() mutable {
        try {
          dogpaw::OperationResult moveResult =
              bridge->entity->moveLayoutStackEntry(entryId, newIndex).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "moveLayoutStackEntry",
                  moveResult.success,
                  moveResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "moveLayoutStackEntry",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `readLayoutStack()` request.
 */
bool dppb_dpe_read_layout_stack_async(void* handle,
                                      const int64_t request_id,
                                      const bool include_resolved,
                                      const bool include_spec) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id, include_resolved, include_spec]() mutable {
        try {
          dogpaw::Result<dogpaw::LayoutStackSnapshot> readResult =
              bridge->entity->readLayoutStack(include_resolved, include_spec).get();
          nlohmann::json resultJson = nlohmann::json::object();
          if (readResult.success) {
            resultJson[JF::LAYOUT_STACK] = readResult.value.toJson();
          }
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readLayoutStack",
                  readResult.success,
                  readResult.error,
                  resultJson));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "readLayoutStack",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `subscribeToLayoutStack()` request.
 *
 * Subsequent notifications are posted as `subscriptionNotification` events on
 * topic `layout_stack/notification`, with the snapshot under the `layoutStack`
 * payload field.
 */
bool dppb_dpe_subscribe_layout_stack_async(void* handle,
                                           const int64_t request_id,
                                           const bool include_resolved,
                                           const bool include_spec,
                                           const bool send_immediately) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id, include_resolved, include_spec,
       send_immediately]() mutable {
        try {
          dogpaw::OperationResult subscribeResult =
              bridge->entity
                  ->subscribeToLayoutStack(
                      dogpaw::LayoutStackChangeCallback(
                          [bridge](const std::string& notificationType,
                                   const dogpaw::DataItemRefByName& itemRef,
                                   const dogpaw::LayoutStackSnapshot& snapshot) {
                            // Enrich the snapshot JSON with itemRef fields so
                            // the Dart subscription handler (which calls
                            // DataItemRef.fromJson on the value payload) can
                            // parse it. LayoutStackSnapshot has no intrinsic
                            // name/namespace, so we attach them from the
                            // notification's item reference.
                            nlohmann::json snapshotWithRef = snapshot.toJson();
                            snapshotWithRef[JF::NAME] = itemRef.name;
                            snapshotWithRef[JF::NAMESPACE_SELECTOR] =
                                itemRef.namespaceSelector.toJson();
                            post_bridge_event(
                                bridge,
                                make_subscription_notification_event(
                                    epiphany::Topics::LAYOUT_STACK_NOTIFICATION,
                                    notificationType,
                                    itemRef,
                                    JF::LAYOUT_STACK,
                                    snapshotWithRef));
                          }),
                      include_resolved,
                      include_spec,
                      send_immediately)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToLayoutStack",
                  subscribeResult.success,
                  subscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToLayoutStack",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromLayoutStack()`
 * request.
 */
bool dppb_dpe_unsubscribe_layout_stack_async(void* handle,
                                             const int64_t request_id) {
  if (handle == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  std::thread requestThread(
      [bridge, request_id]() mutable {
        try {
          dogpaw::OperationResult unsubscribeResult =
              bridge->entity->unsubscribeFromLayoutStack().get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromLayoutStack",
                  unsubscribeResult.success,
                  unsubscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromLayoutStack",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `subscribeToKV()` request.
 */
bool dppb_dpe_subscribe_kv_async(void* handle,
                                 const int64_t request_id,
                                 const char* key,
                                 const char* namespace_selector_json,
                                 const bool include_resolved,
                                 const bool include_spec,
                                 const bool send_immediately) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "subscribeToKV",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> kvKey =
      (key != nullptr) ? std::optional<std::string>(std::string(key))
                       : std::nullopt;
  std::thread requestThread(
      [bridge,
       request_id,
       kvKey,
       namespaceSelector,
       include_resolved,
       include_spec,
       send_immediately]() mutable {
        try {
          dogpaw::OperationResult subscribeResult =
              bridge->entity
                  ->subscribeToKV(
                      dogpaw::KeyValueChangeCallback([bridge](
                          const std::string& notificationType,
                          const dogpaw::DataItemRefByName& itemRef,
                          const dogpaw::KV& kv) {
                        post_bridge_event(
                            bridge,
                            make_subscription_notification_event(
                                epiphany::Topics::KV_NOTIFICATION,
                                notificationType,
                                itemRef,
                                JF::KV,
                                kv.toJson()));
                      }),
                      kvKey,
                      namespaceSelector,
                      include_resolved,
                      include_spec,
                      send_immediately)
                  .get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToKV",
                  subscribeResult.success,
                  subscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "subscribeToKV",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

/**
 * @brief Launch an asynchronous native-backed `unsubscribeFromKV()` request.
 */
bool dppb_dpe_unsubscribe_kv_async(void* handle,
                                   const int64_t request_id,
                                   const char* key,
                                   const char* namespace_selector_json) {
  if (handle == nullptr || namespace_selector_json == nullptr) {
    return false;
  }

  auto* bridge = static_cast<NativeDogPawEntityBridge*>(handle);
  dogpaw::NamespaceSelector namespaceSelector;
  try {
    namespaceSelector = parse_namespace_selector_json(namespace_selector_json);
  } catch (const std::exception& exception) {
    post_bridge_event(
        bridge,
        make_request_result_event(
            request_id,
            "unsubscribeFromKV",
            false,
            exception.what(),
            nlohmann::json::object()));
    return true;
  }

  const std::optional<std::string> kvKey =
      (key != nullptr) ? std::optional<std::string>(std::string(key))
                       : std::nullopt;
  std::thread requestThread(
      [bridge, request_id, kvKey, namespaceSelector]() mutable {
        try {
          dogpaw::OperationResult unsubscribeResult =
              bridge->entity->unsubscribeFromKV(kvKey, namespaceSelector).get();
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromKV",
                  unsubscribeResult.success,
                  unsubscribeResult.error,
                  nlohmann::json::object()));
        } catch (const std::exception& exception) {
          post_bridge_event(
              bridge,
              make_request_result_event(
                  request_id,
                  "unsubscribeFromKV",
                  false,
                  exception.what(),
                  nlohmann::json::object()));
        }
      });
  return store_request_thread(bridge, std::move(requestThread));
}

} // extern "C"
