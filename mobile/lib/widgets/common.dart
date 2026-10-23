import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : AppColors.surfaceHigh,
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: destructive ? TextButton.styleFrom(foregroundColor: AppColors.danger) : null,
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

String formatInr(num rupees) => '₹${NumberFormat('#,##,##0', 'en_IN').format(rupees)}';

String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final d = Duration(seconds: seconds);
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

String formatDate(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '' : DateFormat('d MMM yyyy, h:mm a').format(d);
}

String durationLabel(int days) {
  if (days % 365 == 0) return days == 365 ? '1 year' : '${days ~/ 365} years';
  if (days == 180) return '6 months';
  if (days % 30 == 0) return days == 30 ? '1 month' : '${days ~/ 30} months';
  if (days % 7 == 0) return days == 7 ? '1 week' : '${days ~/ 7} weeks';
  return '$days days';
}

class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, this.onPressed, this.icon, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Material(
          color: AppColors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.button),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 48,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, color: AppColors.onPrimary, size: 20), const SizedBox(width: 8)],
                        Text(label,
                            style: const TextStyle(
                                color: AppColors.onPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.label = 'Premium', this.small = false});
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(color: AppColors.premium, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.workspace_premium, size: small ? 12 : 15, color: AppColors.background),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                color: AppColors.background, fontSize: small ? 10 : 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class CrownButton extends StatelessWidget {
  const CrownButton({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Premium',
        onPressed: onTap,
        icon: const Icon(Icons.workspace_premium, color: AppColors.premium),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.text = 'No Record Found', this.icon = Icons.inbox_outlined, this.action});
  final String text;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
        text: message,
        icon: Icons.cloud_off_outlined,
        action: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset('assets/icon/icon.png', width: size, height: size),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
