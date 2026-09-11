import 'dart:async';
import 'dart:math' as math;

import '../models.dart';

/// A single frame / call location in a profile call tree.
class ProfileFrame {
  const ProfileFrame({
    required this.name,
    this.file = '',
    this.line = 0,
  });

  final String name;
  final String file;
  final int line;

  Map<String, Object?> toJson() => {
    'name': name,
    if (file.isNotEmpty) 'file': file,
    if (line > 0) 'line': line,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileFrame &&
          other.name == name &&
          other.file == file &&
          other.line == line;

  @override
  int get hashCode => Object.hash(name, file, line);
}

/// A timed sample with a stack of frame indices.
class ProfileSample {
  const ProfileSample({
    required this.elapsedMs,
    required this.stackId,
  });

  final double elapsedMs;
  final List<int> stackId;

  Map<String, Object?> toJson() => {
    'elapsed_ms': elapsedMs,
    'stack_id': stackId,
  };
}

/// Speedscope-compatible profile data representation.
class ProfileData {
  ProfileData({
    required this.frames,
    required this.samples,
  });

  final List<ProfileFrame> frames;
  final List<ProfileSample> samples;

  Map<String, Object?> toJson() => {
    'shared': {
      'frames': frames.map((f) => f.toJson()).toList(),
    },
    'samples': samples.map((s) => s.toJson()).toList(),
  };
}

/// Continuous profiling sampler for active transactions.
class SightpaneProfileSampler {
  SightpaneProfileSampler({
    required this.transactionName,
    this.traceId,
    this.threadName = 'main',
    this.sampleInterval = const Duration(milliseconds: 10),
  }) : _stopwatch = Stopwatch()..start();

  final String transactionName;
  final String? traceId;
  final String threadName;
  final Duration sampleInterval;

  final Stopwatch _stopwatch;
  Timer? _timer;

  final List<ProfileFrame> _frames = [];
  final Map<ProfileFrame, int> _frameIndices = {};
  final List<ProfileSample> _samples = [];

  bool _stopped = false;

  /// Whether the sampler is currently running.
  bool get isRunning => _timer != null && !_stopped;

  /// Number of samples collected so far.
  int get sampleCount => _samples.length;

  /// Starts periodic sampling.
  void start() {
    if (_stopped || _timer != null) return;
    _timer = Timer.periodic(sampleInterval, (_) {
      sampleCurrentStack();
    });
  }

  /// Samples the current stack trace.
  void sampleCurrentStack([StackTrace? stackTrace]) {
    if (_stopped) return;
    final st = stackTrace ?? StackTrace.current;
    final frames = _parseStackTrace(st);
    if (frames.isEmpty) return;

    final stackId = <int>[];
    // In Speedscope / Flame Graph root is at index 0, innermost at end.
    for (var i = frames.length - 1; i >= 0; i--) {
      final f = frames[i];
      var idx = _frameIndices[f];
      if (idx == null) {
        idx = _frames.length;
        _frameIndices[f] = idx;
        _frames.add(f);
      }
      stackId.add(idx);
    }

    final elapsed = _stopwatch.elapsedMicroseconds / 1000.0;
    _samples.add(ProfileSample(elapsedMs: elapsed, stackId: stackId));
  }

  /// Manually adds a call stack sample (e.g. from custom instrumented frames).
  void sampleManual(List<String> frameNames, [double? elapsedMs]) {
    if (_stopped || frameNames.isEmpty) return;
    final stackId = <int>[];
    for (final name in frameNames) {
      final frame = ProfileFrame(name: name);
      var idx = _frameIndices[frame];
      if (idx == null) {
        idx = _frames.length;
        _frameIndices[frame] = idx;
        _frames.add(frame);
      }
      stackId.add(idx);
    }
    final elapsed = elapsedMs ?? (_stopwatch.elapsedMicroseconds / 1000.0);
    _samples.add(ProfileSample(elapsedMs: elapsed, stackId: stackId));
  }

  /// Stops sampling and returns the profile envelope item, or null if empty.
  SightpaneItem? stop({required double durationMs}) {
    if (_stopped) return null;
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();

    if (_samples.isEmpty) return null;

    // Approximate CPU time from active sampling intervals
    final cpuTimeMs = math.min(
      durationMs,
      _samples.length * (sampleInterval.inMicroseconds / 1000.0),
    );

    final profileData = ProfileData(
      frames: _frames,
      samples: _samples,
    );

    return SightpaneItem.profile(
      transactionName: transactionName,
      durationMs: durationMs,
      cpuTimeMs: cpuTimeMs,
      threadName: threadName,
      traceId: traceId,
      profileData: profileData.toJson(),
    );
  }

  static final _frameRegex = RegExp(r'#\d+\s+([^\s]+)\s+\((.+):(\d+):?\d*\)');
  static final _simpleFrameRegex = RegExp(r'#\d+\s+([^\s]+)\s+\((.+)\)');

  static List<ProfileFrame> _parseStackTrace(StackTrace trace) {
    final lines = trace.toString().split('\n');
    final frames = <ProfileFrame>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Skip internal framework / profiler frames
      if (trimmed.contains('SightpaneProfileSampler') ||
          trimmed.contains('dart:async') ||
          trimmed.contains('package:stack_trace')) {
        continue;
      }

      final m = _frameRegex.firstMatch(trimmed);
      if (m != null) {
        final name = m.group(1) ?? 'anonymous';
        final file = m.group(2) ?? '';
        final lineNum = int.tryParse(m.group(3) ?? '0') ?? 0;
        frames.add(ProfileFrame(name: name, file: file, line: lineNum));
        continue;
      }

      final m2 = _simpleFrameRegex.firstMatch(trimmed);
      if (m2 != null) {
        final name = m2.group(1) ?? 'anonymous';
        final file = m2.group(2) ?? '';
        frames.add(ProfileFrame(name: name, file: file));
      }
    }
    return frames;
  }
}
