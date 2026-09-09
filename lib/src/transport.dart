import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Delivers an envelope to the backend. `true` = accepted; `false` = will be
/// retried.
abstract class SightpaneTransport {
  Future<bool> send(SightpaneEnvelope envelope);
  Future<void> close() async {}
}

/// `POST <endpoint>/api/v1/envelope`.
class HttpTransport implements SightpaneTransport {
  HttpTransport({
    required this.endpoint,
    required this.apiKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();
  final String endpoint;
  final String apiKey;
  final Duration timeout;
  final http.Client _client;

  Uri get _uri =>
      Uri.parse('${endpoint.replaceFirst(RegExp(r'/+$'), '')}/api/v1/envelope');

  @override
  Future<bool> send(SightpaneEnvelope envelope) async {
    try {
      final r = await _client
          .post(
            _uri,
            headers: {'content-type': 'application/json', 'x-hog-key': apiKey},
            body: jsonEncode(envelope.toJson()),
          )
          .timeout(timeout);
      // A 4xx is a client error, so retrying it is pointless → count it as
      // accepted.
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> close() async => _client.close();
}
