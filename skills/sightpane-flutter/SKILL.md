---
name: sightpane-flutter
description: Use when integrating, configuring, testing, or troubleshooting the sightpane Flutter SDK for error tracking, session replay, analytics, performance monitoring, or in-app surveys in a Dart or Flutter project.
---

# sightpane for Flutter

## Overview

`sightpane` is a single, zero-bloat Dart/Flutter SDK providing error tracking (Sentry-style), product analytics (PostHog-style), and cross-platform session replay (frame-based, DOM-independent), sending compressed envelopes to a self-hosted sightpane backend via `POST /api/v1/envelope`.

## When to Use

- Initializing error tracking, crash reporting, and unhandled async zone error collection in Flutter.
- Setting up cross-platform session replay (works on Web, Android, iOS, macOS, Windows, and Linux).
- Tracking product analytics events (`capture`), identifying users (`identify`), or attaching persistent session properties (`setProperty`).
- Recording HTTP breadcrumbs and distributed tracing headers (`SightpaneHttpClient`).
- Measuring app performance via transactions, spans, and CPU execution profiling (`startTransaction`, `profile`).
- Tracking background worker or cron job heartbeats (`Sightpane.checkin`).
- Showing in-app targeted feedback surveys (`SightpaneSurveyOverlay`).
- Writing unit and widget tests for code that depends on `Sightpane`.

### When NOT to Use

- For backend Go development (use internal Go packages in `sightpane/sightpane`).
- For standard React/Vue/Node.js web development (use `@sightpane/react` or `@sightpane/browser`).

---

## Critical Rules & Traps (STOP & Check)

### 1. The Zone & Binding Trap (App Startup Crash)
`Sightpane.init(..., appRunner:)` initializes Flutter bindings and runs `runApp` inside a single `runZonedGuarded` zone.
```dart
// ❌ WRONG: Calling binding before init causes crashes or zone mismatches
void main() {
  WidgetsFlutterBinding.ensureInitialized(); // DON'T DO THIS BEFORE Sightpane.init
  Sightpane.init(..., appRunner: () => runApp(const MyApp()));
}

// ✅ CORRECT: Let Sightpane.init handle binding and zone setup
void main() {
  Sightpane.init(
    SightpaneOptions(
      endpoint: 'http://localhost:8790',
      apiKey: 'your_project_key',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

### 2. Test Teardown Requirement (Pending Timer Leak)
`Sightpane` runs background timers for heartbeats, replay intervals, and queue flushing. In test environments:
- Always use `FakeTransport` via `SightpaneOptions(transport: FakeTransport())`.
- Always call `await Sightpane.close()` in `tearDown` or at the end of the test body.
- Failure to call `Sightpane.close()` causes `flutter test` to fail with `A Timer is still pending even after the widget tree was disposed`.

### 3. Replay is Image-Based (Not DOM-Based)
Replay records raster frames using a `RepaintBoundary` (`SightpaneReplay`) converted to compressed PNGs.
- It does **not** capture HTML DOM elements; text cannot be selected in replay.
- Recommended defaults: `scale: 0.5` and `interval: Duration(seconds: 1)`. Only changed frames are sent (~20–60 KB per frame).
- Avoid `scale: 1.0` or intervals `< 500ms` in production to prevent excessive memory and network usage.

### 4. Masking Sensitive PII
- Wrap sensitive widgets (passwords, credit cards, user personal data) in `SightpaneMask(child: ...)`. The SDK blacks out their bounding rect in recordings.
- For maximum privacy, set `SightpaneReplayOptions(maskAllText: true)`. To allow specific public text through, wrap it in `SightpaneUnmask(child: ...)`.

### 5. Minified Web Source Maps
Minified web builds report obfuscated stack frames (e.g. `main.dart.js:1234:56`).
- Provide matching `--release` in `SightpaneOptions(release: '1.0.0')`.
- Upload source maps during deployment using `tool/upload_sourcemap.dart`:
  ```bash
  dart run tool/upload_sourcemap.dart --endpoint <url> --token <token> --project <id> --release 1.0.0 build/web/main.dart.js.map
  ```

---

## Quick Reference

| Feature | Primary API | Description |
|---|---|---|
| **Initialize** | `Sightpane.init(options, appRunner:)` | Starts client, error zone, and queue |
| **Capture Error** | `Sightpane.captureException(e, stackTrace:, fatal:, context:)` | Sends error report |
| **Capture Message** | `Sightpane.captureMessage(msg, level:, context:)` | Sends message report |
| **Breadcrumbs** | `Sightpane.addBreadcrumb(...)` / `Sightpane.log(...)` | Adds trail event before errors |
| **Product Event** | `Sightpane.capture('event_name', {'prop': val})` | Custom product analytics event |
| **Identify User** | `Sightpane.identify(SightpaneUser(id:, email:, props:))` | Associates user with session |
| **Session Prop** | `Sightpane.setProperty('key', value)` | Persistent session tag |
| **Replay Boundary**| `SightpaneReplay(child: ...)` | Wraps root widget to capture frames |
| **User Interaction**| `SightpaneUserInteractionWidget(child: ...)` | Tracks taps, clicks, and drag trails |
| **Mask Widget** | `SightpaneMask(child: ...)` | Blacks out bounding rect in replay |
| **Route Observer** | `SightpaneNavigatorObserver()` | Tracks route changes & active page |
| **HTTP Client** | `SightpaneHttpClient(client)` | Logs HTTP breadcrumbs & W3C traceparent |
| **Performance** | `Sightpane.startTransaction(name, op:)` | Measures flow duration & spans |
| **CPU Profile** | `Sightpane.profile(name, () async => ...)` | Samples call execution profile |
| **Cron Heartbeat**| `Sightpane.checkin('slug', status:, durationMs:)` | Pings scheduled monitor |
| **Surveys** | `Sightpane.fetchActiveSurveys()`, `SightpaneSurveyOverlay` | In-app feedback popups |
| **Flush / Close** | `Sightpane.flush()` / `Sightpane.close()` | Flushes queue or shuts down SDK |

---

## Standard App Integration

Wrap your root application structure as follows:

```dart
import 'package:flutter/material.dart';
import 'package:sightpane/sightpane.dart';

void main() {
  Sightpane.init(
    SightpaneOptions(
      endpoint: const String.fromEnvironment('SIGHTPANE_ENDPOINT', defaultValue: 'http://localhost:8790'),
      apiKey: const String.fromEnvironment('SIGHTPANE_KEY', defaultValue: 'dev'),
      release: '1.0.0',
      environment: 'production',
      debug: false,
      storage: SightpaneStorage.createDefault(), // Enables offline disk queue
      replay: const SightpaneReplayOptions(
        enabled: true,
        mode: SightpaneReplayMode.onError, // Buffers in RAM; sends 30s before error + 15s after
        bufferSeconds: 30,
        postErrorSeconds: 15,
        interval: Duration(seconds: 1),
        scale: 0.5,
      ),
    ),
    appRunner: () => runApp(const MainApp()),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [SightpaneNavigatorObserver()],
      builder: (context, child) => SightpaneSurveyOverlay(
        child: SightpaneReplay(
          child: SightpaneUserInteractionWidget(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
```

---

## Implementation Recipes

### 1. Error Handling & Context
```dart
try {
  await checkoutCart();
} catch (e, st) {
  Sightpane.captureException(
    e,
    stackTrace: st,
    fatal: false,
    context: {
      'cart_id': cart.id,
      'item_count': cart.items.length,
      'payment_method': 'credit_card',
    },
  );
}
```

### 2. Product Analytics & User Identification
```dart
// After login:
Sightpane.identify(SightpaneUser(
  id: user.id,
  email: user.email,
  name: user.fullName,
  props: {
    'tier': user.subscriptionTier,
    'team_id': user.teamId,
  },
));

// Session level tag:
Sightpane.setProperty('tenant_region', 'eu-west-1');

// Tracking conversion events:
Sightpane.capture('order_completed', {
  'order_id': order.id,
  'total_usd': order.total,
  'items': order.itemCount,
});
```

### 3. HTTP Client with Distributed Tracing
Wrap standard `http.Client` to record breadcrumbs, measure latency spans, and inject W3C `traceparent` headers:
```dart
final httpClient = SightpaneHttpClient();

// Requests automatically log 'http' breadcrumbs and generate http.client performance spans
final response = await httpClient.get(Uri.parse('https://api.example.com/v1/orders'));
```

### 4. Performance Transactions & Spans
```dart
final tx = Sightpane.startTransaction('checkout_flow', op: 'ui.checkout');

final span = tx.startChild('process_payment', op: 'http.payment');
try {
  await pay();
  span.finish(status: 'ok');
} catch (e) {
  span.finish(status: 'internal_error');
  rethrow;
} finally {
  tx.finish(status: 'ok');
}
```

### 5. Sensitive Data Masking
```dart
// Black out sensitive inputs from session recordings
SightpaneMask(
  child: TextField(
    controller: _creditCardController,
    decoration: const InputDecoration(labelText: 'Credit Card Number'),
    obscureText: true,
  ),
);
```

### 6. Cron & Background Task Check-Ins
```dart
Future<void> runNightlySync() async {
  final sw = Stopwatch()..start();
  try {
    await performDataSync();
    await Sightpane.checkin('nightly-sync', status: 'ok', durationMs: sw.elapsedMilliseconds);
  } catch (e) {
    await Sightpane.checkin('nightly-sync', status: 'error', message: e.toString());
    rethrow;
  }
}
```

---

## Unit and Widget Testing Pattern

Always configure `FakeTransport` and invoke `Sightpane.close()`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sightpane/sightpane.dart';
import '../test/fake_transport.dart'; // Or define your own FakeTransport

void main() {
  late FakeTransport transport;

  setUp(() async {
    transport = FakeTransport();
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://localhost:8790',
        apiKey: 'test-key',
        transport: transport,
        replay: const SightpaneReplayOptions(enabled: false), // Disable replay in tests
      ),
    );
  });

  tearDown(() async {
    await Sightpane.close(); // REQUIRED: cancels periodic timers
  });

  test('captures custom event into envelope', () async {
    Sightpane.capture('button_click', {'btn': 'submit'});
    await Sightpane.flush();

    expect(transport.ofType('event').length, 1);
    expect(transport.ofType('event').first.body['name'], 'button_click');
  });
}
```

---

## Troubleshooting Guide

| Issue / Symptom | Root Cause | Solution |
|---|---|---|
| **`A Timer is still pending...` in tests** | `Sightpane.close()` was not awaited at end of test. | Call `await Sightpane.close()` in `tearDown`. |
| **App crashes on startup with ZoneMismatch** | `WidgetsFlutterBinding.ensureInitialized()` was called before `Sightpane.init`. | Pass `appRunner: () => runApp(...)` to `Sightpane.init` and remove manual binding setup outside the zone. |
| **No events/sessions appear in dashboard** | Bad endpoint, wrong API key, or app failed to flush. | Set `debug: true` in `SightpaneOptions`. Verify console logs `sightpane: initialised ...` and `sent N items`. |
| **Network send failed / 401 Unauthorized** | Backend rejected API key or CORS blocked web request. | Check `POST /api/v1/envelope` in network inspect. Verify key in project settings. |
| **Minified stack trace unreadable in UI** | Source maps were not uploaded for web release. | Upload `.map` file using `tool/upload_sourcemap.dart` with matching `--release`. |
| **Replay causes high memory / network traffic** | `scale: 1.0` or interval is too fast. | Use `scale: 0.5`, `interval: Duration(seconds: 1)`, and `SightpaneReplayMode.onError`. |
