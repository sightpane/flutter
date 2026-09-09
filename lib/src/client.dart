import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'breadcrumbs.dart';
import 'device.dart';
import 'models.dart';
import 'options.dart';
import 'queue.dart';
import 'replay/recorder.dart';
import 'session.dart';
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
    if (appRunner == null) {
      WidgetsFlutterBinding.ensureInitialized();
      _client = SightpaneClient(options);
      return;
    }
    // The binding, the client and runApp all share one zone: that keeps the
    // "zone mismatch" warning away and lets uncaught async errors land here.
    await runZonedGuarded<Future<void>>(() async {
      WidgetsFlutterBinding.ensureInitialized();
      final c = SightpaneClient(options);
      _client = c;
      c.bindFlutterErrors();
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

  static Future<void> close() async {
    await _client?.close();
    _client = null;
  }
}

/// All the state of one session: breadcrumbs, queue, replay.
class SightpaneClient {
  SightpaneClient(this.options)
    : session = SightpaneSession(),
      breadcrumbs = BreadcrumbBuffer(options.maxBreadcrumbs),
      transport =
          options.transport ??
          HttpTransport(endpoint: options.endpoint, apiKey: options.apiKey) {
    queue = SightpaneQueue(
      transport: transport,
      envelopeBuilder: _envelope,
      flushInterval: options.flushInterval,
      maxBatch: options.maxBatch,
      maxQueue: options.maxQueue,
      log: options.debug ? debugPrint : null,
    );
    replay = ReplayRecorder(
      options: options.replay,
      onFrame: _enqueue,
      log: options.debug ? debugPrint : null,
    );
    _device = SightpaneDevice.collect(
      release: options.release,
      environment: options.environment,
      appName: options.appName,
    );
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    if (options.heartbeatInterval > Duration.zero) {
      _heartbeat = Timer.periodic(
        options.heartbeatInterval,
        (_) => sendHeartbeat(),
      );
    }
    if (options.debug) {
      debugPrint(
        'sightpane: initialised endpoint=${options.endpoint} key=${options.apiKey.length > 6 ? '${options.apiKey.substring(0, 6)}…' : options.apiKey} session=${session.id} replay=${options.replay.enabled}',
      );
    }
  }

  final SightpaneOptions options;
  final SightpaneSession session;
  final BreadcrumbBuffer breadcrumbs;
  final SightpaneTransport transport;
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

  void addBreadcrumb(SightpaneBreadcrumb b) {
    breadcrumbs.add(b);
    _enqueue(SightpaneItem.breadcrumb(b));
  }

  void capture(String event, [Map<String, Object?> props = const {}]) =>
      _enqueue(SightpaneItem.event(event, props: props));

  void identify(SightpaneUser user) {
    session.user = user;
    addBreadcrumb(
      SightpaneBreadcrumb(category: 'user', message: 'identify ${user.id}'),
    );
  }

  void setProperty(String key, Object? value) => session.props[key] = value;

  void captureException(
    Object exception, {
    StackTrace? stackTrace,
    bool fatal = false,
    bool handled = true,
    Map<String, Object?> context = const {},
  }) {
    // Grab the screen as it looked when the error hit; the frame's sequence
    // number is attached to the error.
    unawaited(replay.captureNow());
    _enqueue(
      SightpaneItem.error(
        message: exception.toString(),
        exceptionType: exception.runtimeType.toString(),
        stack: (stackTrace ?? StackTrace.current).toString(),
        fatal: fatal,
        handled: handled,
        context: context,
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
      message: message,
      exceptionType: 'Message',
      context: {...context, 'level': level.name},
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
