import 'package:stack_trace/stack_trace.dart';

/// Parsing a web stack trace into frames the backend can map back to source.
///
/// On the web `StackTrace.toString()` is whatever the browser produced, and the
/// three engines disagree about the format:
///
///     Chrome    at aI.$2 (https://app/main.dart.js:12345:67)
///     Firefox   $2@https://app/main.dart.js:12345:67
///     Safari    $2@https://app/main.dart.js:12345:67
///
/// In a release build the names in it are minified, so the text is useless on
/// its own. What is useful is the position — file, line, column — because the
/// server has the source map that turns it back into `lib/cashier.dart:120`.
/// The SDK cannot do that itself: the map is tens of megabytes and lives on the
/// server, which is also the only place it has to be parsed once for everyone.
///
/// So the SDK sends the positions and leaves the resolution to the backend.

/// The most frames sent with one error. A stack is read from the top down and
/// the fingerprint only uses the first three, so this is generous; the cap is
/// there because a runaway recursion produces thousands and an envelope has a
/// size limit.
const _maxFrames = 30;

/// Parses [stack] into `[{uri, line, column, member}]`, ready for the envelope.
///
/// Returns an empty list for anything it cannot read, which includes a native
/// Dart stack: those are already readable and the backend uses the raw text.
/// Nothing here throws — an error while reporting an error would replace the
/// user's bug with ours.
List<Map<String, Object?>> parseWebFrames(String stack) {
  if (stack.isEmpty) return const [];
  Trace trace;
  try {
    trace = Trace.parse(stack);
  } on FormatException {
    return const [];
  } catch (_) {
    return const [];
  }
  final out = <Map<String, Object?>>[];
  for (final f in trace.frames) {
    // A frame with no position cannot be mapped, and one from something that is
    // not a script — an eval, an extension — has no map to be mapped against.
    if (f.line == null) continue;
    final uri = f.uri.toString();
    if (!uri.contains('.js')) continue;
    out.add({
      'uri': uri,
      'line': f.line,
      if (f.column != null) 'column': f.column,
      if (f.member != null && f.member!.isNotEmpty) 'member': f.member,
    });
    if (out.length == _maxFrames) break;
  }
  return out;
}
