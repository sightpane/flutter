import 'package:flutter/widgets.dart';

import '../client.dart';

/// Bounds the area that gets recorded; wrap it around the root of the app
/// (e.g. in `MaterialApp.builder`). When the SDK is not initialised or replay
/// is off it simply renders its child.
class SightpaneReplay extends StatefulWidget {
  const SightpaneReplay({super.key, required this.child});
  final Widget child;

  @override
  State<SightpaneReplay> createState() => _HogReplayState();
}

class _HogReplayState extends State<SightpaneReplay> {
  final _key = GlobalKey(debugLabel: 'SightpaneReplayBoundary');

  @override
  void initState() {
    super.initState();
    Sightpane.maybeClient?.replay.attach(_key);
  }

  @override
  void dispose() {
    Sightpane.maybeClient?.replay.detach(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: _key, child: widget.child);
}
