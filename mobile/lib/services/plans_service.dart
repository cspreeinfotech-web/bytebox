import 'json.dart';
import 'session.dart';

/// Everything about plans comes from the server: plans_for_me() and claim_free_plan().
class PlansService {
  static Future<List<Json>> plansForMe() async {
    final rows = await db.rpc('plans_for_me');
    return List<Json>.from((rows as List).map((r) => (r as Map).cast<String, dynamic>()));
  }

  static Future<Json> claimFree(int planId) async {
    final r = await db.rpc('claim_free_plan', params: {'p_plan_id': planId});
    return (r as Map).cast<String, dynamic>();
  }
}
