import 'json.dart';

/// Pure rules for the Plans screen (unit-tested). The server decides prices and pay_mode;
/// this only maps what it returned to labels and notices.
class PlanLogic {
  static const plansUpdated = 'Plans were updated';

  static String buttonLabel({
    required Json? plan,
    required bool isGuest,
    required bool playStore,
    required bool busy,
  }) {
    if (plan == null) return 'Select a plan';
    final mode = plan['pay_mode'] as String? ?? 'unavailable';
    if (mode == 'unavailable') return 'Payments unavailable';
    if (mode == 'upi' && playStore) return 'Not available in this version';
    if (busy) return mode == 'free' ? 'Activating…' : 'Opening UPI…';
    if (isGuest) return 'Next';
    return mode == 'free' ? 'Activate for free' : 'Continue to payment';
  }

  static bool canContinue({required Json? plan, required bool playStore, required bool busy}) {
    if (plan == null || busy) return false;
    final mode = plan['pay_mode'];
    if (mode == 'free') return true;
    return mode == 'upi' && !playStore;
  }

  /// After a refresh: returns the new selection (null when the plan disappeared) and a notice
  /// when the selected plan disappeared or its price / duration / pay mode changed.
  static ({Json? selected, String? notice}) reconcile(Json? selected, List<Json> fresh) {
    if (selected == null) return (selected: null, notice: null);
    Json? match;
    for (final p in fresh) {
      if (p['id'] == selected['id']) match = p;
    }
    if (match == null) return (selected: null, notice: plansUpdated);
    final changed = match['price_inr'] != selected['price_inr'] ||
        match['duration_days'] != selected['duration_days'] ||
        match['pay_mode'] != selected['pay_mode'];
    return (selected: match, notice: changed ? plansUpdated : null);
  }

  /// "Price updated to ₹X" when the order's price differs from what the user saw.
  static String? priceNotice(Json shownPlan, Json order) {
    final orderPrice = (order['price_inr'] as num?)?.toInt() ??
        double.tryParse('${order['amount']}')?.round();
    final shown = (shownPlan['price_inr'] as num?)?.toInt();
    if (orderPrice == null || shown == null || orderPrice == shown) return null;
    return 'Price updated to ₹$orderPrice';
  }

  /// Plans to list. In the Play build without Play billing only plans free for this user are shown.
  static List<Json> visiblePlans(List<Json> plans, {required bool hidePaid}) =>
      hidePaid ? plans.where((p) => p['pay_mode'] == 'free').toList() : plans;

  static bool anyFree(List<Json> plans) => plans.any((p) => p['free_for_me'] == true);
}
