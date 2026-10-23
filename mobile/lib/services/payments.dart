import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'native.dart';
import 'session.dart';

import 'json.dart';
export 'json.dart';


/// UPI flow: create order → open UPI chooser → save raw answer immediately (survives kill) →
/// report to server with retries (also on next start) → delete saved copy.
class Payments {
  static const _prefix = 'upi_result_';

  static void install() {
    session.afterAuthHooks.add(flushSavedResults);
  }

  /// Server copies price, duration and the current UPI account into the order.
  static Future<Json> createOrder(int planId) async {
    final r = await db.rpc('create_payment_order', params: {'p_plan_id': planId});
    return (r as Map).cast<String, dynamic>();
  }

  /// For orders that only know their plan code (older orders).
  static Future<Json> createOrderByCode(String planCode) async {
    final r = await db.rpc('create_payment_order', params: {'p_plan_code': planCode});
    return (r as Map).cast<String, dynamic>();
  }

  static String upiUri(Json order) {
    final ref = order['reference'] as String;
    return 'upi://pay?pa=${order['upi_id']}'
        '&pn=${Uri.encodeComponent(order['payee_name'] as String)}'
        '&tr=$ref'
        '&am=${order['amount']}'
        '&cu=INR'
        '&tn=${Uri.encodeComponent('${AppConfig.appName} $ref')}';
  }

  /// Opens UPI for [order] and returns the server's view of the order afterwards.
  static Future<Json> pay(Json order) async {
    final orderId = order['order_id'] as String;
    final raw = await Native.payUpi(upiUri(order)); // throws UpiLaunchException
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$orderId', raw);
    return _report(orderId, raw);
  }

  static Future<Json> _report(String orderId, String raw) async {
    Object? last;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final r = await db.rpc('report_payment_result', params: {'p_order_id': orderId, 'p_raw_response': raw});
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('$_prefix$orderId');
        return (r as Map).cast<String, dynamic>();
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    throw last ?? Exception('Could not reach the server');
  }

  /// Retries any UPI answers saved before the app was killed or went offline.
  static Future<void> flushSavedResults() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      final raw = prefs.getString(k) ?? '';
      try {
        await db.rpc('report_payment_result', params: {'p_order_id': k.substring(_prefix.length), 'p_raw_response': raw});
        await prefs.remove(k);
      } catch (e) {
        // Order belongs to another account or does not exist any more → drop it; network errors → keep.
        if ('$e'.contains('Order not found')) await prefs.remove(k);
      }
    }
  }

  static Future<Json?> order(String id) async {
    final r = await db.rpc('get_payment_order', params: {'p_order_id': id});
    return (r as Map?)?.cast<String, dynamic>();
  }

  static Future<List<Json>> history() async => List<Json>.from(await db
      .from('payment_orders')
      .select('id, reference, plan_name, amount_paise, status, created_at, paid_at, reason')
      .eq('user_id', session.user?.id ?? '')
      .order('created_at', ascending: false)
      .limit(100));
}
