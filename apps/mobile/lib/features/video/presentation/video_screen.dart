import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../video_catalog_provider.dart';
import '../video_channel.dart';
import '../video_channel_repository.dart';
import 'video_player_screen.dart';

/// شاشة قنوات الفيديو — تُقرأ ديناميكيًا من Supabase (app.video_channels).
///
/// للدخول من الـ shell: أضف تبويبًا يستخدم [VideoScreen] أو ادفعها عبر
/// الموجّه (routeName = '/video') — الربط في RootShell/AppRouter خارج نطاق
/// هذه الميزة وموثّق في docs/VIDEO_CHANNELS.md.
class VideoScreen extends ConsumerWidget {
  static const routeName = '/video';

  const VideoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(videoChannelsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('القنوات المرئية')),
      body: channels.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error is VideoCatalogException
              ? error.userMessage
              : 'تعذّر تحميل القنوات. تحقق من الاتصال ثم حاول مجددًا.',
          onRetry: () => ref.invalidate(videoChannelsProvider),
        ),
        data: (result) {
          final items = result.channels;
          if (items.isEmpty) {
            return _EmptyState(onRetry: () => ref.invalidate(videoChannelsProvider));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(videoChannelsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + (result.isCached ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (result.isCached && index == 0) {
                  return const ListTile(
                    leading: Icon(Icons.cloud_off_outlined),
                    title: Text('تُعرض آخر قنوات محفوظة على الجهاز'),
                    subtitle: Text('تعذّر تحديث القنوات. اسحب للتحديث عند عودة الاتصال.'),
                  );
                }
                final channel = items[index - (result.isCached ? 1 : 0)];
                return _ChannelTile(channel: channel);
              },
            ),
          );
        },
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final VideoChannel channel;
  const _ChannelTile({required this.channel});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: channel.logoUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  channel.logoUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.ondemand_video, size: 32),
                ),
              )
            : const Icon(Icons.ondemand_video, size: 32),
        title: Text(channel.nameAr),
        subtitle: Text(videoSourceTypeLabel(channel.sourceType)),
        trailing: const Icon(Icons.play_circle_outline),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(channel: channel),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.ondemand_video_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('لا توجد قنوات مرئية حاليًا',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('ستظهر القنوات المعتمدة عند توفرها. اسحب للتحديث لاحقًا.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ]),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;
  const _ErrorState({required this.onRetry, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ]),
      ),
    );
  }
}
