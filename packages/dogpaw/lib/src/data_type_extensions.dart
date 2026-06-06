import 'data_types.dart';
import 'json_constants.dart';

extension DataTypeExtension on DataType {
  String toSnakeCase() {
    switch (this) {
      case DataType.float:
        return JsonFields.DATA_TYPE_FLOAT;
      case DataType.float2:
        return JsonFields.DATA_TYPE_FLOAT2;
      case DataType.float3:
        return JsonFields.DATA_TYPE_FLOAT3;
      case DataType.float4:
        return JsonFields.DATA_TYPE_FLOAT4;
      case DataType.int_:
        return JsonFields.DATA_TYPE_INT;
      case DataType.int2:
        return JsonFields.DATA_TYPE_INT2;
      case DataType.toggle:
        return JsonFields.DATA_TYPE_TOGGLE;
      case DataType.momentary:
        return JsonFields.DATA_TYPE_MOMENTARY;
      case DataType.enum_:
        return JsonFields.DATA_TYPE_ENUM;
      case DataType.audioStream:
        return JsonFields.DATA_TYPE_AUDIO_STREAM;
      case DataType.keyPress:
        return JsonFields.DATA_TYPE_KEY_PRESS;
      case DataType.nearPress:
        return JsonFields.DATA_TYPE_NEAR_PRESS;
      case DataType.rawSensors:
        return JsonFields.DATA_TYPE_RAW_SENSORS;
      case DataType.noteControl:
        return JsonFields.DATA_TYPE_NOTE_CONTROL;
      case DataType.midiMessage:
        return JsonFields.DATA_TYPE_MIDI_MESSAGE;
      case DataType.ledMessage:
        return JsonFields.DATA_TYPE_LED_MESSAGE;
      case DataType.keyPosition:
        return JsonFields.DATA_TYPE_KEY_POSITION;
      case DataType.voiceMessage:
        return JsonFields.DATA_TYPE_VOICE_MESSAGE;
      case DataType.voiceOutputValue:
        return JsonFields.DATA_TYPE_VOICE_OUTPUT_VALUE;
      case DataType.globalOutputValue:
        return JsonFields.DATA_TYPE_GLOBAL_OUTPUT_VALUE;
      case DataType.dppParamQueue:
        return JsonFields.DATA_TYPE_DPP_PARAM_QUEUE;
      case DataType.custom:
        return JsonFields.DATA_TYPE_CUSTOM;
      case DataType.scopeBuffer:
        return JsonFields.DATA_TYPE_SCOPE_BUFFER;
    }
  }
}
