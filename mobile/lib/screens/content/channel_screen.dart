import 'package:flutter/material.dart';

import '../../services/content.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/post_card.dart';
import 'post_screen.dart';
import 'watch.dart';

class ChannelScreen extends StatefulWidget {
  const ChannelScreen({super.key, required this.channelId});
  final String channelId;
  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChannelScreen(channelId: id)));
  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  Json? _ch;
  List<Json> _posts = [];
  bool _joined = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final ch = await Content.channel(widget.channelId);
      if (ch == null) {
        setState(() => _error = 'This channel is not available.');
        return;
      }
      final r = await Future.wait([Content.posts(channelId: widget.channelId, limit: 50), Content.joinedIds()]);
      if (!mounted) return;
      setState(() {
        _ch = ch;
        _posts = r[0] as List<Json>;
        _joined = (r[1] as Set<String>).contains(widget.channelId);
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _toggleJoin() async {
    setState(() => _busy = true);
    try {
      _joined ? await Content.leave(widget.channelId) : await Content.join(widget.channelId);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = _ch;
    return Scaffold(
      appBar: AppBar(
        title: Text(ch?['name'] ?? ''),
        actions: [
          if (ch != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'report') showReportSheet(context, channelId: widget.channelId);
                if (v == 'block' && await confirmBlockChannel(context, widget.channelId, '${ch['name']}')) {
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('Report channel')),
                PopupMenuItem(value: 'block', child: Text('Block channel')),
              ],
            ),
        ],
      ),
      body: ch == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : ErrorRetry(message: _error!, onRetry: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  ChannelAvatar(iconKey: ch['icon_key'] as String?, name: '${ch['name']}', size: 72),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${ch['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      Text('${ch['member_count']} members · ${_posts.length} posts',
                          style: const TextStyle(color: AppColors.textMuted)),
                    ]),
                  ),
                ]),
                if ('${ch['description']}'.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${ch['description']}', style: const TextStyle(color: AppColors.textMuted)),
                ],
                const SizedBox(height: 16),
                if (ch['owner_id'] != session.user?.id)
                  _joined
                      ? OutlinedButton(onPressed: _busy ? null : _toggleJoin, child: const Text('Joined'))
                      : GradientButton(label: 'Join channel', busy: _busy, onPressed: _toggleJoin),
                const SizedBox(height: 20),
                if (_posts.isEmpty) const EmptyState(text: 'No posts yet'),
                for (final p in _posts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: PostCard(post: p, onTap: () => PostScreen.open(context, '${p['id']}')),
                  ),
              ]),
            ),
    );
  }
}
