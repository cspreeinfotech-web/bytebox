import 'dart:io';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/content.dart';
import '../../services/native.dart';
import '../../services/session.dart';
import '../../services/uploader.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/post_card.dart';
import 'channel_screen.dart';
import 'create_channel_screen.dart';

/// Profile → My Channels: status chips and Upload for approved channels.
class MyChannelsList extends StatefulWidget {
  const MyChannelsList({super.key});
  @override
  State<MyChannelsList> createState() => MyChannelsListState();
}

class MyChannelsListState extends State<MyChannelsList> {
  List<Json>? _items;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final r = await Content.myChannels();
      if (mounted) setState(() => _items = r);
    } catch (_) {
      if (mounted) setState(() => _items = []);
    }
  }

  Future<void> _delete(Json ch) async {
    final ok = await confirmDialog(context,
        title: 'Delete channel?', message: 'This removes "${ch['name']}" and its request.', confirm: 'Delete', destructive: true);
    if (!ok) return;
    try {
      await db.rpc('delete_channel', params: {'p_channel_id': ch['id']});
      if (ch['icon_key'] != null) await Uploader.remove('media', ['${ch['icon_key']}']);
      reload();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (items.isEmpty) return const EmptyState(text: 'No Record Found', icon: Icons.video_library_outlined);
    return Column(children: [
      for (final ch in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
              leading: ChannelAvatar(iconKey: ch['icon_key'] as String?, name: '${ch['name']}', size: 44),
              title: Text('${ch['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Align(alignment: Alignment.centerLeft, child: _chip(ch))),
              onTap: ch['review_status'] == 'approved' ? () => ChannelScreen.open(context, '${ch['id']}') : null,
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    await CreateChannelScreen.open(context, existing: ch);
                    reload();
                  }
                  if (v == 'delete') _delete(ch);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (ch['review_status'] != 'approved') const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _chip(Json ch) {
    switch (ch['review_status']) {
      case 'pending':
        return const StatusPill('Waiting for approval', color: AppColors.warning);
      case 'rejected':
        return const StatusPill('Not approved', color: AppColors.danger);
      default:
        return ch['publish_state'] == 'active'
            ? ActionChip(
                avatar: const Icon(Icons.upload, size: 16),
                label: const Text('Upload'),
                onPressed: () async {
                  await UploadPostScreen.open(context, channelId: '${ch['id']}');
                  reload();
                },
              )
            : const StatusPill('Disabled', color: AppColors.textMuted);
    }
  }
}

class _Slot {
  _Slot(this.label);
  final String label;
  PickedFile? file;
  double progress = 0;
  bool done = false;
}

/// Draft → upload (per-file progress) → publish, with cleanup on failure.
class UploadPostScreen extends StatefulWidget {
  const UploadPostScreen({super.key, this.channelId});
  final String? channelId;
  static Future<void> open(BuildContext context, {String? channelId}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => UploadPostScreen(channelId: channelId)));
  @override
  State<UploadPostScreen> createState() => _UploadPostScreenState();
}

class _UploadPostScreenState extends State<UploadPostScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  late String? _channelId = widget.channelId;
  List<Json> _channels = [];
  bool _premium = false;
  bool _busy = false;
  final _main = _Slot('Video or photo');
  final _trailer = _Slot('Trailer (optional)');
  final _thumb = _Slot('Thumbnail');
  int? _durationSec;

  @override
  void initState() {
    super.initState();
    Content.myChannels().then((all) {
      if (!mounted) return;
      setState(() {
        _channels = all.where((c) => c['review_status'] == 'approved' && c['publish_state'] == 'active').toList();
        _channelId ??= _channels.isEmpty ? null : '${_channels.first['id']}';
      });
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick(_Slot slot, {required bool videoOnly}) async {
    final f = await Native.pickFile(mime: videoOnly ? 'video/*' : 'video/*,image/*');
    if (f == null) return;
    if (f.size > AppConfig.maxUploadBytes) {
      if (mounted) showSnack(context, 'Files must be 50 MB or smaller.', error: true);
      return;
    }
    setState(() => slot.file = f);
    if (slot == _main) {
      if (f.isVideo) {
        final info = await Native.videoInfo(f.path);
        final thumb = info['thumbnail'] as String?;
        setState(() {
          _durationSec = (((info['durationMs'] as num?) ?? 0) / 1000).round();
          _thumb.file = thumb == null
              ? null
              : PickedFile(path: thumb, name: 'thumb.jpg', size: File(thumb).lengthSync(), mime: 'image/jpeg');
        });
      } else {
        setState(() {
          _durationSec = null;
          _thumb.file = f;
        });
      }
    }
  }

  String _ext(PickedFile f) => f.name.contains('.') ? f.name.split('.').last.toLowerCase() : (f.isVideo ? 'mp4' : 'jpg');

  Future<void> _publish() async {
    if (!_form.currentState!.validate()) return;
    final main = _main.file;
    if (main == null || _channelId == null) {
      showSnack(context, 'Choose a channel and a video or photo.', error: true);
      return;
    }
    setState(() => _busy = true);
    String? postId;
    final uploaded = <String>[];
    try {
      postId = await db.rpc('create_post_draft', params: {
        'p_channel_id': _channelId,
        'p_title': _title.text.trim(),
        'p_description': _desc.text.trim(),
        'p_kind': main.isVideo ? 'video' : 'photo',
        'p_is_premium': _premium,
      }) as String;

      Future<String?> up(_Slot slot, String name) async {
        final f = slot.file;
        if (f == null) return null;
        // A premium photo must not leak through its thumbnail.
        if (slot == _thumb && !main.isVideo && _premium) return null;
        final key = 'posts/$postId/$name.${slot == _thumb ? 'jpg' : _ext(f)}';
        await Uploader.upload(
          bucket: 'media', key: key, file: File(f.path), contentType: slot == _thumb && main.isVideo ? 'image/jpeg' : f.mime,
          onProgress: (p) => setState(() => slot.progress = p),
        );
        uploaded.add(key);
        setState(() => slot.done = true);
        return key;
      }

      final mainKey = await up(_main, 'main');
      final trailerKey = main.isVideo ? await up(_trailer, 'trailer') : null;
      final thumbKey = await up(_thumb, 'thumb');
      await db.rpc('publish_post', params: {
        'p_post_id': postId,
        'p_media_key': mainKey,
        'p_trailer_key': trailerKey,
        'p_thumbnail_key': thumbKey,
        'p_duration_seconds': _durationSec,
        'p_size_bytes': main.size,
      });
      if (!mounted) return;
      showSnack(context, 'Published!');
      Navigator.pop(context);
    } catch (e) {
      // cleanup: remove uploaded objects and the draft
      await Uploader.remove('media', uploaded);
      if (postId != null) {
        try {
          await db.rpc('delete_post', params: {'p_post_id': postId});
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          for (final s in [_main, _trailer, _thumb]) {
            s.progress = 0;
            s.done = false;
          }
        });
        showSnack(context, friendlyError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _slotTile(_Slot slot, {required bool videoOnly, bool optional = false}) {
    final f = slot.file;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(f == null ? Icons.add_circle_outline : (f.isVideo ? Icons.movie_outlined : Icons.image_outlined),
                color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(slot.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(f == null ? (optional ? 'Not added' : 'Required') : '${f.name} · ${formatBytes(f.size)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ),
            if (slot != _thumb)
              TextButton(
                onPressed: _busy ? null : () => _pick(slot, videoOnly: videoOnly),
                child: Text(f == null ? 'Choose' : 'Change'),
              ),
            if (slot.done) const Icon(Icons.check_circle, color: AppColors.success),
          ]),
          if (_busy && f != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: slot.progress, minHeight: 6, borderRadius: BorderRadius.circular(4)),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Upload content')),
        body: _channels.isEmpty
            ? const EmptyState(
                text: 'You can post once one of your channels is approved.', icon: Icons.hourglass_empty)
            : Form(
                key: _form,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  DropdownButtonFormField<String>(
                    initialValue: _channelId,
                    decoration: const InputDecoration(labelText: 'Channel'),
                    items: [
                      for (final c in _channels) DropdownMenuItem(value: '${c['id']}', child: Text('${c['name']}')),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _channelId = v),
                  ),
                  const SizedBox(height: 14),
                  _slotTile(_main, videoOnly: false),
                  const SizedBox(height: 8),
                  if (_main.file?.isVideo ?? true) _slotTile(_trailer, videoOnly: true, optional: true),
                  if (_thumb.file != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: AspectRatio(aspectRatio: 16 / 9, child: Image.file(File(_thumb.file!.path), fit: BoxFit.cover)),
                    ),
                    const SizedBox(height: 4),
                    const Text('Thumbnail is created automatically.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _title,
                    maxLength: 160,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Add a title' : null,
                  ),
                  TextFormField(
                    controller: _desc,
                    maxLength: 2000,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  SwitchListTile(
                    value: _premium,
                    onChanged: _busy ? null : (v) => setState(() => _premium = v),
                    contentPadding: EdgeInsets.zero,
                    title: const Row(children: [Text('Premium'), SizedBox(width: 8), PremiumBadge(small: true)]),
                    subtitle: const Text('Full video only for Premium members; ads users can watch the trailer.'),
                  ),
                  const SizedBox(height: 4),
                  const Text('Max 50 MB per file.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 16),
                  GradientButton(label: 'Publish', icon: Icons.upload, busy: _busy, onPressed: _publish),
                ]),
              ),
      );
}
