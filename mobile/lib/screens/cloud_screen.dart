import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/content.dart';
import '../services/native.dart';
import '../services/session.dart';
import '../services/uploader.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'content/player_screen.dart';
import 'login_screen.dart';
import 'plans_screen.dart';

/// Cloud file manager: meter, breadcrumb, folders/files, upload, new folder, rename/move/delete.
class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});
  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final List<Json> _path = []; // breadcrumb folders
  List<Json>? _items;
  String? _error;
  String? _uploading;
  double _progress = 0;

  String? get _folderId => _path.isEmpty ? null : '${_path.last['id']}';

  @override
  void initState() {
    super.initState();
    session.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (session.isGuest) {
      setState(() => _items = []);
      return;
    }
    try {
      var q = db.from('cloud_files').select().eq('user_id', session.user!.id);
      q = _folderId == null ? q.isFilter('parent_id', null) : q.eq('parent_id', _folderId!);
      final rows = List<Json>.from(await q.order('is_folder', ascending: false).order('name'));
      if (mounted) setState(() {
        _items = rows.where((r) => r['is_folder'] == true || r['uploaded'] == true).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _openFolder(Json f) {
    setState(() {
      _path.add(f);
      _items = null;
    });
    _load();
  }

  void _goTo(int depth) {
    setState(() {
      _path.removeRange(depth, _path.length);
      _items = null;
    });
    _load();
  }

  Future<void> _newFolder() async {
    final name = await _askName('New folder', '');
    if (name == null) return;
    try {
      await db.rpc('cloud_create_folder', params: {'p_parent_id': _folderId, 'p_name': name});
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _upload() async {
    final f = await Native.pickFile();
    if (f == null) return;
    if (f.size > 50 * 1024 * 1024) {
      if (mounted) showSnack(context, 'Files must be 50 MB or smaller.', error: true);
      return;
    }
    String? fileId;
    setState(() {
      _uploading = f.name;
      _progress = 0;
    });
    try {
      final r = (await db.rpc('cloud_begin_upload', params: {
        'p_parent_id': _folderId, 'p_name': f.name, 'p_size_bytes': f.size, 'p_mime': f.mime,
      }) as Map).cast<String, dynamic>();
      fileId = '${r['file_id']}';
      await Uploader.upload(
        bucket: 'cloud', key: '${r['storage_key']}', file: File(f.path), contentType: f.mime,
        onProgress: (p) => setState(() => _progress = p),
      );
      await db.rpc('cloud_finish_upload', params: {'p_file_id': fileId});
      fileId = null;
      await session.refresh();
      _load();
    } catch (e) {
      if (fileId != null) {
        try {
          await db.rpc('cloud_delete', params: {'p_id': fileId});
        } catch (_) {}
      }
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _open(Json f) async {
    final key = '${f['storage_key']}';
    final mime = '${f['mime_type'] ?? ''}';
    try {
      if (mime.startsWith('video/')) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlayerScreen(mediaKey: key, title: '${f['name']}', bucket: 'cloud')));
        return;
      }
      final url = await Content.signedUrl(key, bucket: 'cloud', fresh: true);
      if (!mounted) return;
      if (mime.startsWith('image/')) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewer(url: url, title: '${f['name']}')));
        return;
      }
      showSnack(context, 'Opening…');
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/${f['id']}_${'${f['name']}'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
      final client = HttpClient();
      final res = await (await client.getUrl(Uri.parse(url))).close();
      await res.pipe(out.openWrite());
      client.close();
      await Native.openFile(out.path, mime: mime.isEmpty ? null : mime);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<String?> _askName(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _actions(Json f) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('${f['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Rename'),
              onTap: () => Navigator.pop(c, 'rename')),
          ListTile(leading: const Icon(Icons.drive_file_move_outline), title: const Text('Move'),
              onTap: () => Navigator.pop(c, 'move')),
          ListTile(leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case 'rename':
          final name = await _askName('Rename', '${f['name']}');
          if (name != null) await db.rpc('cloud_rename', params: {'p_id': f['id'], 'p_name': name});
        case 'move':
          final target = await _pickFolder(exclude: '${f['id']}');
          if (target != null) {
            await db.rpc('cloud_move', params: {'p_id': f['id'], 'p_new_parent_id': target.isEmpty ? null : target});
          }
        case 'delete':
          final ok = await confirmDialog(context,
              title: 'Delete ${f['is_folder'] == true ? 'folder' : 'file'}?',
              message: f['is_folder'] == true
                  ? '"${f['name']}" and everything inside it will be deleted.'
                  : '"${f['name']}" will be deleted.',
              confirm: 'Delete',
              destructive: true);
          if (!ok) return;
          final keys = List<String>.from(await db.rpc('cloud_delete', params: {'p_id': f['id']}) as List);
          await Uploader.remove('cloud', keys);
          await session.refresh();
      }
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  /// Returns folder id, '' for root, or null when cancelled.
  Future<String?> _pickFolder({required String exclude}) async {
    final rows = List<Json>.from(await db
        .from('cloud_files')
        .select('id, name, parent_id')
        .eq('user_id', session.user!.id)
        .eq('is_folder', true)
        .order('name'));
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Move to'), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(c, ''), child: const Text('My Cloud (top level)')),
        for (final r in rows.where((r) => r['id'] != exclude))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, '${r['id']}'), child: Text('📁 ${r['name']}')),
      ]),
    );
  }

  IconData _icon(Json f) {
    if (f['is_folder'] == true) return Icons.folder;
    final m = '${f['mime_type'] ?? ''}';
    if (m.startsWith('image/')) return Icons.image_outlined;
    if (m.startsWith('video/')) return Icons.movie_outlined;
    if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (m.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (m.contains('zip') || m.contains('compressed')) return Icons.folder_zip_outlined;
    if (m.startsWith('text/') || m.contains('document')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Widget _meter() {
    final quota = session.quotaBytes;
    final used = session.usedBytes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.cloud, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Storage', style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${formatBytes(used)} of ${formatBytes(quota)}', style: const TextStyle(color: AppColors.textMuted)),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: quota == 0 ? 0 : (used / quota).clamp(0, 1).toDouble(),
            minHeight: 8,
            borderRadius: BorderRadius.circular(6),
          ),
        ]),
      ),
    );
  }

  Widget _locked() {
    final guest = session.isGuest;
    return EmptyState(
      icon: Icons.cloud_outlined,
      text: guest
          ? 'Log in to use your personal cloud.'
          : session.noPayments
              ? 'Cloud storage is not available for this account yet.'
              : 'Cloud storage comes with Premium — 2 TB for your photos, videos and files.',
      action: GradientButton(
        label: guest ? 'Log in / Create account' : (session.noPayments ? 'See account' : 'See plans'),
        onPressed: () async {
          if (guest) {
            await requireLogin(context);
            _load();
          } else {
            await openPlans(context);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = session.isGuest || session.quotaBytes == 0; // never show 15 GB when quota is 0
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud')),
      floatingActionButton: locked || _uploading != null
          ? null
          : FloatingActionButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (c) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(leading: const Icon(Icons.upload_file), title: const Text('Upload file'),
                        onTap: () {
                          Navigator.pop(c);
                          _upload();
                        }),
                    ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: const Text('New folder'),
                        onTap: () {
                          Navigator.pop(c);
                          _newFolder();
                        }),
                  ]),
                ),
              ),
              child: const Icon(Icons.add),
            ),
      body: locked
          ? _locked()
          : RefreshIndicator(
              onRefresh: () async {
                await session.refresh();
                await _load();
              },
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
                _meter(),
                if (_uploading != null) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_upload_outlined),
                      title: Text(_uploading!, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(value: _progress, borderRadius: BorderRadius.circular(4)),
                      ),
                      trailing: Text('${(_progress * 100).round()}%'),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    TextButton(onPressed: () => _goTo(0), child: const Text('My Cloud')),
                    for (var i = 0; i < _path.length; i++) ...[
                      const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                      TextButton(onPressed: () => _goTo(i + 1), child: Text('${_path[i]['name']}')),
                    ],
                  ]),
                ),
                if (_error != null)
                  ErrorRetry(message: _error!, onRetry: _load)
                else if (_items == null)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                else if (_items!.isEmpty)
                  const EmptyState(text: 'This folder is empty', icon: Icons.folder_open)
                else
                  for (final f in _items!)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(_icon(f), color: f['is_folder'] == true ? AppColors.warning : AppColors.primary, size: 30),
                      title: Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: f['is_folder'] == true
                          ? null
                          : Text('${formatBytes((f['size_bytes'] as num).toInt())} · ${formatDate(f['created_at'] as String?)}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      onTap: () => f['is_folder'] == true ? _openFolder(f) : _open(f),
                      onLongPress: () => _actions(f),
                      trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _actions(f)),
                    ),
              ]),
            ),
    );
  }
}
