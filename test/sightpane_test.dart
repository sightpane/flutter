import 'package:flutter/widgets.dart';
import 'package:sightpane/sightpane.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeTransport t;

  setUp(() async {
    t = FakeTransport();
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://x',
        apiKey: 'k',
        transport: t,
        release: '1.2.3',
        flushInterval: const Duration(days: 1),
        captureFlutterErrors: false,
        replay: const SightpaneReplayOptions(enabled: false),
      ),
    );
  });

  tearDown(() => Sightpane.close());

  test(
    'captureException carries breadcrumbs, route, device and user',
    () async {
      Sightpane.identify(const SightpaneUser(id: 'u1'));
      Sightpane.setProperty('location', 'NOVO');
      Sightpane.client.currentRoute = '/cashier';
      Sightpane.log('opened cashier');
      Sightpane.captureException(
        StateError('boom'),
        stackTrace: StackTrace.current,
        context: {'customer': 'c1'},
      );
      await Sightpane.flush();
      final err = t.ofType('error').single;
      expect(err.body['message'], 'Bad state: boom');
      expect(err.body['exception'], 'StateError');
      expect(err.body['route'], '/cashier');
      expect(err.body['context'], {'customer': 'c1'});
      final crumbs = err.body['breadcrumbs'] as List;
      expect(
        crumbs.map((c) => (c as Map)['message']),
        containsAll(['identify u1', 'opened cashier']),
      );
      final env = t.envelopes.last;
      expect(env.user?.id, 'u1');
      expect(env.props, {'location': 'NOVO'});
      expect(env.device['release'], '1.2.3');
      expect(env.device['platform'], isNotEmpty);
      expect(env.device['app_type'], 'desktop');
      expect(env.device.containsKey('browser'), isFalse);
    },
  );

  test('capture queues product events; close sends session_end', () async {
    Sightpane.capture('deposit', {'amount': 50});
    await Sightpane.close();
    expect(t.ofType('event').single.body['name'], 'deposit');
    expect(t.ofType('session_end'), hasLength(1));
    expect(t.closed, 1);
    expect(Sightpane.isInitialized, isFalse);
  });

  test('beforeSend can drop items', () async {
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://x',
        apiKey: 'k',
        transport: t,
        captureFlutterErrors: false,
        replay: const SightpaneReplayOptions(enabled: false),
        beforeSend: (i) => i.type == 'event' ? null : i,
      ),
    );
    Sightpane.capture('secret');
    Sightpane.log('kept');
    await Sightpane.flush();
    expect(t.ofType('event'), isEmpty);
    expect(t.ofType('breadcrumb').single.body['message'], 'kept');
  });

  test('FlutterError.onError is captured as unhandled and the previous handler still runs', () async {
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://x',
        apiKey: 'k',
        transport: t,
        flushInterval: const Duration(days: 1),
        replay: const SightpaneReplayOptions(enabled: false),
      ),
    );
    var prevCalls = 0;
    final prev = FlutterError.onError;
    FlutterError.onError = (_) => prevCalls++;
    Sightpane.client.bindFlutterErrors();
    FlutterError.reportError(
      FlutterErrorDetails(exception: Exception('render'), library: 'widgets'),
    );
    await Sightpane.flush();
    final err = t.ofType('error').single;
    expect(err.body['handled'], false);
    expect((err.body['context'] as Map)['library'], 'widgets');
    expect(prevCalls, 1);
    await Sightpane.close();
    expect(FlutterError.onError, isNot(prev)); // previous (counter) restored
    FlutterError.onError = prev;
  });
}
