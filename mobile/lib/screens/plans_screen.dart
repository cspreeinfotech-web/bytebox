import 'package:flutter/material.dart';

import '../config.dart';
import '../services/native.dart';
import '../services/payments.dart';
import '../services/plan_logic.dart';
import '../services/plans_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/plan_card.dart';
import 'login_screen.dart';
import 'payment_screens.dart';
import 'profile_screen.dart';

/// Opens Plans; resolves true when a purchase or free claim activated Premium.
Future<bool> openPlans(BuildContext context) async {
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PlansScreen()));
  return r == true;
}

/// Plans screen (also the Profile tab). Everything shown comes from plans_for_me() and refreshes on open,
/// pull-to-refresh, app resume and every Realtime change of plans / app mode / payment settings.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, this.asTab = false});
  final bool asTab;
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> with WidgetsBindingObserver {
  List<Json> _plans = [];
  Json? _selected;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _seenVersion = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.addListener(_sessionChanged);
    _seenVersion = session.settingsVersion;
    _load();
    session.refresh().catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(quiet: true);
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (session.settingsVersion != _seenVersion) {
      _seenVersion = session.settingsVersion;
      _load(quiet: true);
    }
    setState(() {});
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final fresh = await PlansService.plansForMe();
      if (!mounted) return;
      final r = PlanLogic.reconcile(_selected, PlanLogic.visiblePlans(fresh, hidePaid: session.hidePaid));
      setState(() {
        _plans = PlanLogic.visiblePlans(fresh, hidePaid: session.hidePaid);
        _selected = r.selected;
        _error = null;
      });
      if (r.notice != null) showSnack(context, r.notice!);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continue() async {
    final plan = _selected;
    if (plan == null) return;
    if (session.isGuest) {
      final ok = await requireLogin(context, message: 'Log in or create an account to get this plan.');
      if (!ok || !mounted) return;
      // Back with the same plan selected: refresh (eligibility may differ for this account) and continue.
      await _load(quiet: true);
      if (!mounted || _selected == null) return;
    }
    final current = _selected!;
    if (!PlanLogic.canContinue(plan: current, playStore: AppConfig.playStore, busy: false)) return;
    if (current['pay_mode'] == 'free') {
      await _claimFree(current);
    } else {
      await _payUpi(current);
    }
  }

  Future<void> _claimFree(Json plan) async {
    setState(() => _busy = true);
    try {
      final r = await PlansService.claimFree((plan['id'] as num).toInt());
      await session.refresh();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreeClaimSuccessScreen(result: r)));
      if (mounted && !widget.asTab) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      _load(quiet: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payUpi(Json plan) async {
    setState(() => _busy = true);
    try {
      final order = await Payments.createOrder((plan['id'] as num).toInt());
      if (!mounted) return;
      final notice = PlanLogic.priceNotice(plan, order);
      if (notice != null) {
        final go = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(notice),
            content: Text('${order['plan_name']} is now ₹${order['price_inr']} for ${order['duration_days']} days.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
            ],
          ),
        );
        _load(quiet: true);
        if (go != true || !mounted) return;
      }
      if (order['reused'] == true && order['status'] == 'pending') {
        await _openStatus('${order['order_id']}');
        return;
      }
      final result = await Payments.pay(order); // UPI ID / payee come from the order, never cached
      if (!mounted) return;
      setState(() => _busy = false);
      await _openStatus('${result['order_id']}');
    } on UpiLaunchException catch (e) {
      if (mounted) showSnack(context, e.noUpiApp ? 'No UPI app found' : e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      _load(quiet: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openStatus(String orderId) async {
    final activated = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: orderId)));
    await session.refresh();
    if (activated == true && mounted && !widget.asTab) Navigator.pop(context, true);
  }

  Widget _banner() {
    final plan = session.plan;
    final order = session.openOrder;
    if (plan != null) {
      return _Banner(
        color: AppColors.success,
        icon: Icons.verified,
        text: '${plan['name']} active until ${formatDate(plan['ends_at'] as String?)}',
      );
    }
    if (order != null && !session.freeMode && !AppConfig.playStore) {
      return _Banner(
        color: AppColors.warning,
        icon: Icons.hourglass_top,
        text: 'Payment for ${order['plan_name']} (${formatInr(num.parse('${order['amount']}'))}) is not finished. Tap to check.',
        onTap: () => _openStatus('${order['order_id']}'),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final freeMode = session.freeMode;
    final perks = const ['Full premium videos', '2 TB cloud storage', 'Downloads', 'Early access to new channels'];
    final anyFree = PlanLogic.anyFree(_plans);
    final unavailable = _plans.isNotEmpty && _plans.every((p) => p['pay_mode'] == 'unavailable');
    // Play build without Play billing and nothing free to claim: this is just the account page.
    final accountOnly = session.hidePaid && _plans.isEmpty && !_loading;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.asTab,
        title: Text(accountOnly ? 'Account' : 'Premium'),
        actions: [
          IconButton(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined, size: 28),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await session.refresh();
          await _load(quiet: true);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
          _banner(),
          if (!freeMode && anyFree)
            const _Banner(color: AppColors.success, icon: Icons.card_giftcard, text: 'Plans are free for you for a limited time'),
          if (!accountOnly) Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: AppColors.premiumGradient, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.workspace_premium, color: AppColors.premium, size: 30),
                SizedBox(width: 8),
                Text('${AppConfig.appName} Premium',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onPrimary)),
              ]),
              const SizedBox(height: 12),
              for (final p in perks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.check_circle, size: 18, color: AppColors.premium),
                    const SizedBox(width: 8),
                    Text(p, style: const TextStyle(color: AppColors.onPrimary)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          if (freeMode || AppConfig.playStore) ...[const FreeAccountCard(), const SizedBox(height: 18)],
          if (!freeMode) ..._planCards(unavailable),
        ]),
      ),
      bottomNavigationBar: freeMode || _plans.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: GradientButton(
                  label: PlanLogic.buttonLabel(
                      plan: _selected, isGuest: session.isGuest, playStore: AppConfig.playStore, busy: _busy),
                  onPressed: PlanLogic.canContinue(plan: _selected, playStore: AppConfig.playStore, busy: _busy)
                      ? _continue
                      : null,
                ),
              ),
            ),
    );
  }

  List<Widget> _planCards(bool unavailable) {
    if (_loading && _plans.isEmpty) {
      return const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))];
    }
    if (_error != null && _plans.isEmpty) return [ErrorRetry(message: _error!, onRetry: _load)];
    if (_plans.isEmpty) return session.hidePaid ? const [] : [const EmptyState(text: 'No plans available right now')];
    return [
      RadioGroup<String>(
        groupValue: _selected == null ? null : '${_selected!['id']}',
        onChanged: (v) => setState(() => _selected = _plans.firstWhere((p) => '${p['id']}' == v)),
        child: Column(children: [
          for (final p in _plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PlanCard(
                plan: p,
                playStore: AppConfig.playStore,
                selected: _selected?['id'] == p['id'],
                onTap: () => setState(() => _selected = p),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      if (!session.hidePaid) Text(
        unavailable
            ? 'Payments are paused. Please try again later.'
            : 'Pay securely with any UPI app. Your plan starts as soon as the payment is confirmed.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    ];
  }
}

/// Shown after a successful free claim.
class FreeClaimSuccessScreen extends StatelessWidget {
  const FreeClaimSuccessScreen({super.key, required this.result});
  final Json result;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.celebration, size: 80, color: AppColors.success),
            const SizedBox(height: 16),
            Text('Your ${result['plan_name']} is active until ${formatDate(result['ends_at'] as String?)}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Enjoy full premium videos, 2 TB cloud and downloads.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 28),
            GradientButton(label: 'Done', onPressed: () => Navigator.pop(context)),
          ]),
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text, this.onTap});
  final Color color;
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
              if (onTap != null) Icon(Icons.chevron_right, color: color),
            ]),
          ),
        ),
      );
}

/// Free mode / Play build: no plans, no prices — cloud usage, access status, Request full access.
class FreeAccountCard extends StatefulWidget {
  const FreeAccountCard({super.key});
  @override
  State<FreeAccountCard> createState() => _FreeAccountCardState();
}

class _FreeAccountCardState extends State<FreeAccountCard> {
  bool _busy = false;

  // `const FreeAccountCard()` is not rebuilt by its parent, so it listens to the session itself
  // (otherwise it keeps showing "Log in" after the user has logged in).
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: session, builder: (context, _) => _card(context));

  Widget _card(BuildContext context) {
    final quota = session.quotaBytes;
    final used = session.usedBytes;
    final status = session.accessStatus;
    final full = session.hasAdsAccess;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Free account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (session.isGuest) ...[
            const Text('Log in to get free cloud storage.', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            GradientButton(
                label: 'Log in / Create account', onPressed: () async {
                  await requireLogin(context);
                  if (mounted) setState(() {});
                }),
          ] else ...[
            Text(quota > 0 ? 'Cloud: ${formatBytes(used)} of ${formatBytes(quota)} used' : 'Cloud storage not available',
                style: const TextStyle(color: AppColors.textMuted)),
            if (quota > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: (used / quota).clamp(0, 1).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(6)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              const Text('Access: '),
              full
                  ? const StatusPill('Full access', color: AppColors.success)
                  : switch (status) {
                      'pending' => const StatusPill('Request pending', color: AppColors.warning),
                      'rejected' => const StatusPill('Not approved', color: AppColors.danger),
                      _ => const StatusPill('Standard', color: AppColors.textMuted),
                    },
            ]),
            if (!full && status != 'pending') ...[
              const SizedBox(height: 14),
              GradientButton(
                label: 'Request full access',
                busy: _busy,
                onPressed: () async {
                  setState(() => _busy = true);
                  try {
                    await session.requestFullAccess();
                    if (context.mounted) showSnack(context, 'Request sent. We will review it soon.');
                  } catch (e) {
                    if (context.mounted) showSnack(context, friendlyError(e), error: true);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
              ),
            ],
          ],
        ]),
      ),
    );
  }
}
