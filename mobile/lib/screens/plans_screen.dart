import 'package:flutter/material.dart';

import '../config.dart';
import '../services/native.dart';
import '../services/payments.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'login_screen.dart';
import 'payment_screens.dart';
import 'profile_screen.dart';

/// Opens Plans; resolves true when a purchase activated Premium.
Future<bool> openPlans(BuildContext context) async {
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PlansScreen()));
  return r == true;
}

/// Plans screen. Also the Profile tab (asTab) — profile page opens from the account icon.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, this.asTab = false});
  final bool asTab;
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  String? _selected;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    session.addListener(_changed);
    session.refresh().catchError((_) {});
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_selected != null && !session.plans.any((p) => p['code'] == _selected)) _selected = null;
    setState(() {});
  }

  String get _buttonLabel {
    if (_opening) return 'Opening UPI…';
    if (_selected == null) return 'Select a plan';
    return session.isGuest ? 'Next' : 'Continue to payment';
  }

  Future<void> _continue() async {
    if (_selected == null) return;
    if (session.isGuest) {
      final ok = await requireLogin(context, message: 'Log in or create an account to buy a plan.');
      if (!ok || !mounted) return; // after login we come back here with the plan selected and continue
    }
    setState(() => _opening = true);
    try {
      final order = await Payments.createOrder(_selected!);
      if (!mounted) return;
      // Same-plan open order that's already being verified → show its status instead of paying again.
      if (order['reused'] == true && order['status'] == 'pending') {
        setState(() => _opening = false);
        await _openStatus('${order['order_id']}');
        return;
      }
      final result = await Payments.pay(order);
      if (!mounted) return;
      setState(() => _opening = false);
      await _openStatus('${result['order_id']}');
    } on UpiLaunchException catch (e) {
      if (mounted) showSnack(context, e.noUpiApp ? 'No UPI app found' : e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _opening = false);
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
    if (order != null && !session.noPayments) {
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
    final free = session.noPayments;
    final perks = const ['Full premium videos', '2 TB cloud storage', 'Downloads', 'Early access to new channels'];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.asTab,
        title: const Text('Premium'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined, size: 28),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await session.refresh();
          await session.loadPlans();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
          _banner(),
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.premiumGradient,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
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
          if (free) const FreeAccountCard() else ..._planCards(),
        ]),
      ),
      bottomNavigationBar: free
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: GradientButton(
                  label: _buttonLabel,
                  busy: false,
                  onPressed: _selected == null || _opening ? null : _continue,
                ),
              ),
            ),
    );
  }

  List<Widget> _planCards() {
    if (session.plans.isEmpty) return [const EmptyState(text: 'No plans available right now')];
    return [
      RadioGroup<String>(
        groupValue: _selected,
        onChanged: (v) => setState(() => _selected = v),
        child: Column(children: [
          for (final p in session.plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () => setState(() => _selected = '${p['code']}'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.fromLTRB(4, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color: _selected == p['code'] ? AppColors.primary : AppColors.outline,
                      width: _selected == p['code'] ? 2 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Radio<String>(value: '${p['code']}'),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('${p['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          if (p['badge'] != null) ...[
                            const SizedBox(width: 8),
                            StatusPill('${p['badge']}', color: AppColors.accent),
                          ],
                        ]),
                        Text(durationLabel((p['duration_days'] as num).toInt()),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ]),
                    ),
                    Text('₹ ${p['price_inr']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      const Text('Pay securely with any UPI app. Your plan starts as soon as the payment is confirmed.',
          textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
    ];
  }
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

  @override
  Widget build(BuildContext context) {
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
