# sightpane for Flutter

The Dart and Flutter SDK for [sightpane](https://github.com/sightpane/sightpane).
Published on pub.dev as **`sightpane`**.

| Repository | What it is |
|---|---|
| [sightpane/sightpane](https://github.com/sightpane/sightpane) | the Go backend this sends envelopes to |
| [sightpane/ui](https://github.com/sightpane/ui) | the dashboard that plays them back |
| **[sightpane/flutter](https://github.com/sightpane/flutter)** (here) | this SDK |

The SDK talks to the backend over one endpoint, `POST /api/v1/envelope`, with the
project's key in `X-Sightpane-Key`. Nothing else is shared between the
repositories, so this one can be released on its own schedule — but a change to
the envelope shape has to land in the backend first, since an old server counts
an unknown item type as rejected.

---

**Error tracking** (Sentry-style), **product analytics** (PostHog-style) and
**session replay** for Flutter, in one SDK, talking to `sightpane/backend`.

Session replay does not depend on the DOM: `SightpaneReplay` captures a frame from its
boundary at an interval (RepaintBoundary → PNG), blacks out `SightpaneMask` regions and
paints taps onto the frame. That is why it works the same on **web,
Linux/macOS/Windows, Android and iOS**.

## Install

```yaml
dependencies:
  sightpane:
    path: ../sightpane/package
```

```dart
import 'package:sightpane/sightpane.dart';

void main() {
  Sightpane.init(
    SightpaneOptions(
      endpoint: 'http://localhost:8790',
      apiKey: 'dev',
      release: '1.4.2',
      environment: 'staging',
      replay: const SightpaneReplayOptions(interval: Duration(seconds: 1), scale: 0.5),
    ),
    appRunner: () => runApp(const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router, // go_router: observers: [SightpaneNavigatorObserver()]
    builder: (context, child) => SightpaneReplay(child: SightpaneUserInteractionWidget(child: child!)),
  );
}
```

- `Sightpane.captureException(e, stackTrace: st)` / `Sightpane.captureMessage('...')`
- `Sightpane.capture('deposit', {'amount': 50})` — a product event
- `Sightpane.identify(SightpaneUser(id: 'u1', email: 'a@b.c'))`, `Sightpane.setProperty('location', 'NOVO')`
- `Sightpane.log('till opened')` / `Sightpane.addBreadcrumb(SightpaneBreadcrumb(category: 'grpc', message: 'ListCustomers'))`
- Pointer and touch trail: `SightpaneUserInteractionWidget` sends hover, drag,
  press/release and scroll as `pointer` packets (movement every 50 ms and at
  least 3 px, clicks always; `SightpaneReplayOptions.recordPointer`,
  `pointerSampleInterval`). The dashboard player draws the trail, the cursor and
  click rings on top of the frame.
- `SightpaneMask(child: TextField(obscureText: true))` — blacked out in the recording
- `SightpaneHttpClient()` — turns `package:http` requests into `http` breadcrumbs
- Heartbeat: the current route is sent every 20 s (`SightpaneOptions.heartbeatInterval`,
  paused in the background) so the dashboard can show who is on which page right
  now. On web, `user_agent` / `browser` are added to the device info; visitors are
  counted per user + IP + browser.
- `Sightpane.flush()` / `Sightpane.close()`

Starting through `appRunner` collects uncaught zone errors, `FlutterError.onError`
and `PlatformDispatcher.onError` automatically, preserving any hooks that were
already installed. Every error carries the breadcrumbs at that moment, the current
route and a fresh frame number; on the backend the same exception with the same
first three app frames becomes one "error group".

## Queue and network

Items collect in memory and go out over `POST /api/v1/envelope` when
`flushInterval` (5 s) elapses or `maxBatch` (50) fills; errors are sent
immediately. On a network failure the items are kept and retried with a
2 → 4 → … → 60 s backoff. Past `maxQueue`, frames are dropped first, then
non-error items; errors are never dropped. There is no persistent on-disk queue:
if the app is closed before a batch is sent, that batch is lost.

## In tests

Pass a fake transport with `SightpaneOptions.transport`; in widget tests call
`await Sightpane.close()` at the end of the test body, so no timer is left pending.

## Troubleshooting

- If no session shows up in the dashboard, start with `debug: true` and read the
  console: `sightpane: initialised endpoint=… key=…` on startup, then
  `sent N items` lines. No "initialised" line means `Sightpane.init` never ran (usually
  the key did not make it into the build through `--dart-define`; **a hot restart
  does not refresh build settings, stop and relaunch the app**).
- `send failed` means the address, CORS or the key (401). Check the response to
  `POST /api/v1/envelope` in the browser's network tab.
- Recording runs continuously; an error only triggers a fresh frame plus an
  immediate send.

## Limits

- Frame recording is image-based: text cannot be selected and there are no DOM
  events; file size is traded off with `scale` and `interval` (0.5 scale, 1 s →
  typically 20–60 KB per frame on a normal screen, and only changed frames are sent).
- `SightpaneMask` only blacks out the rectangle of the widget it wraps; while scrolling,
  the position at the moment of capture is used.
- On web the last batch may not be sent when the tab is closed (no `sendBeacon`).

## License

**Apache-2.0** (`LICENSE`, `NOTICE`). This SDK is embedded into applications, so
it is deliberately permissive: it can go into closed-source products, and the
licence carries an explicit patent grant. Keep the licence and copyright notice.

The backend and dashboard are separate repositories under AGPL-3.0-or-later.
Embedding this SDK puts no AGPL obligation on your application.

Copyright (C) 2026 Can Us.
