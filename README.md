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
- Session replay modes: `SightpaneReplayOptions(mode: SightpaneReplayMode.onError, bufferSeconds: 30, postErrorSeconds: 15)`
  keeps the last 30 seconds of frames and pointer interactions in an in-memory ring buffer.
  When an error occurs, it automatically flushes the pre-error buffer and records live
  for another 15 seconds before returning to buffering mode. Set `mode: SightpaneReplayMode.always`
  for continuous streaming, or `SightpaneReplayMode.off` to disable.
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

## In-app surveys

Surveys (NPS, CSAT, rating, single choice, open text) are created per project in
the dashboard. `SightpaneSurveyOverlay` fetches the active ones and slides a card
in at the bottom of the screen when a survey's targeting matches. Nothing is
shown until the overlay is mounted, so put it in `builder:` around the other
wrappers, once:

```dart
MaterialApp.router(
  routerConfig: router, // go_router: observers: [SightpaneNavigatorObserver()]
  builder: (context, child) => SightpaneSurveyOverlay(
    child: SightpaneReplay(child: SightpaneUserInteractionWidget(child: child!)),
  ),
);
```

With a plain `MaterialApp`, pass the observer as
`navigatorObservers: [SightpaneNavigatorObserver()]`. The targeting set in the
dashboard works like this:

- **URL pattern**: compared with the current route, the same one the heartbeat
  reports. The observer takes it from the route's `settings.name`, which is the
  path for `MaterialApp.routes`. For go_router it is the GoRoute's `name`, or its
  `path` when it has none (relative, for a nested route). Pass
  `SightpaneNavigatorObserver(routeNameOf: …)` to report something else.
  `/checkout` matches that route, and `/checkout/*` matches it and everything
  under it. Without the observer there is no route, and a survey with a URL
  pattern never shows.
- **Event trigger**: the survey shows when that event is captured.
  `Sightpane.capture('purchase_success')` shows a survey whose trigger is
  `purchase_success`, as long as its URL pattern, if it has one, matches too.
- **Neither**: shown as soon as the list arrives.

The list is fetched again when the app comes back to the foreground, and on
navigation once it is a minute old, so a survey activated in the dashboard shows
up without a restart. An answered or dismissed survey does not come back while
the app runs; after a restart it can. The answer goes out after the envelopes
still in the queue, so the backend already knows the session it belongs to. If
the answer is not stored, the card stays with the answer still selected, and
pressing Submit again retries. With `debug: true`, a refused fetch or answer is
logged with its HTTP status.

## Example

[`example/`](example) is a small till application that drives every part of this
package, and it is also the manual test rig — press a button, watch it land in
the dashboard.

```bash
docker compose up -d --build   # a backend, from a checkout of sightpane/sightpane
cd example && flutter run -d chrome
```

Its defaults point at `http://localhost:8790` with key `dev`, which is what that
backend seeds, so there is nothing to configure. See [example/README.md](example/README.md)
for what each button should produce.

## Release builds and source maps

A minified web build reports its stack as `main.dart.js:4321:19`: the names are
gone, and because they move with every build the same failure lands in a new
issue each release. The SDK sends the positions beside the raw stack and the
backend resolves them against the map you upload for that release.

```bash
flutter build web --source-maps
dart run tool/upload_sourcemap.dart \
  --endpoint http://localhost:8790 --token "$SIGHTPANE_TOKEN" \
  --project 1 --release 1.0.0 \
  build/web/main.dart.js.map
```

`--release` has to be the same string as `SightpaneOptions.release`; that is what
the server matches an error against. Upload as part of the deploy, before the
build goes out — an error that arrives before its map is stored unsymbolicated
and stays that way. The token is a **user** token for an owner of the project,
not the project API key: a source map is a build output, and the key that ships
inside the app may only write envelopes.

Nothing to do on native platforms. A Dart stack trace is already readable, so the
SDK sends no positions there and the backend groups on the text as before.

## Queue and network

Items collect in memory and go out over `POST /api/v1/envelope` when
`flushInterval` (5 s) elapses or `maxBatch` (50) fills; errors are sent
immediately. On a network failure the items are kept and retried with a
2 → 4 → … → 60 s backoff. Past `maxQueue`, frames are dropped first, then
non-error items; errors are never dropped.

Persistent offline queuing is provided via `SightpaneOptions.storage` (or
`SightpaneStorage.createDefault()`). When configured, pending error reports, spans,
and product analytics events are safely stored across application crashes or offline
shutdowns and retransmitted on the next launch. Frames and raw pointer moves are
excluded from persistent storage to preserve disk space and mobile bandwidth.
On web platforms, `visibilitychange` and `pagehide` events automatically trigger an
immediate queue flush.

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
- A survey that never shows: check that `SightpaneSurveyOverlay` is mounted (see
  [In-app surveys](#in-app-surveys)), that the survey is active, and that its URL
  pattern matches the route the session reports. With `debug: true`, a refused
  fetch is logged as `fetchActiveSurveys: HTTP …`.

## Limits

- Frame recording is image-based: text cannot be selected and there are no DOM
  events; file size is traded off with `scale` and `interval` (0.5 scale, 1 s →
  typically 20–60 KB per frame on a normal screen, and only changed frames are sent).
- `SightpaneMask` only blacks out the rectangle of the widget it wraps; while scrolling,
  the position at the moment of capture is used.
- On web, `pagehide` and `visibilitychange` trigger an immediate flush, but browsers
  may still abort requests if the tab is closed immediately.

## License

**Apache-2.0** (`LICENSE`, `NOTICE`). This SDK is embedded into applications, so
it is deliberately permissive: it can go into closed-source products, and the
licence carries an explicit patent grant. Keep the licence and copyright notice.

The backend and dashboard are separate repositories under AGPL-3.0-or-later.
Embedding this SDK puts no AGPL obligation on your application.

Copyright (C) 2026 Can Us.
