// sightpane — error tracking, product analytics and session replay you host yourself.
// Copyright (C) 2026 Can Us
//
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Client for sending cron job & scheduled task heartbeat check-ins to Sightpane.
class CronCheckinClient {
  const CronCheckinClient({
    required this.endpoint,
    required this.apiKey,
    this.client,
  });

  final String endpoint;
  final String apiKey;
  final http.Client? client;

  /// Sends a check-in ping for monitor [slug].
  /// [status] must be 'ok', 'in_progress', or 'error'.
  Future<bool> checkin(
    String slug, {
    String status = 'ok',
    int? durationMs,
    String? message,
  }) async {
    final base = endpoint.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/crons/$slug/checkin');
    final httpClient = client ?? http.Client();
    try {
      final res = await httpClient.post(
        uri,
        headers: {
          'content-type': 'application/json',
          'x-sightpane-key': apiKey,
        },
        body: jsonEncode({
          'status': status,
          'duration_ms': ?durationMs,
          'message': ?message,
        }),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
