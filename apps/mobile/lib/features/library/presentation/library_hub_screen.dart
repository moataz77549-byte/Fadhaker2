import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_models.dart';
import '../../../core/repositories/fadhkur_repository.dart';

class LibraryHubScreen extends ConsumerWidget {
  const LibraryHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).length;
    final playlists = ref.watch(playlistsProvider).length;
    final downloads = ref.watch(downloadsProvider)
        .where((item) => item.status == DownloadStatus.completed)
        .length;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('مكتبتي', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'المحتوى الذي حفظته أنت، وليس قوائم افتراضية.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: '$favorites',
                label: 'مفضلة',
                icon: Icons.star_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                value: '$playlists',
                label: 'قوائم',
                icon: Icons.queue_music_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                value: '$downloads',
                label: 'تنزيلات',
                icon: Icons.download_done_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _LibraryTile(
          icon: Icons.star_rounded,
          title: 'المفضلة',
          subtitle: 'القراء والمحطات التي حفظتها',
          route: '/favorites',
        ),
        _LibraryTile(
          icon: Icons.queue_music_rounded,
          title: 'قوائم التشغيل',
          subtitle: 'ورد الاستماع والقوائم الشخصية',
          route: '/playlists',
        ),
        _LibraryTile(
          icon: Icons.download_for_offline_rounded,
          title: 'التنزيلات',
          subtitle: 'الاستماع دون اتصال وحالة التحقق',
          route: '/library',
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, color: scheme.secondary),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => Navigator.of(context).pushNamed(route),
      ),
    );
  }
}
