import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'session.dart';

import 'json.dart';
export 'json.dart';


/// Channels, posts, media URLs, reports, device-level blocks.
class Content {
  static final _urlCache = <String, (String, DateTime)>{};
  static List<Json>? _categories;
  static Set<String>? _blocked;

  // ---------------------------------------------------------------- media
  /// Signed URL valid for 3600 s; only issued when can_read_media() allows it.
  static Future<String> signedUrl(String key, {bool fresh = false, String bucket = 'media'}) async {
    final cacheKey = '$bucket/$key';
    final hit = _urlCache[cacheKey];
    if (!fresh && hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    final url = await db.storage.from(bucket).createSignedUrl(key, AppConfig.signedUrlSeconds);
    _urlCache[cacheKey] = (url, DateTime.now().add(const Duration(minutes: 50)));
    return url;
  }

  static void forget(String key, {String bucket = 'media'}) => _urlCache.remove('$bucket/$key');

  // ----------------------------------------------------------- categories
  static Future<List<Json>> categories() async {
    _categories ??= List<Json>.from(await db.from('categories').select().eq('active', true).order('position'));
    return _categories!;
  }

  // ---------------------------------------------------------------- posts
  static Future<List<Json>> posts({
    String? query,
    String? category,
    String? channelId,
    bool feed = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await db.rpc('search_posts', params: {
      'p_query': (query?.trim().isEmpty ?? true) ? null : query!.trim(),
      'p_category': category,
      'p_channel_id': channelId,
      'p_feed': feed,
      'p_limit': limit,
      'p_offset': offset,
      if (session.hidePaid && !session.isPremium) 'p_hide_premium': true,
    });
    final blocked = await blockedChannels();
    return List<Json>.from(rows as List).where((p) => !blocked.contains(p['channel_id'])).toList();
  }

  static Future<Json?> post(String id) async => await db
      .from('posts')
      .select('*, channel:channels(id, name, icon_key, category, owner_id)')
      .eq('id', id)
      .maybeSingle();

  static Future<void> recordView(String postId) async {
    try {
      await db.rpc('record_view', params: {'p_post_id': postId});
    } catch (_) {}
  }

  static Future<void> report({required String reason, String? postId, String? channelId, String? details}) =>
      db.rpc('submit_report', params: {
        'p_reason': reason,
        'p_post_id': postId,
        'p_channel_id': channelId,
        'p_details': details,
      });

  // ------------------------------------------------------------- channels
  static Future<List<Json>> channels({String? category}) async {
    var q = db.from('channels').select().eq('review_status', 'approved').eq('publish_state', 'active');
    if (category != null) q = q.eq('category', category);
    final rows = await q.order('member_count', ascending: false).limit(100);
    final blocked = await blockedChannels();
    return List<Json>.from(rows).where((c) => !blocked.contains(c['id'])).toList();
  }

  static Future<Json?> channel(String id) async => await db.from('channels').select().eq('id', id).maybeSingle();

  static Future<List<Json>> myChannels() async {
    final uid = session.user?.id;
    if (uid == null) return [];
    return List<Json>.from(await db.from('channels').select().eq('owner_id', uid).order('created_at', ascending: false));
  }

  static Future<Set<String>> joinedIds() async {
    final uid = session.user?.id;
    if (uid == null) return {};
    final rows = await db.from('channel_members').select('channel_id').eq('user_id', uid);
    return {for (final r in rows) r['channel_id'] as String};
  }

  static Future<void> join(String id) => db.rpc('join_channel', params: {'p_channel_id': id});
  static Future<void> leave(String id) => db.rpc('leave_channel', params: {'p_channel_id': id});

  // ------------------------------------------------------ device blocking
  static Future<Set<String>> blockedChannels() async {
    if (_blocked != null) return _blocked!;
    final p = await SharedPreferences.getInstance();
    return _blocked = (p.getStringList('blocked_channels') ?? []).toSet();
  }

  static Future<void> setBlocked(String channelId, bool blocked) async {
    final set = await blockedChannels();
    blocked ? set.add(channelId) : set.remove(channelId);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('blocked_channels', set.toList());
  }
}
