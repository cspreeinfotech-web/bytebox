import 'package:flutter/material.dart';

import '../../services/content.dart';
import '../../services/native.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../login_screen.dart';
import '../plans_screen.dart';
import 'player_screen.dart';

/// Watch rules (enforced again by storage RLS):
/// free → login → play · premium + plan → play · premium, ads user w/o plan → trailer → subscribe →
/// login → Plans → auto-play after purchase · organic w/o access → Plans.
class Watch {
  static Future<void> play(BuildContext context, Json post) async {
    final premium = post['is_premium'] == true;
    if (!premium) {
      if (!await requireLogin(context, message: 'Log in or create a free account to watch this.')) return;
      if (context.mounted) await _openMain(context, post);
      return;
    }
    if (session.isPremium) {
      await _openMain(context, post);
      return;
    }
    if (session.hidePaid && !session.freeMode) {
      // Play build without Play billing: premium videos can't be unlocked in this app.
      showSnack(context, 'This video is not available for your account.');
      return;
    }
    if (session.hasAdsAccess && post['trailer_key'] != null) {
      await trailer(context, post);
      return;
    }
    await _subscribeThenPlay(context, post);
  }

  static Future<void> trailer(BuildContext context, Json post) async {
    final key = post['trailer_key'] as String?;
    if (key == null) return;
    final ended = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PlayerScreen(mediaKey: key, title: '${post['title']}', postId: post['id'], isTrailer: true),
    ));
    if (ended != true || !context.mounted || post['is_premium'] != true || session.isPremium) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enjoyed the trailer?'),
        content: const Text('Please subscribe to watch the full video'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Subscribe')),
        ],
      ),
    );
    if (go == true && context.mounted) await _subscribeThenPlay(context, post);
  }

  static Future<void> _subscribeThenPlay(BuildContext context, Json post) async {
    if (!session.noPayments && !await requireLogin(context, message: 'Log in to choose a plan.')) return;
    if (!context.mounted) return;
    await openPlans(context);
    await session.refresh();
    if (session.isPremium && context.mounted) await _openMain(context, post);
  }

  static Future<void> _openMain(BuildContext context, Json post) async {
    final key = post['media_key'] as String?;
    if (key == null) return;
    if (post['kind'] == 'photo') {
      try {
        final url = await Content.signedUrl(key);
        Content.recordView(post['id']);
        if (context.mounted) {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PhotoViewer(url: url, title: '${post['title']}')));
        }
      } catch (e) {
        if (context.mounted) showSnack(context, 'This photo is not available for your account.', error: true);
      }
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(mediaKey: key, title: '${post['title']}', postId: post['id']),
    ));
  }

  /// Downloads only for premium / full access.
  static Future<void> download(BuildContext context, Json post) async {
    if (!session.isPremium && session.hidePaid && !session.freeMode) {
      showSnack(context, 'Downloads are not available for your account.');
      return;
    }
    if (!session.isPremium) {
      final free = session.noPayments;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(free ? 'Download needs full access' : 'Download is a Premium feature'),
          content: Text(free
              ? 'Request full access to download videos to your phone.'
              : 'Choose a plan to download videos and watch them offline.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(free ? 'Get full access' : 'See plans')),
          ],
        ),
      );
      if (go == true && context.mounted) {
        if (!free && !await requireLogin(context)) return;
        if (context.mounted) await openPlans(context);
      }
      return;
    }
    final key = post['media_key'] as String?;
    if (key == null) return;
    try {
      final url = await Content.signedUrl(key, fresh: true);
      final ext = key.split('.').last;
      final safe = '${post['title']}'.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
      await Native.download(url, '${safe.isEmpty ? 'video' : safe}-${'${post['id']}'.substring(0, 6)}.$ext',
          title: '${post['title']}');
      if (context.mounted) showSnack(context, 'Downloading to Downloads/Bytebox…');
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e), error: true);
    }
  }
}

/// Report reasons (E27).
Future<void> showReportSheet(BuildContext context, {String? postId, String? channelId}) async {
  const reasons = {
    'sexual': 'Sexual or nude content',
    'violence': 'Violence or dangerous content',
    'hate': 'Hate speech or harassment',
    'copyright': 'Copyright — this is my content',
    'spam': 'Spam, scam or misleading',
    'other': 'Other',
  };
  String? picked;
  final details = TextEditingController();
  var busy = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Report', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('What is wrong with this content?', style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: picked,
            onChanged: (v) => set(() => picked = v),
            child: Column(children: [
              for (final e in reasons.entries)
                RadioListTile<String>(value: e.key, title: Text(e.value), contentPadding: EdgeInsets.zero, dense: true),
            ]),
          ),
          if (picked == 'other' || picked == 'copyright')
            TextField(
              controller: details,
              maxLines: 3,
              maxLength: 2000,
              decoration: InputDecoration(
                  hintText: picked == 'copyright' ? 'Link to your original work, your contact' : 'Tell us more'),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: 'Send report',
              busy: busy,
              onPressed: picked == null
                  ? null
                  : () async {
                      set(() => busy = true);
                      try {
                        await Content.report(
                            reason: picked!, postId: postId, channelId: channelId, details: details.text.trim());
                        if (c.mounted) Navigator.pop(c);
                        if (context.mounted) showSnack(context, 'Thanks — our team will review this report.');
                      } catch (e) {
                        set(() => busy = false);
                        if (c.mounted) showSnack(c, friendlyError(e), error: true);
                      }
                    },
            ),
          ),
        ]),
      ),
    ),
  );
}

Future<bool> confirmBlockChannel(BuildContext context, String channelId, String name) async {
  final ok = await confirmDialog(
    context,
    title: 'Block $name?',
    message: "You won't see this channel or its posts on this device any more. "
        'Blocking is private — the channel is not told. To report a problem to our team, use Report instead. '
        'You can unblock it from Settings → Blocked channels.',
    confirm: 'Block',
    destructive: true,
  );
  if (ok) await Content.setBlocked(channelId, true);
  return ok;
}
