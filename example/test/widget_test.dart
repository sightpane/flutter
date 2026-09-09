// sightpane — error tracking, product analytics and session replay you host yourself.
// Copyright (C) 2026 Can Us
//
// SPDX-License-Identifier: Apache-2.0

// The example is the manual test rig, so it has one automated test of its own:
// press every button and check the SDK produced what the label promises. It is
// here to catch the example rotting — a renamed method or a changed signature
// fails the SDK's own tests, but a button that quietly stopped sending anything
// would not.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightpane/sightpane.dart';
import 'package:sightpane_example/main.dart';

/// Collects envelopes instead of sending them. The SDK's own copy of this lives
/// in its test/ directory, which another package cannot import.
class RecordingTransport implements SightpaneTransport {
  final envelopes = <SightpaneEnvelope>[];

  List<SightpaneItem> get items => [for (final e in envelopes) ...e.items];
  Iterable<SightpaneItem> ofType(String t) => items.where((i) => i.type == t);
  Iterable<Object?> namesOf(String t) => ofType(t).map((i) => i.body['name']);

  @override
  Future<bool> send(SightpaneEnvelope envelope) async {
    envelopes.add(envelope);
    return true;
  }

  @override
  Future<void> close() async {}
}

void main() {
  late RecordingTransport transport;

  setUp(() async {
    transport = RecordingTransport();
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://example.invalid',
        apiKey: 'test',
        transport: transport,
        // Replay off: capturing frames needs runAsync and a real raster, and
        // the SDK's own replay_test.dart already covers that.
        replay: const SightpaneReplayOptions(enabled: false),
      ),
    );
  });

  /// Pumps the app on a surface tall enough to build the whole list. The home
  /// page is a ListView and the default 800×600 test window leaves half the
  /// buttons unbuilt, so a finder for one of them legitimately finds nothing.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // In the app this happens inside init's appRunner, which a test cannot use
    // because the test binding owns the zone. It belongs here and not in setUp:
    // the binding installs its own FlutterError.onError when the test body
    // starts, so a handler bound earlier would simply be overwritten. The SDK
    // chains to whatever it found, which is why takeException still sees it.
    Sightpane.client.bindFlutterErrors();
    await tester.pumpWidget(const ExampleApp());
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  testWidgets('the buttons send what their labels say', (tester) async {
    await pumpApp(tester);

    await press(tester, 'Identify as u1');
    expect(Sightpane.client.session.user?.id, 'u1');

    await press(tester, 'Set branch = NOVO');
    expect(Sightpane.client.session.props['branch'], 'NOVO');

    await press(tester, 'Add to basket');
    await press(tester, 'Log a line');
    await press(tester, 'A custom category');
    await press(tester, 'Handled exception');
    await Sightpane.flush();

    final errors = transport.ofType('error').toList();
    expect(errors, hasLength(1));
    expect(errors.single.body['exception'], 'FormatException');
    expect(errors.single.body['handled'], true);
    // The breadcrumbs pressed before it ride along on the error as well as
    // going out as items of their own, which is what makes the issue page show
    // what led up to the failure.
    expect(
      (errors.single.body['breadcrumbs'] as List).length,
      greaterThanOrEqualTo(3),
    );

    expect(transport.namesOf('event'), ['add_to_basket']);
    // identify and the initial route both add one of their own, so this checks
    // the categories rather than a count that would move on any small change.
    expect(
      transport.ofType('breadcrumb').map((i) => i.body['category']),
      containsAll(<String>['user', 'log', 'grpc', 'navigation']),
    );

    await Sightpane.close();
  });

  testWidgets('navigating reports the route', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Go to checkout'));
    await tester.pumpAndSettle();

    expect(find.text('Checkout'), findsOneWidget);
    expect(Sightpane.client.currentRoute, '/checkout');

    await tester.tap(find.text('Pay and go back'));
    await tester.pumpAndSettle();
    await Sightpane.flush();

    expect(transport.namesOf('event'), contains('purchase'));
    await Sightpane.close();
  });

  testWidgets('a throw inside build is reported as unhandled', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Throw inside build (breaks the screen)'));
    await tester.pump();

    // The framework hands the build failure to FlutterError.onError, which the
    // SDK has bound; the test binding records it too, and taking it here is
    // what keeps the test from failing on an error it asked for.
    expect(tester.takeException(), isA<StateError>());
    await Sightpane.flush();

    final error = transport.ofType('error').single;
    expect(error.body['exception'], 'StateError');
    expect(error.body['handled'], false);

    await Sightpane.close();
  });
}
