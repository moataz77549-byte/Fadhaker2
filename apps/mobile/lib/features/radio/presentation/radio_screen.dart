import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/repositories/quran_yutla_repository.dart';
import '../../../core/services/audio_playback_service.dart';
import '../../../core/services/radio_catalog_service.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../player/presentation/playback_options.dart';
import '../radio_catalog_provider.dart';
import '../radio_station.dart';
import '../smart_radio_controller.dart';

class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(radioStationsProvider);
    // Selectors دقيقة: إعادة البناء فقط عند تغيّر حالة التشغيل/المحطة
    // الحالية — لا عند كل تحديث لموضع التشغيل (كل ثانية).
    final isPlaying =
        ref.watch(audioPlaybackProvider.select((s) => s.isPlaying));
    final currentUri =
        ref.watch(audioPlaybackProvider.select((s) => s.currentUri));
    final sleepMinutes = ref.watch(
        audioPlaybackProvider.select((s) => s.sleepTimerMinutes));
    final speed =
        ref.watch(audioPlaybackProvider.select((s) => s.speed));
    final playbackError = ref.watch(
        audioPlaybackProvider.select((s) => s.errorMessage));
    final audio = ref.read(audioPlaybackProvider.notifier);
    final smart = ref.watch(smartRadioProvider);
    final smartController = ref.read(smartRadioProvider.notifier);
    final favorites = ref.watch(favoritesProvider);
    final favoriteActions = ref.read(favoritesProvider.notifier);
    return Scaffold(
      body: stations.when(
        // Keep startup deterministic; this screen is also mounted in the
        // IndexedStack before the user opens the radio tab.
        loading: () => const SkeletonList(itemHeight: 88),
        error: (error, _) => FadhkurEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'تعذّر تحميل المحطات',
          subtitle: 'تحقق من الاتصال بالإنترنت ثم حاول مجددًا.',
          actionLabel: 'إعادة المحاولة',
          onAction: () => ref.invalidate(radioStationsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return FadhkurEmptyState(
              icon: Icons.radio_outlined,
              title: 'لا توجد محطات متاحة حاليًا',
              subtitle: 'تحقق من الاتصال بالإنترنت ثم حاول مجددًا.',
              actionLabel: 'إعادة المحاولة',
              onAction: () => ref.invalidate(radioStationsProvider),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(radioStationsProvider),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const FadhkurBrandMark(size: 68, isRadio: true),
              const SizedBox(height: 16),
              const Text('إذاعات القرآن الكريم المباشرة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('محطات الإدارة الإنتاجية أولًا ثم محطات افتراضية مدمجة',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
              const SizedBox(height: 12),
              _SmartRadioCard(
                state: smart,
                isPlaying: smart.active && isPlaying,
                onPlayPause: () async {
                  await AppHaptics.lightTap();
                  if (smart.active && isPlaying) {
                    // Pausing is an explicit user choice: stop automatic
                    // schedule switches as well so Smart Radio cannot resume
                    // itself later in the background.
                    smartController.deactivate();
                    await audio.togglePlayPause();
                  } else if (smart.active) {
                    await audio.togglePlayPause();
                  } else {
                    await smartController.start();
                  }
                },
                onRefresh: smart.active
                    ? () => smartController.refreshNow()
                    : null,
              ),
              const SizedBox(height: 12),
              if (playbackError != null) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.wifi_off_outlined),
                    title: Text(playbackError),
                    subtitle: const Text('اسحب للتحديث أو اختر إذاعة أخرى.'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _PlaybackControlsRow(
                sleepMinutes: sleepMinutes,
                speed: speed,
                onSleepTimer: () => showSleepTimerSheet(context, ref),
                onSpeed: () => showSpeedSheet(context, ref),
              ),
              const SizedBox(height: 12),
              ...items.map((station) {
                final active = currentUri == station.streamUrl && isPlaying;
                return _StationTile(
                  station: station,
                  active: active,
                  isFavorite: favorites.contains(station.id),
                  onToggleFavorite: () async {
                    favoriteActions.toggleFavorite(station.id);
                    await AppHaptics.confirm();
                  },
                  onPlayPause: () async {
                    await AppHaptics.lightTap();
                    if (!active) smartController.deactivate();
                    if (active) {
                      await audio.togglePlayPause();
                      return;
                    }
                    await audio.playRadio(
                      station.nameAr,
                      stationKindLabel(station.kind),
                      station.streamUrl,
                      fallbackUrl: station.fallbackUrl,
                      bitrateKbps: station.bitrateKbps,
                    );
                    if (ref.read(audioPlaybackProvider).errorMessage == null) return;
                    // A single bounded retry with the latest approved URL.
                    // If the catalog is offline the existing fallback remains
                    // available; no unbounded reconnect loop is started.
                    try {
                      final latest = await radioCatalogService.refreshStation(station.id);
                      if (latest != null) {
                        await audio.playRadio(
                          latest.nameAr,
                          stationKindLabel(latest.kind),
                          latest.streamUrl,
                          fallbackUrl: latest.fallbackUrl,
                          bitrateKbps: latest.bitrateKbps,
                        );
                      }
                    } catch (_) {
                      // Error banner above remains visible to the user.
                    }
                  },
                );
              }),
            ]),
          );
        },
      ),
    );
  }
}

class _SmartRadioCard extends StatelessWidget {
  const _SmartRadioCard({
    required this.state,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onRefresh,
  });

  final SmartRadioState state;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback? onRefresh;

  String? _timeOnly(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolution = state.resolution;
    final next = resolution?.next;
    final nextTime = _timeOnly(next?.startsAt);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: scheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إذاعة فذكر الذكية',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'محتوى يتغير حسب وقتك ومواقيت الصلاة',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onPrimary.withValues(alpha: 0.82),
                            ),
                      ),
                    ],
                  ),
                ),
                if (state.active && onRefresh != null)
                  IconButton(
                    tooltip: 'تحديث البرنامج الآن',
                    onPressed: state.loading ? null : onRefresh,
                    icon: Icon(Icons.refresh_rounded, color: scheme.onPrimary),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (state.loading && resolution == null)
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'جارٍ اختيار البرنامج الأنسب الآن…',
                    style: TextStyle(color: scheme.onPrimary),
                  ),
                ],
              )
            else ...[
              Text(
                resolution == null
                    ? 'الآن: تلاوات قرآنية حسب وقتك'
                    : 'الآن: ${resolution.program.title}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimary,
                    ),
              ),
              if (resolution != null) ...[
                const SizedBox(height: 3),
                Text(
                  resolution.program.sourceName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.82),
                      ),
                ),
              ],
              if (next != null) ...[
                const SizedBox(height: 8),
                Text(
                  nextTime == null
                      ? 'التالي: ${next.title}'
                      : 'التالي: ${next.title} • $nextTime',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.9),
                      ),
                ),
              ],
            ],
            if (state.usingFallback || state.message != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  state.message ?? 'يتم تشغيل الوضع الاحتياطي',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.onPrimary,
                foregroundColor: scheme.primary,
              ),
              onPressed: state.loading && resolution == null
                  ? null
                  : onPlayPause,
              icon: Icon(
                state.active && isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              label: Text(
                state.active && isPlaying
                    ? 'إيقاف مؤقت'
                    : state.active
                        ? 'متابعة التشغيل'
                        : 'تشغيل إذاعة فذكر',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// صف أدوات التشغيل: مؤقت النوم + سرعة التشغيل.
class _PlaybackControlsRow extends StatelessWidget {
  const _PlaybackControlsRow({
    required this.sleepMinutes,
    required this.speed,
    required this.onSleepTimer,
    required this.onSpeed,
  });

  final int? sleepMinutes;
  final double speed;
  final VoidCallback onSleepTimer;
  final VoidCallback onSpeed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onSleepTimer,
            icon: Icon(
              sleepMinutes == null
                  ? Icons.timer_outlined
                  : Icons.timer,
              size: 20,
              color: sleepMinutes == null ? null : scheme.primary,
            ),
            label: Text(
              sleepMinutes == null
                  ? 'مؤقت النوم'
                  : 'مؤقت: $sleepMinutes د',
              style: TextStyle(
                fontWeight: sleepMinutes == null
                    ? FontWeight.normal
                    : FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onSpeed,
            icon: Icon(
              Icons.speed_outlined,
              size: 20,
              color: speed == 1.0 ? null : scheme.primary,
            ),
            label: Text(
              speed == 1.0 ? 'سرعة التشغيل' : 'السرعة: ${speed}x',
              style: TextStyle(
                fontWeight:
                    speed == 1.0 ? FontWeight.normal : FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StationTile extends StatelessWidget {
  final RadioStation station;
  final bool active;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onPlayPause;

  const _StationTile({
    required this.station,
    required this.active,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _Logo(station: station, active: active),
        title: Text(station.nameAr),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _Chip(stationKindLabel(station.kind)),
                _Chip(station.streamType),
                if (station.isFeatured) const _Chip('مميزة'),
              ],
            ),
          ],
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(isFavorite ? Icons.star : Icons.star_border),
            tooltip: 'مفضلة',
            onPressed: onToggleFavorite,
          ),
          IconButton(
            icon: Icon(active ? Icons.pause : Icons.play_arrow),
            tooltip: active ? 'إيقاف مؤقت' : 'تشغيل',
            onPressed: onPlayPause,
          ),
        ]),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final RadioStation station;
  final bool active;

  const _Logo({required this.station, required this.active});

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(active ? Icons.equalizer : Icons.radio,
          color: Theme.of(context).colorScheme.onPrimaryContainer),
    );
    final url = station.logoUrl;
    if (url == null) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const SizedBox(width: 48, height: 48, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
