import 'package:flutter/services.dart';

class PickedFile {
  PickedFile({required this.path, required this.name, required this.size, required this.mime});
  final String path;
  final String name;
  final int size;
  final String mime;
  bool get isVideo => mime.startsWith('video/');
  bool get isImage => mime.startsWith('image/');
}

class UpiLaunchException implements Exception {
  UpiLaunchException(this.code, this.message);
  final String code;
  final String message;
  bool get noUpiApp => code == 'NO_UPI_APP';
  @override
  String toString() => message;
}

/// Thin wrappers over the Kotlin MethodChannels in MainActivity.kt.
class Native {
  static const _upi = MethodChannel('app/upi');
  static const _native = MethodChannel('app/native');

  /// Opens the UPI chooser and returns the raw response ("" when the user came back without paying).
  static Future<String> payUpi(String uri) async {
    try {
      return (await _upi.invokeMethod<String>('pay', {'uri': uri})) ?? '';
    } on PlatformException catch (e) {
      throw UpiLaunchException(e.code, e.message ?? 'Could not open UPI');
    }
  }

  static Future<PickedFile?> pickFile({String mime = '*/*'}) async {
    final m = await _native.invokeMapMethod<String, dynamic>('pickFile', {'mime': mime});
    if (m == null) return null;
    return PickedFile(
      path: m['path'] as String,
      name: m['name'] as String,
      size: (m['size'] as num).toInt(),
      mime: m['mime'] as String,
    );
  }

  /// {durationMs, thumbnail(path or null)}
  static Future<Map<String, dynamic>> videoInfo(String path) async =>
      (await _native.invokeMapMethod<String, dynamic>('videoInfo', {'path': path})) ?? {};

  static Future<void> download(String url, String fileName, {String title = 'Bytebox'}) =>
      _native.invokeMethod('download', {'url': url, 'fileName': fileName, 'title': title});

  static Future<void> share(String text, {String title = 'Share'}) =>
      _native.invokeMethod('share', {'text': text, 'title': title});

  static Future<void> openFile(String path, {String? mime}) =>
      _native.invokeMethod('openFile', {'path': path, 'mime': mime});

  static Future<Map<String, dynamic>> deviceInfo() async {
    try {
      return (await _native.invokeMapMethod<String, dynamic>('deviceInfo')) ?? {};
    } catch (_) {
      return {};
    }
  }
}
