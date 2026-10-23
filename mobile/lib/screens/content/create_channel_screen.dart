import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/content.dart';
import '../../services/native.dart';
import '../../services/session.dart';
import '../../services/uploader.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/post_card.dart';
import '../login_screen.dart';

/// Create (or edit) a channel. New channels are always sent for approval.
class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key, this.existing});
  final Json? existing;

  static Future<void> open(BuildContext context, {Json? existing}) async {
    if (!await requireLogin(context, title: 'Please log in', message: 'Log in to create a channel')) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreateChannelScreen(existing: existing)));
  }

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?['name'] as String?);
  late final _desc = TextEditingController(text: widget.existing?['description'] as String?);
  late final _tags = TextEditingController(text: ((widget.existing?['tags'] as List?) ?? []).join(', '));
  late String? _category = widget.existing?['category'] as String?;
  List<Json> _categories = [];
  PickedFile? _icon;
  bool _busy = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    Content.categories().then((c) {
      if (mounted) setState(() => _categories = c);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final f = await Native.pickFile(mime: 'image/jpeg,image/png,image/webp');
    if (f == null) return;
    if (f.size >= 5 * 1024 * 1024) {
      if (mounted) showSnack(context, 'Picture must be smaller than 5 MB.', error: true);
      return;
    }
    setState(() => _icon = f);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final tags = _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    try {
      String id;
      if (_editing) {
        id = '${widget.existing!['id']}';
      } else {
        id = await db.rpc('create_channel', params: {
          'p_name': _name.text.trim(),
          'p_category': _category,
          'p_description': _desc.text.trim(),
          'p_tags': tags,
        }) as String;
      }
      String? iconKey;
      if (_icon != null) {
        final ext = _icon!.name.contains('.') ? _icon!.name.split('.').last.toLowerCase() : 'jpg';
        iconKey = 'channels/$id/icon.$ext';
        await Uploader.upload(bucket: 'media', key: iconKey, file: File(_icon!.path), contentType: _icon!.mime, upsert: true);
        Content.forget(iconKey);
      }
      if (_editing || iconKey != null) {
        await db.rpc('update_channel', params: {
          'p_channel_id': id,
          'p_name': _name.text.trim(),
          'p_category': _category,
          'p_description': _desc.text.trim(),
          'p_tags': tags,
          'p_icon_key': iconKey,
        });
      }
      if (!mounted) return;
      if (_editing) {
        Navigator.pop(context);
        showSnack(context, 'Channel updated.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Request sent'),
          content: const Text('Your channel was sent for review. '
              "You'll find it under Profile → My Channels. Once it's approved, you can start posting."),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_editing ? 'Edit channel' : 'Create channel')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Center(
              child: GestureDetector(
                onTap: _pickIcon,
                child: Stack(children: [
                  ClipOval(
                    child: SizedBox(
                      width: 104,
                      height: 104,
                      child: _icon != null
                          ? Image.file(File(_icon!.path), fit: BoxFit.cover)
                          : (widget.existing?['icon_key'] != null
                              ? MediaImage(mediaKey: widget.existing!['icon_key'] as String)
                              : Container(
                                  color: AppColors.surfaceHigh,
                                  child: const Icon(Icons.add_a_photo_outlined, color: AppColors.textMuted, size: 34))),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                      child: const Icon(Icons.edit, size: 16, color: AppColors.onPrimary),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
                child: Text('Channel picture (under 5 MB)', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Channel name'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'At least 3 characters' : null,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in _categories) DropdownMenuItem(value: '${c['slug']}', child: Text('${c['name']}')),
              ],
              onChanged: (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Choose a category' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _desc,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(labelText: 'Tags (optional)', hintText: 'cooking, recipes, india'),
            ),
            if (!_editing) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(child: Text('New channels are reviewed before they appear in the app.')),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            GradientButton(label: _editing ? 'Save changes' : 'Send for approval', busy: _busy, onPressed: _submit),
          ]),
        ),
      );
}
