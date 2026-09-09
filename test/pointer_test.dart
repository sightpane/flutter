import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:sightpane/sightpane.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

void main() {
  late FakeTransport t;
  setUp(() async {
    t = FakeTransport();
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://x',
        apiKey: 'k',
        transport: t,
        flushInterval: const Duration(days: 1),
        captureFlutterErrors: false,
        replay: const SightpaneReplayOptions(
          interval: Duration(days: 1),
          pointerSampleInterval: Duration.zero,
        ),
      ),
    );
  });

  testWidgets(
    'hover, drag, click and scroll become a pointer packet with normalized coordinates',
    (tester) async {
      tester.view.physicalSize = const Size(400, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: SightpaneReplay(
            child: SightpaneUserInteractionWidget(child: SizedBox.expand()),
          ),
        ),
      );
      final rec = Sightpane.client.replay;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(40, 20));
      await tester.pump();
      await mouse.moveTo(const Offset(80, 40));
      await tester.pump(const Duration(milliseconds: 60));
      await mouse.moveTo(
        const Offset(81, 41),
      ); // 1 px counts as standing still, so no sample
      await tester.pump(const Duration(milliseconds: 60));
      await mouse.moveTo(const Offset(200, 100));
      await tester.pump(const Duration(milliseconds: 60));
      await mouse.down(const Offset(200, 100));
      await mouse.up();
      await tester.pump();
      rec.flushPointer();
      expect(rec.pendingPointerSamples, 0);
      await Sightpane.flush();
      final packet = t.ofType('pointer').single;
      final events = (packet.body['events'] as List).cast<Map>();
      expect(events.where((e) => e['k'] == 'down').single['x'], 0.5);
      expect(events.where((e) => e['k'] == 'down').single['y'], 0.5);
      expect(events.where((e) => e['k'] == 'up'), hasLength(1));
      final moves = events.where((e) => e['k'] == 'move').toList();
      expect(moves.length, inInclusiveRange(2, 3));
      expect(moves.any((e) => e['x'] == 0.2 && e['y'] == 0.2), isTrue);
      expect(moves.any((e) => e['x'] == 0.2025), isFalse); // 1 px drift gone
      expect(events.first['t'], 0);
      expect(events.last['t'], greaterThanOrEqualTo(events.first['t'] as int));
      await Sightpane.close();
    },
  );

  testWidgets(
    'a frame capture flushes pending pointer samples first; disabled recordPointer records nothing',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SightpaneReplay(
            child: SightpaneUserInteractionWidget(child: SizedBox.expand()),
          ),
        ),
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(Sightpane.client.replay.pendingPointerSamples, 2); // down + up
      await tester.runAsync(() => Sightpane.client.replay.captureNow());
      expect(Sightpane.client.replay.pendingPointerSamples, 0);
      expect(
        Sightpane.client.queue.pending.map((i) => i.type),
        containsAll(['pointer', 'frame']),
      );
      await Sightpane.close();

      await Sightpane.init(
        SightpaneOptions(
          endpoint: 'http://x',
          apiKey: 'k',
          transport: t,
          captureFlutterErrors: false,
          replay: const SightpaneReplayOptions(
            interval: Duration(days: 1),
            recordPointer: false,
          ),
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: SightpaneReplay(
            child: SightpaneUserInteractionWidget(child: SizedBox.expand()),
          ),
        ),
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(Sightpane.client.replay.pendingPointerSamples, 0);
      await Sightpane.close();
    },
  );
}
