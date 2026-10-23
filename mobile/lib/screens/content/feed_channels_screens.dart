import 'package:flutter/material.dart';

import '../../services/content.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/post_card.dart';
import '../plans_screen.dart';
import 'channel_screen.dart';
import 'create_channel_screen.dart';
import 'post_screen.dart';

/// Feed: newest posts from channels the user joined.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<List<Json>> _future = Content.posts(feed: true, limit: 50);

  Future<void> _reload() async {
    setState(() => _future = Content.posts(feed: true, limit: 50));
    await _future.catchError((_) => <Json>[]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Feed'), actions: [CrownButton(onTap: () => openPlans(context))]),
        body: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<Json>>(
            future: _future,
            builder: (c, s) {
              if (s.hasError) return ErrorRetry(message: friendlyError(s.error!), onRetry: _reload);
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final posts = s.data!;
              if (posts.isEmpty) {
                return ListView(children: const [
                  SizedBox(height: 80),
                  EmptyState(
                    text: 'Join channels to see their newest posts here.',
                    icon: Icons.dynamic_feed_outlined,
                  ),
                ]);
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: posts.length,
                itemBuilder: (c, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: PostCard(post: posts[i], onTap: () => PostScreen.open(context, '${posts[i]['id']}')),
                ),
              );
            },
          ),
        ),
      );
}

/// Channels tab: approved channels the user can see, join/leave, Add Channel.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});
  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<Json>? _channels;
  Set<String> _joined = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Content.channels(), Content.joinedIds()]);
      if (!mounted) return;
      setState(() {
        _channels = r[0] as List<Json>;
        _joined = r[1] as Set<String>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _toggle(Json ch) async {
    final id = '${ch['id']}';
    try {
      _joined.contains(id) ? await Content.leave(id) : await Content.join(id);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Channels'), actions: [CrownButton(onTap: () => openPlans(context))]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await CreateChannelScreen.open(context);
            _load();
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Channel'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _channels == null
              ? (_error == null
                  ? const Center(child: CircularProgressIndicator())
                  : ErrorRetry(message: _error!, onRetry: _load))
              : _channels!.isEmpty
                  ? ListView(children: const [SizedBox(height: 80), EmptyState()])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: _channels!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (c, i) {
                        final ch = _channels![i];
                        final joined = _joined.contains(ch['id']);
                        final mine = ch['owner_id'] == session.user?.id;
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            onTap: () async {
                              await ChannelScreen.open(context, '${ch['id']}');
                              _load();
                            },
                            leading: ChannelAvatar(iconKey: ch['icon_key'] as String?, name: '${ch['name']}', size: 46),
                            title: Text('${ch['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${ch['member_count']} members',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            trailing: mine
                                ? const StatusPill('Yours', color: AppColors.primary)
                                : joined
                                    ? OutlinedButton(
                                        style: OutlinedButton.styleFrom(minimumSize: const Size(84, 36)),
                                        onPressed: () => _toggle(ch),
                                        child: const Text('Joined'))
                                    : FilledButton(
                                        style: FilledButton.styleFrom(minimumSize: const Size(84, 36)),
                                        onPressed: () => _toggle(ch),
                                        child: const Text('Join')),
                          ),
                        );
                      },
                    ),
        ),
      );
}
