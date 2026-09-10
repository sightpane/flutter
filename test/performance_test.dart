import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sightpane/sightpane.dart';

import 'fake_transport.dart';

void main() {
  test('transaction and span lifecycle emits transaction item with child spans', () async {
    final transport = FakeTransport();
    final client = SightpaneClient(
      SightpaneOptions(
        endpoint: 'http://example.com',
        apiKey: 'key',
        transport: transport,
        flushInterval: Duration.zero,
      ),
    );

    final tx = client.startTransaction('checkout_flow', op: 'ui.workflow');
    expect(tx.name, 'checkout_flow');
    expect(tx.op, 'ui.workflow');
    expect(tx.isFinished, isFalse);

    final childSpan = tx.startChild('db.query', 'SELECT items');
    expect(childSpan.op, 'db.query');
    expect(childSpan.name, 'SELECT items');
    expect(childSpan.parentSpanId, tx.spanId);
    expect(childSpan.traceId, tx.traceId);

    childSpan.finish(status: 'ok');
    expect(childSpan.isFinished, isTrue);

    tx.finish(status: 'ok');
    expect(tx.isFinished, isTrue);

    await client.flush();

    expect(transport.envelopes, isNotEmpty);
    final env = transport.envelopes.first;
    final items = env.items.where((i) => i.type == 'transaction').toList();
    expect(items, hasLength(1));

    final txItem = items.first;
    expect(txItem.body['name'], 'checkout_flow');
    expect(txItem.body['op'], 'ui.workflow');
    expect(txItem.body['status'], 'ok');
    final spans = txItem.body['spans'] as List;
    expect(spans, hasLength(1));
    final child = spans.first as Map<String, Object?>;
    expect(child['name'], 'SELECT items');
    expect(child['op'], 'db.query');
    expect(child['parent_span_id'], tx.spanId);
  });

  test('recordSpan enqueues a standalone span item', () async {
    final transport = FakeTransport();
    final client = SightpaneClient(
      SightpaneOptions(
        endpoint: 'http://example.com',
        apiKey: 'key',
        transport: transport,
        flushInterval: Duration.zero,
      ),
    );

    client.recordSpan(
      op: 'compute',
      name: 'fibonacci',
      durationMs: 42.5,
      status: 'ok',
      tags: {'n': 20},
    );

    await client.flush();

    final env = transport.envelopes.first;
    final spans = env.items.where((i) => i.type == 'span').toList();
    expect(spans, hasLength(1));
    expect(spans.first.body['op'], 'compute');
    expect(spans.first.body['name'], 'fibonacci');
    expect(spans.first.body['duration_ms'], 42.5);
  });

  test('SightpaneHttpClient emits both breadcrumb and span', () async {
    final transport = FakeTransport();
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://example.com',
        apiKey: 'key',
        transport: transport,
        flushInterval: Duration.zero,
      ),
    );

    final mockClient = MockClient((request) async {
      return http.Response('{"ok":true}', 200);
    });
    final client = SightpaneHttpClient(mockClient);

    final res = await client.get(Uri.parse('http://api.example.com/users'));
    expect(res.statusCode, 200);

    final breadcrumbs = Sightpane.client.breadcrumbs.snapshot();
    expect(breadcrumbs.any((b) => b.category == 'http'), isTrue);

    await Sightpane.flush();
    final items = transport.envelopes.expand((e) => e.items).toList();
    final spans = items.where((i) => i.type == 'span' && i.body['op'] == 'http.client').toList();
    expect(spans, isNotEmpty);
    expect(spans.first.body['name'], contains('/users'));
    expect(spans.first.body['status'], '200');

    await Sightpane.close();
  });

  testWidgets('SightpaneNavigatorObserver emits navigation route span', (tester) async {
    final transport = FakeTransport();
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://example.com',
        apiKey: 'key',
        transport: transport,
        flushInterval: Duration.zero,
      ),
    );

    final observer = SightpaneNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('Home')),
        routes: {
          '/details': (context) => const Scaffold(body: Text('Details')),
        },
      ),
    );

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/details');
    await tester.pumpAndSettle();

    await Sightpane.flush();
    final items = transport.envelopes.expand((e) => e.items).toList();
    final routeSpans = items.where((i) => i.type == 'span' && i.body['op'] == 'navigation').toList();
    expect(routeSpans, isNotEmpty);
    expect(
      routeSpans.any((s) => (s.body['name'] as String).contains('/details')),
      isTrue,
    );

    await Sightpane.close();
  });
}
