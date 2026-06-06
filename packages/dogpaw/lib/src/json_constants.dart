// ignore_for_file: constant_identifier_names

/// JSON field constants used for communication with the Epiphany server
/// These match the constants defined in EpiphanyConstants.hpp
library;

class JsonFields {
  // Common
  static const String SPEC = "spec";
  static const String RESOLVED = "resolved";
  static const String INCLUDE_RESOLVED = "includeResolved";
  static const String INCLUDE_SPEC = "includeSpec";
  static const String REQUEST_ID = "requestId";
  static const String SERVER_REQUEST_ID = "serverRequestId";
  static const String MESSAGE = "message";
  static const String METHOD = "method";
  static const String EVENT_TYPE = "eventType";
  static const String NAME = "name";
  static const String ENTITY_NAME = "entityName";
  static const String LAUNCH_STAGE = "launchStage";
  static const String LAUNCH_DETAIL = "launchDetail";
  static const String ENTITY_LIFECYCLE_CONNECTED = "entity_connected";
  static const String ENTITY_LIFECYCLE_DISCONNECTED = "entity_disconnected";
  static const String SOURCE_ENTITY = "sourceEntity";
  static const String NOTIFICATION_TYPE = "type";
  static const String TYPE = "type";
  static const String NAMESPACE_SELECTOR = "namespaceSelector";

  // Server Responses
  static const String STATUS = "status";
  static const String ERROR_CODE = "errorCode";
  static const String SUCCESS = "success";
  static const String ERROR = "error";
  static const String NOT_IMPLEMENTED = "not_implemented";

  // App info file, launcher
  static const String APP_NAME = "name";
  static const String RUNTIME_APP_NAME = "appName";
  static const String DISPLAY_NAME = "displayName";
  static const String ICON = "icon";
  static const String VISIBLE = "visible";
  static const String FLUTTER_APP = "flutterApp";
  static const String APPS = "apps";
  static const String ENTITIES = "entities";
  static const String COUNT = "count";
  static const String LAUNCH_METADATA = "launchMetadata";
  static const String PROCESS_NAME = "processName";
  static const String PROCESS_IDS = "processIds";
  static const String PROCESSES = "processes";
  static const String PROCESS_COMMAND = "command";
  static const String PROCESS_LAUNCH_IMMEDIATELY = "launchImmediately";

  // Color/ColorSpec
  static const String RGBA = "rgba";
  static const String THEME_COLOR = "themeColor";
  static const String NOTE_CATEGORY_MAP = "noteCategoryMap";
  static const String NOTE_NUMBER_MAP = "noteNumberMap";
  static const String KEY_ID_MAP = "keyIdMap";
  static const String FIRST_MAP = "firstMap";
  static const String BLEND = "blend";

  // Data References
  static const String REF_TYPE = "refType";
  static const String REF_NAME = "refName";
  static const String REF_DATA = "refData";
  static const String REF_TYPE_NAME = "name";
  static const String REF_TYPE_CURRENT = "current";
  static const String REF_TYPE_INLINE = "inline";

  // Key Intents
  static const String KEY_STATE_REST = "rest";
  static const String KEY_STATE_ACTIVE = "active";
  static const String KEY_STATE_PRESSED = "pressed";
  static const String SOURCE = "source";
  static const String DESTINATION = "destination";
  static const String HORIZONTAL_POSITION = "horizontal";
  static const String VERTICAL_POSITION = "vertical";
  static const String INTENT = "intent";
  static const String MIDI_NOTE = "midiNote";
  static const String MIDI_CC = "midiCC";
  static const String PRINT_CONSOLE = "printConsole";
  static const String CUSTOM = "custom";
  static const String MIDI_NOTE_FIELD = "midiNote";
  static const String NOTE_NAME = "noteName";
  static const String SEMITONES_FROM_ROOT = "semitonesFromRoot";
  static const String SCALE_DEGREES_FROM_ROOT = "scaleDegreesFromRoot";
  static const String OCTAVE = "octave";
  static const String MIDI_CHANNEL = "midiChannel";
  static const String CC_NUMBER = "ccNumber";
  static const String CC_NAME = "ccName";
  static const String MODE = "mode";
  static const String TOGGLE = "toggle";
  static const String CONTINUOUS = "continuous";
  static const String START_STATE = "startState";
  static const String TRIGGER_STATE = "triggerState";
  static const String STATE_TRANSITION = "stateTransition";
  static const String CUSTOM_PAYLOAD = "payload";

  // Layout
  static const String KEY_INTENTS = "keyIntents";
  static const String KEY_COLORS = "keyColors";
  static const String SCOPE = "scope";
  static const String TARGET_KEY = "targetKey";
  static const String LAYOUTS = "layouts";
  static const String LAYOUT_STACK = "layoutStack";
  static const String LAYOUT_STACK_ENTRIES = "layoutStackEntries";
  static const String LAYOUT_REF = "layoutRef";
  static const String ENTRY_ID = "entryId";
  static const String RESOLVED_LAYOUT = "resolvedLayout";
  static const String INDEX = "index";
  static const String NEW_INDEX = "newIndex";
  static const String ADD_TO_LAYOUT_STACK = "addToLayoutStack";
  static const String THEME_REF = "themeRef";
  static const String SCALE_REF = "scaleRef";
  static const String WORKSPACE = "workspace";

  // Scale
  static const String ROOT_NOTE = "rootNote";
  static const String NOTE_CATEGORIES = "noteCategories";

  // Theme
  static const String PRIMARY_COLOR = "primaryColor";
  static const String SECONDARY_COLOR = "secondaryColor";
  static const String ACCENT_COLOR = "accentColor";
  static const String BACKGROUND_COLOR = "backgroundColor";

  // KV pairs
  static const String VALUE = "value";

  // Entity direct message
  static const String TARGET_ENTITY = "targetEntity";
  static const String SENDER_ENTITY = "senderEntity";
  static const String TARGET_REF = "targetRef";

  // Entity commands
  static const String COMMAND = "command";
  static const String COMMAND_ID = "commandId";
  static const String PARAMS = "params";
  static const String DELIVERY_POLICY = "deliveryPolicy";
  static const String IF_TARGET_MISSING = "ifTargetMissing";
  static const String IF_TARGET_MISSING_FAIL = "fail";
  static const String IF_TARGET_MISSING_LAUNCH_IF_REGISTERED =
      "launch_if_registered";
  static const String WAIT_FOR_READY = "waitForReady";
  static const String COMMAND_STATUS = "commandStatus";
  static const String COMMAND_STATUS_ACCEPTED = "accepted";
  static const String COMMAND_STATUS_COMPLETED = "completed";
  static const String COMMAND_STATUS_ERROR = "error";
  static const String RESULT = "result";

  // Endpoint management
  static const String ENDPOINT = "endpoint";
  static const String ENDPOINTS = "endpoints";
  static const String ENDPOINT_NAME = "endpointName";
  static const String DESCRIPTION = "description";
  static const String DIRECTION = "direction";
  static const String DATA_TYPE = "dataType";
  static const String CONNECTION_POLICY = "connectionPolicy";
  static const String CATEGORY = "category";
  static const String QUEUE_SHM_NAME = "queueShmName";
  static const String SOCKET_PATH = "socketPath";
  static const String SHARED_DATA_NAME = "sharedDataName";
  static const String SHM_NAMESPACE_PREFIX = "shmNamespacePrefix";
  static const String JACK_PORT_NAME = "jackPortName";
  static const String JACK_CLIENT_NAME = "jackClientName";
  static const String FULL_JACK_PORT_NAME = "fullJackPortName";
  static const String JACK_BINDING_MODE = "jackBindingMode";
  static const String FLAGS = "flags";
  static const String GROUP_KEY = "groupKey";
  static const String SHIM_TARGET_REF = "shimTargetRef";
  static const String FILE_PATH = "filePath";

  // Connection management
  static const String CONNECTION = "connection";
  static const String CONNECTIONS = "connections";
  static const String TARGET = "target";
  static const String CONNECTION_REQUEST_ITEM = "connectionRequest";
  static const String CONNECTION_REQUESTS = "connectionRequests";
  static const String FOLLOW_REQUEST_ITEM = "followRequest";
  static const String FOLLOW_REQUESTS = "followRequests";
  static const String CONNECTION_ID = "connectionId";
  static const String CONNECTION_NAME = "connectionName";
  static const String SOURCE_REF = "sourceRef";
  static const String DESTINATION_REF = "destinationRef";
  static const String FOLLOWER_REF = "followerRef";
  static const String LEADER_CRITERIA = "leaderCriteria";
  static const String MAPPING = "mapping";
  static const String INDEX_CONVERSION = "indexConversion";
  static const String PRIORITY = "priority";
  static const String ENABLED = "enabled";
  static const String METADATA = "metadata";
  static const String REQUEST = "request";

  // Data type constraints
  static const String CONSTRAINTS = "constraints";
  static const String UNITS = "units";
  static const String DEFAULT_VALUE = "defaultValue";
  static const String ENUM_VALUES = "enumValues";
  static const String CUSTOM_SCHEMA = "customSchema";
  static const String BASE_TYPE = "baseType";
  static const String INDEX_TYPE = "indexType";
  static const String INDEX_SPEC = "indexSpec";

  // Mapping and conversion
  static const String MAPPING_TYPE = "mappingType";
  static const String INPUT_RANGE = "inputRange";
  static const String OUTPUT_RANGE = "outputRange";
  static const String CURVE = "curve";
  static const String EXPRESSION = "expression";
  static const String STRATEGY = "strategy";
  static const String CONVERTER = "converter";
  static const String PARAMETERS = "parameters";

  // Search criteria
  static const String CRITERIA = "criteria";
  static const String FIELD = "field";
  static const String OPERATOR = "operator";
  static const String EQUALS = "equals";
  static const String CONTAINS = "contains";
  static const String AND = "and";
  static const String OR = "or";
  static const String AND_CRITERIA = "and";
  static const String OR_CRITERIA = "or";

  // Priority levels
  static const String PRIORITY_REALTIME = "realtime";
  static const String PRIORITY_HIGH = "high";
  static const String PRIORITY_NORMAL = "normal";
  static const String PRIORITY_BACKGROUND = "background";

  // Endpoint categories
  static const String CATEGORY_MESSAGE_QUEUE = "message_queue";
  static const String CATEGORY_CONTINUOUS = "continuous";
  static const String CATEGORY_AUDIO_STREAM = "audio_stream";
  static const String CATEGORY_JACK_MIDI_STREAM = "jack_midi_stream";
  static const String CATEGORY_FILE_BACKED = "file_backed";

  // JACK binding modes
  static const String JACK_BINDING_MODE_REGISTER_NEW_PORT = "register_new_port";
  static const String JACK_BINDING_MODE_ADOPT_EXISTING_PORT =
      "adopt_existing_port";

  // Endpoint directions
  static const String DIRECTION_INPUT = "input";
  static const String DIRECTION_OUTPUT = "output";
  static const String DIRECTION_BIDIRECTIONAL = "bidirectional";

  // Index types
  static const String INDEX_TYPE_NONE = "none";
  static const String INDEX_TYPE_KEY = "key";
  static const String INDEX_TYPE_VOICE = "voice";
  static const String INDEX_TYPE_CUSTOM = "custom";

  // Data types (base types)
  static const String DATA_TYPE_FLOAT = "float";
  static const String DATA_TYPE_FLOAT2 = "float2";
  static const String DATA_TYPE_FLOAT3 = "float3";
  static const String DATA_TYPE_FLOAT4 = "float4";
  static const String DATA_TYPE_INT = "int";
  static const String DATA_TYPE_INT2 = "int2";
  static const String DATA_TYPE_TOGGLE = "toggle";
  static const String DATA_TYPE_MOMENTARY = "momentary";
  static const String DATA_TYPE_ENUM = "enum";
  static const String DATA_TYPE_AUDIO_STREAM = "audio_stream";
  static const String DATA_TYPE_KEY_PRESS = "key_press";
  static const String DATA_TYPE_NEAR_PRESS = "near_press";
  static const String DATA_TYPE_RAW_SENSORS = "raw_sensors";
  static const String DATA_TYPE_NOTE_CONTROL = "note_control";
  static const String DATA_TYPE_MIDI_MESSAGE = "midi_message";
  static const String DATA_TYPE_LED_MESSAGE = "led_message";
  static const String DATA_TYPE_KEY_POSITION = "key_position";
  static const String DATA_TYPE_VOICE_MESSAGE = "voice_message";
  static const String DATA_TYPE_VOICE_OUTPUT_VALUE = "voice_output_value";
  static const String DATA_TYPE_GLOBAL_OUTPUT_VALUE = "global_output_value";
  static const String DATA_TYPE_DPP_PARAM_QUEUE = "dpp_param_queue";
  static const String DATA_TYPE_CUSTOM = "custom";
  static const String DATA_TYPE_SCOPE_BUFFER = "scope_buffer";

  // Mapping types
  static const String MAPPING_TYPE_LINEAR = "linear";
  static const String MAPPING_TYPE_LOGARITHMIC = "logarithmic";
  static const String MAPPING_TYPE_EXPRESSION = "expression";
  static const String MAPPING_TYPE_CUSTOM = "custom";

  // Conversion strategies
  static const String CONVERSION_NONE = "none";
  static const String CONVERSION_UNIFORM = "uniform";
  static const String CONVERSION_LINEAR = "linear";
  static const String CONVERSION_MAX_VALUE = "max_value";
  static const String CONVERSION_AVERAGE_VALUE = "average_value";
  static const String CONVERSION_WEIGHTED_AVERAGE = "weighted_average";
  static const String CONVERSION_FIRST_ACTIVE = "first_active";
  static const String CONVERSION_KEY_TO_VOICE = "key_to_voice";
  static const String CONVERSION_VOICE_TO_KEY = "voice_to_key";
  static const String CONVERSION_CUSTOM_CONVERTER = "custom_converter";

  // Data references
  static const String CURRENT = "current";

  // Notification types
  static const String LAYOUT_NOTIFICATION = "layout/notification";
  static const String THEME_NOTIFICATION = "theme/notification";
  static const String SCALE_NOTIFICATION = "scale/notification";
  static const String ENDPOINT_NOTIFICATION = "endpoint/notification";
  static const String CONNECTION_NOTIFICATION = "connection/notification";
  static const String CONNECTION_ESTABLISHED = "connection/established";
  static const String CONNECTION_REMOVED = "connection/removed";
  static const String KV_NOTIFICATION = "kv/notification";
  static const String LAYOUT_STACK_NOTIFICATION = "layout_stack/notification";

  // Key-value store
  static const String KV = "kv";

  // Subscriptions
  static const String CURRENT_TARGET = "current";
  static const String SEND_IMMEDIATELY = "send_immediately";

  // Log section control
  static const String SECTION_TITLE = "sectionTitle";
  static const String FLUSH = "flush";

  // Range values
  static const String MIN = "min";
  static const String MAX = "max";
  static const String RANGE = "range";

  // Additional status values
  static const String FAILURE = "failure";

  // Additional JsonFields
  static const String TOPIC = "topic";
  static const String LAYOUT = "layout";
  static const String THEME = "theme";
  static const String SCALE = "scale";
  static const String KEY_FIELD =
      "key"; // Renamed from KEY to avoid conflict, or use context
  static const String MAX_CONNECTIONS = "maxConnections";
  static const String AUTO_CONNECT_CRITERIA = "autoConnectCriteria";
  static const String MERGING_STRATEGY_ADD = "add";
  static const String MERGING_STRATEGY_MULTIPLY = "multiply";
  static const String MERGING_STRATEGY_REPLACE = "replace";
  static const String MERGING_STRATEGY_LATEST = "latest";

  // Additional data fields
  static const String KVS = "kvs";
  static const String THEMES = "themes";
  static const String SCALES = "scales";

  // App management
  static const String APP = "app";
  static const String APP_ID = "appId";
  static const String PROCESS = "process";
  static const String PROCESS_ID = "processId";
  static const String ARGS = "args";

  // Additional constants for KeyEvent
  static const String KEY_EVENT_TYPE = "keyEventType";
  static const String COLUMN = "column";
  static const String ROW = "row";
  static const String VELOCITY = "velocity";
  static const String OLD_STATE = "oldState";
  static const String NEW_STATE = "newState";
  static const String TIMESTAMP = "timestamp";

  // Additional constants for Color
  static const String RED = "red";
  static const String GREEN = "green";
  static const String BLUE = "blue";
  static const String ALPHA = "alpha";
  static const String INFO = "info";

  // Additional constants for LEDMessage and ProcessInfo
  static const String MODIFIER_LAYER = "modifierLayer";
  static const String PID = "pid";
  static const String START_TIME = "startTime";
  static const String RUNNING = "running";
  static const String PROCESS_TYPE = "processType";

  // Additional constants for EntityData
  static const String NETWORK_ID = "networkId";
}

class Topics {
  static const String RESPONSE_SUFFIX = "/response";

  // App management
  static const String APP_LAUNCH = "app/launch";
  static const String APP_STOP = "app/stop";
  static const String APP_KILL_ALL = "app/kill_all";

  // App directory management
  static const String APP_DIRECTORY_ADD = "app/directory/add";
  static const String APP_DIRECTORY_REMOVE = "app/directory/remove";
  static const String EXECUTABLE_DIRECTORY_ADD = "executable/directory/add";
  static const String EXECUTABLE_DIRECTORY_REMOVE =
      "executable/directory/remove";
  static const String APP_CACHE_REFRESH = "app/cache/refresh";

  // Process management
  static const String PROCESS_LAUNCH = "process/launch";
  static const String PROCESS_STOP = "process/stop";
  static const String PROCESS_LIST = "process/list";
  static const String PROCESS_STATUS = "process/status";

  // Key-Value store
  static const String KV_SET = "kv/set";
  static const String KV_CREATE = "kv/create";
  static const String KV_READ = "kv/read";
  static const String KV_UPDATE = "kv/update";
  static const String KV_DELETE = "kv/delete";
  static const String KV_LIST = "kv/list";
  static const String KV_SUBSCRIBE = "kv/subscribe";
  static const String KV_UNSUBSCRIBE = "kv/unsubscribe";
  static const String KV_NOTIFICATION = "kv/notification";

  // Layout
  static const String LAYOUT_SET = "layout/set";
  static const String LAYOUT_CREATE = "layout/create";
  static const String LAYOUT_READ = "layout/read";
  static const String LAYOUT_UPDATE = "layout/update";
  static const String LAYOUT_DELETE = "layout/delete";
  static const String LAYOUT_LIST = "layout/list";
  static const String LAYOUT_SUBSCRIBE = "layout/subscribe";
  static const String LAYOUT_UNSUBSCRIBE = "layout/unsubscribe";
  static const String LAYOUT_NOTIFICATION = "layout/notification";
  static const String LAYOUT_STACK_ADD = "layout_stack/add";
  static const String LAYOUT_STACK_REMOVE = "layout_stack/remove";
  static const String LAYOUT_STACK_MOVE = "layout_stack/move";
  static const String LAYOUT_STACK_READ = "layout_stack/read";
  static const String LAYOUT_STACK_SUBSCRIBE = "layout_stack/subscribe";
  static const String LAYOUT_STACK_UNSUBSCRIBE = "layout_stack/unsubscribe";
  static const String LAYOUT_STACK_NOTIFICATION = "layout_stack/notification";

  // Theme
  static const String THEME_SET = "theme/set";
  static const String THEME_CREATE = "theme/create";
  static const String THEME_READ = "theme/read";
  static const String THEME_UPDATE = "theme/update";
  static const String THEME_DELETE = "theme/delete";
  static const String THEME_LIST = "theme/list";
  static const String THEME_SUBSCRIBE = "theme/subscribe";
  static const String THEME_UNSUBSCRIBE = "theme/unsubscribe";
  static const String THEME_NOTIFICATION = "theme/notification";
  static const String THEME_SET_CURRENT = "theme/set_current";
  static const String THEME_READ_CURRENT = "theme/get_current";
  static const String THEME_REMOVE_CURRENT = "theme/remove_current";

  // Scale
  static const String SCALE_SET = "scale/set";
  static const String SCALE_CREATE = "scale/create";
  static const String SCALE_READ = "scale/read";
  static const String SCALE_UPDATE = "scale/update";
  static const String SCALE_DELETE = "scale/delete";
  static const String SCALE_LIST = "scale/list";
  static const String SCALE_SUBSCRIBE = "scale/subscribe";
  static const String SCALE_UNSUBSCRIBE = "scale/unsubscribe";
  static const String SCALE_NOTIFICATION = "scale/notification";
  static const String SCALE_SET_CURRENT = "scale/set_current";
  static const String SCALE_READ_CURRENT = "scale/get_current";
  static const String SCALE_REMOVE_CURRENT = "scale/remove_current";

  // Connection management
  static const String ENDPOINT_SET = "endpoint/set";
  static const String ENDPOINT_CREATE = "endpoint/create";
  static const String ENDPOINT_READ = "endpoint/read";
  static const String ENDPOINT_UPDATE = "endpoint/update";
  static const String ENDPOINT_DELETE = "endpoint/delete";
  static const String ENDPOINT_LIST = "endpoint/list";
  static const String ENDPOINT_SUBSCRIBE = "endpoint/subscribe";
  static const String ENDPOINT_UNSUBSCRIBE = "endpoint/unsubscribe";
  static const String ENDPOINT_NOTIFICATION = "endpoint/notification";

  static const String ENDPOINT_SEARCH = "endpoint/search";

  static const String CONNECTION_READ = "connection/read";
  static const String CONNECTION_LIST = "connection/list";
  static const String CONNECTION_SUBSCRIBE = "connection/subscribe";
  static const String CONNECTION_UNSUBSCRIBE = "connection/unsubscribe";
  static const String CONNECTION_NOTIFICATION = "connection/notification";

  static const String CONNECTION_REQUEST_SET = "connection_request/set";
  static const String CONNECTION_REQUEST_CREATE = "connection_request/create";
  static const String CONNECTION_REQUEST_READ = "connection_request/read";
  static const String CONNECTION_REQUEST_UPDATE = "connection_request/update";
  static const String CONNECTION_REQUEST_DELETE = "connection_request/delete";
  static const String CONNECTION_REQUEST_LIST = "connection_request/list";
  static const String FOLLOW_REQUEST_SET = "follow_request/set";
  static const String FOLLOW_REQUEST_CREATE = "follow_request/create";
  static const String FOLLOW_REQUEST_READ = "follow_request/read";
  static const String FOLLOW_REQUEST_UPDATE = "follow_request/update";
  static const String FOLLOW_REQUEST_DELETE = "follow_request/delete";
  static const String FOLLOW_REQUEST_LIST = "follow_request/list";
  static const String CONNECTION_REQUEST_SUBSCRIBE =
      "connection_request/subscribe";
  static const String CONNECTION_REQUEST_UNSUBSCRIBE =
      "connection_request/unsubscribe";
  static const String CONNECTION_REQUEST_NOTIFICATION =
      "connection_request/notification";

  static const String CONNECTION_VALIDATION_REQUEST =
      "connection/validation_request";
  static const String CONNECTION_REQUEST = "connection/request";

  // Key state
  static const String KEY_STATE_SET = "key/state/set";
  static const String KEY_STATE_READ = "key/state/get";
  static const String KEY_STATE_READ_ALL = "key/states/getAll";
  static const String KEY_EVENT = "key/event";

  // Direct messages
  static const String ENTITY_DIRECT_MESSAGE = "entity/direct_message";

  // Entity commands (structured request/response pattern)
  static const String ENTITY_COMMAND = "entity/command";
  static const String ENTITY_COMMAND_RESPONSE = "entity/command/response";

  // Debug and system
  static const String DEBUG_SYSTEM_INFO = "debug/system_info";
  static const String UTILS_LOG = "utils/log";
  static const String LOG_SECTION_START = "log/section/start";
  static const String LOG_SECTION_FLUSH = "log/section/flush";
  static const String LOG_SECTION_END = "log/section/end";
  static const String ENTITY_SET = "entity/set";
  static const String ENTITY_CREATE = "entity/create";
  static const String ENTITY_READY = "entity/ready";
  static const String ENTITY_READ = "entity/read";
  static const String ENTITY_UPDATE = "entity/update";
  static const String ENTITY_DELETE = "entity/delete";
  static const String ENTITY_LIST = "entity/list";
  static const String ENTITY_SUBSCRIBE = "entity/subscribe";
  static const String ENTITY_UNSUBSCRIBE = "entity/unsubscribe";
  static const String ENTITY_NOTIFICATION = "entity/notification";

  // Global state
  static const String GLOBAL_STATE_SAVE = "globalState/save";
  static const String GLOBAL_STATE_LOAD = "globalState/load";
  static const String PRESET_REQUEST = "preset/request";
  static const String PRESET_REQUEST_RESPONSE = "preset/request_response";
}

class ErrorCodes {
  static const int SUCCESS = 0;
  static const int UNKNOWN_ERROR = 1000;
  static const int INVALID_JSON = 1001;
  static const int MISSING_FIELD = 1002;
  static const int APP_NOT_FOUND = 2001;
  static const int APP_ALREADY_RUNNING = 2002;
  static const int APP_LAUNCH_FAILED = 2003;
  static const int APP_STOP_FAILED = 2004;
  static const int DIRECTORY_NOT_FOUND = 2005;
  static const int DIRECTORY_ALREADY_EXISTS = 2006;
  static const int DIRECTORY_ACCESS_FAILED = 2007;
  static const int CACHE_REFRESH_FAILED = 2008;
  static const int PROCESS_NOT_FOUND = 3001;
  static const int PROCESS_ALREADY_RUNNING = 3002;
  static const int PROCESS_LAUNCH_FAILED = 3003;
  static const int PROCESS_STOP_FAILED = 3004;
  static const int EXECUTABLE_NOT_FOUND = 3005;
  static const int PERMISSION_DENIED = 3006;
  static const int FLUTTER_APP_LAUNCH_FAILED = 4001;
  static const int HARDWARE_THREAD_FAILED = 5001;
}
