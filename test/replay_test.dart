import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:sightpane/sightpane.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

Future<ui.Image> decode(List<int> png) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
  return (await codec.getNextFrame()).image;
}

Future<Color> pixel(ui.Image img, int x, int y) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * img.width + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

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
          scale: 0.5,
        ),
      ),
    );
  });
  tearDown(() => Sightpane.close());

  testWidgets(
    'captures a half-scale frame, blacks out SightpaneMask, skips unchanged frames, attaches taps',
    (tester) async {
      tester.view.physicalSize = const Size(400, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SightpaneReplay(
            child: SightpaneUserInteractionWidget(
              child: ColoredBox(
                color: const Color(0xFFFF0000),
                child: Stack(
                  children: [
                    Positioned(
                      left: 200,
                      top: 0,
                      width: 200,
                      height: 200,
                      child: SightpaneMask(
                        child: Container(color: const Color(0xFF00FF00)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(MaskRegistry.count, 1);
      final rec = Sightpane.client.replay;
      expect(rec.isRunning, isTrue);
      await tester.runAsync(() => rec.captureNow());
      expect(rec.lastSeq, 1);
      final frame = Sightpane.client.queue.pending
          .where((i) => i.isFrame)
          .single;
      expect(frame.body['width'], 200);
      expect(frame.body['height'], 100);
      final img = await tester.runAsync(
        () => decode(base64Decode(frame.body['png'] as String)),
      );
      expect(img!.width, 200);
      expect(
        await tester.runAsync(() => pixel(img, 50, 50)),
        const Color(0xFFFF0000),
      ); // unmasked red
      expect(
        await tester.runAsync(() => pixel(img, 150, 50)),
        const Color(0xFF000000),
      ); // masked black

      // Unchanged screen → no new frame.
      await tester.runAsync(() => rec.captureNow());
      expect(rec.lastSeq, 1);

      // A tap → the frame is sent along with it, even though the image is
      // identical.
      await tester.tapAt(const Offset(100, 100));
      await tester.pump();
      await tester.runAsync(() => rec.captureNow());
      expect(rec.lastSeq, 2);
      final f2 = Sightpane.client.queue.pending.where((i) => i.isFrame).last;
      final taps = f2.body['taps'] as List;
      expect((taps.single as Map)['x'], 0.25);
      expect((taps.single as Map)['y'], 0.5);
      await Sightpane.close();
    },
  );

  testWidgets('an error triggers a fresh frame and references its seq', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SightpaneReplay(child: Text('x'))),
    );
    await tester.runAsync(() async {
      Sightpane.captureException(Exception('e'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await Sightpane.flush();
    expect(t.ofType('frame'), hasLength(1));
    expect(Sightpane.client.replay.lastSeq, 1);
    await Sightpane.close();
  });

  testWidgets('replay disabled: no frames, boundary still renders', (
    tester,
  ) async {
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://x',
        apiKey: 'k',
        transport: t,
        captureFlutterErrors: false,
        replay: const SightpaneReplayOptions(enabled: false),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: SightpaneReplay(child: Text('visible'))),
    );
    expect(find.text('visible'), findsOneWidget);
    await tester.runAsync(() => Sightpane.client.replay.captureNow());
    expect(Sightpane.client.replay.lastSeq, isNull);
    await Sightpane.close();
  });
}
