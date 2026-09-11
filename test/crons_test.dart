// sightpane — error tracking, product analytics and session replay you host yourself.
// Copyright (C) 2026 Can Us
//
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sightpane/sightpane.dart';
import 'package:sightpane/src/crons/crons.dart';

void main() {
  group('CronCheckinClient', () {
    test('checkin sends correct headers and body to crons checkin endpoint', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'checkin_id': 1,
            'monitor_status': 'ok',
          }),
          200,
        );
      });

      final client = CronCheckinClient(
        endpoint: 'https://sightpane.example.com',
        apiKey: 'test_project_key_123',
        client: mockClient,
      );

      final success = await client.checkin(
        'nightly-backup',
        status: 'ok',
        durationMs: 3450,
        message: 'Backup succeeded',
      );

      expect(success, isTrue);
      expect(
        capturedRequest.url.toString(),
        'https://sightpane.example.com/api/v1/crons/nightly-backup/checkin',
      );
      expect(capturedRequest.headers['x-sightpane-key'], 'test_project_key_123');
      expect(capturedRequest.headers['content-type'], 'application/json');

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['status'], 'ok');
      expect(body['duration_ms'], 3450);
      expect(body['message'], 'Backup succeeded');
    });

    test('checkin returns false on server failure', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final client = CronCheckinClient(
        endpoint: 'https://sightpane.example.com',
        apiKey: 'key',
        client: mockClient,
      );

      final success = await client.checkin('failing-job');
      expect(success, isFalse);
    });
  });
}
