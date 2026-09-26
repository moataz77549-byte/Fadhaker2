import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_models.dart';
import '../../../core/repositories/fadhkur_repository.dart';
import '../../../core/services/audio_playback_service.dart';
import '../../quran/data/surah_metadata.dart';
import '../data/reciter_catalog_service.dart';

class RecitationsScreen extends ConsumerWidget {
  const RecitationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recitersAsync = ref.watch(recitersProvider);
    final favorites = ref.watch(favoritesProvider);
    final favNotifier = ref.read(favoritesProvider.notifier);

    return Scaffold(
      body: recitersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error is ReciterCatalogException
              ? error.userMessage
              : 'تعذّر تحميل القراء. حاول مجددًا.',
          onRetry: () => ref.invalidate(recitersProvider),
        ),
        data: (reciters) {
          if (reciters.isEmpty) {
            return const Center(
              child: Text(
                'لا يوجد قراء مفعّلون حاليًا.\nيمكن إدارتهم من لوحة الإدارة.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: reciters.length,
            itemBuilder: (context, index) {
              final reciter = reciters[index];
              final isFav = favorites.contains(reciter.id);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReciterDetailScreen(reciter: reciter),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor:
                              const Color(0xFF2E9E9E).withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.person,
                            color: Color(0xFF2E9E9E),
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reciter.nameAr,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                reciter.riwaya,
                                style: const TextStyle(
                                  color: Color(0xFF5B677A),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${reciter.surahsCount} سورة',
                                style: const TextStyle(
                                  color: Color(0xFFC77955),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isFav ? Icons.star : Icons.star_border,
                            color: const Color(0xFFC77955),
                          ),
                          onPressed: () => favNotifier.toggleFavorite(reciter.id),
                        ),
                        const Icon(
                          Icons.chevron_left,
                          color: Color(0xFF5B677A),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ReciterDetailScreen extends ConsumerWidget {
  final ReciterModel reciter;

  const ReciterDetailScreen({super.key, required this.reciter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(reciterTracksProvider(reciter.id));
    final audioNotifier = ref.read(audioPlaybackProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(reciter.nameAr)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              color: const Color(0xFF243B6B),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor:
                          const Color(0xFF2E9E9E).withValues(alpha: 0.25),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      reciter.nameAr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reciter.riwaya,
                      style: const TextStyle(
                        color: Color(0xFF2E9E9E),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (reciter.bio.isNotEmpty)
                      Text(
                        reciter.bio,
                        style: const TextStyle(
                          color: Color(0xFF9DAEC6),
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'المصدر: ${reciter.provider}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'التلاوات القرآنية الكاملة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: tracksAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(
                message: error is ReciterCatalogException
                    ? error.userMessage
                    : 'تعذّر تحميل التلاوات. حاول مجددًا.',
                onRetry: () =>
                    ref.invalidate(reciterTracksProvider(reciter.id)),
              ),
              data: (tracks) {
                if (tracks.isEmpty) {
                  return const Center(child: Text('لا توجد تلاوات متاحة لهذا القارئ حاليًا.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    if (track.surahNumber < 1 || track.surahNumber > allSurahs.length) {
                      return const SizedBox.shrink();
                    }
                    final surah = allSurahs[track.surahNumber - 1];
                    final playable = track.audioUrl.isNotEmpty;
                    final sName = surah.displayName;
                    final firstInMoshaf = index == 0 ||
                        tracks[index - 1].moshafId != track.moshafId;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      if (firstInMoshaf && track.moshafName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                          child: Text(track.moshafName,
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                      Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              const Color(0xFF2E9E9E).withValues(alpha: 0.12),
                          child: Text(
                            '${surah.number}',
                            style: const TextStyle(
                              color: Color(0xFF243B6B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          sName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          playable
                              ? '${surah.ayahs} آيات • ${surah.revelationType} • ${track.quality}'
                              : 'التلاوة غير متاحة في الكتالوج حاليًا',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.download_for_offline_outlined,
                                color: Color(0xFFC77955),
                              ),
                              tooltip: 'تنزيل التلاوة',
                              onPressed: !playable
                                  ? null
                                  : () => _downloadTrack(context, track.audioUrl,
                                        reciter.id, track.moshafId, surah.number),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.play_circle_outline,
                                color: Color(0xFF2E9E9E),
                                size: 30,
                              ),
                              tooltip: 'تشغيل',
                              onPressed: !playable
                                  ? null
                                  : () => _playTrack(audioNotifier, sName,
                                        reciter.nameAr, track.audioUrl,
                                        reciter.id, track.moshafId, surah.number),
                            ),
                          ],
                        ),
                      ),
                      ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<File> _trackFile(String reciterId, String moshafId, int surahNumber) async {
    final root = await getApplicationDocumentsDirectory();
    final safeId = reciterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeMoshaf = moshafId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final directory = safeMoshaf.isEmpty ? safeId : '$safeId/$safeMoshaf';
    return File('${root.path}/quran/recitations/$directory/'
        'surah_${surahNumber.toString().padLeft(3, '0')}.mp3');
  }

  Future<void> _playTrack(FadhkurAudioNotifier audio, String title,
      String reciter, String url, String reciterId, String moshafId,
      int surahNumber) async {
    final local = await _trackFile(reciterId, moshafId, surahNumber);
    if (await local.exists() && await local.length() > 0) {
      await audio.playOfflineTrack(title, reciter, local.path);
    } else {
      await audio.playQuranTrack(title, reciter, url);
    }
  }

  Future<void> _downloadTrack(
    BuildContext context,
    String url,
    String reciterId,
    String moshafId,
    int surahNumber,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(content: Text('جارٍ تنزيل التلاوة...')),
      );
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https') throw const HttpException('Invalid audio URL');
      final file = await _trackFile(reciterId, moshafId, surahNumber);
      await file.parent.create(recursive: true);
      final partial = File('${file.path}.part');
      final client = http.Client();
      try {
        final request = http.Request('GET', uri);
        final response = await client.send(request).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
        // Stream to disk rather than holding a full surah in memory. The
        // atomic rename keeps interrupted files out of offline playback.
        final sink = partial.openWrite();
        try {
          await response.stream.timeout(const Duration(seconds: 30))
              .pipe(sink);
        } finally {
          await sink.close();
        }
        if (await partial.length() == 0) throw const HttpException('Empty audio');
        if (await file.exists()) await file.delete();
        await partial.rename(file.path);
      } finally {
        client.close();
        if (await partial.exists()) await partial.delete();
      }
      messenger.showSnackBar(
        SnackBar(content: Text('تم تنزيل التلاوة في الجهاز')),
      );
    } catch (error) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر تنزيل التلاوة. تحقق من الاتصال وحاول مجددًا.')),
      );
    }
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
