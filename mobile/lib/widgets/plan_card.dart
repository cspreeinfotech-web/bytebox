import 'package:flutter/material.dart';

import '../services/json.dart';
import '../theme.dart';
import 'common.dart';

/// One plan row: radio, name, duration label, price (crossed out + FREE when free for this user), badge.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.plan, required this.selected, required this.onTap, this.playStore = false});
  final Json plan;
  final bool selected;
  final VoidCallback onTap;
  final bool playStore;

  @override
  Widget build(BuildContext context) {
    final mode = plan['pay_mode'] as String? ?? 'unavailable';
    final free = mode == 'free';
    final dimmed = mode == 'unavailable' || (mode == 'upi' && playStore);
    final price = '₹ ${plan['price_inr']}';
    return Opacity(
      opacity: dimmed ? 0.7 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(4, 12, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? (free ? AppColors.success : AppColors.primary) : AppColors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(children: [
            Radio<String>(value: '${plan['id']}'),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${plan['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  if (plan['badge'] != null) StatusPill('${plan['badge']}', color: AppColors.accent),
                ]),
                Text('${plan['duration_label'] ?? durationLabel((plan['duration_days'] as num).toInt())}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(price,
                  key: const Key('plan-price'),
                  style: TextStyle(
                    fontSize: free ? 14 : 20,
                    fontWeight: FontWeight.w700,
                    color: free ? AppColors.textMuted : AppColors.text,
                    decoration: free ? TextDecoration.lineThrough : null,
                  )),
              if (free)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(20)),
                  child: const Text('FREE',
                      style: TextStyle(color: AppColors.background, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
