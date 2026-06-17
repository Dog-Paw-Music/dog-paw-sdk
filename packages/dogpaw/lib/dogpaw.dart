library dogpaw;

// Public package surface for app-facing DogPawEntity usage.
// Low-level FFI bridge internals stay under src/ffi and are imported directly
// only by internal infrastructure such as test fixtures.

// Core data types
export 'src/data_types.dart';
export 'src/data_item_type.dart';
export 'src/data_item_ref.dart';
export 'src/data_reference.dart';
export 'src/namespace_selector.dart';

// Data structures
export 'src/range.dart';
export 'src/data_type_spec.dart';
export 'src/connection_policy.dart';
export 'src/endpoint.dart';
export 'src/connection.dart';
export 'src/mapping_config.dart';
export 'src/modulation_config.dart';
export 'src/kv.dart';
export 'src/theme.dart';
export 'src/scale.dart';
export 'src/scale_catalog.dart';
export 'src/key_intent.dart';
export 'src/layout.dart';
export 'src/layout_builder.dart';
export 'src/layout_draft.dart';
export 'src/layout_query.dart';
export 'src/layout_stack.dart';
export 'src/key_event.dart';
export 'src/pos_data.dart';
export 'src/raw_pos_data.dart';
export 'src/scope_buffer_data.dart';
export 'src/knob_data.dart';
export 'src/led_message.dart';
export 'src/near_press_position_data.dart';
export 'src/search_criteria.dart';
export 'src/process_info.dart';

// Result types
export 'src/result.dart';

// Core utilities
export 'src/app_logger.dart';
export 'src/home_screen_commands.dart';
export 'src/launch_metadata.dart';
export 'src/path_utils.dart';

// Main API class
export 'src/dogpaw_entity.dart';

