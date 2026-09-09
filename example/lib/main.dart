// sightpane — error tracking, product analytics and session replay you host yourself.
// Copyright (C) 2026 Can Us
//
// SPDX-License-Identifier: Apache-2.0

/// A till application, small enough to read in one sitting and complete enough
/// to make every part of the SDK show up in the dashboard.
///
/// It is also the manual test rig: `flutter test` proves an envelope was built,
/// never that a server accepted it, so this is how a contract change gets tried
/// against a real backend before it ships.
///
///     docker compose up -d --build          # in the sightpane/sightpane checkout
///     flutter run -d chrome                 # here
///
/// Then sign in to http://localhost:8790 as admin@sightpane.local / admin123.
/// Every button below is labelled with what it should produce there.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sightpane/sightpane.dart';

/// Where the backend is. The defaults match what `docker compose up` seeds, so
/// the example runs against a fresh install with nothing to configure.
///
/// A hot restart does not pick up a changed --dart-define; stop the app and
/// launch it again.
const endpoint = String.fromEnvironment(
  'SIGHTPANE_ENDPOINT',
  defaultValue: 'http://localhost:8790',
);
const apiKey = String.fromEnvironment(
  'SIGHTPANE_KEY',
  defaultValue: 'dev',
);

Future<void> main() async {
  await Sightpane.init(
    SightpaneOptions(
      endpoint: endpoint,
      apiKey: apiKey,
      release: '1.0.0+1',
      environment: 'example',
      appName: 'sightpane example',
      // Louder and quicker than a real app would be, so something appears in
      // the dashboard while you are still looking at it.
      debug: true,
      flushInterval: const Duration(seconds: 2),
      replay: const SightpaneReplayOptions(
        interval: Duration(seconds: 1),
        scale: 0.5,
      ),
    ),
    // appRunner is what puts the binding, the client and runApp in one zone, so
    // an uncaught async error further down still reaches captureException.
    appRunner: () => runApp(const ExampleApp()),
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'sightpane example',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFF5A524),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    // The observer turns every push and pop into a navigation breadcrumb and
    // moves the session's current_route, which is what the live view shows.
    navigatorObservers: [SightpaneNavigatorObserver()],
    routes: {
      '/': (_) => const HomePage(),
      '/checkout': (_) => const CheckoutPage(),
    },
    initialRoute: '/',
    // Both wrappers go around everything, once. SightpaneReplay is the boundary
    // the frames are captured from, and the interaction widget is what turns
    // taps and drags into the pointer trail drawn over them.
    builder: (context, child) =>
        SightpaneReplay(child: SightpaneUserInteractionWidget(child: child!)),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _basket = 0;
  bool _explode = false;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Throwing inside build is the one error the zone cannot catch on its own;
    // FlutterError.onError picks it up, which is what captureFlutterErrors
    // binds. The dashboard should show it as unhandled.
    if (_explode) throw StateError('the till drawer is jammed');

    return Scaffold(
      appBar: AppBar(title: const Text('sightpane example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Who is using it',
            subtitle:
                'identify sets the user on the session; a property sticks to it '
                'until the session ends. Both show up on the session in the '
                'dashboard and in the live view.',
            children: [
              _Button(
                'Identify as u1',
                () {
                  Sightpane.identify(
                    const SightpaneUser(
                      id: 'u1',
                      email: 'kasiyer@example.com',
                      name: 'Kasiyer',
                      props: {'role': 'cashier'},
                    ),
                  );
                  _say('identified as u1');
                },
              ),
              _Button(
                'Set branch = NOVO',
                () {
                  Sightpane.setProperty('branch', 'NOVO');
                  _say('branch = NOVO');
                },
              ),
            ],
          ),
          _Section(
            title: 'Product analytics',
            subtitle:
                'Events with properties. They drive the events page and the '
                '"top events" list on the project overview.',
            children: [
              _Button(
                'Add to basket',
                () {
                  setState(() => _basket++);
                  Sightpane.capture('add_to_basket', {
                    'item': 'espresso',
                    'price': 45,
                    'basket_size': _basket,
                  });
                  _say('event: add_to_basket');
                },
              ),
              _Button(
                'Go to checkout',
                () => Navigator.of(context).pushNamed('/checkout'),
              ),
            ],
          ),
          _Section(
            title: 'Breadcrumbs',
            subtitle:
                'The trail leading up to an error. They are held in memory and '
                'only attached when something goes wrong, so send a few first '
                'and then throw.',
            children: [
              _Button(
                'Log a line',
                () {
                  Sightpane.log('till opened', data: {'drawer': 2});
                  _say('breadcrumb: log');
                },
              ),
              _Button(
                'Log a warning',
                () {
                  Sightpane.log(
                    'printer is low on paper',
                    level: SightpaneLevel.warning,
                  );
                  _say('breadcrumb: warning');
                },
              ),
              _Button(
                'A custom category',
                () {
                  Sightpane.addBreadcrumb(
                    SightpaneBreadcrumb(
                      category: 'grpc',
                      message: 'ListCustomers',
                      data: {'took_ms': 42},
                    ),
                  );
                  _say('breadcrumb: grpc');
                },
              ),
            ],
          ),
          _Section(
            title: 'Errors',
            subtitle:
                'All four group into issues by exception type and the first '
                'three application stack frames, so the two throws below are '
                'two issues and pressing one twice is one issue seen twice.',
            children: [
              _Button(
                'Handled exception',
                () {
                  try {
                    throw const FormatException('the barcode is not a number');
                  } catch (e, st) {
                    Sightpane.captureException(
                      e,
                      stackTrace: st,
                      context: {'barcode': '86901234x'},
                    );
                  }
                  _say('captured a handled exception');
                },
              ),
              _Button(
                'Uncaught async error',
                () {
                  // No await and no catch: this reaches the zone that
                  // Sightpane.init put runApp inside.
                  unawaited(
                    Future<void>.delayed(
                      const Duration(milliseconds: 100),
                      () => throw TimeoutException('the payment terminal timed out'),
                    ),
                  );
                  _say('an uncaught error is on its way');
                },
              ),
              _Button(
                'A message, no exception',
                () {
                  Sightpane.captureMessage(
                    'the day-end total does not add up',
                    level: SightpaneLevel.error,
                    context: {'difference': -12.5},
                  );
                  _say('captured a message');
                },
              ),
              _Button(
                'Throw inside build (breaks the screen)',
                () => setState(() => _explode = true),
                danger: true,
              ),
            ],
          ),
          _Section(
            title: 'Session replay',
            subtitle:
                'A frame a second, only when it changed. The counter gives the '
                'recorder something to notice; the card number is wrapped in '
                'SightpaneMask and has to come out black in the replay.',
            children: [
              Text(
                'Basket: $_basket',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const SightpaneMask(
                child: Card(
                  child: ListTile(
                    title: Text('4242 4242 4242 4242'),
                    subtitle: Text('masked in the replay'),
                  ),
                ),
              ),
            ],
          ),
          _Section(
            title: 'Delivery',
            subtitle:
                'The queue sends every couple of seconds, and immediately when '
                'an error goes in. Flush when you do not want to wait.',
            children: [
              _Button(
                'Flush now',
                () async {
                  await Sightpane.flush();
                  _say('flushed');
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'sending to $endpoint with key "$apiKey"',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// A second route, so the navigator observer has something to report and the
/// live view shows a session moving between pages.
class CheckoutPage extends StatelessWidget {
  const CheckoutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Checkout')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('The live view should show this session on /checkout.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              Sightpane.capture('purchase', {'total': 45, 'method': 'card'});
              Navigator.of(context).pop();
            },
            child: const Text('Pay and go back'),
          ),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title, subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

class _Button extends StatelessWidget {
  const _Button(this.label, this.onPressed, {this.danger = false});
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SizedBox(
      width: double.infinity,
      child: danger
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(label),
            )
          : FilledButton.tonal(onPressed: onPressed, child: Text(label)),
    ),
  );
}
