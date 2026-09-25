import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/audio_playback_service.dart';
import '../../player/presentation/full_player_sheet.dart';

class MiniAudioPlayerBar extends ConsumerWidget {
  const MiniAudioPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSource =
        ref.watch(audioPlaybackProvider.select((s) => s.currentUri.isNotEmpty));
    if (!hasSource) return const SizedBox.shrink();

    final isPlaying =
        ref.watch(audioPlaybackProvider.select((s) => s.isPlaying));
    final mode = ref.watch(audioPlaybackProvider.select((s) => s.mode));
    final currentTitle =
        ref.watch(audioPlaybackProvider.select((s) => s.currentTitle));
    final currentSubtitle =
        ref.watch(audioPlaybackProvider.select((s) => s.currentSubtitle));
    final sleepMinutes = ref.watch(
      audioPlaybackProvider.select((s) => s.sleepTimerMinutes),
    );
    final notifier = ref.read(audioPlaybackProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const FullPlayerSheet(),
          );
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 10, 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  mode == PlaybackMode.radio
                      ? Icons.radio_rounded
                      : Icons.graphic_eq_rounded,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            currentSubtitle.isEmpty
                                ? (mode == PlaybackMode.radio
                                    ? 'بث مباشر'
                                    : 'تشغيل صوتي')
                                : currentSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                        ),
                        if (sleepMinutes != null) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.bedtime_outlined,
                            size: 14,
                            color: scheme.tertiary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$sleepMinutes د',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.tertiary),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
                onPressed: notifier.togglePlayPause,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
