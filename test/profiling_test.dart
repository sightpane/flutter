import 'package:flutter_test/flutter_test.dart';
import 'package:sightpane/sightpane.dart';

import 'fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SightpaneProfileSampler collects samples and encodes to Speedscope format', () {

    final sampler = SightpaneProfileSampler(
      transactionName: 'checkout_profile',
      traceId: 'trace-123',
    );

    sampler.sampleManual(['root', 'loadItems', 'parseJSON'], 10.0);
    sampler.sampleManual(['root', 'loadItems', 'parseJSON'], 20.0);
    sampler.sampleManual(['root', 'loadItems', 'regexMatch'], 30.0);

    expect(sampler.sampleCount, 3);

    final item = sampler.stop(durationMs: 45.0);
    expect(item, isNotNull);
    expect(item!.type, 'profile');
    expect(item.body['transaction_name'], 'checkout_profile');
    expect(item.body['trace_id'], 'trace-123');
    expect(item.body['duration_ms'], 45.0);
    expect(item.body['cpu_time_ms'], isNotNull);

    final profileData = item.body['profile_data'] as Map<String, Object?>;
    final shared = profileData['shared'] as Map<String, Object?>;
    final frames = shared['frames'] as List;
    expect(frames, hasLength(4)); // root, loadItems, parseJSON, regexMatch

    final samples = profileData['samples'] as List;
    expect(samples, hasLength(3));
  });

  test('transaction emits profile item when profile: true', () async {
    final transport = FakeTransport();
    final client = SightpaneClient(
      SightpaneOptions(
        endpoint: 'http://example.com',
        apiKey: 'key',
        transport: transport,
        flushInterval: Duration.zero,
        profilesSampleRate: 0.0, // disabled by default
      ),
    );

    final tx = client.startTransaction('heavy_tx', profile: true);
    expect(tx.sampler, isNotNull);

    tx.sampler!.sampleManual(['main', 'runOperation'], 12.0);
    tx.finish();

    await client.flush();

    expect(transport.envelopes, isNotEmpty);
    final env = transport.envelopes.first;
    final profileItems = env.items.where((i) => i.type == 'profile').toList();
    expect(profileItems, hasLength(1));

    final p = profileItems.first;
    expect(p.body['transaction_name'], 'heavy_tx');
    expect(p.body['trace_id'], tx.traceId);
  });

  test('profilesSampleRate: 1.0 automatically enables profiling on startTransaction', () async {
    final transport = FakeTransport();
    final client = SightpaneClient(
      SightpaneOptions(
        endpoint: 'http://example.com',
        apiKey: 'key',
        transport: transport,
        flushInterval: Duration.zero,
        profilesSampleRate: 1.0,
      ),
    );

    final tx = client.startTransaction('auto_profiled_tx');
    expect(tx.sampler, isNotNull);

    tx.sampler!.sampleManual(['app', 'render'], 15.0);
    tx.finish();

    await client.flush();

    final env = transport.envelopes.first;
    final profileItems = env.items.where((i) => i.type == 'profile').toList();
    expect(profileItems, hasLength(1));
  });

  test('client.profile helper profiles async block and finishes cleanly', () async {
    final transport = FakeTransport();
    final client = SightpaneClient(
      SightpaneOptions(
        endpoint: 'http://example.com',
        apiKey: 'key',
        transport: transport,
        flushInterval: Duration.zero,
      ),
    );

    final result = await client.profile('fetch_data', () async {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      return 42;
    });

    expect(result, 42);

    await client.flush();

    expect(transport.envelopes, isNotEmpty);
    final env = transport.envelopes.first;
    final txItems = env.items.where((i) => i.type == 'transaction').toList();
    expect(txItems, hasLength(1));
    expect(txItems.first.body['name'], 'fetch_data');
  });

  test('sampler stops and cancels timer on finish without leaks', () async {
    final sampler = SightpaneProfileSampler(
      transactionName: 'timer_test',
      sampleInterval: const Duration(milliseconds: 5),
    );

    sampler.start();
    expect(sampler.isRunning, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    final item = sampler.stop(durationMs: 25.0);

    expect(sampler.isRunning, isFalse);
    expect(item, isNotNull);
    expect(sampler.sampleCount, greaterThan(0));

    // Calling stop again returns null and does not fail
    expect(sampler.stop(durationMs: 30.0), isNull);
  });
}
