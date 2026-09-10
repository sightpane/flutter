import 'package:flutter/widgets.dart';

/// An area blacked out in the recording: password, card number, id...
class SightpaneMask extends StatefulWidget {
  const SightpaneMask({super.key, required this.child});
  final Widget child;

  @override
  State<SightpaneMask> createState() => _HogMaskState();
}

class _HogMaskState extends State<SightpaneMask> {
  @override
  void initState() {
    super.initState();
    MaskRegistry.register(this);
  }

  @override
  void dispose() {
    MaskRegistry.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The registry of on-screen [SightpaneMask]s; their rectangles are computed while a
/// frame is being captured.
class MaskRegistry {
  static final Set<State> _masks = {};

  static void register(State s) => _masks.add(s);
  static void unregister(State s) => _masks.remove(s);
  static int get count => _masks.length;

  /// Mask rectangles in [ancestor]'s coordinate space, or global when null.
  static List<Rect> rects({RenderObject? ancestor}) {
    final out = <Rect>[];
    for (final s in _masks) {
      if (!s.mounted) continue;
      final ro = s.context.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
      try {
        final tl = ro.localToGlobal(Offset.zero, ancestor: ancestor);
        out.add(tl & ro.size);
      } catch (_) {
        // In another tree, or not laid out yet; skip it.
      }
    }
    return out;
  }
}

/// An area that should NOT be masked, even when maskAllText is enabled.
class SightpaneUnmask extends StatefulWidget {
  const SightpaneUnmask({super.key, required this.child});
  final Widget child;

  @override
  State<SightpaneUnmask> createState() => _SightpaneUnmaskState();
}

typedef HogUnmask = SightpaneUnmask;

class _SightpaneUnmaskState extends State<SightpaneUnmask> {
  @override
  void initState() {
    super.initState();
    UnmaskRegistry.register(this);
  }

  @override
  void dispose() {
    UnmaskRegistry.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Registry of [SightpaneUnmask]s.
class UnmaskRegistry {
  static final Set<State> _unmasks = {};

  static void register(State s) => _unmasks.add(s);
  static void unregister(State s) => _unmasks.remove(s);
  static int get count => _unmasks.length;

  static List<Rect> rects({RenderObject? ancestor}) {
    final out = <Rect>[];
    for (final s in _unmasks) {
      if (!s.mounted) continue;
      final ro = s.context.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
      try {
        final tl = ro.localToGlobal(Offset.zero, ancestor: ancestor);
        out.add(tl & ro.size);
      } catch (_) {}
    }
    return out;
  }
}
