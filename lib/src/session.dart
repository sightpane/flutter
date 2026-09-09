import 'dart:math';

import 'models.dart';

/// One session, from app launch to app shutdown.
class SightpaneSession {
  SightpaneSession({String? id, DateTime? startedAt})
    : id = id ?? newId(),
      startedAt = startedAt ?? DateTime.now().toUtc();
  final String id;
  final DateTime startedAt;
  SightpaneUser? user;
  final Map<String, Object?> props = {};

  /// A random 32-character hex id, laid out like a UUID v4.
  static String newId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }
}
