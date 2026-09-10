import 'dart:async';

import 'package:sightpane/sightpane.dart';

class FakeTransport implements SightpaneTransport {
  FakeTransport({this.ok = true, this.retryAfter});
  bool ok;
  @override
  Duration? retryAfter;
  final envelopes = <SightpaneEnvelope>[];
  int closed = 0;
  Completer<void>? gate;

  List<SightpaneItem> get items => [for (final e in envelopes) ...e.items];
  List<SightpaneItem> ofType(String t) =>
      items.where((i) => i.type == t).toList();

  @override
  Future<bool> send(SightpaneEnvelope envelope) async {
    if (gate != null) await gate!.future;
    if (!ok) return false;
    envelopes.add(envelope);
    return true;
  }

  @override
  Future<void> close() async => closed++;
}
