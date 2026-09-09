import 'package:flutter/material.dart';
import 'package:sightpane/sightpane.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

void main() {
  late FakeTransport t;
  setUp(() async {
    t = FakeTransport();
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://x',
        apiKey: 'k',
        transport: t,
        flushInterval: const Duration(days: 1),
        captureFlutterErrors: false,
        replay: const SightpaneReplayOptions(enabled: false),
      ),
    );
  });
  tearDown(() => Sightpane.close());

  testWidgets('taps are described by their text and recorded as ui.click', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SightpaneUserInteractionWidget(
          child: Scaffold(
            body: Column(
              children: [
                ElevatedButton(onPressed: () {}, child: const Text('Save')),
                const IconButton(
                  icon: Icon(Icons.add),
                  onPressed: null,
                  tooltip: 'Add',
                ),
                const TextField(),
                const Expanded(
                  child: Center(child: SizedBox(width: 50, height: 50)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byType(TextField));
    await tester.tap(find.byType(Center).last);
    await tester.pump();
    final clicks = Sightpane.client.breadcrumbs
        .snapshot()
        .where((b) => b.category == 'ui.click')
        .toList();
    expect(clicks.map((b) => b.message), [
      'tap "Save"',
      'tap "Add"',
      'tap "input"',
      'tap',
    ]);
    expect(clicks.first.data['x'], isA<int>());
    await Sightpane.close();
  });

  testWidgets('a drag is not a click', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SightpaneUserInteractionWidget(
          child: Scaffold(
            body: ListView(
              children: const [SizedBox(height: 2000, child: Text('tall'))],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(
      Sightpane.client.breadcrumbs.snapshot().where(
        (b) => b.category == 'ui.click',
      ),
      isEmpty,
    );
    await Sightpane.close();
  });

  testWidgets(
    'navigator observer records push and pop and tracks the current route',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [SightpaneNavigatorObserver()],
          routes: {
            '/': (_) => const Text('home'),
            '/detail': (_) => const Text('detail'),
          },
        ),
      );
      nav.currentState!.pushNamed('/detail');
      await tester.pumpAndSettle();
      expect(Sightpane.client.currentRoute, '/detail');
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      final navs = Sightpane.client.breadcrumbs
          .snapshot()
          .where((b) => b.category == 'navigation')
          .map((b) => b.message)
          .toList();
      expect(navs, ['push /', 'push /detail', 'pop /']);
      expect(Sightpane.client.currentRoute, '/');
      await Sightpane.close();
    },
  );

  testWidgets('SightpaneHttpClient leaves http breadcrumbs', (tester) async {
    // flutter_test's fake HttpClient returns 400; the breadcrumb is still
    // written.
    final c = SightpaneHttpClient();
    try {
      await tester.runAsync(() => c.get(Uri.parse('http://127.0.0.1:1/x')));
    } catch (_) {}
    final http = Sightpane.client.breadcrumbs
        .snapshot()
        .where((b) => b.category == 'http')
        .single;
    expect(http.message, 'GET http://127.0.0.1:1/x');
    expect(
      http.data.containsKey('status') || http.data.containsKey('error'),
      isTrue,
    );
    await Sightpane.close();
  });
}
