import 'dart:convert';

import 'package:sightpane/sightpane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('envelope serializes session, user, device and items', () {
    final b = SightpaneBreadcrumb(
      category: 'log',
      message: 'hi',
      ts: DateTime.utc(2026, 9, 7, 10),
    );
    final env = SightpaneEnvelope(
      sessionId: 'abc',
      startedAt: DateTime.utc(2026, 9, 7, 9),
      user: const SightpaneUser(id: 'u1', email: 'a@b.c'),
      device: const {'platform': 'linux'},
      props: const {'location': 'NOVO'},
      items: [
        SightpaneItem.breadcrumb(b),
        SightpaneItem.event(
          'deposit',
          props: {'amount': 50},
          ts: DateTime.utc(2026),
        ),
        SightpaneItem.error(
          message: 'boom',
          exceptionType: 'StateError',
          stack: 'a\nb',
          frameSeq: 3,
          route: '/x',
          breadcrumbs: [b],
          ts: DateTime.utc(2026),
        ),
        SightpaneItem.frame(
          seq: 3,
          width: 10,
          height: 5,
          png: [1, 2, 3],
          taps: [SightpaneTap(x: 0.5, y: 0.25, ts: DateTime.utc(2026))],
          ts: DateTime.utc(2026),
        ),
        SightpaneItem.sessionEnd(ts: DateTime.utc(2026)),
      ],
    );
    final j = jsonDecode(jsonEncode(env.toJson())) as Map<String, dynamic>;
    expect(j['sdk'], {
      'name': 'sightpane',
      'version': SightpaneEnvelope.sdkVersionString,
    });
    expect(j['session']['id'], 'abc');
    expect(j['session']['user'], {'id': 'u1', 'email': 'a@b.c'});
    expect(j['session']['props'], {'location': 'NOVO'});
    final items = j['items'] as List;
    expect(items.map((i) => i['type']), [
      'breadcrumb',
      'event',
      'error',
      'frame',
      'session_end',
    ]);
    expect(items[0], {
      'type': 'breadcrumb',
      'ts': '2026-09-07T10:00:00.000Z',
      'category': 'log',
      'message': 'hi',
      'level': 'info',
    });
    expect(items[1]['props'], {'amount': 50});
    expect(items[2]['frame_seq'], 3);
    expect(items[2]['route'], '/x');
    expect(items[2]['handled'], true);
    expect((items[2]['breadcrumbs'] as List).length, 1);
    expect(items[3]['png'], base64Encode([1, 2, 3]));
    expect(items[3]['taps'][0]['x'], 0.5);
  });

  test('breadcrumb buffer drops the oldest beyond capacity', () {
    final buf = BreadcrumbBuffer(2);
    for (var i = 0; i < 5; i++) {
      buf.add(SightpaneBreadcrumb(category: 'c', message: '$i'));
    }
    expect(buf.snapshot().map((b) => b.message), ['3', '4']);
  });

  test('session ids are unique uuid-shaped hex', () {
    final a = SightpaneSession.newId(), b = SightpaneSession.newId();
    expect(a, hasLength(32));
    expect(a, isNot(b));
    expect(a[12], '4');
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
  });
}
