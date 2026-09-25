import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/features_manager.dart';

class ListenHubScreen extends ConsumerWidget {
  const ListenHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(featuresManagerProvider);
    final scheme = Theme.of(context).colorScheme;

    final items = <_ListenItem>[
      if (features.radioEnabled)
        const _ListenItem(
          title: 'إذاعات القرآن',
          subtitle: 'بث مباشر ومحطات قرآنية منتقاة',
          icon: Icons.radio_rounded,
          route: '/radio',
        ),
      const _ListenItem(
        title: 'القراء والتلاوات',
        subtitle: 'استمع حسب القارئ والسورة والرواية',
        icon: Icons.record_voice_over_rounded,
        route: '/reciters',
      ),
      const _ListenItem(
        title: 'قوائم التشغيل',
        subtitle: 'رتّب ورد الاستماع والسور المحفوظة',
        icon: Icons.queue_music_rounded,
        route: '/playlists',
      ),
      const _ListenItem(
        title: 'القنوات المرئية',
        subtitle: 'دروس ومحاضرات وقنوات موثقة',
        icon: Icons.ondemand_video_rounded,
        route: '/video',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'الاستماع',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'كل ما تسمعه في مكان واحد، مع استمرار التشغيل في الخلفية.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primary,
                scheme.primaryContainer,
              ],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.headphones_rounded,
                  color: scheme.onPrimary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'استماع مستمر',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'التحكم من شاشة القفل والإشعارات متاح على Android.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimary.withValues(alpha: 0.82),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ListenCard(item: item),
          ),
        ),
      ],
    );
  }
}

class _ListenCard extends StatelessWidget {
  const _ListenCard({required this.item});
  final _ListenItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).pushNamed(item.route),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(item.icon, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListenItem {
  const _ListenItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}
