import 'package:fake_async/fake_async.dart';
import 'package:sightpane/sightpane.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

void main() {
  SightpaneEnvelope build(List<SightpaneItem> items) => SightpaneEnvelope(
    sessionId: 's',
    startedAt: DateTime.utc(2026),
    items: items,
  );

  test('flushes on the interval and when the batch fills', () {
    fakeAsync((async) {
      final t = FakeTransport();
      final q = SightpaneQueue(
        transport: t,
        envelopeBuilder: build,
        flushInterval: const Duration(seconds: 5),
        maxBatch: 3,
      );
      q.add(SightpaneItem.event('a'));
      async.elapse(const Duration(seconds: 4));
      expect(t.envelopes, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(t.items.length, 1);
      for (var i = 0; i < 3; i++) {
        q.add(SightpaneItem.event('b$i'));
      }
      async.flushMicrotasks();
      expect(t.envelopes.length, 2);
      expect(t.envelopes.last.items.length, 3);
    });
  });

  test('errors flush immediately', () {
    fakeAsync((async) {
      final t = FakeTransport();
      final q = SightpaneQueue(transport: t, envelopeBuilder: build);
      q.add(SightpaneItem.error(message: 'x', exceptionType: 'E'));
      async.flushMicrotasks();
      expect(t.ofType('error').length, 1);
    });
  });

  test('a failed send keeps items and retries with backoff', () {
    fakeAsync((async) {
      final t = FakeTransport(ok: false);
      final q = SightpaneQueue(
        transport: t,
        envelopeBuilder: build,
        flushInterval: const Duration(seconds: 1),
      );
      q.add(SightpaneItem.event('a'));
      async.elapse(const Duration(seconds: 1));
      expect(q.length, 1);
      expect(t.envelopes, isEmpty);
      t.ok = true;
      async.elapse(const Duration(seconds: 1)); // 2s backoff not elapsed yet
      expect(t.envelopes, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(t.items.length, 1);
      expect(q.length, 0);
      expect(q.sent, 1);
    });
  });

  test(
    'over the queue limit frames go first, then non-errors; errors survive',
    () {
      fakeAsync((async) {
        final t = FakeTransport(ok: false);
        final q = SightpaneQueue(
          transport: t,
          envelopeBuilder: build,
          maxQueue: 3,
          maxBatch: 100,
        );
        q.add(SightpaneItem.error(message: 'e', exceptionType: 'E'));
        async.flushMicrotasks();
        q.add(SightpaneItem.frame(seq: 1, width: 1, height: 1, png: [0]));
        q.add(SightpaneItem.event('a'));
        q.add(SightpaneItem.event('b'));
        expect(q.pending.map((i) => i.type), ['error', 'event', 'event']);
        q.add(SightpaneItem.event('c'));
        expect(q.pending.map((i) => i.type), ['error', 'event', 'event']);
        expect(q.pending.last.body['name'], 'c');
        expect(q.dropped, 2);
      });
    },
  );

  test('large frames split batches by byte budget', () {
    fakeAsync((async) {
      final t = FakeTransport();
      final q = SightpaneQueue(
        transport: t,
        envelopeBuilder: build,
        maxBatch: 10,
        maxBatchBytes: 1000,
      );
      for (var i = 0; i < 3; i++) {
        q.add(
          SightpaneItem.frame(
            seq: i,
            width: 1,
            height: 1,
            png: List.filled(600, 0),
          ),
        );
      }
      q.flush();
      async.flushMicrotasks();
      expect(t.envelopes.length, 3);
    });
  });
}
