import 'package:flutter_test/flutter_test.dart';
import 'package:sightpane/sightpane.dart';

import 'fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sessionSampleRate: 0 disables frames and breadcrumbs, but errors still go out', () async {
    final transport = FakeTransport();
    final client = SightpaneClient(
      SightpaneOptions(
        endpoint: 'http://localhost',
        apiKey: 'key',
        sessionSampleRate: 0.0,
        transport: transport,
      ),
    );

    expect(client.sampled, isFalse);

    // Try adding breadcrumb
    client.addBreadcrumb(SightpaneBreadcrumb(category: 'ui', message: 'button tap'));
    expect(client.breadcrumbs.length, 0);

    // Try capturing an error
    client.captureException('network failure');
    await client.flush();

    // Verify only error was sent, no frames or breadcrumbs
    expect(transport.items.length, 1);
    expect(transport.items.first.type, 'error');
    expect(transport.items.first.body['message'], 'network failure');
    expect(transport.ofType('breadcrumb'), isEmpty);
    expect(transport.ofType('frame'), isEmpty);

    await client.close();
  });

  test('errorSampleRate: 0 drops errors', () async {
    final transport = FakeTransport();
    final client = SightpaneClient(
      SightpaneOptions(
        endpoint: 'http://localhost',
        apiKey: 'key',
        sessionSampleRate: 1.0,
        errorSampleRate: 0.0,
        transport: transport,
      ),
    );

    client.captureException('dropped error');
    await client.flush();

    expect(transport.ofType('error'), isEmpty);
    await client.close();
  });

  test('tracesSampleRate: 0 drops spans', () async {
    final transport = FakeTransport();
    final client = SightpaneClient(
      SightpaneOptions(
        endpoint: 'http://localhost',
        apiKey: 'key',
        tracesSampleRate: 0.0,
        transport: transport,
      ),
    );

    client.recordSpan(op: 'http', name: 'GET /api', durationMs: 42);
    await client.flush();

    expect(transport.ofType('span'), isEmpty);
    await client.close();
  });
}
