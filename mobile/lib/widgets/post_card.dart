import 'package:flutter/material.dart';

import '../services/content.dart';
import '../theme.dart';
import 'common.dart';

/// Loads an image from the private media bucket through a signed URL.
class MediaImage extends StatefulWidget {
  const MediaImage({super.key, required this.mediaKey, this.fit = BoxFit.cover, this.placeholderIcon});
  final String? mediaKey;
  final BoxFit fit;
  final IconData? placeholderIcon;
  @override
  State<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<MediaImage> {
  Future<String>? _url;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MediaImage old) {
    super.didUpdateWidget(old);
    if (old.mediaKey != widget.mediaKey) _load();
  }

  void _load() => _url = widget.mediaKey == null ? null : Content.signedUrl(widget.mediaKey!);

  Widget get _placeholder => Container(
        color: AppColors.surfaceHigh,
        alignment: Alignment.center,
        child: Icon(widget.placeholderIcon ?? Icons.movie_outlined, color: AppColors.textMuted, size: 36),
      );

  @override
  Widget build(BuildContext context) {
    if (_url == null) return _placeholder;
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (!snap.hasData) return _placeholder;
        return Image.network(
          snap.data!,
          fit: widget.fit,
          errorBuilder: (_, _, _) => _placeholder,
          loadingBuilder: (_, child, progress) => progress == null ? child : _placeholder,
        );
      },
    );
  }
}

class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, required this.iconKey, required this.name, this.size = 36});
  final String? iconKey;
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: iconKey == null
              ? Container(
                  decoration: const BoxDecoration(gradient: AppColors.brandGradient),
                  alignment: Alignment.center,
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: TextStyle(
                          color: AppColors.onPrimary, fontWeight: FontWeight.w700, fontSize: size * 0.42)),
                )
              : MediaImage(mediaKey: iconKey, placeholderIcon: Icons.person),
        ),
      );
}

/// 16:9 thumbnail, scrim, play overlay, duration pill, Premium badge.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, required this.onTap, this.compact = false});
  final Json post;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final premium = post['is_premium'] == true;
    final isPhoto = post['kind'] == 'photo';
    final dur = formatDuration((post['duration_seconds'] as num?)?.toInt());
    final views = (post['view_count'] as num?)?.toInt() ?? 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              MediaImage(mediaKey: post['thumbnail_key'] as String?,
                  placeholderIcon: isPhoto ? Icons.image_outlined : Icons.movie_outlined),
              const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.thumbScrim)),
              if (!isPhoto)
                Center(
                  child: Container(
                    width: compact ? 40 : 54,
                    height: compact ? 40 : 54,
                    decoration: BoxDecoration(
                      color: AppColors.scrimLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.7), width: 1.5),
                    ),
                    child: Icon(Icons.play_arrow_rounded, color: AppColors.onPrimary, size: compact ? 26 : 34),
                  ),
                ),
              if (premium) const Positioned(left: 10, top: 10, child: PremiumBadge(small: true)),
              if (dur.isNotEmpty)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.scrim, borderRadius: BorderRadius.circular(6)),
                    child: Text(dur, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!compact) ...[
              ChannelAvatar(iconKey: post['channel_icon_key'] as String?, name: '${post['channel_name'] ?? ''}'),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${post['title']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: compact ? 13 : 15)),
                const SizedBox(height: 2),
                Text('${post['channel_name'] ?? ''} · $views ${views == 1 ? 'view' : 'views'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Post lists use 1 column on phones, 2 on small tablets / landscape phones, 3 on wide tablets.
int postColumns(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w >= 1100 ? 3 : (w >= 680 ? 2 : 1);
}

/// Number of rows needed to show [count] posts in [columns] columns.
int postRowCount(int count, int columns) => (count + columns - 1) ~/ columns;

/// One row of up to [columns] post cards (empty cells keep the column widths equal).
class PostRow extends StatelessWidget {
  const PostRow({super.key, required this.posts, required this.row, required this.columns, required this.onOpen});
  final List<Json> posts;
  final int row;
  final int columns;
  final void Function(Json post) onOpen;

  @override
  Widget build(BuildContext context) {
    final start = row * columns;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var c = 0; c < columns; c++) ...[
        if (c > 0) const SizedBox(width: 16),
        Expanded(
          child: start + c < posts.length
              ? PostCard(post: posts[start + c], onTap: () => onOpen(posts[start + c]))
              : const SizedBox.shrink(),
        ),
      ],
    ]);
  }
}
