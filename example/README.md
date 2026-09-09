# sightpane example

A till application, small enough to read in one sitting and complete enough that
every part of the SDK shows up in the dashboard. It is the package's example and
its manual test rig: `flutter test` proves an envelope was built, never that a
server accepted one, so this is how a contract change gets tried against a real
backend before it ships.

## Run it

```bash
# 1. a backend, from a checkout of github.com/sightpane/sightpane
docker compose up -d --build

# 2. the app
flutter run -d chrome
```

The defaults — `http://localhost:8790`, key `dev` — are what `docker compose up`
seeds, so there is nothing to configure. Sign in to the dashboard at
<http://localhost:8790> as `admin@sightpane.local` / `admin123` and watch the
project the app is sending to.

Point it somewhere else with `--dart-define`:

```bash
flutter run -d chrome \
  --dart-define=SIGHTPANE_ENDPOINT=https://sightpane.example.com \
  --dart-define=SIGHTPANE_KEY=your-project-key
```

A hot restart does **not** pick up a changed `--dart-define`. Stop the app and
launch it again, or the old key stays compiled in.

## What each button is for

| Button | What should appear |
|---|---|
| Identify as u1 | the session gets a user; the live view shows the email |
| Set branch = NOVO | a session property, on the session detail page |
| Add to basket | an `add_to_basket` event with properties, on the events page |
| Go to checkout | a navigation breadcrumb, and `current_route` moves in the live view |
| Log a line / warning / custom category | breadcrumbs, and the trail attached to the next error |
| Handled exception | an issue, marked handled |
| Uncaught async error | an issue, marked unhandled — it reaches the zone `init` opened |
| A message, no exception | an issue with no stack trace |
| Throw inside build | breaks the screen; `FlutterError.onError` reports it |
| Flush now | sends immediately instead of waiting for the interval |

The two throws group into two issues, because issues are keyed on the exception
type and the first three application stack frames. Pressing one of them twice is
one issue seen twice, which is the behaviour worth checking after any change to
fingerprinting.

Replay records a frame a second and only when the picture changed, so press
something to give the recorder a reason. The card number on the home page is
wrapped in `SightpaneMask` and has to come out black in the replay — that is the
one thing worth looking at every time, because a masking regression leaks real
data and nothing else in the test suite would catch it.

## Its own test

```bash
flutter test
```

Presses every button against a recording transport and checks the SDK produced
what the label promises. It is here to catch the example rotting: a renamed
method fails the SDK's own tests, but a button that quietly stopped sending
anything would not.

Two things the test cannot reach, and the reason they are not covered:
frame capture needs a real raster (`replay_test.dart` in the SDK covers it), and
the uncaught async error needs the zone that `Sightpane.init(appRunner:)` opens,
which the test binding owns instead.

## Other platforms

Scaffolded for Android, iOS and web. Add the rest with:

```bash
flutter create --platforms=linux,macos,windows .
```
