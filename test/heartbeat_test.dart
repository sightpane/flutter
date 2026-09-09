import 'package:sightpane/sightpane.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'heartbeats carry the current route and stop while backgrounded',
    () async {
      final t = FakeTransport();
      await Sightpane.init(
        SightpaneOptions(
          endpoint: 'http://x',
          apiKey: 'k',
          transport: t,
          captureFlutterErrors: false,
          replay: const SightpaneReplayOptions(enabled: false),
          heartbeatInterval: const Duration(days: 1),
          flushInterval: const Duration(days: 1),
        ),
      );
      Sightpane.client.currentRoute = '/cashier';
      Sightpane.client.sendHeartbeat();
      await Sightpane.flush();
      final hb = t.ofType('heartbeat').single;
      expect(hb.body['route'], '/cashier');
      // No heartbeats while the app is backgrounded.
      Sightpane.client.debugSetForeground(false);
      Sightpane.client.sendHeartbeat();
      await Sightpane.flush();
      expect(t.ofType('heartbeat'), hasLength(1));
      Sightpane.client.debugSetForeground(true);
      Sightpane.client.sendHeartbeat();
      await Sightpane.flush();
      expect(t.ofType('heartbeat'), hasLength(2));
      await Sightpane.close();
    },
  );

  test('device info carries a browser label on every platform', () {
    final d = SightpaneDevice.collect();
    expect(d['browser'], isNotEmpty);
  });
}
