import 'models.dart';
import 'storage.dart';
import 'transport.dart';

/// Replay capture modes.
enum SightpaneReplayMode {
  /// Continuously captures and emits frames to the queue as they change.
  always,

  /// Buffers frames in memory; when an error occurs, flushes the buffered
  /// frames (up to [SightpaneReplayOptions.bufferSeconds]) and records live for
  /// [SightpaneReplayOptions.postErrorSeconds], then returns to buffering.
  onError,

  /// Completely disables recording.
  off,
}

/// Session replay settings.
class SightpaneReplayOptions {
  const SightpaneReplayOptions({
    this.enabled = true,
    this.mode = SightpaneReplayMode.always,
    this.bufferSeconds = 30,
    this.postErrorSeconds = 15,
    this.interval = const Duration(seconds: 1),
    this.scale = 0.5,
    this.maxPendingFrames = 60,
    this.skipUnchanged = true,
    this.recordPointer = true,
    this.pointerSampleInterval = const Duration(milliseconds: 50),
    this.maskAllText = false,
  });

  /// When disabled, [SightpaneReplay] just renders its child.
  final bool enabled;

  /// Recording mode: always, onError, or off.
  final SightpaneReplayMode mode;

  /// In [SightpaneReplayMode.onError] mode, how many seconds of prior frames to keep in memory.
  final int bufferSeconds;

  /// In [SightpaneReplayMode.onError] mode, how many seconds of live recording to send after an error.
  final int postErrorSeconds;

  /// When enabled, all RenderParagraph and RenderEditable text rectangles are masked out,
  /// with [SightpaneUnmask] as the exception.
  final bool maskAllText;

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
    this.storage,
    this.sessionSampleRate = 1.0,
    this.errorSampleRate = 1.0,
    this.tracesSampleRate = 1.0,
    this.profilesSampleRate = 0.0,
    this.scrub,
  });

  /// PII scrubbing rules applied to breadcrumbs, error messages, and props.
  /// If null, [defaultScrubRules] are used.
  final List<ScrubRule>? scrub;

  /// Effective PII scrubbing rules.
  List<ScrubRule> get effectiveScrubRules => scrub ?? defaultScrubRules;

  /// Applies all [effectiveScrubRules] to [input].
  String scrubText(String input) {
    var out = input;
    for (final rule in effectiveScrubRules) {
      out = rule.apply(out);
    }
    return out;
  }

  /// Sampling rate for sessions (0.0 to 1.0). When not sampled, recording and
  /// breadcrumbs are disabled for the session, but errors are still captured.
  final double sessionSampleRate;

  /// Sampling rate for captured errors (0.0 to 1.0).
  final double errorSampleRate;

  /// Sampling rate for performance transactions/spans (0.0 to 1.0).
  final double tracesSampleRate;

  /// Sampling rate for continuous CPU profiling during transactions (0.0 to 1.0).
  final double profilesSampleRate;


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

  /// Storage for the persistent offline queue. When provided (or [SightpaneStorage.createDefault()]),
  /// pending non-frame items are saved across app restarts and restored on [Sightpane.init].
  final SightpaneStorage? storage;
}

/// A PII scrubbing rule that matches a pattern and replaces it.
class ScrubRule {
  const ScrubRule(this.pattern, [this.replacement = '[REDACTED]']);
  final Pattern pattern;
  final String replacement;

  String apply(String input) => input.replaceAll(pattern, replacement);
}

final defaultScrubRules = <ScrubRule>[
  ScrubRule(
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
    '[EMAIL]',
  ),
  ScrubRule(
    RegExp(r'\b(?:\d[ -]*?){13,16}\b'),
    '[CARD]',
  ),
  ScrubRule(
    RegExp(r'\b[1-9]\d{10}\b'),
    '[TCKN]',
  ),
  ScrubRule(
    RegExp(r'(\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}'),
    '[PHONE]',
  ),
];
