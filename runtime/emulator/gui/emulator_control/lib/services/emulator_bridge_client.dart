import 'dart:convert';
import 'dart:io';

import '../models/emulator_bridge_models.dart';

typedef BridgeTransport = Future<BridgeHttpResponse> Function(
  String method,
  Uri uri,
  String? body,
);

/// Raw HTTP response returned by the bridge transport.
///
/// Purpose: separates emulator bridge protocol parsing from the concrete
/// `dart:io` HTTP implementation so tests can inject fake responses.
/// Parameters: [statusCode] is the HTTP status and [body] is the response text.
/// Return value: immutable transport response.
/// Requirements: [body] should contain bridge JSON for successful requests.
/// Guarantees: construction does not perform I/O.
/// Invariants: this object does not interpret response content.
class BridgeHttpResponse {
  const BridgeHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// HTTP client for the local Dog Paw emulator bridge.
///
/// Purpose: gives the Flutter GUI a typed API over the Python bridge endpoints.
/// Parameters: [baseUri] is the bridge origin; [transport] optionally replaces
/// the default HTTP transport for tests.
/// Return value: client instance for bridge requests.
/// Requirements: the Python bridge should be listening for real requests.
/// Guarantees: methods throw [BridgeClientException] for failed bridge calls.
/// Invariants: simulator-specific Unix socket details stay hidden behind the
/// Python bridge.
class EmulatorBridgeClient {
  EmulatorBridgeClient({required this.baseUri, BridgeTransport? transport})
      : _transport = transport ?? _defaultTransport;

  final Uri baseUri;
  final BridgeTransport _transport;

  /// Fetch bridge health and simulator socket readiness.
  ///
  /// Purpose: lets the GUI show which emulator backends are currently ready.
  /// Parameters: none.
  /// Return value: decoded [BridgeHealth] model.
  /// Requirements: `/api/health` must be served by the bridge.
  /// Guarantees: non-2xx responses throw [BridgeClientException].
  /// Invariants: does not mutate emulator state.
  Future<BridgeHealth> fetchHealth() async {
    final jsonObject = await _requestJson('GET', '/api/health');
    return BridgeHealth.fromJson(jsonObject);
  }

  /// Fetch the current simulated LED state.
  ///
  /// Purpose: lets the GUI render the key-grid LED colors reported by LEDComms.
  /// Parameters: none.
  /// Return value: decoded [LedSnapshot] model.
  /// Requirements: LEDComms introspection must be running for fresh data.
  /// Guarantees: non-2xx responses throw [BridgeClientException].
  /// Invariants: does not mutate simulator state.
  Future<LedSnapshot> fetchLedSnapshot() async {
    final jsonObject = await _requestJson('GET', '/api/led/snapshot');
    return LedSnapshot.fromJson(jsonObject);
  }

  /// Fetch the current simulated ButtonsAndKnobs state.
  ///
  /// Purpose: lets the GUI render raw encoder positions, normalized values, and
  /// button pressed states from the BAK backend.
  /// Parameters: none.
  /// Return value: decoded [BakSnapshot] model.
  /// Requirements: BAK simulator control socket must be available.
  /// Guarantees: non-2xx responses throw [BridgeClientException].
  /// Invariants: does not mutate simulator state.
  Future<BakSnapshot> fetchBakSnapshot() async {
    final jsonObject = await _requestJson('GET', '/api/bak/snapshot');
    return BakSnapshot.fromJson(jsonObject);
  }

  /// Send one rich key-state update through the emulator bridge.
  ///
  /// Purpose: lets the GUI drive active-only, pressed, pressure, bend, and
  /// release semantics through the PicoComms simulator contract.
  /// Parameters: [request] carries the full key-state target for one key.
  /// Return value: future that completes after the bridge accepts the command.
  /// Requirements: PicoComms simulator control socket must be available.
  /// Guarantees: command payload preserves [KeyInteractionRequest] values.
  /// Invariants: does not directly access private Unix sockets.
  Future<void> setKeyState(KeyInteractionRequest request) async {
    await _requestJson('POST', '/api/key/set', {
      'col': request.col,
      'row': request.row,
      'state': request.state.bridgeName,
      'velocity': request.velocity,
      'vertical': request.vertical,
      'horizontal': request.horizontal,
    });
  }

  /// Send a key tap command through the emulator bridge.
  ///
  /// Purpose: lets the GUI simulate a full key tap lifecycle.
  /// Parameters: [col] and [row] are logical Dog Paw coordinates in range 0..7.
  /// Return value: future that completes after the bridge accepts the command.
  /// Requirements: PicoComms simulator control socket must be available.
  /// Guarantees: command payload is `{col,row}`.
  /// Invariants: does not directly access private Unix sockets.
  Future<void> tapKey({required int col, required int row}) async {
    await _requestJson('POST', '/api/key/tap', {'col': col, 'row': row});
  }

  /// Request one key-pattern file to play once through the bridge.
  ///
  /// Purpose: gives the GUI access to the existing saved-pattern playback path.
  /// Parameters: [path] is the local JSON pattern path.
  /// Return value: future that completes after the bridge accepts the command.
  /// Requirements: [path] must point to a readable key-pattern JSON file.
  /// Guarantees: command targets the `/api/key/play` bridge endpoint.
  /// Invariants: does not parse the pattern file in Flutter.
  Future<void> playKeyPattern({required String path}) async {
    await _requestJson('POST', '/api/key/play', {'path': path});
  }

  /// Request one key-pattern file to loop through the bridge.
  ///
  /// Purpose: lets the GUI start repeating playback of a saved key-pattern file.
  /// Parameters: [path] is the local JSON pattern path.
  /// Return value: future that completes after the bridge accepts the command.
  /// Requirements: [path] must point to a readable key-pattern JSON file.
  /// Guarantees: command targets the `/api/key/loop` bridge endpoint.
  /// Invariants: does not parse the pattern file in Flutter.
  Future<void> loopKeyPattern({required String path}) async {
    await _requestJson('POST', '/api/key/loop', {'path': path});
  }

  /// Request the currently running key pattern to stop through the bridge.
  ///
  /// Purpose: gives the GUI a one-click way to stop simulator-owned pattern
  /// playback.
  /// Parameters: none.
  /// Return value: future that completes after the bridge accepts the command.
  /// Requirements: PicoComms simulator control socket must be available.
  /// Guarantees: command targets the `/api/key/stop` bridge endpoint.
  /// Invariants: does not directly access private Unix sockets.
  Future<void> stopKeyPattern() async {
    await _requestJson('POST', '/api/key/stop');
  }

  /// Send a BAK button tap command through the emulator bridge.
  ///
  /// Purpose: lets the GUI trigger one simulated button press/release.
  /// Parameters: [index] is the BAK button index in range 0..5.
  /// Return value: future that completes after the bridge accepts the command.
  /// Requirements: ButtonsAndKnobs control socket must be available.
  /// Guarantees: command targets the `button/tap` bridge endpoint.
  /// Invariants: does not directly access private Unix sockets.
  Future<void> tapBakButton({required int index}) async {
    await _requestJson('POST', '/api/bak/button/tap', {'index': index});
  }

  /// Send a BAK knob relative rotation command through the bridge.
  ///
  /// Purpose: lets the GUI test knob movement without physical hardware.
  /// Parameters: [index] is the BAK knob index in range 0..5; [delta] is the
  /// signed relative rotation amount.
  /// Return value: future that completes after the bridge accepts the command.
  /// Requirements: ButtonsAndKnobs control socket must be available.
  /// Guarantees: command targets the `knob/rotate` bridge endpoint.
  /// Invariants: does not directly access private Unix sockets.
  Future<void> rotateBakKnob({required int index, required int delta}) async {
    await _requestJson(
      'POST',
      '/api/bak/knob/rotate',
      {'index': index, 'value': delta},
    );
  }

  /// Set one BAK knob's raw encoder position through the bridge.
  ///
  /// Purpose: lets the GUI drag a simulated encoder to an absolute raw value.
  /// Parameters: [index] is the BAK knob index in range 0..5; [raw] is the
  /// synthetic encoder position.
  /// Return value: future that completes after the bridge accepts the command.
  /// Requirements: ButtonsAndKnobs control socket must be available.
  /// Guarantees: command targets the `knob/set` bridge endpoint.
  /// Invariants: does not directly access private Unix sockets.
  Future<void> setBakKnobRaw({required int index, required int raw}) async {
    await _requestJson(
      'POST',
      '/api/bak/knob/set',
      {'index': index, 'value': raw},
    );
  }

  /// Set one BAK knob's normalized value through the bridge.
  ///
  /// Purpose: lets the GUI drive provider-owned 0..1 knob state directly.
  /// Parameters: [index] is the BAK knob index in range 0..5; [value] is the
  /// normalized value expected to be in range 0..1.
  /// Return value: future that completes after the bridge accepts the command.
  /// Requirements: ButtonsAndKnobs control socket must be available.
  /// Guarantees: command targets the `knob/setNormalized` bridge endpoint.
  /// Invariants: does not directly access private Unix sockets.
  Future<void> setBakKnobNormalized({
    required int index,
    required double value,
  }) async {
    await _requestJson(
      'POST',
      '/api/bak/knob/setNormalized',
      {'index': index, 'value': value},
    );
  }

  /// Send one JSON request to the bridge and decode its object response.
  ///
  /// Purpose: centralizes status-code and JSON-object validation.
  /// Parameters: [method] is `GET` or `POST`; [path] is the API path; [payload]
  /// is an optional JSON object for POST-like requests.
  /// Return value: decoded JSON object.
  /// Requirements: bridge responses must be JSON objects.
  /// Guarantees: failed status codes and malformed JSON throw exceptions.
  /// Invariants: [baseUri] is not modified.
  Future<Map<String, Object?>> _requestJson(
    String method,
    String path, [
    Map<String, Object?>? payload,
  ]) async {
    final uri = baseUri.replace(path: path, queryParameters: null);
    final body = payload == null ? null : jsonEncode(payload);
    final response = await _transport(method, uri, body);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const BridgeClientException(
          'Bridge response was not a JSON object');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as String? ?? 'Bridge request failed';
      final detail = decoded['detail'] as String?;
      if (detail != null && detail.isNotEmpty) {
        throw BridgeClientException('$error: $detail');
      }
      throw BridgeClientException(error);
    }
    return decoded;
  }

  /// Default `dart:io` transport for bridge requests.
  ///
  /// Purpose: performs the actual localhost HTTP request used by the desktop
  /// Flutter app.
  /// Parameters: [method] is the HTTP method; [uri] is the full bridge endpoint;
  /// [body] is an optional JSON request body.
  /// Return value: raw [BridgeHttpResponse].
  /// Requirements: the process must have local network access.
  /// Guarantees: closes the temporary [HttpClient] after each request.
  /// Invariants: no retry or polling policy is embedded here.
  static Future<BridgeHttpResponse> _defaultTransport(
    String method,
    Uri uri,
    String? body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      if (body != null) {
        final bodyBytes = utf8.encode(body);
        request.contentLength = bodyBytes.length;
        request.add(bodyBytes);
      }
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      return BridgeHttpResponse(response.statusCode, responseBody);
    } finally {
      client.close(force: true);
    }
  }
}

/// Exception thrown when the bridge returns unusable data or an error status.
///
/// Purpose: gives UI state a small, user-displayable failure type.
/// Parameters: [message] is the user-facing failure reason.
/// Return value: exception object.
/// Requirements: [message] should not include stack traces.
/// Guarantees: [toString] returns the message only.
/// Invariants: this exception carries no retry state.
class BridgeClientException implements Exception {
  const BridgeClientException(this.message);

  final String message;

  /// Return the bridge failure message.
  ///
  /// Purpose: keeps error labels concise in the GUI.
  /// Parameters: none.
  /// Return value: [message].
  /// Requirements: none.
  /// Guarantees: no exception type prefix is added.
  /// Invariants: [message] is unchanged.
  @override
  String toString() {
    return message;
  }
}
