/// Default runtime entity and endpoint names used by stock [EndpointInfo] helpers.
///
/// These match the current stock stack (`BladeHW` key sensors, `LEDComms` lights).
/// Keep them in one place so a future public rename is a single edit.
///
/// Prefer [EndpointInfo.forKeyPressInput], [EndpointInfo.forKeyPositionInput],
/// [EndpointInfo.forLedOverlayOutput], and [EndpointInfo.forLedPrimaryOutput]
/// when declaring app endpoints.
abstract final class DefaultDogPawEndpoints {
  /// Epiphany entity that publishes key_press / key_position (picoComms today).
  static const String keyPressSourceEntity = 'BladeHW';

  /// Output endpoint name on [keyPressSourceEntity] for key transitions.
  static const String keyPressEndpointName = 'key_press';

  /// Output endpoint name on [keyPressSourceEntity] for continuous key position.
  static const String keyPositionEndpointName = 'key_position';

  /// Epiphany entity that receives LED overlay/primary traffic.
  static const String ledSourceEntity = 'LEDComms';

  /// Always-on overlay / flash input on [ledSourceEntity].
  static const String ledOverlayInputName = 'led_overlay_input';

  /// Claim-gated continuous key-feedback input on [ledSourceEntity].
  static const String ledPrimaryInputName = 'led_primary_input';
}
