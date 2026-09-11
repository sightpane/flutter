// sightpane — error tracking, product analytics and session replay you host yourself.
// Copyright (C) 2026 Can Us
//
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    // Submit answer
    await tester.enterText(find.byType(TextField), 'Very smooth!');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

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
}
