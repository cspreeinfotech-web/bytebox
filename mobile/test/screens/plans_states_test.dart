@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:bytebox/services/plan_logic.dart';
import 'package:bytebox/theme.dart';
import 'package:bytebox/widgets/common.dart';
import 'package:bytebox/widgets/plan_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the Plans screen states with real widgets and saves PNGs to docs/live-controls/
/// (run with: flutter test --tags screenshots --update-goldens).
List<Map<String, dynamic>> plans(String Function(String code) mode) => [
      for (final p in [
        ['trial', 'Trial', 49, 7, '1 week', null],
        ['silver', 'Silver', 129, 7, '1 week', null],
        ['gold', 'Gold', 259, 30, '1 month', 'Best value'],
        ['platinum', 'Platinum', 599, 180, '6 months', null],
        ['diamond', 'Diamond', 999, 365, '1 year', null],
      ])
        {
          'id': p[0].hashCode, 'code': p[0], 'name': p[1], 'price_inr': p[2], 'duration_days': p[3],
          'duration_label': p[4], 'badge': p[5], 'pay_mode': mode(p[0] as String),
          'free_for_me': mode(p[0] as String) == 'free',
        }
    ];

Widget screen(List<Map<String, dynamic>> items, {String? note, bool freeBanner = false}) {
  final selected = items[2];
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: Scaffold(
      appBar: AppBar(title: const Text('Premium'), actions: const [
        Padding(padding: EdgeInsets.all(12), child: Icon(Icons.account_circle_outlined, size: 28)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (freeBanner)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.button)),
            child: const Row(children: [
              Icon(Icons.card_giftcard, color: AppColors.success),
              SizedBox(width: 10),
              Text('Plans are free for you for a limited time',
                  style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
            ]),
          ),
        RadioGroup<String>(
          groupValue: '${selected['id']}',
          onChanged: (_) {},
          child: Column(children: [
            for (final p in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PlanCard(plan: p, selected: p == selected, onTap: () {}),
              ),
          ]),
        ),
        if (note != null)
          Text(note, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: GradientButton(
            label: PlanLogic.buttonLabel(plan: selected, isGuest: false, playStore: false, busy: false),
            onPressed: PlanLogic.canContinue(plan: selected, playStore: false, busy: false) ? () {} : null,
          ),
        ),
      ),
    ),
  );
}

Future<void> loadFonts() async {
  final loader = FontLoader('Poppins');
  for (final f in ['Regular', 'Medium', 'Bold']) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$f.ttf').readAsBytesSync())));
  }
  await loader.load();
  final icons = FontLoader('MaterialIcons');
  final path = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(path).existsSync()) {
    icons.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    await icons.load();
  }
}

void main() {
  setUpAll(loadFonts);

  Future<void> capture(WidgetTester t, Widget w, String name) async {
    t.view.physicalSize = const Size(1080, 2160);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);
    await t.pumpWidget(w);
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../../docs/live-controls/app-plans-$name.png'));
  }

  testWidgets('upi', (t) => capture(t, screen(plans((_) => 'upi'),
      note: 'Pay securely with any UPI app. Your plan starts as soon as the payment is confirmed.'), 'upi'));
  testWidgets('free for organic', (t) => capture(t, screen(plans((c) => c == 'diamond' ? 'upi' : 'free'), freeBanner: true), 'free'));
  testWidgets('unavailable', (t) => capture(t, screen(plans((_) => 'unavailable'),
      note: 'Payments are paused. Please try again later.'), 'unavailable'));
}
