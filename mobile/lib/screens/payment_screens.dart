import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/native.dart';
import '../services/payments.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Pops `true` once the order is successful.
class PaymentStatusScreen extends StatefulWidget {
  const PaymentStatusScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen> with WidgetsBindingObserver {
  Json? _order;
  Timer? _poll;
  final _started = DateTime.now();
  bool _checking = false;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(_started) > const Duration(minutes: 10)) {
        _poll?.cancel();
        return;
      }
      final s = _order?['status'];
      if (s == 'initiated' || s == 'pending' || s == null) _check(quiet: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check(quiet: true);
  }

  Future<void> _check({bool quiet = false}) async {
    if (_checking) return;
    if (!quiet) setState(() => _checking = true);
    try {
      await Payments.flushSavedResults();
      final o = await Payments.order(widget.orderId);
      if (!mounted) return;
      final wasSuccess = _order?['status'] == 'success';
      setState(() => _order = o);
      if (o?['status'] == 'success' && !wasSuccess) await session.refresh();
    } catch (e) {
      if (mounted && !quiet) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _payAgain() async {
    final code = _order?['plan_code'] as String?;
    if (code == null) return;
    setState(() => _paying = true);
    try {
      final order = await Payments.createOrder(code);
      final r = await Payments.pay(order);
      if (!mounted) return;
      if (r['order_id'] != widget.orderId) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: '${r['order_id']}')));
        return;
      }
      setState(() => _order = r);
      if (r['status'] == 'success') await session.refresh();
    } on UpiLaunchException catch (e) {
      if (mounted) showSnack(context, e.noUpiApp ? 'No UPI app found' : e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  ({IconData icon, Color color, String title, String body}) get _view {
    switch (_order?['status']) {
      case 'success':
        return (icon: Icons.check_circle, color: AppColors.success, title: 'Payment successful!',
            body: 'Your plan is now active.');
      case 'pending':
        return (icon: Icons.hourglass_top, color: AppColors.warning, title: 'Checking your payment…',
            body: 'We are verifying this payment. This screen updates by itself.');
      case 'failed':
        return (icon: Icons.cancel, color: AppColors.danger, title: 'Payment failed',
            body: 'Your UPI app reported that the payment failed. No plan was activated.');
      case 'cancelled':
        return (icon: Icons.block, color: AppColors.textMuted, title: 'Order cancelled',
            body: 'This order was closed. You can start a new payment from Plans.');
      case 'revoked':
        return (icon: Icons.gpp_bad, color: AppColors.danger, title: 'Payment reversed',
            body: 'This payment was reversed after review. Contact support if you think this is wrong.');
      case 'initiated':
        return (icon: Icons.info_outline, color: AppColors.warning, title: 'Payment not completed',
            body: 'We did not receive a confirmation from your UPI app.');
      default:
        return (icon: Icons.sync, color: AppColors.textMuted, title: 'Loading…', body: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final v = _view;
    final status = o?['status'];
    final success = status == 'success';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, success);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payment status'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, success)),
        ),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const SizedBox(height: 12),
          Icon(v.icon, size: 72, color: v.color),
          const SizedBox(height: 12),
          Text(v.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(v.body, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          if (status == 'pending') ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 24),
          if (o != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _row('Order number', SelectableText('${o['reference']}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                      copy: '${o['reference']}'),
                  const Divider(height: 20),
                  _row('Plan', Text('${o['plan_name']}')),
                  const Divider(height: 20),
                  _row('Amount', Text(formatInr(num.parse('${o['amount']}')))),
                ]),
              ),
            ),
          const SizedBox(height: 12),
          if (!success)
            const Text('If money was taken, keep this order number; we will verify it.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 20),
          if (!success) ...[
            OutlinedButton.icon(
              onPressed: _checking ? null : _check,
              icon: _checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: const Text('Check payment status'),
            ),
            const SizedBox(height: 10),
          ],
          if (status == 'initiated' || status == 'failed') ...[
            GradientButton(label: _paying ? 'Opening UPI…' : 'Pay again', busy: _paying, onPressed: _payAgain),
            const SizedBox(height: 10),
          ],
          success
              ? GradientButton(label: 'Done', onPressed: () => Navigator.pop(context, true))
              : TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back to plans')),
        ]),
      ),
    );
  }

  Widget _row(String label, Widget value, {String? copy}) => Row(children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted)),
        const Spacer(),
        value,
        if (copy != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copy));
              showSnack(context, 'Order number copied');
            },
          ),
      ]);
}

class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key});

  static Color statusColor(String s) => switch (s) {
        'success' => AppColors.success,
        'pending' || 'initiated' => AppColors.warning,
        'failed' || 'revoked' => AppColors.danger,
        _ => AppColors.textMuted,
      };

  static String statusLabel(String s) => switch (s) {
        'success' => 'Paid',
        'pending' => 'Checking',
        'initiated' => 'Not completed',
        'failed' => 'Failed',
        'cancelled' => 'Cancelled',
        'revoked' => 'Reversed',
        _ => s,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payment history')),
        body: FutureBuilder<List<Json>>(
          future: Payments.history(),
          builder: (c, s) {
            if (s.hasError) return EmptyState(text: friendlyError(s.error!));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            if (s.data!.isEmpty) return const EmptyState();
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: s.data!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (c, i) {
                final o = s.data![i];
                final st = '${o['status']}';
                return Card(
                  child: ListTile(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: '${o['id']}'))),
                    title: Text('${o['plan_name']} · ${formatInr((o['amount_paise'] as num) / 100)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${o['reference']}\n${formatDate(o['created_at'] as String?)}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    isThreeLine: true,
                    trailing: StatusPill(statusLabel(st), color: statusColor(st)),
                  ),
                );
              },
            );
          },
        ),
      );
}
