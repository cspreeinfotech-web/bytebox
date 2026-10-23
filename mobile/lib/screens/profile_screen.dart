import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show HttpMethod;

import '../services/content.dart';
import '../services/links.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'content/create_channel_screen.dart';
import 'content/my_channels_screen.dart';
import 'login_screen.dart';
import 'payment_screens.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _channels = GlobalKey<MyChannelsListState>();

  @override
  void initState() {
    super.initState();
    session.addListener(_changed);
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: session.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(controller: ctrl, maxLength: 40, autofocus: true,
            decoration: const InputDecoration(labelText: 'Display name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await session.setDisplayName(name);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  String get _memberLine {
    if (session.plan != null) return '${session.plan!['name']} active';
    if (session.isPremium) return 'Full access';
    return 'Free account';
  }

  @override
  Widget build(BuildContext context) {
    final name = session.displayName;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await session.refresh();
          await _channels.currentState?.reload();
        },
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 230,
            title: const Text('Profile'),
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: const BoxDecoration(gradient: AppColors.premiumGradient),
                child: SafeArea(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                      child: CircleAvatar(
                        radius: 38,
                        backgroundColor: AppColors.surfaceHigh,
                        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.text)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Flexible(
                        child: Text(name, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onPrimary)),
                      ),
                      if (session.isPremium) ...[const SizedBox(width: 8), const PremiumBadge(small: true)],
                    ]),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: AppColors.onPrimary),
                        onPressed: _editName,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit name'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: AppColors.onPrimary),
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text('Settings'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                  ]),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(children: [
              if (session.isGuest)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text("You're using the app as a guest.", style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('Create an account to keep your plan, cloud files and channels.',
                          style: TextStyle(color: AppColors.textMuted)),
                      const SizedBox(height: 14),
                      GradientButton(
                        label: 'Log in / Create account',
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                      ),
                    ]),
                  ),
                )
              else
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: Text(session.email ?? ''),
                      subtitle: Text(_memberLine),
                      trailing: session.isPremium ? const Icon(Icons.verified, color: AppColors.premium) : null,
                    ),
                    if (session.ownsApprovedChannel)
                      ListTile(
                        leading: const Icon(Icons.upload_outlined),
                        title: const Text('Upload content'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await UploadPostScreen.open(context);
                          _channels.currentState?.reload();
                        },
                      ),
                    if (!session.noPayments)
                      ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: const Text('Payment history'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const PaymentHistoryScreen())),
                      ),
                  ]),
                ),
              const SizedBox(height: 24),
              Row(children: [
                const Text('My Channels', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    await CreateChannelScreen.open(context);
                    _channels.currentState?.reload();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Channel'),
                ),
              ]),
              const SizedBox(height: 8),
              MyChannelsList(key: _channels),
            ]),
          ),
        ]),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _deleteAccount(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete account?',
      message: 'This permanently deletes your account, cloud files and channels. '
          'Payment records are kept as required by law. This cannot be undone.',
      confirm: 'Delete account',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      final res = await db.functions.invoke('delete-account', method: HttpMethod.post);
      if (res.status != 200) throw Exception((res.data as Map?)?['error'] ?? 'Could not delete account');
      await session.logOut();
      if (context.mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        showSnack(context, 'Your account was deleted.');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(children: [
          ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy Policy'),
              onTap: () => Links.open(Links.privacy)),
          ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Terms of Use'),
              onTap: () => Links.open(Links.terms)),
          ListTile(leading: const Icon(Icons.groups_outlined), title: const Text('Community Guidelines'),
              onTap: () => Links.open(Links.community)),
          ListTile(leading: const Icon(Icons.currency_rupee), title: const Text('Refund Policy'),
              onTap: () => Links.open(Links.refund)),
          ListTile(leading: const Icon(Icons.support_agent), title: const Text('Contact support'),
              onTap: () => Links.mailSupport()),
          ListTile(leading: const Icon(Icons.block), title: const Text('Blocked channels'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _BlockedChannels()))),
          const Divider(),
          if (session.isLoggedIn)
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                final ok = await confirmDialog(context, title: 'Log out?', message: 'You will continue as a guest.',
                    confirm: 'Logout');
                if (!ok) return;
                try {
                  await session.logOut();
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                } catch (e) {
                  if (context.mounted) showSnack(context, friendlyError(e), error: true);
                }
              },
            ),
          if (session.isLoggedIn)
            ListTile(
              leading: const Icon(Icons.delete_forever, color: AppColors.danger),
              title: const Text('Delete Account', style: TextStyle(color: AppColors.danger)),
              onTap: () => _deleteAccount(context),
            ),
        ]),
      );
}

class _BlockedChannels extends StatefulWidget {
  const _BlockedChannels();
  @override
  State<_BlockedChannels> createState() => _BlockedChannelsState();
}

class _BlockedChannelsState extends State<_BlockedChannels> {
  List<Json> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = (await Content.blockedChannels()).toList();
    final rows = ids.isEmpty ? <Json>[] : List<Json>.from(await db.from('channels').select('id, name').inFilter('id', ids));
    if (mounted) {
      setState(() {
        _items = [
          for (final id in ids) rows.firstWhere((r) => r['id'] == id, orElse: () => {'id': id, 'name': 'Unavailable channel'})
        ];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Blocked channels')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const EmptyState()
                : ListView(children: [
                    for (final c in _items)
                      ListTile(
                        title: Text('${c['name']}'),
                        trailing: TextButton(
                          onPressed: () async {
                            await Content.setBlocked('${c['id']}', false);
                            _load();
                          },
                          child: const Text('Unblock'),
                        ),
                      ),
                  ]),
      );
}
