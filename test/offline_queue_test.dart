import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightpane/sightpane.dart';

import 'fake_transport.dart';

void main() {
  SightpaneEnvelope build(List<SightpaneItem> items) => SightpaneEnvelope(
    sessionId: 's',
    startedAt: DateTime.utc(2026),
    items: items,
  );

  test('offline errors persist to storage, frames are ignored', () {
    fakeAsync((async) {
      final storage = InMemorySightpaneStorage();
      final transport = FakeTransport(ok: false); // offline

      final q1 = SightpaneQueue(
        transport: transport,
        envelopeBuilder: build,
        storage: storage,
      );

      // Add an error and a frame while offline
      q1.add(SightpaneItem.error(message: 'disk crash', exceptionType: 'DiskError'));
      q1.add(SightpaneItem.frame(seq: 1, width: 100, height: 100, png: [1, 2, 3]));
      async.flushMicrotasks();

      // Verify in-memory storage contains the error but NOT the frame
      final persisted = storage.readSync();
      expect(persisted, hasLength(1));
      expect(persisted.first.type, 'error');
      expect(persisted.first.body['message'], 'disk crash');

      q1.close();

      // Now simulate app restarting online
      final onlineTransport = FakeTransport(ok: true);
      final q2 = SightpaneQueue(
        transport: onlineTransport,
        envelopeBuilder: build,
        storage: storage,
      );

      // Restore items from storage and let async operations drain
      q2.restoreFromStorage();
      async.flushMicrotasks();

      // Sent to transport successfully
      expect(onlineTransport.ofType('error'), hasLength(1));
      expect(onlineTransport.ofType('error').first.body['message'], 'disk crash');
      expect(q2.length, 0);

      // Storage is now empty
      expect(storage.readSync(), isEmpty);
      q2.close();
    });
  });

  test('FileSightpaneStorage persists errors to disk and restores them', () async {
    final tempDir = Directory.systemTemp.createTempSync('sightpane_test_');
    final filePath = '${tempDir.path}/queue.json';

    try {
      final storage = FileSightpaneStorage(path: filePath);
      final transportOffline = FakeTransport(ok: false);

      final q1 = SightpaneQueue(
        transport: transportOffline,
        envelopeBuilder: build,
        storage: storage,
      );

      q1.add(SightpaneItem.error(message: 'saved to file', exceptionType: 'IOError'));
      q1.add(SightpaneItem.event('navigation_event'));
      // A frame should be skipped from storage
      q1.add(SightpaneItem.frame(seq: 2, width: 50, height: 50, png: [9, 8]));

      // Force persistence to disk and close
      await q1.close();

      // Check file content directly
      final file = File(filePath);
      expect(file.existsSync(), isTrue);

      // Restore in a second queue instance (reopening app online)
      final transportOnline = FakeTransport(ok: true);
      final q2 = SightpaneQueue(
        transport: transportOnline,
        envelopeBuilder: build,
        storage: storage,
      );

      await q2.restoreFromStorage();
      await pumpEventQueue();

      // Verify items sent
      expect(transportOnline.items, hasLength(2));
      expect(transportOnline.ofType('error').first.body['message'], 'saved to file');
      expect(transportOnline.ofType('event').first.body['name'], 'navigation_event');

      await q2.close();
      expect(file.existsSync(), isFalse); // File removed after successful drain
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });

  test('Sightpane.init restores offline error from previous session on restart', () async {
    final storage = InMemorySightpaneStorage();
    final offlineTransport = FakeTransport(ok: false);

    await Sightpane.init(
      SightpaneOptions(
        apiKey: 'test-key',
        endpoint: 'http://localhost',
        transport: offlineTransport,
        storage: storage,
      ),
    );

    Sightpane.captureException('offline crash');
    // Shutdown the app
    await Sightpane.close();

    expect(storage.readSync(), isNotEmpty);
    expect(offlineTransport.ofType('error'), isEmpty);

    // Restart app online
    final onlineTransport = FakeTransport(ok: true);
    await Sightpane.init(
      SightpaneOptions(
        apiKey: 'test-key',
        endpoint: 'http://localhost',
        transport: onlineTransport,
        storage: storage,
      ),
    );

    // Pump to allow async send to complete
    await pumpEventQueue();

    expect(onlineTransport.ofType('error'), hasLength(1));
    expect(onlineTransport.ofType('error').first.body['message'], 'offline crash');
    expect(storage.readSync(), isEmpty);

    await Sightpane.close();
  });
}
