import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../client.dart';
import '../models.dart';

/// Records taps as `ui.click` breadcrumbs and marks them on the replay frames.
/// Wrap it around the root of the app (e.g. in `MaterialApp.builder`).
class SightpaneUserInteractionWidget extends StatefulWidget {
  const SightpaneUserInteractionWidget({
    super.key,
    required this.child,
    this.slop = 12,
  });
  final Widget child;

  /// Most drift allowed between pointer down and up; beyond it the gesture is
  /// not counted as a tap.
  final double slop;

  @override
  State<SightpaneUserInteractionWidget> createState() =>
      _HogUserInteractionWidgetState();
}

class _HogUserInteractionWidgetState
    extends State<SightpaneUserInteractionWidget> {
  Offset? _down;

  void _pointer(String kind, PointerEvent e) =>
      Sightpane.maybeClient?.replay.recordPointer(kind, e.position);

  void _onDown(PointerDownEvent e) {
    _down = e.position;
    _pointer('down', e);
  }

  void _onUp(PointerUpEvent e) {
    _pointer('up', e);
    final d = _down;
    _down = null;
    if (d == null || (e.position - d).distance > widget.slop) return;
    final c = Sightpane.maybeClient;
    if (c == null) return;
    final box = context.findRenderObject();
    final label = box is RenderBox ? describeTapTarget(box, e.position) : '';
    c.replay.recordTap(e.position);
    c.addBreadcrumb(
      SightpaneBreadcrumb(
        category: 'ui.click',
        message: label.isEmpty ? 'tap' : 'tap "$label"',
        data: {
          'x': e.position.dx.round(),
          'y': e.position.dy.round(),
          if (label.isNotEmpty) 'label': label,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerUp: _onUp,
    onPointerHover: (e) => _pointer('move', e),
    onPointerMove: (e) => _pointer('move', e),
    onPointerSignal: (e) => _pointer('scroll', e),
    child: widget.child,
  );
}

/// Finds the most meaningful label at the tapped point: text, a semantics
/// label, or the widget type. An empty result means nothing was found.
String describeTapTarget(RenderBox root, Offset globalPosition) {
  final result = BoxHitTestResult();
  root.hitTest(result, position: root.globalToLocal(globalPosition));
  String? semantic;
  for (final entry in result.path) {
    final t = entry.target;
    if (t is RenderParagraph) {
      final s = t.text.toPlainText().trim();
      // Icon fonts draw with private use area (U+E000–U+F8FF) characters;
      // those do not count as text, so fall through to the semantics label.
      if (s.isNotEmpty && !_isIconGlyph(s)) return _truncate(s);
    }
    if (t is RenderSemanticsAnnotations) {
      final l = t.properties.label ?? t.properties.tooltip;
      if (l != null && l.isNotEmpty) semantic ??= l;
    }
  }
  if (semantic != null) return _truncate(semantic);
  // With no text, only meaningful leaf types get named; layout boxes
  // (Padding, Center, Flex...) stay a plain "tap".
  for (final entry in result.path) {
    final t = entry.target;
    if (t is RenderEditable) return 'input';
    if (t is RenderImage) return 'image';
  }
  return '';
}

bool _isIconGlyph(String s) => s.runes.every(
  (r) => (r >= 0xE000 && r <= 0xF8FF) || (r >= 0xF0000 && r <= 0x10FFFD),
);

String _truncate(String s) => s.length > 60 ? '${s.substring(0, 57)}…' : s;
