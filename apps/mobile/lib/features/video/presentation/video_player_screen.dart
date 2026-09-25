import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../video_channel.dart';

/// شاشة تشغيل قناة فيديو.
///
/// - HLS/MP4: عبر video_player + chewie (ملء الشاشة + تدوير تلقائي).
/// - يوتيوب: عبر youtube_player_flutter.
/// - حالات: تحميل، تخزين مؤقت (buffering)، خطأ مع إعادة المحاولة.
/// - تُحرَّر كل المتحكمات عند الخروج لتقليل استهلاك الذاكرة.
///
/// الاعتماديات المطلوبة في pubspec.yaml:
/// video_player, chewie, youtube_player_flutter
class VideoPlayerScreen extends StatefulWidget {
  final VideoChannel channel;

  const VideoPlayerScreen({super.key, required this.channel});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  YoutubePlayerController? _youtubeController;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final channel = widget.channel;
    if (channel.sourceType == VideoSourceType.youtube) {
      _initializeYoutube(channel);
      return;
    }
    await _initializeStream(channel);
  }

  void _initializeYoutube(VideoChannel channel) {
    final videoId = channel.youtubeVideoId;
    if (videoId == null) {
      setState(() {
        _loading = false;
        _error = 'رابط يوتيوب غير صالح.';
      });
      return;
    }
    _youtubeController = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
      ),
    );
    setState(() => _loading = false);
  }

  Future<void> _initializeStream(VideoChannel channel) async {
    try {
      final videoController = VideoPlayerController.networkUrl(
        Uri.parse(channel.streamUrl),
      );
      await videoController.initialize();
      final chewieController = ChewieController(
        videoPlayerController: videoController,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        // تدوير تلقائي عند ملء الشاشة، وعودة للوضع العمودي عند الخروج.
        deviceOrientationsOnEnterFullScreen: const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: const [DeviceOrientation.portraitUp],
        placeholder: const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, message) => _PlayerError(
          message: 'تعذّر تشغيل البث.',
          onRetry: _retry,
        ),
      );
      if (!mounted) {
        await videoController.dispose();
        chewieController.dispose();
        return;
      }
      setState(() {
        _videoController = videoController;
        _chewieController = chewieController;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // حالة عدم الاتصال تُميَّز برسالة صريحة بدل رسالة الخطأ العامة.
      final offline = e is SocketException;
      setState(() {
        _loading = false;
        _error = offline
            ? 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة ثم حاول مجددًا.'
            : 'تعذّر تشغيل الفيديو (انتهت المهلة أو توقف البث). حاول مجددًا.';
      });
    }
  }

  Future<void> _retry() async {
    _disposeControllers();
    setState(() {
      _loading = true;
      _error = null;
    });
    await _initialize();
  }

  void _disposeControllers() {
    _chewieController?.dispose();
    _chewieController = null;
    _videoController?.dispose();
    _videoController = null;
    _youtubeController?.dispose();
    _youtubeController = null;
  }

  @override
  void dispose() {
    _disposeControllers();
    // إعادة اتجاه الشاشة الافتراضي عند مغادرة المشغّل.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    return Scaffold(
      appBar: AppBar(title: Text(channel.nameAr)),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _buildPlayer(),
            ),
          ),
          ListTile(
            leading: channel.logoUrl != null
                ? ClipOval(
                    child: Image.network(
                      channel.logoUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.ondemand_video, size: 32),
                    ),
                  )
                : const Icon(Icons.ondemand_video, size: 32),
            title: Text(channel.nameAr,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(videoSourceTypeLabel(channel.sourceType)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    if (_loading) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 12),
          Text('جارٍ تحميل الفيديو…', style: TextStyle(color: Colors.white70)),
        ]),
      );
    }
    if (_error != null) {
      return _PlayerError(message: _error!, onRetry: _retry);
    }
    final youtubeController = _youtubeController;
    if (youtubeController != null) {
      return YoutubePlayer(controller: youtubeController);
    }
    final chewieController = _chewieController;
    final videoController = _videoController;
    if (chewieController != null && videoController != null) {
      return Stack(
        children: [
          Chewie(controller: chewieController),
          // مؤشر التخزين المؤقت (buffering) فوق المشغّل.
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: videoController,
            builder: (context, value, _) {
              if (value.isBuffering && !value.hasError) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      );
    }
    return _PlayerError(message: 'تعذّر تهيئة المشغّل.', onRetry: _retry);
  }
}

class _PlayerError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _PlayerError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ]),
      ),
    );
  }
}
