import 'package:flutter/material.dart';

import '../../services/content.dart';
import '../../services/links.dart';
import '../../services/native.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/post_card.dart';
import 'channel_screen.dart';
import 'watch.dart';

/// Netflix-style post page.
class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.postId});
  final String postId;
  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostScreen(postId: id)));
  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  Json? _post;
  List<Json> _more = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await Content.post(widget.postId);
      if (p == null) {
        setState(() => _error = 'This post is not available.');
        return;
      }
      final ch = (p['channel'] as Map?)?.cast<String, dynamic>() ?? {};
      final more = await Content.posts(category: ch['category'] as String?, limit: 12);
      if (!mounted) return;
      setState(() {
        _post = p;
        _more = more.where((m) => m['id'] != p['id']).take(8).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Icon(icon, color: AppColors.text),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = _post;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error == null ? const Center(child: CircularProgressIndicator()) : ErrorRetry(message: _error!, onRetry: _load),
      );
    }
    final ch = (p['channel'] as Map?)?.cast<String, dynamic>() ?? {};
    final premium = p['is_premium'] == true;
    final hasTrailer = p['trailer_key'] != null && session.hasAdsAccess;
    final isPhoto = p['kind'] == 'photo';
    final views = (p['view_count'] as num?)?.toInt() ?? 0;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: MediaQuery.of(context).size.width * 9 / 16,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              MediaImage(mediaKey: p['thumbnail_key'] as String?),
              const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.thumbScrim)),
              if (premium) const Positioned(left: 16, bottom: 16, child: PremiumBadge()),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['title']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                [
                  '$views ${views == 1 ? 'view' : 'views'}',
                  if (formatDuration((p['duration_seconds'] as num?)?.toInt()).isNotEmpty)
                    formatDuration((p['duration_seconds'] as num?)?.toInt()),
                  formatDate(p['published_at'] as String?),
                ].join(' · '),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: isPhoto ? 'View' : 'Play',
                icon: isPhoto ? Icons.image_outlined : Icons.play_arrow_rounded,
                onPressed: () async {
                  await Watch.play(context, p);
                  if (mounted) _load();
                },
              ),
              if (hasTrailer) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Watch.trailer(context, p),
                  icon: const Icon(Icons.movie_outlined),
                  label: const Text('Trailer'),
                ),
              ],
              const SizedBox(height: 12),
              Row(children: [
                _action(Icons.share_outlined, 'Share',
                    () => Native.share('${p['title']}\n${Links.post(p['id'])}', title: 'Share post')),
                _action(Icons.video_library_outlined, 'Channel', () => ChannelScreen.open(context, '${p['channel_id']}')),
                _action(Icons.flag_outlined, 'Report',
                    () => showReportSheet(context, postId: p['id'], channelId: p['channel_id'])),
                if (!isPhoto) _action(Icons.download_outlined, 'Download', () => Watch.download(context, p)),
              ]),
              const Divider(height: 28),
              InkWell(
                onTap: () => ChannelScreen.open(context, '${p['channel_id']}'),
                child: Row(children: [
                  ChannelAvatar(iconKey: ch['icon_key'] as String?, name: '${ch['name'] ?? ''}', size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${ch['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ]),
              ),
              if ('${p['description']}'.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('${p['description']}', style: const TextStyle(color: AppColors.textMuted, height: 1.5)),
              ],
              const SizedBox(height: 24),
              if (_more.isNotEmpty)
                const Text('More like this', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 12, childAspectRatio: 0.95),
            delegate: SliverChildBuilderDelegate(
              (c, i) => PostCard(
                post: _more[i],
                compact: true,
                onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => PostScreen(postId: '${_more[i]['id']}'))),
              ),
              childCount: _more.length,
            ),
          ),
        ),
      ]),
    );
  }
}
