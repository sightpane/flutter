import 'dart:async';

import 'package:clock/clock.dart';

import 'models.dart';
import 'storage.dart';
import 'transport.dart';

/// Collects items and ships them as envelopes, either on an interval or as soon
/// as a batch is full; on a failed send it keeps the items and retries with a
/// growing backoff.
class SightpaneQueue {
  SightpaneQueue({
    required this.transport,
    required this.envelopeBuilder,
    this.flushInterval = const Duration(seconds: 5),
    this.maxBatch = 50,
    this.maxQueue = 2000,
    this.maxBatchBytes = 1500000,
    this.storage,
    this.log,
  });

  final SightpaneTransport transport;
  final SightpaneEnvelope Function(List<SightpaneItem> items) envelopeBuilder;
  final Duration flushInterval;
  final int maxBatch;
  final int maxQueue;
  final int maxBatchBytes;
  final SightpaneStorage? storage;
  final void Function(String)? log;

  final List<SightpaneItem> _pending = [];
  Timer? _timer;
  bool _persistScheduled = false;
  Future<void>? _inFlight;
  Duration _backoff = Duration.zero;
  DateTime? _notBefore;
  int dropped = 0;
  int sent = 0;

  List<SightpaneItem>? _inFlightBatch;

  int get length => _pending.length;
  List<SightpaneItem> get pending => List.unmodifiable(_pending);

  bool _shouldPersist(SightpaneItem item) =>
      !item.isFrame && item.type != 'pointer';

  void _schedulePersist() {
    if (storage == null || _persistScheduled) return;
    _persistScheduled = true;
    scheduleMicrotask(() async {
      if (!_persistScheduled) return;
      _persistScheduled = false;
      await persistNow();
    });
  }

  /// Writes pending items immediately to persistent storage.
  Future<void> persistNow() async {
    _persistScheduled = false;
    final s = storage;
    if (s == null) return;
    try {
      final inFlight = _inFlightBatch ?? const <SightpaneItem>[];
      final toSave = [...inFlight, ..._pending].where(_shouldPersist).toList();
      await s.write(toSave);
    } catch (e) {
      log?.call('sightpane: could not write to offline storage: $e');
    }
  }

  /// Restores pending items saved from a previous run or crash.
  Future<void> restoreFromStorage() async {
    final s = storage;
    if (s == null) return;
    try {
      final items = await s.read();
      if (items.isNotEmpty) {
        log?.call(
          'sightpane: restored ${items.length} items from offline storage',
        );
        _pending.addAll(items);
        _enforceLimit();
        flush();
      }
    } catch (e) {
      log?.call('sightpane: could not read from offline storage: $e');
    }
  }

  void add(SightpaneItem item) {
    _pending.add(item);
    _enforceLimit();
    if (_shouldPersist(item)) {
      _schedulePersist();
    }
    _timer ??= Timer(flushInterval, () {
      _timer = null;
      flush();
    });
    if (_pending.length >= maxBatch || item.isError) {
      flush();
    }
  }

  /// Past the queue limit the oldest frames are dropped first, then the oldest
  /// non-error items; errors are always kept.
  void _enforceLimit() {
    while (_pending.length > maxQueue) {
      var i = _pending.indexWhere((e) => e.isFrame);
      if (i < 0) i = _pending.indexWhere((e) => !e.isError);
      if (i < 0) i = 0;
      _pending.removeAt(i);
      dropped++;
    }
  }

  /// Sends everything pending. Only one send runs at a time.
  Future<void> flush() {
    if (_inFlight != null) return _inFlight!;
    if (_pending.isEmpty) return Future.value();
    final nb = _notBefore;
    if (nb != null && clock.now().isBefore(nb)) {
      _timer ??= Timer(nb.difference(clock.now()), () {
        _timer = null;
        flush();
      });
      return Future.value();
    }
    final f = _drain();
    _inFlight = f;
    return f.whenComplete(() => _inFlight = null);
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final batch = _takeBatch();
      _inFlightBatch = batch;
      final ok = await transport.send(envelopeBuilder(batch));
      _inFlightBatch = null;
      if (ok) {
        sent += batch.length;
        _backoff = Duration.zero;
        _notBefore = null;
        log?.call('sightpane: sent ${batch.length} items (total $sent)');
        _schedulePersist();
        continue;
      }
      _pending.insertAll(0, batch);
      final retryAfter = transport.retryAfter;
      if (retryAfter != null && retryAfter > Duration.zero) {
        _backoff = retryAfter;
      } else {
        _backoff = _backoff == Duration.zero
            ? const Duration(seconds: 2)
            : Duration(seconds: (_backoff.inSeconds * 2).clamp(2, 60));
      }
      _notBefore = clock.now().add(_backoff);
      log?.call('sightpane: send failed, retrying in ${_backoff.inSeconds}s');
      _schedulePersist();
      _timer ??= Timer(_backoff, () {
        _timer = null;
        flush();
      });
      return;
    }
    _schedulePersist();
  }

  List<SightpaneItem> _takeBatch() {
    final batch = <SightpaneItem>[];
    var bytes = 0;
    while (_pending.isNotEmpty && batch.length < maxBatch) {
      final next = _pending.first;
      if (batch.isNotEmpty && bytes + next.approxBytes > maxBatchBytes) break;
      batch.add(_pending.removeAt(0));
      bytes += next.approxBytes;
    }
    return batch;
  }

  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    await flush();
    await persistNow();
  }
}
