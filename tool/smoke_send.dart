// Sends an SDK-shaped envelope to a live backend (no Flutter, plain Dart).
//   dart run tool/smoke_send.dart http://localhost:8790 <api-key>
import 'dart:io';

import 'package:sightpane/src/models.dart';
import 'package:sightpane/src/session.dart';
import 'package:sightpane/src/transport.dart';

Future<void> main(List<String> args) async {
  final t = HttpTransport(endpoint: args[0], apiKey: args[1]);
  final s = SightpaneSession();
  final ok = await t.send(
    SightpaneEnvelope(
      sessionId: s.id,
      startedAt: s.startedAt,
      user: const SightpaneUser(id: 'smoke', email: 'smoke@test'),
      device: const {'platform': 'linux', 'release': 'smoke'},
      items: [
        SightpaneItem.breadcrumb(
          SightpaneBreadcrumb(category: 'navigation', message: '/'),
        ),
        SightpaneItem.event('smoke'),
        SightpaneItem.sessionEnd(),
      ],
    ),
  );
  stdout.writeln('sent=$ok session=${s.id}');
  await t.close();
}
