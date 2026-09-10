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
        captureFlutterErrors: false,
        replay: const SightpaneReplayOptions(enabled: false),
      ),
    );
  });

  tearDown(() => Sightpane.close());

  test('default scrub rules redact email, credit card, TCKN, and phone number from breadcrumbs', () async {
    Sightpane.addBreadcrumb(
      SightpaneBreadcrumb(
        category: 'user.input',
        message: 'User email is test.user@example.com and phone is +90 (555) 123-4567',
        data: {
          'tckn': '12345678901',
          'card': '4111 2222 3333 4444',
          'safe': 'normal text',
        },
      ),
    );

    await Sightpane.flush();
    final item = t.ofType('breadcrumb').single;
    expect(item.body['message'], 'User email is [EMAIL] and phone is [PHONE]');
    final data = item.body['data'] as Map;
    expect(data['tckn'], '[TCKN]');
    expect(data['card'], '[CARD]');
    expect(data['safe'], 'normal text');
  });

  test('default scrub rules redact PII from error messages and context', () async {
    Sightpane.captureException(
      Exception('Payment failed for card 4111222233334444 and email customer@domain.org'),
      context: {
        'phone': '0532 999 8888',
        'national_id': '98765432109',
      },
    );

    await Sightpane.flush();
    final item = t.ofType('error').single;
    expect(item.body['message'], 'Exception: Payment failed for card [CARD] and email [EMAIL]');
    final ctx = item.body['context'] as Map;
    expect(ctx['phone'], '[PHONE]');
    expect(ctx['national_id'], '[TCKN]');
  });

  test('default scrub rules redact PII from captureMessage and props', () async {
    Sightpane.captureMessage('Contact me at alice.smith@mail.co.uk');
    Sightpane.setProperty('contact', 'Call +1 (800) 555-0199');

    await Sightpane.flush();
    final item = t.ofType('error').single;
    expect(item.body['message'], 'Contact me at [EMAIL]');
    expect(Sightpane.client.session.props['contact'], 'Call [PHONE]');
  });
}
