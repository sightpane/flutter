// sightpane — error tracking, product analytics and session replay you host yourself.
// Copyright (C) 2026 Can Us
//
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sightpane/sightpane.dart';

import 'fake_transport.dart';

void main() {
  group('W3C TraceContext and SightpaneHttpClient', () {
    test('SightpaneTraceContext parses and formats W3C traceparent', () {
      const header = '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01';
      final tc = SightpaneTraceContext.tryParse(header);
      expect(tc, isNotNull);
      expect(tc!.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(tc.spanId, '00f067aa0ba902b7');
      expect(tc.sampled, isTrue);
      expect(tc.toTraceparent(), header);

      // Invalid headers
      expect(SightpaneTraceContext.tryParse(''), isNull);
      expect(SightpaneTraceContext.tryParse('invalid-header'), isNull);
      expect(SightpaneTraceContext.tryParse('01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'), isNull);
      expect(SightpaneTraceContext.tryParse('00-00000000000000000000000000000000-00f067aa0ba902b7-01'), isNull);
    });

    test('SightpaneHttpClient automatically injects traceparent header', () async {
      final transport = FakeTransport();
      await Sightpane.init(
        SightpaneOptions(
          endpoint: 'http://example.com',
          apiKey: 'key',
          transport: transport,
          flushInterval: Duration.zero,
        ),
      );

      String? capturedTraceparent;
      final mockClient = MockClient((request) async {
        capturedTraceparent = request.headers['traceparent'];
        return http.Response('{"status":"ok"}', 200);
      });

      final client = SightpaneHttpClient(mockClient);
      final res = await client.get(Uri.parse('https://api.example.com/checkout'));
      expect(res.statusCode, 200);

      expect(capturedTraceparent, isNotNull);
      expect(capturedTraceparent, startsWith('00-'));
      final parsed = SightpaneTraceContext.tryParse(capturedTraceparent);
      expect(parsed, isNotNull);
      expect(parsed!.traceId.length, 32);
      expect(parsed.spanId.length, 16);
      expect(parsed.sampled, isTrue);

      await Sightpane.close();
    });

    test('SightpaneHttpClient inherits traceId and parentSpanId from active transaction', () async {
      final transport = FakeTransport();
      await Sightpane.init(
        SightpaneOptions(
          endpoint: 'http://example.com',
          apiKey: 'key',
          transport: transport,
          flushInterval: Duration.zero,
        ),
      );

      final tx = Sightpane.startTransaction('user_checkout', op: 'ui.action');
      expect(tx, isNotNull);
      expect(Sightpane.currentTransaction, tx);

      String? capturedTraceparent;
      final mockClient = MockClient((request) async {
        capturedTraceparent = request.headers['traceparent'];
        return http.Response('{"order_id":123}', 201);
      });

      final client = SightpaneHttpClient(mockClient);
      await client.post(Uri.parse('https://api.example.com/orders'));

      expect(capturedTraceparent, isNotNull);
      final parsed = SightpaneTraceContext.tryParse(capturedTraceparent);
      expect(parsed, isNotNull);
      // Inherited trace ID from transaction
      expect(parsed!.traceId, tx.traceId);

      tx.finish(status: 'ok');
      expect(Sightpane.currentTransaction, isNull);

      await Sightpane.flush();
      final items = transport.envelopes.expand((e) => e.items).toList();
      final spans = items.where((i) => i.type == 'span' && i.body['op'] == 'http.client').toList();
      expect(spans, isNotEmpty);
      expect(spans.first.body['trace_id'], tx.traceId);
      expect(spans.first.body['parent_span_id'], tx.spanId);

      await Sightpane.close();
    });
  });
}
