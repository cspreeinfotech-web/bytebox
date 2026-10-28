import 'package:bytebox/services/plan_logic.dart';
import 'package:bytebox/theme.dart';
import 'package:bytebox/widgets/plan_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> plan({int id = 3, int price = 259, int days = 30, String mode = 'upi', bool free = false}) => {
      'id': id, 'code': 'gold', 'name': 'Gold', 'price_inr': price, 'duration_days': days,
      'duration_label': '1 month', 'perks': ['Full premium videos'], 'badge': 'Best value',
      'free_for_me': free, 'pay_mode': mode,
    };

Widget host(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: RadioGroup<String>(groupValue: null, onChanged: (_) {}, child: child)),
    );

void main() {
  group('plan card states', () {
    testWidgets('upi: normal price', (t) async {
      await t.pumpWidget(host(PlanCard(plan: plan(), selected: true, onTap: () {})));
      expect(find.text('₹ 259'), findsOneWidget);
      expect(find.text('FREE'), findsNothing);
      final style = t.widget<Text>(find.byKey(const Key('plan-price'))).style!;
      expect(style.decoration, isNot(TextDecoration.lineThrough));
    });

    testWidgets('free: crossed-out price + FREE badge', (t) async {
      await t.pumpWidget(host(PlanCard(plan: plan(mode: 'free', free: true), selected: false, onTap: () {})));
      expect(find.text('FREE'), findsOneWidget);
      final style = t.widget<Text>(find.byKey(const Key('plan-price'))).style!;
      expect(style.decoration, TextDecoration.lineThrough);
    });

    testWidgets('unavailable: price visible, card dimmed', (t) async {
      await t.pumpWidget(host(PlanCard(plan: plan(mode: 'unavailable'), selected: false, onTap: () {})));
      expect(find.text('₹ 259'), findsOneWidget);
      expect(t.widget<Opacity>(find.byType(Opacity).first).opacity, lessThan(1));
    });

    testWidgets('realtime update re-renders the new price', (t) async {
      await t.pumpWidget(host(PlanCard(plan: plan(), selected: true, onTap: () {})));
      await t.pumpWidget(host(PlanCard(plan: plan(price: 299), selected: true, onTap: () {})));
      expect(find.text('₹ 299'), findsOneWidget);
      expect(find.text('₹ 259'), findsNothing);
    });
  });

  group('button labels', () {
    test('per state', () {
      expect(PlanLogic.buttonLabel(plan: null, isGuest: false, playStore: false, busy: false), 'Select a plan');
      expect(PlanLogic.buttonLabel(plan: plan(), isGuest: false, playStore: false, busy: false), 'Continue to payment');
      expect(PlanLogic.buttonLabel(plan: plan(), isGuest: false, playStore: false, busy: true), 'Opening UPI…');
      expect(PlanLogic.buttonLabel(plan: plan(mode: 'free'), isGuest: false, playStore: false, busy: false), 'Activate for free');
      expect(PlanLogic.buttonLabel(plan: plan(mode: 'unavailable'), isGuest: false, playStore: false, busy: false), 'Payments unavailable');
      expect(PlanLogic.buttonLabel(plan: plan(), isGuest: false, playStore: true, busy: false), 'Not available in this version');
      expect(PlanLogic.buttonLabel(plan: plan(mode: 'free'), isGuest: false, playStore: true, busy: false), 'Activate for free');
    });

    test('guest gets Next and can continue (login then the same flow resumes)', () {
      expect(PlanLogic.buttonLabel(plan: plan(), isGuest: true, playStore: false, busy: false), 'Next');
      expect(PlanLogic.buttonLabel(plan: plan(mode: 'free'), isGuest: true, playStore: false, busy: false), 'Next');
      expect(PlanLogic.canContinue(plan: plan(), playStore: false, busy: false), isTrue);
      expect(PlanLogic.canContinue(plan: plan(mode: 'unavailable'), playStore: false, busy: false), isFalse);
      expect(PlanLogic.canContinue(plan: plan(), playStore: true, busy: false), isFalse);
    });
  });

  group('live updates', () {
    test('selected plan changed → notice and refreshed selection', () {
      final r = PlanLogic.reconcile(plan(), [plan(price: 299)]);
      expect(r.notice, PlanLogic.plansUpdated);
      expect(r.selected!['price_inr'], 299);
    });

    test('selected plan hidden → selection cleared', () {
      final r = PlanLogic.reconcile(plan(), [plan(id: 9)]);
      expect(r.selected, isNull);
      expect(r.notice, PlanLogic.plansUpdated);
    });

    test('unchanged → no notice', () {
      expect(PlanLogic.reconcile(plan(), [plan()]).notice, isNull);
    });

    test('order with a new amount → "Price updated to ₹X"', () {
      expect(PlanLogic.priceNotice(plan(), {'price_inr': 299, 'amount': '299.00'}), 'Price updated to ₹299');
      expect(PlanLogic.priceNotice(plan(), {'price_inr': 259, 'amount': '259.00'}), isNull);
    });
  });

  group('Play build without Play billing', () {
    test('only plans free for the user are listed', () {
      final all = [plan(id: 1), plan(id: 2, mode: 'free', free: true), plan(id: 3, mode: 'unavailable')];
      expect(PlanLogic.visiblePlans(all, hidePaid: true).map((p) => p['id']), [2]);
      expect(PlanLogic.visiblePlans(all, hidePaid: false).length, 3);
      expect(PlanLogic.visiblePlans([plan()], hidePaid: true), isEmpty);
    });
  });
}
