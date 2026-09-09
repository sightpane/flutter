import 'dart:convert';

/// An identified user.
class SightpaneUser {
  const SightpaneUser({
    required this.id,
    this.email = '',
    this.name = '',
    this.props = const {},
  });
  final String id;
  final String email;
  final String name;
  final Map<String, Object?> props;

  Map<String, Object?> toJson() => {
    'id': id,
    if (email.isNotEmpty) 'email': email,
    if (name.isNotEmpty) 'name': name,
    if (props.isNotEmpty) 'props': props,
  };
}

enum SightpaneLevel { debug, info, warning, error }

/// A step on the way to an error: navigation, a tap, an HTTP call, a log...
class SightpaneBreadcrumb {
  SightpaneBreadcrumb({
    required this.category,
    required this.message,
    this.data = const {},
    this.level = SightpaneLevel.info,
    DateTime? ts,
  }) : ts = ts ?? DateTime.now().toUtc();
  final DateTime ts;

  /// `navigation`, `ui.click`, `http`, `log`, `custom`...
  final String category;
  final String message;
  final Map<String, Object?> data;
  final SightpaneLevel level;

  Map<String, Object?> toJson() => {
    'ts': ts.toIso8601String(),
    'category': category,
    'message': message,
    'level': level.name,
    if (data.isNotEmpty) 'data': data,
  };
}

/// A tap on a recorded frame.
class SightpaneTap {
  const SightpaneTap({required this.x, required this.y, required this.ts});

  /// Coordinate normalized to 0–1 inside the frame.
  final double x, y;
  final DateTime ts;
  Map<String, Object?> toJson() => {'x': x, 'y': y, 'ts': ts.toIso8601String()};
}

/// A pointer sample: `move` (hover or drag), `down`, `up`, `scroll`.
class SightpanePointerSample {
  const SightpanePointerSample({
    required this.kind,
    required this.x,
    required this.y,
    required this.ts,
  });
  final String kind;

  /// Coordinate normalized to 0–1 against the replay boundary.
  final double x, y;
  final DateTime ts;
}

/// One item inside an envelope. [type] is one of: breadcrumb, event, error,
/// frame, pointer, session_end.
class SightpaneItem {
  SightpaneItem._(this.type, this.ts, this.body);

  factory SightpaneItem.breadcrumb(SightpaneBreadcrumb b) =>
      SightpaneItem._('breadcrumb', b.ts, b.toJson()..remove('ts'));

  factory SightpaneItem.event(
    String name, {
    Map<String, Object?> props = const {},
    DateTime? ts,
  }) => SightpaneItem._('event', ts ?? DateTime.now().toUtc(), {
    'name': name,
    if (props.isNotEmpty) 'props': props,
  });

  factory SightpaneItem.error({
    required String message,
    required String exceptionType,
    String stack = '',
    bool fatal = false,
    bool handled = true,
    Map<String, Object?> context = const {},
    List<SightpaneBreadcrumb> breadcrumbs = const [],
    int? frameSeq,
    String? route,
    DateTime? ts,
    List<Map<String, Object?>> frames = const [],
  }) => SightpaneItem._('error', ts ?? DateTime.now().toUtc(), {
    'message': message,
    'exception': exceptionType,
    'stack': stack,
    'fatal': fatal,
    'handled': handled,
    'route': ?route,
    'frame_seq': ?frameSeq,
    // The positions of a minified web stack, for the backend to resolve against
    // an uploaded source map. Absent everywhere else: a native stack is already
    // readable and `stack` is all the server needs.
    if (frames.isNotEmpty) 'frames': frames,
    if (context.isNotEmpty) 'context': context,
    if (breadcrumbs.isNotEmpty)
      'breadcrumbs': [for (final b in breadcrumbs) b.toJson()],
  });

  factory SightpaneItem.frame({
    required int seq,
    required int width,
    required int height,
    required List<int> png,
    List<SightpaneTap> taps = const [],
    DateTime? ts,
  }) => SightpaneItem._('frame', ts ?? DateTime.now().toUtc(), {
    'seq': seq,
    'width': width,
    'height': height,
    'png': base64Encode(png),
    if (taps.isNotEmpty) 'taps': [for (final t in taps) t.toJson()],
  });

  /// A packet of pointer samples; [ts] is the time of the first sample and each
  /// sample carries its offset from it in milliseconds.
  factory SightpaneItem.pointer(List<SightpanePointerSample> samples) {
    final t0 = samples.first.ts;
    double r(double v) => (v * 10000).round() / 10000;
    return SightpaneItem._('pointer', t0, {
      'events': [
        for (final s in samples)
          {
            't': s.ts.difference(t0).inMilliseconds,
            'x': r(s.x),
            'y': r(s.y),
            'k': s.kind,
          },
      ],
    });
  }

  /// A heartbeat: the session is still open and this is its current route. The
  /// backend only refreshes the session.
  factory SightpaneItem.heartbeat({String? route, DateTime? ts}) =>
      SightpaneItem._('heartbeat', ts ?? DateTime.now().toUtc(), {
        'route': ?route,
      });

  factory SightpaneItem.sessionEnd({DateTime? ts}) =>
      SightpaneItem._('session_end', ts ?? DateTime.now().toUtc(), const {});

  final String type;
  final DateTime ts;
  final Map<String, Object?> body;

  bool get isError => type == 'error';
  bool get isFrame => type == 'frame';

  /// Rough byte estimate, used for the queue's batch budget.
  int get approxBytes => isFrame
      ? (body['png'] as String).length + 200
      : (type == 'pointer' ? 40 * (body['events'] as List).length + 100 : 400);

  Map<String, Object?> toJson() => {
    'type': type,
    'ts': ts.toIso8601String(),
    ...body,
  };
}

/// A single request to the backend.
class SightpaneEnvelope {
  const SightpaneEnvelope({
    required this.sessionId,
    required this.startedAt,
    required this.items,
    this.user,
    this.device = const {},
    this.props = const {},
    this.sdkVersion = sdkVersionString,
  });
  static const sdkVersionString = '0.1.0';
  final String sessionId;
  final DateTime startedAt;
  final SightpaneUser? user;
  final Map<String, Object?> device;
  final Map<String, Object?> props;
  final List<SightpaneItem> items;
  final String sdkVersion;

  Map<String, Object?> toJson() => {
    'sdk': {'name': 'sightpane', 'version': sdkVersion},
    'session': {
      'id': sessionId,
      'started_at': startedAt.toIso8601String(),
      if (user != null) 'user': user!.toJson(),
      'device': device,
      if (props.isNotEmpty) 'props': props,
    },
    'items': [for (final i in items) i.toJson()],
  };
}
