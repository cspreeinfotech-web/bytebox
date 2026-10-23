import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// Opens Plans; resolves true when a purchase activated Premium. (Full screen in Stage 6.)
Future<bool> openPlans(BuildContext context) async {
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PlansScreen()));
  return r == true;
}

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key, this.asTab = false});
  final bool asTab;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Premium')),
        body: const EmptyState(text: 'Plans arrive in the next stage.', icon: Icons.workspace_premium_outlined),
      );
}
