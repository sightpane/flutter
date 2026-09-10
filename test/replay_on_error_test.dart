import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightpane/sightpane.dart';

void main() {
  test(
    'in onError mode no frames/pointers are sent when there is no error; on error the last 30s buffer is flushed and live recording continues for postErrorSeconds',
    () {
      fakeAsync((async) {
        final framesSent = <SightpaneItem>[];
        final options = const SightpaneReplayOptions(
          enabled: true,
          mode: SightpaneReplayMode.onError,
          bufferSeconds: 30,
          postErrorSeconds: 15,
        );

        final recorder = ReplayRecorder(
          options: options,
          onFrame: (item) => framesSent.add(item),
        );

        // Simulate items emitted over 45 seconds (one every 5s)
        for (var s = 0; s < 9; s++) {
          async.elapse(const Duration(seconds: 5));
          recorder.emitForTesting(SightpaneItem.event('frame_$s'));
        }

        // Before any error, nothing is sent to onFrame
        expect(framesSent, isEmpty);
        // Ring buffer holds items from the last 30 seconds (6 items: 15s to 45s)
        expect(recorder.bufferedItemsCount, greaterThan(0));
        final bufferedCount = recorder.bufferedItemsCount;

        // An error occurs -> flushOnError() is called
        recorder.flushOnError();

        // All buffered items from the last 30 seconds are flushed to onFrame
        expect(framesSent, hasLength(bufferedCount));
        expect(recorder.bufferedItemsCount, 0);

        // Live recording continues for 15 seconds (postErrorSeconds)
        async.elapse(const Duration(seconds: 5));
        recorder.emitForTesting(SightpaneItem.event('live_1'));
        // Emitted directly to onFrame while live
        expect(framesSent, hasLength(bufferedCount + 1));

        // Advance past postErrorSeconds (15s total from error event)
        async.elapse(const Duration(seconds: 15));
        recorder.emitForTesting(SightpaneItem.event('buffered_again'));

        // Has returned to buffering mode: no new item sent to onFrame, added to ring buffer
        expect(framesSent, hasLength(bufferedCount + 1));
        expect(recorder.bufferedItemsCount, 1);
      });
    },
  );

  test('always mode emits items immediately without buffering', () {
    final framesSent = <SightpaneItem>[];
    final recorder = ReplayRecorder(
      options: const SightpaneReplayOptions(
        enabled: true,
        mode: SightpaneReplayMode.always,
      ),
      onFrame: (item) => framesSent.add(item),
    );

    recorder.emitForTesting(SightpaneItem.event('always_item'));

    expect(framesSent, hasLength(1));
    expect(recorder.bufferedItemsCount, 0);
  });

  test('off mode disables recording completely', () {
    final framesSent = <SightpaneItem>[];
    final recorder = ReplayRecorder(
      options: const SightpaneReplayOptions(
        enabled: true,
        mode: SightpaneReplayMode.off,
      ),
      onFrame: (item) => framesSent.add(item),
    );

    recorder.emitForTesting(SightpaneItem.event('off_item'));

    expect(framesSent, isEmpty);
    expect(recorder.bufferedItemsCount, 0);
  });
}
