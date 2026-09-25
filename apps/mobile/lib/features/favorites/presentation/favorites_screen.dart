import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repositories/fadhkur_repository.dart';
import '../../../core/services/audio_playback_service.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/empty_state.dart';
import '../../radio/radio_catalog_provider.dart';
import '../../recitations/data/reciter_catalog_service.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stationsAsync = ref.watch(radioStationsProvider);
    final recitersAsync = ref.watch(recitersProvider);
    final favorites = ref.watch(favoritesProvider);
    final favNotifier = ref.read(favoritesProvider.notifier);
    final audioNotifier = ref.read(audioPlaybackProvider.notifier);

    final stations = stationsAsync.asData?.value ?? const [];
    final reciters = recitersAsync.asData?.value ?? const [];
    final favStations =
        stations.where((s) => favorites.contains(s.id)).toList(growable: false);
    final favReciters =
        reciters.where((r) => favorites.contains(r.id)).toList(growable: false);

    if ((stationsAsync.isLoading || recitersAsync.isLoading) &&
        favorites.isNotEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          bottom: TabBar(
            tabs: [
              Tab(text: 'المحطات المفضلة'),
              Tab(text: 'القراء المفضلون'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            favStations.isEmpty
                ? FadhkurEmptyState(
                    icon: Icons.radio_outlined,
                    title: 'لا توجد محطات في المفضلة حاليًا',
                    subtitle: stationsAsync.hasError
                        ? 'تعذر تحديث كتالوج المحطات. أعد المحاولة عند توفر الاتصال.'
                        : 'اضغط على النجمة بجانب أي محطة في شاشة الإذاعة لحفظها هنا.',
                    actionLabel:
                        stationsAsync.hasError ? 'إعادة المحاولة' : 'تصفح الإذاعات',
                    onAction: () {
                      if (stationsAsync.hasError) {
                        ref.invalidate(radioStationsProvider);
                      } else {
                        Navigator.of(context).pushNamed('/radio');
                      }
                    },
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: favStations.length,
                    itemBuilder: (ctx, i) {
                      final s = favStations[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.radio,
                            color: Color(0xFF2E9E9E),
                          ),
                          title: Text(
                            s.nameAr,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle:
                              s.currentTrack.isEmpty ? null : Text(s.currentTrack),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.star,
                                  color: Color(0xFFC77955),
                                ),
                                onPressed: () async {
                                  favNotifier.toggleFavorite(s.id);
                                  await AppHaptics.confirm();
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.play_arrow,
                                  color: Color(0xFF243B6B),
                                ),
                                onPressed: () => audioNotifier.playRadio(
                                    s.nameAr,
                                    s.currentTrack,
                                    s.streamUrl,
                                    fallbackUrl: s.fallbackUrl,
                                    bitrateKbps: s.bitrateKbps,
                                  ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            favReciters.isEmpty
                ? FadhkurEmptyState(
                    icon: Icons.record_voice_over_outlined,
                    title: 'لا يوجد قراء في المفضلة حاليًا',
                    subtitle: recitersAsync.hasError
                        ? 'تعذر تحديث كتالوج القراء. أعد المحاولة عند توفر الاتصال.'
                        : 'اضغط على النجمة بجانب أي قارئ لحفظه هنا والوصول السريع لتلاواته.',
                    actionLabel:
                        recitersAsync.hasError ? 'إعادة المحاولة' : 'تصفح القراء',
                    onAction: () {
                      if (recitersAsync.hasError) {
                        ref.invalidate(recitersProvider);
                      } else {
                        Navigator.of(context).pushNamed('/reciters');
                      }
                    },
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: favReciters.length,
                    itemBuilder: (ctx, i) {
                      final r = favReciters[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.person,
                            color: Color(0xFF2E9E9E),
                          ),
                          title: Text(
                            r.nameAr,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(r.riwaya),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.star,
                              color: Color(0xFFC77955),
                            ),
                            onPressed: () async {
                              favNotifier.toggleFavorite(r.id);
                              await AppHaptics.confirm();
                            },
                          ),
                          onTap: () =>
                              Navigator.of(context).pushNamed('/reciters'),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
