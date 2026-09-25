import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/audio_playback_service.dart';
import 'playback_options.dart';

class FullPlayerSheet extends ConsumerWidget {
  const FullPlayerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying =
        ref.watch(audioPlaybackProvider.select((s) => s.isPlaying));
    final mode = ref.watch(audioPlaybackProvider.select((s) => s.mode));
    final currentTitle =
        ref.watch(audioPlaybackProvider.select((s) => s.currentTitle));
    final currentSubtitle =
        ref.watch(audioPlaybackProvider.select((s) => s.currentSubtitle));
    final currentUri =
        ref.watch(audioPlaybackProvider.select((s) => s.currentUri));
    final sleepMinutes =
        ref.watch(audioPlaybackProvider.select((s) => s.sleepTimerMinutes));
    final speed = ref.watch(audioPlaybackProvider.select((s) => s.speed));
    final notifier = ref.read(audioPlaybackProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                Expanded(
                  child: Text(
                    mode == PlaybackMode.radio ? 'بث مباشر' : 'مشغل التلاوات',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.secondary,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'مشاركة',
                  onPressed: currentUri.isEmpty
                      ? null
                      : () {
                          final text = [
                            if (currentTitle.isNotEmpty) currentTitle,
                            if (currentSubtitle.isNotEmpty) currentSubtitle,
                            currentUri,
                          ].join('\n');
                          Share.share(text);
                        },
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryContainer,
                    scheme.secondaryContainer,
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    mode == PlaybackMode.radio
                        ? Icons.radio_rounded
                        : Icons.graphic_eq_rounded,
                    size: 78,
                    color: scheme.primary,
                  ),
                  if (mode == PlaybackMode.radio)
                    Positioned(
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'مباشر',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onErrorContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              currentTitle.isEmpty ? 'لا يوجد مصدر قيد التشغيل' : currentTitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            Text(
              currentSubtitle.isEmpty
                  ? (mode == PlaybackMode.radio ? 'إذاعة قرآن' : 'تلاوة قرآنية')
                  : currentSubtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 18),
            const _PlayerProgress(),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _OptionButton(
                  icon: sleepMinutes == null
                      ? Icons.bedtime_outlined
                      : Icons.bedtime_rounded,
                  label: sleepMinutes == null
                      ? 'مؤقت'
                      : '$sleepMinutes د',
                  active: sleepMinutes != null,
                  onTap: () => showSleepTimerSheet(context, ref),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(72, 72),
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary,
                  ),
                  onPressed: notifier.togglePlayPause,
                  iconSize: 38,
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                _OptionButton(
                  icon: Icons.speed_rounded,
                  label: '${speed}x',
                  active: speed != 1.0,
                  onTap: () => showSpeedSheet(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                await notifier.stop();
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('إيقاف التشغيل'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 70,
        height: 62,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? scheme.secondaryContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? scheme.onSecondaryContainer : scheme.onSurface,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: active
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerProgress extends ConsumerWidget {
  const _PlayerProgress();

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(audioPlaybackProvider.select((s) => s.mode));
    final scheme = Theme.of(context).colorScheme;

    if (mode == PlaybackMode.radio) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'بث حي متواصل',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
        ),
      );
    }

    final position =
        ref.watch(audioPlaybackProvider.select((s) => s.position));
    final duration =
        ref.watch(audioPlaybackProvider.select((s) => s.duration));
    final notifier = ref.read(audioPlaybackProvider.notifier);
    final totalMs = duration.inMilliseconds;
    final value = totalMs > 0
        ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      children: [
        Slider(
          value: value,
          onChanged: totalMs > 0
              ? (next) => notifier.seek(
                    Duration(milliseconds: (next * totalMs).round()),
                  )
              : null,
        ),
        Row(
          children: [
            Text(
              _format(position),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const Spacer(),
            Text(
              _format(duration),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}
