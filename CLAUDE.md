# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Three repositories, one contract

sightpane is self-hosted error tracking, product analytics and frame-based session
replay. It is split across three repositories that release independently:

| Repository | What it is | Licence |
|---|---|---|
| [sightpane/sightpane](https://github.com/sightpane/sightpane) | Go backend on Fiber v3 + TimescaleDB, the Docker deployment, the product roadmap under `future-todo-files/` | AGPL-3.0-or-later |
| [sightpane/ui](https://github.com/sightpane/ui) | the Flutter web dashboard the backend serves | AGPL-3.0-or-later |
| [sightpane/flutter](https://github.com/sightpane/flutter) | the Dart/Flutter SDK, `sightpane` on pub.dev | Apache-2.0 |

**You can only see one of them at a time.** When a change touches the envelope
contract below, say plainly which of the other two also needs a change and what
it is — nobody reading this repository can check for themselves.

**English is the working language**: code comments, READMEs, issues and commit
messages. The dashboard's user interface is the exception — it is localized, and
its strings live in `lib/l10n/` in the ui repository.

## Commands

```bash
flutter analyze && flutter test
flutter test test/queue_test.dart                          # a single file
flutter test --plain-name "drops frames first"             # a single test by name
dart run tool/smoke_send.dart http://localhost:8790 dev    # a real envelope to a running backend

cd example && flutter analyze && flutter test              # the example has its own tests
cd example && flutter run -d chrome                        # drive the SDK by hand
```

`smoke_send.dart` and `example/` are the only things here that touch a real
backend. Everything else runs against `FakeTransport`, which proves the envelope
was built but not that a server accepts it — run the smoke script, or the
example, once per contract change.

`GITHUB_TOKEN` in this environment is a dummy that causes 401. Always run the
GitHub CLI as `env -u GITHUB_TOKEN gh …`.

## The envelope contract

Everything hinges on `POST /api/v1/envelope` (header `X-Sightpane-Key`), body `{sdk, session{id, started_at, user, device, props}, items[]}`. Item `type` values: `breadcrumb`, `event`, `error`, `frame` (base64 PNG + `taps`), `pointer` (`events[{t,x,y,k}]`), `heartbeat` (updates session `last_seen_at`/`current_route`, writes no row), `session_end`. Backend answers 202 `{accepted, rejected}`; unknown items are silently counted as rejected, so contract drift does not fail loudly.

The contract lives in three repositories and they must move together:
- **here** — `lib/src/models.dart` (`SightpaneItem` factories, `SightpaneEnvelope.toJson`), pinned by `test/models_test.dart`
- [sightpane/sightpane](https://github.com/sightpane/sightpane) — `internal/store/ingest.go`, pinned by its `internal/server/server_test.go`
- [sightpane/ui](https://github.com/sightpane/ui) — `lib/core/models.dart` and the `FakeApi` fixture

A new item type must land in the backend **first**: an older server counts an
unknown type as `rejected` and stores nothing, silently. Ship the server, then
the SDK, then the dashboard.

## The SDK

- `Hog` is the static facade; `SightpaneClient` owns session, `BreadcrumbBuffer`, `SightpaneQueue`, `ReplayRecorder`, heartbeat timer and `AppLifecycleListener`. `Sightpane.init(..., appRunner:)` must create the binding, the client and `runApp` inside the same `runZonedGuarded` zone (`hog.dart`); touching `WidgetsBinding.instance` earlier crashes.
- `SightpaneQueue` (`queue.dart`): in-memory only, flushes on `flushInterval`/`maxBatch` or immediately on an error item; failed batches are re-inserted at the **head** with 2→4→…→60 s backoff measured via `package:clock` (so `fakeAsync` can drive it — never `DateTime.now()` on that path). Over `maxQueue` it drops frames first, then non-errors; errors are never dropped. `HttpTransport` treats any 4xx as accepted (no retry).
- Replay: `SightpaneReplay` wraps a `RepaintBoundary`; `ReplayRecorder` captures PNGs on an interval, skips byte-identical frames unless taps happened, and blacks out `SightpaneMask` rects. `SightpaneUserInteractionWidget` emits `pointer` samples throttled by interval **and** ≥3 px distance; taps always go through.
- **Source maps** (`stack.dart`): on the web only, `captureException` also sends
  `frames[{uri,line,column,member}]` parsed out of the browser's stack with
  `package:stack_trace` — `stack` itself is unchanged, so this is additive and an
  older backend ignores it. A native stack is already readable and produces no
  frames. `parseWebFrames` never throws: an error while reporting an error would
  replace the user's bug with ours. `tool/upload_sourcemap.dart` posts the maps;
  the backend resolves and groups on them (see 01-source-maps).
- Platform splits are conditional imports (`device_web.dart` / `device_io.dart`, chosen in `device.dart`); nothing under `lib/src` may import `dart:io` or `package:web` unconditionally.
- Tests: `SightpaneOptions(transport: FakeTransport())` from `test/fake_transport.dart`; every widget test must end with `await Sightpane.close()` inside the body or it fails on pending timers. `toImage`/PNG decode need `tester.runAsync`.

## Repo conventions

- `.claude/skills/` carries the shared workflow skills (`code-auditor`, `spec-first-testing`, `debugging-advanced`, `issue-writer`, `pr-writer`, `pr-reviewer`). Provenance of the vendored ones is in `SOURCE-vendored-skills.md`.
- The official `dart-flutter` plugin is enabled at project scope in `.claude/settings.json`.
- `lib/sightpane.dart` carries the Apache-2.0 SPDX header. This package is embedded into other people's applications, which is why it is permissive and why its dependency list stays at `http`, `clock`, `web` and `stack_trace` — a new dependency is a decision, not a detail. `stack_trace` was added for web stack parsing: it is the Dart team's, it is what `flutter_test` already pulls in, and the alternative was hand-written regexes for three browser formats.
- Test fixtures must not use literal "today" dates; derive from `DateTime.now()`.
- `example/` is a real Flutter app with a path dependency on this package, so it
  follows the working tree rather than the last release. It has its own
  `flutter test`, which exists to catch a button that quietly stopped sending
  anything — a renamed method fails the tests here, that would not. Two things
  its tests cannot reach: frame capture needs a real raster, and the uncaught
  async error needs the zone `init(appRunner:)` opens, which the test binding
  owns. `bindFlutterErrors()` has to be called inside the test body, never in
  `setUp`, or the binding overwrites it.
- The roadmap for all three repositories lives in [sightpane/sightpane](https://github.com/sightpane/sightpane) under `future-todo-files/`.
