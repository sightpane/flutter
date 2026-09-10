import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'breadcrumbs.dart';
import 'device.dart';
import 'lifecycle.dart';
import 'models.dart';
import 'options.dart';
import 'queue.dart';
import 'replay/recorder.dart';
import 'session.dart';
import 'stack.dart';
import 'storage.dart';
import 'transport.dart';

/// The SDK's static entry point.
///
/// ```dart
/// await Sightpane.init(SightpaneOptions(endpoint: 'http://localhost:8790', apiKey: 'dev'),
///   appRunner: () => runApp(const MyApp()));
/// ```
class Sightpane {
  static SightpaneClient? _client;

  static bool get isInitialized => _client != null;

  /// Whether the current session was chosen by [SightpaneOptions.sessionSampleRate].
  static bool get sampled => _client?.sampled ?? true;

  /// Throws if the SDK has not been initialised.
  static SightpaneClient get client {
    final c = _client;
    if (c == null) throw StateError('Sightpane.init was not called');
    return c;
  }

  /// Null if the SDK has not been initialised.
  static SightpaneClient? get maybeClient => _client;

  /// Sets the SDK up; when [appRunner] is given the app runs inside a zone that
  /// collects uncaught errors.
  static Future<void> init(
    SightpaneOptions options, {
    FutureOr<void> Function()? appRunner,
  }) async {
    await _client?.close();
    final appStartWatch = Stopwatch()..start();
    final appStartTs = DateTime.now().toUtc();
    void recordAppStart() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appStartWatch.stop();
        _client?.recordSpan(
          op: 'app.start',
          name: 'app_start',
          durationMs: appStartWatch.elapsedMicroseconds / 1000.0,
          status: 'ok',
          tags: const {'cold_start': true},
          ts: appStartTs,
        );
      });
    }

    if (appRunner == null) {
      WidgetsFlutterBinding.ensureInitialized();
      final c = SightpaneClient(options);
      _client = c;
      await c.queue.restoreFromStorage();
      recordAppStart();
      return;
    }
    // The binding, the client and runApp all share one zone: that keeps the
    // "zone mismatch" warning away and lets uncaught async errors land here.
    await runZonedGuarded<Future<void>>(() async {
      WidgetsFlutterBinding.ensureInitialized();
      final c = SightpaneClient(options);
      _client = c;
      c.bindFlutterErrors();
      await c.queue.restoreFromStorage();
      recordAppStart();
      await appRunner();
    }, (e, st) => _client?.captureException(e, stackTrace: st, handled: false));
  }

  static void captureException(
    Object exception, {
    StackTrace? stackTrace,
    bool fatal = false,
    Map<String, Object?> context = const {},
  }) => _client?.captureException(
    exception,
    stackTrace: stackTrace,
    fatal: fatal,
    context: context,
  );

  static void captureMessage(
    String message, {
    SightpaneLevel level = SightpaneLevel.info,
    Map<String, Object?> context = const {},
  }) => _client?.captureMessage(message, level: level, context: context);

  static void addBreadcrumb(SightpaneBreadcrumb breadcrumb) =>
      _client?.addBreadcrumb(breadcrumb);

  /// Shorthand for a breadcrumb in the `log` category.
  static void log(
    String message, {
    SightpaneLevel level = SightpaneLevel.info,
    Map<String, Object?> data = const {},
  }) => addBreadcrumb(
    SightpaneBreadcrumb(
      category: 'log',
      message: message,
      level: level,
      data: data,
    ),
  );

  /// A product event (PostHog's `capture`).
  static void capture(String event, [Map<String, Object?> props = const {}]) =>
      _client?.capture(event, props);

  static void identify(SightpaneUser user) => _client?.identify(user);

  /// A property that sticks to the session (e.g. location, role).
  static void setProperty(String key, Object? value) =>
      _client?.setProperty(key, value);

  static Future<void> flush() => _client?.flush() ?? Future.value();

  /// Starts a performance transaction.
  static SightpaneTransaction startTransaction(
    String name, {
    String op = 'custom',
    Map<String, Object?> tags = const {},
  }) => client.startTransaction(name, op: op, tags: tags);

  static Future<void> close() async {
    await _client?.close();
    _client = null;
  }
}

/// All the state of one session: breadcrumbs, queue, replay.
class SightpaneClient {
  SightpaneClient(this.options, {math.Random? random})
    : session = SightpaneSession(),
      breadcrumbs = BreadcrumbBuffer(options.maxBreadcrumbs),
      _random = random ?? math.Random(),
      sampled = _isSampled(options.sessionSampleRate, random ?? math.Random()),
      transport =
          options.transport ??
          HttpTransport(endpoint: options.endpoint, apiKey: options.apiKey) {
    queue = SightpaneQueue(
      transport: transport,
      envelopeBuilder: _envelope,
      flushInterval: options.flushInterval,
      maxBatch: options.maxBatch,
      maxQueue: options.maxQueue,
      storage: options.storage,
      log: options.debug ? debugPrint : null,
    );
    final replayOptions = sampled
        ? options.replay
        : const SightpaneReplayOptions(
            enabled: false,
            mode: SightpaneReplayMode.off,
          );
    replay = ReplayRecorder(
      options: replayOptions,
      onFrame: _enqueue,
      log: options.debug ? debugPrint : null,
    );
    _device = SightpaneDevice.collect(
      release: options.release,
      environment: options.environment,
      appName: options.appName,
    );
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    bindPageHide(() {
      unawaited(flush());
    });
    if (options.heartbeatInterval > Duration.zero) {
      _heartbeat = Timer.periodic(
        options.heartbeatInterval,
        (_) => sendHeartbeat(),
      );
    }
    if (options.debug) {
      debugPrint(
        'sightpane: initialised endpoint=${options.endpoint} key=${options.apiKey.length > 6 ? '${options.apiKey.substring(0, 6)}…' : options.apiKey} session=${session.id} replay=${replayOptions.enabled} sampled=$sampled',
      );
    }
  }

  static bool _isSampled(double rate, math.Random random) {
    if (rate >= 1.0) return true;
    if (rate <= 0.0) return false;
    return random.nextDouble() < rate;
  }

  final SightpaneOptions options;
  final SightpaneSession session;
  final BreadcrumbBuffer breadcrumbs;
  final SightpaneTransport transport;
  final math.Random _random;

  /// Whether this session was sampled for recordings and breadcrumbs.
  final bool sampled;

  late final SightpaneQueue queue;
  late final ReplayRecorder replay;
  late Map<String, Object?> _device;
  AppLifecycleListener? _lifecycle;
  Timer? _heartbeat;
  bool _foreground = true;
  FlutterExceptionHandler? _prevFlutterOnError;
  ui.ErrorCallback? _prevPlatformOnError;
  bool _errorsBound = false;

  /// The current route, as reported by the navigation observer.
  String? currentRoute;

  Map<String, Object?> get device => _device;

  SightpaneEnvelope _envelope(List<SightpaneItem> items) => SightpaneEnvelope(
    sessionId: session.id,
    startedAt: session.startedAt,
    user: session.user,
    device: _device,
    props: session.props,
    items: items,
  );

  void _enqueue(SightpaneItem item) {
    final bs = options.beforeSend;
    final out = bs == null ? item : bs(item);
    if (out != null) queue.add(out);
  }

  /// Binds the Flutter and platform error hooks; hooks already installed are
  /// kept and still called.
  void bindFlutterErrors() {
    if (!options.captureFlutterErrors || _errorsBound) return;
    _errorsBound = true;
    _prevFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      captureException(
        details.exception,
        stackTrace: details.stack,
        handled: false,
        context: {
          'library': details.library ?? '',
          'context': details.context?.toDescription() ?? '',
        },
      );
      _prevFlutterOnError?.call(details);
    };
    _prevPlatformOnError = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (e, st) {
      captureException(e, stackTrace: st, handled: false);
      return _prevPlatformOnError?.call(e, st) ?? true;
    };
  }

  SightpaneBreadcrumb _scrubBreadcrumb(SightpaneBreadcrumb b) {
    return SightpaneBreadcrumb(
      category: b.category,
      message: options.scrubText(b.message),
      level: b.level,
      data: _scrubMap(b.data),
      ts: b.ts,
    );
  }

  Map<String, Object?> _scrubMap(Map<String, Object?> input) {
    if (input.isEmpty) return input;
    final out = <String, Object?>{};
    for (final entry in input.entries) {
      final v = entry.value;
      if (v is String) {
        out[entry.key] = options.scrubText(v);
      } else if (v is Map<String, Object?>) {
        out[entry.key] = _scrubMap(v);
      } else {
        out[entry.key] = v;
      }
    }
    return out;
  }

  void addBreadcrumb(SightpaneBreadcrumb b) {
    if (!sampled) return;
    final scrubbed = _scrubBreadcrumb(b);
    breadcrumbs.add(scrubbed);
    _enqueue(SightpaneItem.breadcrumb(scrubbed));
  }

  void capture(String event, [Map<String, Object?> props = const {}]) =>
      _enqueue(SightpaneItem.event(event, props: _scrubMap(props)));

  void identify(SightpaneUser user) {
    session.user = user;
    addBreadcrumb(
      SightpaneBreadcrumb(category: 'user', message: 'identify ${user.id}'),
    );
  }

  void setProperty(String key, Object? value) =>
      session.props[key] = value is String ? options.scrubText(value) : value;

  void captureException(
    Object exception, {
    StackTrace? stackTrace,
    bool fatal = false,
    bool handled = true,
    Map<String, Object?> context = const {},
  }) {
    if (!_isSampled(options.errorSampleRate, _random)) return;
    if (sampled) {
      // In onError mode, flush the pre-error buffered frames into the queue.
      replay.flushOnError();
      // Grab the screen as it looked when the error hit; the frame's sequence
      // number is attached to the error.
      unawaited(replay.captureNow());
    }
    final stackText = (stackTrace ?? StackTrace.current).toString();
    _enqueue(
      SightpaneItem.error(
        message: options.scrubText(exception.toString()),
        exceptionType: exception.runtimeType.toString(),
        stack: stackText,
        frames: kIsWeb ? parseWebFrames(stackText) : const [],
        fatal: fatal,
        handled: handled,
        context: _scrubMap(context),
        breadcrumbs: breadcrumbs.snapshot(),
        frameSeq: replay.lastSeq,
        route: currentRoute,
      ),
    );
  }

  void captureMessage(
    String message, {
    SightpaneLevel level = SightpaneLevel.info,
    Map<String, Object?> context = const {},
  }) => _enqueue(
    SightpaneItem.error(
      message: options.scrubText(message),
      exceptionType: 'Message',
      context: {..._scrubMap(context), 'level': level.name},
      breadcrumbs: breadcrumbs.snapshot(),
      frameSeq: replay.lastSeq,
      route: currentRoute,
    ),
  );

  @visibleForTesting
  void debugSetForeground(bool v) => _foreground = v;

  /// A heartbeat; queued only while the app is in the foreground.
  void sendHeartbeat() {
    if (!_foreground) return;
    _enqueue(SightpaneItem.heartbeat(route: currentRoute));
  }

  void _onLifecycle(AppLifecycleState state) {
    _foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (state == AppLifecycleState.resumed) sendHeartbeat();
    addBreadcrumb(
      SightpaneBreadcrumb(category: 'app.lifecycle', message: state.name),
    );
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(flush());
    }
    if (state == AppLifecycleState.detached) {
      _enqueue(SightpaneItem.sessionEnd());
      unawaited(flush());
    }
  }

  /// Starts a performance transaction.
  SightpaneTransaction startTransaction(
    String name, {
    String op = 'custom',
    Map<String, Object?> tags = const {},
  }) => SightpaneTransaction(client: this, name: name, op: op, tags: tags);

  /// Records a completed span.
  void recordSpan({
    required String op,
    required String name,
    required double durationMs,
    String status = 'ok',
    String? parentSpanId,
    String? spanId,
    String? traceId,
    Map<String, Object?> tags = const {},
    DateTime? ts,
  }) {
    if (!_isSampled(options.tracesSampleRate, _random)) return;
    _enqueue(
      SightpaneItem.span(
        op: op,
        name: name,
        durationMs: durationMs,
        status: status,
        parentSpanId: parentSpanId,
        spanId: spanId,
        traceId: traceId,
        tags: tags,
        ts: ts,
      ),
    );
  }

  Future<void> flush() => queue.flush();

  Future<void> close() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    replay.stop();
    if (_errorsBound) {
      _errorsBound = false;
      FlutterError.onError = _prevFlutterOnError;
      ui.PlatformDispatcher.instance.onError = _prevPlatformOnError;
    }
    _enqueue(SightpaneItem.sessionEnd());
    await queue.close();
    await transport.close();
  }
}

String _randomHex(int chars) {
  final rnd = DateTime.now().microsecondsSinceEpoch;
  return rnd.toRadixString(16).padLeft(chars, '0').substring(0, chars);
}

/// A span representing a timed sub-operation within a transaction.
class SightpaneSpan {
  SightpaneSpan({
    required this.op,
    required this.name,
    required this.traceId,
    required this.parentSpanId,
    String? spanId,
    DateTime? startTs,
    this.tags = const {},
  })  : spanId = spanId ?? _randomHex(8),
        startTs = startTs ?? DateTime.now().toUtc(),
        _stopwatch = Stopwatch()..start();

  final String op;
  final String name;
  final String traceId;
  final String parentSpanId;
  final String spanId;
  final DateTime startTs;
  final Map<String, Object?> tags;
  final Stopwatch _stopwatch;
  double? durationMs;
  String status = 'ok';
  bool _finished = false;

  bool get isFinished => _finished;

  void finish({String? status}) {
    if (_finished) return;
    _finished = true;
    _stopwatch.stop();
    durationMs = _stopwatch.elapsedMicroseconds / 1000.0;
    if (status != null) this.status = status;
  }

  Map<String, Object?> toJson() => {
    'op': op,
    'name': name,
    'ts': startTs.toIso8601String(),
    'duration_ms': durationMs ?? (_stopwatch.elapsedMicroseconds / 1000.0),
    'status': status,
    'span_id': spanId,
    'parent_span_id': parentSpanId,
    if (tags.isNotEmpty) 'tags': tags,
  };
}

/// A performance transaction containing a root span and optional child spans.
class SightpaneTransaction {
  SightpaneTransaction({
    required this.client,
    required this.name,
    this.op = 'custom',
    String? traceId,
    String? spanId,
    DateTime? startTs,
    this.tags = const {},
  })  : traceId = traceId ?? _randomHex(16),
        spanId = spanId ?? _randomHex(8),
        startTs = startTs ?? DateTime.now().toUtc(),
        _stopwatch = Stopwatch()..start();

  final SightpaneClient client;
  final String name;
  final String op;
  final String traceId;
  final String spanId;
  final DateTime startTs;
  final Map<String, Object?> tags;
  final Stopwatch _stopwatch;
  final List<SightpaneSpan> _children = [];
  double? durationMs;
  String status = 'ok';
  bool _finished = false;

  bool get isFinished => _finished;

  SightpaneSpan startChild(String op, String name, {Map<String, Object?> tags = const {}}) {
    final span = SightpaneSpan(
      op: op,
      name: name,
      traceId: traceId,
      parentSpanId: spanId,
      tags: tags,
    );
    _children.add(span);
    return span;
  }

  void finish({String? status}) {
    if (_finished) return;
    _finished = true;
    _stopwatch.stop();
    durationMs = _stopwatch.elapsedMicroseconds / 1000.0;
    if (status != null) this.status = status;
    for (final c in _children) {
      if (!c.isFinished) c.finish();
    }
    client._enqueue(
      SightpaneItem.transaction(
        op: op,
        name: name,
        durationMs: durationMs!,
        status: this.status,
        spanId: spanId,
        traceId: traceId,
        tags: tags,
        spans: [for (final c in _children) c.toJson()],
        ts: startTs,
      ),
    );
  }
}

