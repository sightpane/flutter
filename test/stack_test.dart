import 'package:flutter_test/flutter_test.dart';
import 'package:sightpane/sightpane.dart';
import 'package:sightpane/src/stack.dart';

import 'fake_transport.dart';

// A minified release build reports its stack in the browser's own format, and
// the three engines disagree about what that is. The positions are the only
// useful part — the names are minified — and the backend turns them back into
// Dart source with the map uploaded for that release.

const _v8 =
    'Error\n'
    '    at Object.wrapException (https://app.example.com/main.dart.js:4321:19)\n'
    '    at aI.\$2 (https://app.example.com/main.dart.js:12345:67)';

const _firefox =
    'wrapException@https://app.example.com/main.dart.js:4321:19\n'
    '\$2@https://app.example.com/main.dart.js:12345:67';

const _nativeDart =
    '#0      CashierPage.settle (package:app/cashier.dart:120:5)\n'
    '#1      main (package:app/main.dart:10:3)';

void main() {
  test('a Chrome stack becomes positions the backend can map', () {
    expect(parseWebFrames(_v8), [
      {
        'uri': 'https://app.example.com/main.dart.js',
        'line': 4321,
        'column': 19,
        'member': 'Object.wrapException',
      },
      {
        'uri': 'https://app.example.com/main.dart.js',
        'line': 12345,
        'column': 67,
        'member': 'aI.\$2',
      },
    ]);
  });

  test('Firefox and Safari write it differently and parse the same', () {
    final frames = parseWebFrames(_firefox);
    expect(frames, hasLength(2));
    expect(frames.first['uri'], 'https://app.example.com/main.dart.js');
    expect(frames.first['line'], 4321);
    expect(frames.first['column'], 19);
  });

  // A native stack is already readable, so there is nothing to resolve and
  // nothing to send: the backend groups on the raw text as it always has.
  test('a native Dart stack produces no frames', () {
    expect(parseWebFrames(_nativeDart), isEmpty);
  });

  // Reporting an error must never itself throw, and a stack is the least
  // trustworthy string in the process.
  test('anything unreadable produces no frames instead of throwing', () {
    for (final s in [
      '',
      'not a stack at all',
      'at (((',
      '\n\n\n',
      'at x (https://app.example.com/style.css:1:1)', // not a script
    ]) {
      expect(parseWebFrames(s), isEmpty, reason: 'for ${s.isEmpty ? "''" : s}');
    }
  });

  test('a runaway stack is capped rather than filling the envelope', () {
    final huge = [
      'Error',
      for (var i = 0; i < 500; i++)
        '    at aI.\$2 (https://app.example.com/main.dart.js:$i:1)',
    ].join('\n');
    expect(parseWebFrames(huge), hasLength(30));
  });

  // The wire shape: `frames` rides beside `stack`, never instead of it, so a
  // backend that does not know about it loses nothing.
  test('frames travel beside the raw stack, and only when there are some', () {
    final withFrames = SightpaneItem.error(
      message: 'boom',
      exceptionType: 'StateError',
      stack: _v8,
      frames: parseWebFrames(_v8),
    ).toJson();
    expect(withFrames['stack'], _v8);
    expect(withFrames['frames'], hasLength(2));

    final without = SightpaneItem.error(
      message: 'boom',
      exceptionType: 'StateError',
      stack: _nativeDart,
    ).toJson();
    expect(without['stack'], _nativeDart);
    expect(without.containsKey('frames'), isFalse);
  });

  // On a native platform captureException must not spend anything on this:
  // there is no map, no browser and nothing to parse.
  testWidgets('captureException sends no frames off the web', (tester) async {
    final t = FakeTransport();
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://example.invalid',
        apiKey: 'k',
        transport: t,
        replay: const SightpaneReplayOptions(enabled: false),
      ),
    );
    Sightpane.captureException(StateError('boom'), stackTrace: StackTrace.current);
    await Sightpane.flush();
    expect(t.ofType('error'), hasLength(1));
    expect(t.ofType('error').single.toJson().containsKey('frames'), isFalse);
    await Sightpane.close();
  });
}
