import 'models.dart';
import 'transport.dart';

/// Session replay settings.
class SightpaneReplayOptions {
  const SightpaneReplayOptions({
    this.enabled = true,
    this.interval = const Duration(seconds: 1),
    this.scale = 0.5,
    this.maxPendingFrames = 60,
    this.skipUnchanged = true,
    this.recordPointer = true,
    this.pointerSampleInterval = const Duration(milliseconds: 50),
  });

  /// When disabled, [SightpaneReplay] just renders its child.
  final bool enabled;

  /// Time between two frames.
  final Duration interval;

  /// Frame pixels per logical pixel (0.5 → half resolution).
  final double scale;

  /// Most frames allowed to wait for delivery; past that the oldest drop.
  final int maxPendingFrames;

  /// Frames byte-for-byte identical to the previous one are not sent.
  final bool skipUnchanged;

  /// Also record pointer moves, down/up and scrolling.
  final bool recordPointer;

  /// Sampling interval for moves; down/up are always recorded.
  final Duration pointerSampleInterval;
}

/// [Sightpane.init] settings.
class SightpaneOptions {
  const SightpaneOptions({
    required this.endpoint,
    required this.apiKey,
    this.environment = 'production',
    this.release = '',
    this.appName = '',
    this.flushInterval = const Duration(seconds: 5),
    this.maxBatch = 50,
    this.maxQueue = 2000,
    this.maxBreadcrumbs = 100,
    this.replay = const SightpaneReplayOptions(),
    this.debug = false,
    this.transport,
    this.beforeSend,
    this.captureFlutterErrors = true,
    this.heartbeatInterval = const Duration(seconds: 20),
  });

  /// Backend root address, e.g. `http://localhost:8790`.
  final String endpoint;

  /// The project's API key (`X-Sightpane-Key`).
  final String apiKey;
  final String environment;
  final String release;
  final String appName;

  /// How often the queue sends what it has collected.
  final Duration flushInterval;

  /// Most items packed into a single envelope.
  final int maxBatch;

  /// Most items held in memory; past that the oldest non-error items drop.
  final int maxQueue;
  final int maxBreadcrumbs;
  final SightpaneReplayOptions replay;

  /// Writes SDK logs to the console.
  final bool debug;

  /// For tests and custom transports; [HttpTransport] is used when null.
  final SightpaneTransport? transport;

  /// Called for every item before it is sent; returning null drops the item.
  final SightpaneItem? Function(SightpaneItem item)? beforeSend;

  /// Binds `FlutterError.onError` and `PlatformDispatcher.onError`.
  final bool captureFlutterErrors;

  /// Heartbeat interval behind the live "who is on which page" view;
  /// [Duration.zero] turns it off. Nothing is sent while the app is in the
  /// background.
  final Duration heartbeatInterval;
}
