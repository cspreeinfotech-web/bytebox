import 'dart:async';
import 'dart:io';

import '../config.dart';
import 'session.dart';

/// Streams a file to Supabase Storage with byte-level progress (the SDK upload has none).
/// Storage RLS still decides whether the upload is allowed.
class Uploader {
  static Future<void> upload({
    required String bucket,
    required String key,
    required File file,
    required String contentType,
    void Function(double progress)? onProgress,
    bool upsert = false,
  }) async {
    final token = db.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Not signed in');
    final total = await file.length();
    if (total > AppConfig.maxUploadBytes) throw Exception('Files must be 50 MB or smaller');

    final uri = Uri.parse('${AppConfig.supabaseUrl}/storage/v1/object/$bucket/${Uri.encodeFull(key)}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(uri);
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set('apikey', AppConfig.supabaseKey)
        ..set(HttpHeaders.contentTypeHeader, contentType)
        ..set('x-upsert', upsert ? 'true' : 'false')
        ..set('cache-control', 'max-age=3600');
      req.contentLength = total;
      var sent = 0;
      onProgress?.call(0);
      await for (final chunk in file.openRead()) {
        req.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent / total);
        await req.flush();
      }
      final res = await req.close();
      final body = await res.transform(const SystemEncoding().decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(body)?.group(1) ?? body;
        throw Exception(msg.contains('row-level security') ? 'You are not allowed to upload here' : msg);
      }
      onProgress?.call(1);
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> remove(String bucket, List<String> keys) async {
    if (keys.isEmpty) return;
    try {
      await db.storage.from(bucket).remove(keys);
    } catch (_) {}
  }
}
