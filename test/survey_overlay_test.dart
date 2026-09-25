// sightpane — error tracking, product analytics and session replay you host yourself.
// Copyright (C) 2026 Can Us
//
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sightpane/sightpane.dart';

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

  testWidgets('renders NPS survey, selects score and records breadcrumb upon submit', (tester) async {
    SurveyAnswer? submittedAnswer;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SightpaneSurveyCard(
            prompt: const SurveyPrompt(
              id: 'nps_1',
              type: SurveyType.nps,
              question: 'How likely are you to recommend Sightpane?',
              description: 'Scale 0 to 10',
            ),
            onSubmit: (ans) => submittedAnswer = ans,
          ),
        ),
      ),
    );

    expect(find.text('How likely are you to recommend Sightpane?'), findsOneWidget);
    expect(find.text('Scale 0 to 10'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);

    // Tap score 10
    await tester.tap(find.text('10'));
    await tester.pump();

    // Tap submit
    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(submittedAnswer, isNotNull);
    expect(submittedAnswer!.surveyId, 'nps_1');
    expect(submittedAnswer!.score, 10);
    await Sightpane.close();
  });

  testWidgets('renders open text survey and submits response', (tester) async {
    SurveyAnswer? submittedAnswer;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SightpaneSurveyCard(
            prompt: const SurveyPrompt(
              id: 'feedback_1',
              type: SurveyType.openText,
              question: 'What can we improve?',
            ),
            onSubmit: (ans) => submittedAnswer = ans,
          ),
        ),
      ),
    );

    expect(find.text('What can we improve?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Add dark mode to replay');
    await tester.pump();

    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(submittedAnswer, isNotNull);
    expect(submittedAnswer!.surveyId, 'feedback_1');
    expect(submittedAnswer!.responseText, 'Add dark mode to replay');
    await Sightpane.close();
  });

  test('SurveyTargeting matches routes correctly', () {
    const t1 = SurveyTargeting(urlPattern: '/checkout');
    expect(t1.matchesRoute('/checkout'), isTrue);
    expect(t1.matchesRoute('/checkout/'), isTrue);
    expect(t1.matchesRoute('#/checkout'), isTrue);
    expect(t1.matchesRoute('/'), isFalse);
    expect(t1.matchesRoute('/orders'), isFalse);

    const t2 = SurveyTargeting(urlPattern: '/products/*');
    expect(t2.matchesRoute('/products/123'), isTrue);
    expect(t2.matchesRoute('/products/shoes/nike'), isTrue);
    expect(t2.matchesRoute('/cart'), isFalse);

    const t3 = SurveyTargeting();
    expect(t3.matchesRoute('/anything'), isTrue);
  });

  testWidgets('SightpaneSurveyOverlay displays survey when route matches', (tester) async {
    const survey = SightpaneSurvey(
      id: 'srv_checkout',
      name: 'Checkout Feedback',
      type: SurveyType.openText,
      question: 'How was checkout?',
      targeting: SurveyTargeting(urlPattern: '/checkout'),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SightpaneSurveyOverlay(
          activeSurveys: [survey],
          child: Scaffold(
            body: Text('Checkout Screen'),
          ),
        ),
      ),
    );

    // Initial route is not /checkout, so survey should not be visible
    expect(find.text('How was checkout?'), findsNothing);

    // Change current route to /checkout
    Sightpane.currentRoute = '/checkout';
    await tester.pumpAndSettle();

    // Now survey card is visible
    expect(find.text('How was checkout?'), findsOneWidget);

    // Submit answer; the backend accepts it
    await withHttp(() async {
      await tester.enterText(find.byType(TextField), 'Very smooth!');
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
    }, (_) async => http.Response('{}', 201));

    // Thank you card appears
    expect(find.text('Thank you for your feedback!'), findsOneWidget);

    // Wait for auto-dismiss timer
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Thank you for your feedback!'), findsNothing);

    await Sightpane.close();
  });

  testWidgets('SightpaneSurveyOverlay dismisses on X button', (tester) async {
    const survey = SightpaneSurvey(
      id: 'srv_1',
      name: 'NPS',
      type: SurveyType.nps,
      question: 'Recommend us?',
      targeting: SurveyTargeting(urlPattern: '/'),
    );

    Sightpane.currentRoute = '/';

    await tester.pumpWidget(
      const MaterialApp(
        home: SightpaneSurveyOverlay(
          activeSurveys: [survey],
          child: Scaffold(
            body: Text('Home Screen'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Recommend us?'), findsOneWidget);

    // Tap dismiss (X icon)
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Recommend us?'), findsNothing);

    await Sightpane.close();
  });

  testWidgets('an event-trigger survey is shown by capturing that event, and only that one', (tester) async {
    const survey = SightpaneSurvey(
      id: 'srv_buy',
      name: 'After purchase',
      type: SurveyType.nps,
      question: 'How was buying?',
      targeting: SurveyTargeting(eventTrigger: 'purchase'),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SightpaneSurveyOverlay(
          activeSurveys: [survey],
          child: Scaffold(body: Text('Shop')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('How was buying?'), findsNothing);

    Sightpane.capture('signup');
    await tester.pumpAndSettle();
    expect(find.text('How was buying?'), findsNothing);

    Sightpane.capture('purchase');
    await tester.pumpAndSettle();
    expect(find.text('How was buying?'), findsOneWidget);

    await Sightpane.close();
  });

  // The README mounts the overlay in MaterialApp.builder, which puts it beside
  // the Navigator rather than under it: no Overlay above the card's TextField.
  testWidgets('open text survey mounted in MaterialApp.builder can be typed into', (tester) async {
    const survey = SightpaneSurvey(
      id: 'srv_text',
      name: 'Feedback',
      type: SurveyType.openText,
      question: 'What can we improve?',
    );
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [SightpaneNavigatorObserver()],
        builder: (context, child) => SightpaneSurveyOverlay(
          activeSurveys: const [survey],
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TextButton(onPressed: () => taps++, child: const Text('Under')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What can we improve?'), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'More charts');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('More charts'), findsOneWidget);

    // The layer the card sits in must not swallow taps meant for the app.
    await tester.tap(find.text('Under'));
    expect(taps, 1);

    await Sightpane.close();
  });

  testWidgets('the survey card stays above the on-screen keyboard', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    const survey = SightpaneSurvey(
      id: 'srv_text',
      name: 'Feedback',
      type: SurveyType.openText,
      question: 'What can we improve?',
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SightpaneSurveyOverlay(
          activeSurveys: const [survey],
          child: child!,
        ),
        home: const Scaffold(body: Text('Home')),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byType(SightpaneSurveyCard));
    expect(card.bottom, lessThanOrEqualTo(800 - 300));

    await Sightpane.close();
  });

  test('submitting an answer first sends what is queued, so the session exists', () async {
    Sightpane.capture('opened_settings');
    var envelopesBeforeSubmit = -1;
    Map<String, Object?>? body;

    final ok = await Sightpane.client.submitSurveyResponse(
      surveyId: '7',
      score: 9,
      client: MockClient((req) async {
        envelopesBeforeSubmit = t.envelopes.length;
        body = jsonDecode(req.body) as Map<String, Object?>;
        return http.Response('{}', 201);
      }),
    );

    expect(ok, isTrue);
    expect(envelopesBeforeSubmit, 1);
    expect(body!['session_id'], t.envelopes.single.sessionId);
    expect(body!['score'], 9);
  });

  test('a refused fetch or submit is logged when debug is on', () async {
    await Sightpane.init(
      SightpaneOptions(
        endpoint: 'http://x',
        apiKey: 'k',
        transport: FakeTransport(),
        flushInterval: const Duration(days: 1),
        captureFlutterErrors: false,
        replay: const SightpaneReplayOptions(enabled: false),
        debug: true,
      ),
    );
    final logged = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = previous);
    final refuse = MockClient(
      (_) async => http.Response('{"error":"unknown api key"}', 401),
    );

    expect(await Sightpane.fetchActiveSurveys(client: refuse), isEmpty);
    expect(
      await Sightpane.submitSurveyResponse(surveyId: '7', score: 9, client: refuse),
      isFalse,
    );

    expect(logged.where((l) => l.contains('401')), hasLength(2));
  });

  testWidgets('a failed submit keeps the card to try again instead of thanking', (tester) async {
    const survey = SightpaneSurvey(
      id: 'srv_nps',
      name: 'NPS',
      type: SurveyType.nps,
      question: 'Recommend us?',
    );
    var status = 500;
    var requests = 0;

    await withHttp(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SightpaneSurveyOverlay(
            activeSurveys: [survey],
            child: Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(requests, 1);
      expect(find.text('Thank you for your feedback!'), findsNothing);
      expect(find.text('Recommend us?'), findsOneWidget);
      expect(find.textContaining('Could not send'), findsOneWidget);

      // The score is still selected; Submit again is the retry.
      status = 201;
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(requests, 2);
      expect(find.text('Thank you for your feedback!'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }, (_) async {
      requests++;
      return http.Response('{}', status);
    });

    await Sightpane.close();
  });
}

// The SDK opens a fresh http.Client() for every survey request; inside
// runWithClient that is this mock instead of a real socket, which the test
// binding would answer with 400.
Future<T> withHttp<T>(Future<T> Function() body, MockClientHandler handler) =>
    http.runWithClient(body, () => MockClient(handler));
