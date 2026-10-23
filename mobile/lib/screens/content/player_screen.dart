import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../services/content.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

enum _Rotation { auto, landscape, portrait }

/// Full-screen player. Pops `true` when playback reached the end.
/// Retry always fetches a NEW signed URL and resumes from the last position.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen(
      {super.key, required this.mediaKey, required this.title, this.postId, this.isTrailer = false, this.bucket = 'media'});
  final String mediaKey;
  final String bucket;
  final String title;
  final String? postId;
  final bool isTrailer;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _c;
  String? _error;
  bool _controls = true;
  bool _ended = false;
  bool _viewRecorded = false;
  Duration _resumeAt = Duration.zero;
  _Rotation _rotation = _Rotation.auto;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _open(fresh: false);
  }

  Future<void> _open({required bool fresh}) async {
    setState(() => _error = null);
    final old = _c;
    _c = null;
    old?.removeListener(_tick);
    await old?.dispose();
    try {
      final url = await Content.signedUrl(widget.mediaKey, fresh: fresh, bucket: widget.bucket);
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      if (_resumeAt > Duration.zero) await c.seekTo(_resumeAt);
      c.addListener(_tick);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
      _autoHide();
      if (!_viewRecorded && widget.postId != null && !widget.isTrailer) {
        _viewRecorded = true;
        Content.recordView(widget.postId!);
      }
    } catch (e) {
      final denied = friendlyError(e).contains('Object not found') || '$e'.contains('400');
      if (mounted) {
        setState(() => _error = denied
            ? 'This video is not available for your account.'
            : 'Could not play this video. Check your connection and retry.');
      }
    }
  }

  void _tick() {
    final c = _c;
    if (c == null) return;
    final v = c.value;
    if (v.hasError) {
      _resumeAt = v.position;
      setState(() => _error = 'Playback stopped. Tap Retry to continue.');
      return;
    }
    if (v.isInitialized && v.position > Duration.zero) _resumeAt = v.position;
    if (!_ended && v.isInitialized && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 300) && !v.isPlaying) {
      _ended = true;
      Navigator.of(context).pop(true);
      return;
    }
    if (mounted) setState(() {});
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) setState(() => _controls = false);
    });
  }

  Future<void> _seekBy(int seconds) async {
    final c = _c;
    if (c == null) return;
    var t = c.value.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (t > c.value.duration) t = c.value.duration;
    await c.seekTo(t);
    _autoHide();
  }

  void _cycleRotation() {
    setState(() => _rotation = _Rotation.values[(_rotation.index + 1) % _Rotation.values.length]);
    SystemChrome.setPreferredOrientations(switch (_rotation) {
      _Rotation.auto => DeviceOrientation.values,
      _Rotation.landscape => [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      _Rotation.portrait => [DeviceOrientation.portraitUp],
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c?.removeListener(_tick);
    _c?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  String _fmt(Duration d) => formatDuration(d.inSeconds).isEmpty ? '0:00' : formatDuration(d.inSeconds);

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _controls = !_controls);
          if (_controls) _autoHide();
        },
        child: Stack(fit: StackFit.expand, children: [
          Center(
            child: c != null && c.value.isInitialized
                ? AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))
                : _error == null
                    ? const CircularProgressIndicator()
                    : const SizedBox.shrink(),
          ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _open(fresh: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ]),
              ),
            ),
          if (_controls || c == null) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Row(children: [
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context, false)),
                  Expanded(
                    child: Text(widget.isTrailer ? 'Trailer · ${widget.title}' : widget.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: 'Rotation: ${_rotation.name}',
                    onPressed: _cycleRotation,
                    icon: Icon(switch (_rotation) {
                      _Rotation.auto => Icons.screen_rotation,
                      _Rotation.landscape => Icons.stay_current_landscape,
                      _Rotation.portrait => Icons.stay_current_portrait,
                    }),
                  ),
                ]),
              ),
            ),
            if (c != null && c.value.isInitialized) ...[
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(iconSize: 40, icon: const Icon(Icons.replay_10), onPressed: () => _seekBy(-10)),
                  const SizedBox(width: 24),
                  IconButton(
                    iconSize: 64,
                    icon: Icon(c.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    onPressed: () {
                      c.value.isPlaying ? c.pause() : c.play();
                      _autoHide();
                    },
                  ),
                  const SizedBox(width: 24),
                  IconButton(iconSize: 40, icon: const Icon(Icons.forward_10), onPressed: () => _seekBy(10)),
                ]),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(children: [
                      Text(_fmt(c.value.position), style: const TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: c.value.position.inMilliseconds
                              .clamp(0, c.value.duration.inMilliseconds)
                              .toDouble(),
                          max: c.value.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                          onChanged: (v) => c.seekTo(Duration(milliseconds: v.round())),
                          onChangeEnd: (_) => _autoHide(),
                        ),
                      ),
                      Text(_fmt(c.value.duration), style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.url, required this.title});
  final String url;
  final String title;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: InteractiveViewer(maxScale: 5, child: Center(child: Image.network(url))),
      );
}
