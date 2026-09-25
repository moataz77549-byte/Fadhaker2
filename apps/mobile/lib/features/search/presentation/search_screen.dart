import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/audio_playback_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../quran/data/surah_metadata.dart';
import '../../radio/radio_catalog_provider.dart';
import '../../recitations/data/reciter_catalog_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';

  String _normalize(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه');
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(radioStationsProvider);
    final recitersAsync = ref.watch(recitersProvider);
    final audioNotifier = ref.read(audioPlaybackProvider.notifier);
    final normalizedQuery = _normalize(_query);

    final stations = stationsAsync.asData?.value ?? const [];
    final reciters = recitersAsync.asData?.value ?? const [];

    final filteredStations = normalizedQuery.isEmpty
        ? const []
        : stations
            .where(
              (s) =>
                  _normalize(s.nameAr).contains(normalizedQuery) ||
                  _normalize(s.currentTrack).contains(normalizedQuery),
            )
            .toList(growable: false);

    final filteredReciters = normalizedQuery.isEmpty
        ? const []
        : reciters
            .where(
              (r) =>
                  _normalize(r.nameAr).contains(normalizedQuery) ||
                  _normalize(r.riwaya).contains(normalizedQuery),
            )
            .toList(growable: false);

    final filteredSurahs = normalizedQuery.isEmpty
        ? const []
        : allSurahs
            .where(
              (s) =>
                  _normalize(s.displayName).contains(normalizedQuery) ||
                  s.number.toString() == normalizedQuery,
            )
            .toList(growable: false);

    final loading = stationsAsync.isLoading || recitersAsync.isLoading;
    final hasCatalogError = stationsAsync.hasError && recitersAsync.hasError;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'ابحث في السور، القراء، والمحطات...',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: (val) => setState(() => _query = val.trim()),
        ),
      ),
      body: _query.isEmpty
          ? const FadhkurEmptyState(
              icon: Icons.search_outlined,
              title: 'ابحث في التطبيق',
              subtitle: 'اكتب اسم سورة أو قارئ أو إذاعة للبحث المباشر.',
            )
          : loading
              ? const Center(child: CircularProgressIndicator())
              : hasCatalogError
                  ? FadhkurEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'تعذر تحديث كتالوج البحث',
                      subtitle:
                          'يمكنك البحث في السور الآن، وأعد المحاولة لتحميل القراء والمحطات.',
                      actionLabel: 'إعادة المحاولة',
                      onAction: () {
                        ref.invalidate(radioStationsProvider);
                        ref.invalidate(recitersProvider);
                      },
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (filteredSurahs.isNotEmpty) ...[
                          const Text(
                            'السور',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...filteredSurahs.map(
                            (s) => Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${s.number}'),
                                ),
                                title: Text(
                                  s.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text('${s.ayahs} آيات'),
                                onTap: () => Navigator.of(context).pushNamed(
                                  '/quran',
                                  arguments: {'surah': s.number},
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (filteredStations.isNotEmpty) ...[
                          const Text(
                            'المحطات الإذاعية',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...filteredStations.map(
                            (s) => Card(
                              child: ListTile(
                                leading: const Icon(
                                  Icons.radio,
                                  color: Color(0xFF2E9E9E),
                                ),
                                title: Text(
                                  s.nameAr,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: s.currentTrack.isEmpty
                                    ? null
                                    : Text(s.currentTrack),
                                trailing: IconButton(
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
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (filteredReciters.isNotEmpty) ...[
                          const Text(
                            'القراء',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...filteredReciters.map(
                            (r) => Card(
                              child: ListTile(
                                leading: const Icon(
                                  Icons.person,
                                  color: Color(0xFF2E9E9E),
                                ),
                                title: Text(
                                  r.nameAr,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(r.riwaya),
                                onTap: () =>
                                    Navigator.of(context).pushNamed('/reciters'),
                              ),
                            ),
                          ),
                        ],
                        if (filteredStations.isEmpty &&
                            filteredReciters.isEmpty &&
                            filteredSurahs.isEmpty)
                          const FadhkurEmptyState(
                            icon: Icons.search_off_outlined,
                            title: 'لا توجد نتائج مطابقة',
                            subtitle: 'جرّب كلمة بحث أخرى.',
                          ),
                      ],
                    ),
    );
  }
}
