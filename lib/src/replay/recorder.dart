import 'dart:async';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../models.dart';
import '../options.dart';
import 'mask.dart';

class _BufferedReplayItem {
  _BufferedReplayItem(this.ts, this.item);
  final DateTime ts;
  final SightpaneItem item;
}

/// Captures frames from the [SightpaneReplay] boundary at a fixed interval, blacks
/// out the masks, encodes the result as PNG and hands it to [onFrame] for the
/// queue.
class ReplayRecorder {
  ReplayRecorder({required this.options, required this.onFrame, this.log});
  final SightpaneReplayOptions options;
  final void Function(SightpaneItem) onFrame;
  final void Function(String)? log;

  GlobalKey? _boundaryKey;
  Timer? _timer;
  int _seq = 0;
  int? _lastHash;
  bool _busy = false;
  final List<SightpaneTap> _taps = [];
  final List<SightpanePointerSample> _pointer = [];
  DateTime? _lastMoveTs;
  Offset? _lastMove;
  Size? _lastLogicalSize;
  final List<_BufferedReplayItem> _ringBuffer = [];
  DateTime? _liveUntil;

  /// Number of pointer samples waiting to be sent (for tests).
  int get pendingPointerSamples => _pointer.length;

  /// Number of items currently buffered in onError mode (for tests).
  int get bufferedItemsCount => _ringBuffer.length;

  /// Emits an item directly into the recorder pipeline (for tests).
  @visibleForTesting
  void emitForTesting(SightpaneItem item) => _emit(item);

  int? get lastSeq => _seq == 0 ? null : _seq;
  bool get isRunning => _timer != null;

  bool get _isLive {
    if (!options.enabled || options.mode == SightpaneReplayMode.off) return false;
    if (options.mode == SightpaneReplayMode.always) return true;
    final until = _liveUntil;
    if (until == null) return false;
    return clock.now().isBefore(until);
  }

  void _emit(SightpaneItem item) {
    if (_isLive) {
      onFrame(item);
    } else if (options.enabled && options.mode == SightpaneReplayMode.onError) {
      final now = clock.now();
      _ringBuffer.add(_BufferedReplayItem(now, item));
      _trimRingBuffer(now);
    }
  }

  void _trimRingBuffer(DateTime now) {
    final cutoff = now.subtract(Duration(seconds: options.bufferSeconds));
    while (_ringBuffer.isNotEmpty && _ringBuffer.first.ts.isBefore(cutoff)) {
      _ringBuffer.removeAt(0);
    }
  }

  /// Flushes any ring-buffered frames and switches to live mode for [options.postErrorSeconds].
  void flushOnError() {
    if (options.mode == SightpaneReplayMode.onError && options.enabled) {
      flushPointer();
      final now = clock.now();
      _trimRingBuffer(now);
      for (final entry in _ringBuffer) {
        onFrame(entry.item);
      }
      _ringBuffer.clear();
      _liveUntil = now.add(Duration(seconds: options.postErrorSeconds));
    }
  }

  /// The boundary has been attached; periodic capture starts.
  void attach(GlobalKey boundaryKey) {
    _boundaryKey = boundaryKey;
    if (!options.enabled || options.mode == SightpaneReplayMode.off) return;
    _timer?.cancel();
    _timer = Timer.periodic(options.interval, (_) => captureNow());
  }

  void detach(GlobalKey boundaryKey) {
    if (_boundaryKey == boundaryKey) stop();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _boundaryKey = null;
    _ringBuffer.clear();
    _liveUntil = null;
  }

  /// A tap in global logical coordinates; it rides along on the next frame.
  void recordTap(Offset global) {
    final key = _boundaryKey;
    final ro = key?.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final local = ro.globalToLocal(global);
    _taps.add(
      SightpaneTap(
        x: (local.dx / ro.size.width).clamp(0, 1),
        y: (local.dy / ro.size.height).clamp(0, 1),
        ts: DateTime.now().toUtc(),
      ),
    );
  }

  /// A pointer sample; moves are thinned out by both time and distance.
  void recordPointer(String kind, Offset global) {
    if (!options.enabled ||
        options.mode == SightpaneReplayMode.off ||
        !options.recordPointer) {
      return;
    }
    final key = _boundaryKey;
    final ro = key?.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final now = DateTime.now().toUtc();
    if (kind == 'move') {
      final lastTs = _lastMoveTs, last = _lastMove;
      // Until the sampling interval has elapsed a move is skipped, however far
      // the pointer has travelled.
      if (lastTs != null &&
          now.difference(lastTs) < options.pointerSampleInterval) {
        return;
      }
      // The interval elapsed, but a pointer that stayed put still adds no
      // sample.
      if (last != null && (global - last).distance < 3) {
        return;
      }
      _lastMoveTs = now;
      _lastMove = global;
    }
    final local = ro.globalToLocal(global);
    _pointer.add(
      SightpanePointerSample(
        kind: kind,
        x: (local.dx / ro.size.width).clamp(0, 1),
        y: (local.dy / ro.size.height).clamp(0, 1),
        ts: now,
      ),
    );
    if (_pointer.length >= 400) flushPointer();
  }

  /// Hands the pointer samples collected so far to the queue as one packet.
  void flushPointer() {
    if (_pointer.isEmpty) return;
    _emit(SightpaneItem.pointer(List.of(_pointer)));
    _pointer.clear();
  }

  /// Captures a frame right now; this is what an error calls. Returns quietly
  /// when there is no boundary.
  Future<void> captureNow() async {
    flushPointer();
    if (!options.enabled ||
        options.mode == SightpaneReplayMode.off ||
        _busy) {
      return;
    }
    final ro = _boundaryKey?.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.hasSize || ro.debugNeedsPaint) {
      return;
    }
    _busy = true;
    try {
      final image = await ro.toImage(pixelRatio: options.scale);
      final masks = MaskRegistry.rects(ancestor: ro);
      final png = await _encode(image, masks, options.scale);
      image.dispose();
      if (png == null) return;
      final hash = _fnv(png);
      final taps = List<SightpaneTap>.from(_taps);
      _taps.clear();
      final sizeChanged = _lastLogicalSize != ro.size;
      _lastLogicalSize = ro.size;
      if (options.skipUnchanged &&
          hash == _lastHash &&
          taps.isEmpty &&
          !sizeChanged) {
        return;
      }
      _lastHash = hash;
      _seq++;
      _emit(
        SightpaneItem.frame(
          seq: _seq,
          width: (ro.size.width * options.scale).round(),
          height: (ro.size.height * options.scale).round(),
          png: png,
          taps: taps,
        ),
      );
    } catch (e) {
      log?.call('sightpane: could not capture a frame: $e');
    } finally {
      _busy = false;
    }
  }

  static Future<List<int>?> _encode(
    ui.Image image,
    List<Rect> masks,
    double scale,
  ) async {
    ui.Image out = image;
    if (masks.isNotEmpty) {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImage(image, Offset.zero, Paint());
      final paint = Paint()..color = const Color(0xFF000000);
      for (final r in masks) {
        canvas.drawRect(
          Rect.fromLTWH(
            r.left * scale,
            r.top * scale,
            r.width * scale,
            r.height * scale,
          ),
          paint,
        );
      }
      out = await rec.endRecording().toImage(image.width, image.height);
    }
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    if (!identical(out, image)) out.dispose();
    return data?.buffer.asUint8List();
  }

  static int _fnv(List<int> bytes) {
    var h = 0x811c9dc5;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }
}
