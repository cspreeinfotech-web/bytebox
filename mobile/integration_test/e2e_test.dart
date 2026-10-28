// End-to-end run on an emulator against the real backend with seeded demo data.
// Flow (direct ads build): guest → consent → Explore → premium post → trailer → "Enjoyed the trailer?" →
// subscribe → login → Plans → ₹49 Trial → UPI (no UPI app on emulator) → simulated UPI SUCCESS → activation.
// Flow (play build): login → Cloud (15 GB, folders/files) → Plans tab (Free account card) → Profile.
import 'package:bytebox/config.dart';
import 'package:bytebox/main.dart' as app;
import 'package:bytebox/screens/payment_screens.dart';
import 'package:bytebox/services/payments.dart';
import 'package:bytebox/services/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const demoEmail = String.fromEnvironment('DEMO_VIEWER_EMAIL');
const demoPassword = String.fromEnvironment('DEMO_PASSWORD');
const premiumTitle = String.fromEnvironment('DEMO_PREMIUM_TITLE', defaultValue: 'Goa Sunset Timelapse');
const shotPrefix = String.fromEnvironment('SHOT_PREFIX', defaultValue: 'phone');

late IntegrationTestWidgetsFlutterBinding binding;

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 45)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 300));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $f');
}

Future<void> settle(WidgetTester t, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// The host (tools/e2e/run.sh) watches for this marker and grabs the screen with `adb screencap`.
/// (Flutter's in-process screenshot crashes the emulator's software GPU on phone profiles.)
Future<void> shot(WidgetTester t, String name) async {
  await settle(t, 1200);
  // Never accept a screen that shows a load error (e.g. a missing database function).
  expect(find.text('Retry'), findsNothing, reason: 'error screen at $name');
  expect(find.textContaining('schema cache'), findsNothing, reason: 'server error at $name');
  // ignore: avoid_print
  print('E2E_SHOT:${shotPrefix}_$name');
  await settle(t, 2500);
}

Future<void> boot(WidgetTester t) async {
  app.main();
  final agree = find.text('Agree & continue');
  final explore = find.text('Latest');
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 300));
    if (agree.evaluate().isNotEmpty) {
      await shot(t, 'e2e-01-consent');
      await t.tap(agree);
      break;
    }
    if (explore.evaluate().isNotEmpty) break;
  }
  await pumpUntil(t, explore);
}

Future<void> login(WidgetTester t) async {
  await pumpUntil(t, find.widgetWithText(TextFormField, 'Email'));
  await t.enterText(find.widgetWithText(TextFormField, 'Email'), demoEmail);
  await t.enterText(find.widgetWithText(TextFormField, 'Password'), demoPassword);
  await t.tap(find.text('Log in').last);
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bytebox end-to-end', (t) async {
    await boot(t);
    expect(session.isGuest, isTrue);

    if (!AppConfig.playStore) {
      // ----------------------------------------------------- ads build: trailer → subscribe → pay
      await pumpUntil(t, find.text(premiumTitle));
      await shot(t, '3-explore');

      await t.tap(find.text(premiumTitle).first);
      await pumpUntil(t, find.text('Trailer'));
      await shot(t, '4-post');

      await t.tap(find.text('Trailer'));
      await settle(t, 1800);
      await shot(t, '5-player');
      await pumpUntil(t, find.text('Enjoyed the trailer?'), timeout: const Duration(seconds: 30));
      await shot(t, 'e2e-02-trailer-end');
      await t.tap(find.text('Subscribe'));

      await pumpUntil(t, find.text('Please log in'));
      await t.tap(find.text('Log in').last);
      await login(t);

      await pumpUntil(t, find.text('Trial'));
      await t.tap(find.text('Trial'));
      await settle(t);
      await shot(t, '2-plans');

      // Emulators have no UPI app: the chooser either opens empty or reports "No UPI app found".
      // Simulate the UPI app's SUCCESS answer for a fresh ₹49 order through the same server path.
      final order = await Payments.createOrderByCode('trial');
      final ref = order['reference'];
      await db.rpc('report_payment_result', params: {
        'p_order_id': order['order_id'],
        'p_raw_response': 'txnId=E2E$ref&responseCode=00&Status=SUCCESS&txnRef=$ref&ApprovalRefNo=E2E${ref.toString().substring(8)}',
      });
      final nav = app.navigatorKey.currentState!;
      nav.push(MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: '${order['order_id']}')));
      await pumpUntil(t, find.text('Payment successful!'));
      await shot(t, 'e2e-03-payment-success');
      expect(session.isPremium, isTrue);
      await t.tap(find.text('Done'));
      await settle(t);
      // Leaving Plans returns to the post: premium is active now, so the full video auto-plays.
      await t.pageBack();
      await settle(t, 4000);
      await shot(t, 'e2e-04-full-video');
    } else {
      // ----------------------------------------------------- play build: cloud + free account
      await t.tap(find.text('Profile').last);
      await pumpUntil(t, find.byIcon(Icons.account_circle_outlined));
      await t.tap(find.byIcon(Icons.account_circle_outlined));
      await pumpUntil(t, find.text('Log in / Create account'));
      await t.tap(find.text('Log in / Create account').first);
      await login(t);
      await pumpUntil(t, find.text('My Channels'));
      await settle(t, 2500);
      await shot(t, '6-profile');
      await t.pageBack();
      await settle(t);
      expect(find.text('Log in to get free cloud storage.'), findsNothing, reason: 'account card must refresh after login');
      await shot(t, '2-plans');

      await t.tap(find.text('Cloud').last);
      await pumpUntil(t, find.text('Photos'));
      await shot(t, '1-cloud');

      await t.tap(find.text('Explore').last);
      await pumpUntil(t, find.text('Latest'));
      await pumpUntil(t, find.text('Hidden Waterfalls of Kerala')); // a free demo video must be listed
      await shot(t, '3-explore');
      await t.tap(find.text('Channels').last);
      await settle(t, 3000);
      await shot(t, '5-channels');
      await t.tap(find.text('Feed').last);
      await settle(t, 3000);
      await shot(t, '4-feed');
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
