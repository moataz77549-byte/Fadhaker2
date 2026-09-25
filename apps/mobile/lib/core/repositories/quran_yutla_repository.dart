import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';
import '../services/quran_download_service.dart';
import '../services/radio_catalog_service.dart';

/// Compatibility repository.
///
/// Remote catalogs are deliberately NOT mirrored here. Production stations and
/// reciters are exposed through feature-specific live providers so screens
/// cannot accidentally fall back to stale hard-coded demo content.
class FadhkurRepository {
  const FadhkurRepository();

  List<RadioStationModel> get stations => const [];
  List<ReciterModel> get reciters => const [];
  List<DhikrModel> get adhkarList => const [];
  List<MemorizationPlanModel> get memorizationPlans => const [];
}

final quranRepositoryProvider =
    Provider<FadhkurRepository>((ref) => const FadhkurRepository());

final radioCatalogProvider = FutureProvider<List<RadioStationModel>>((ref) async {
  return radioCatalogService.load();
});

class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super(const {}) {
    unawaited(_restore());
  }

  static const _prefsKey = 'fadhkur.library.favorite_ids.v1';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefsKey) ?? const <String>[];
      if (saved.isNotEmpty && state.isEmpty) {
        state = saved.toSet();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = state.toList()..sort();
      await prefs.setStringList(_prefsKey, values);
    } catch (_) {}
  }

  void toggleFavorite(String id) {
    if (id.trim().isEmpty) return;
    final next = {...state};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
    unawaited(_persist());
  }

  bool isFavorite(String id) => state.contains(id);
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<String>>(
  (ref) => FavoritesNotifier(),
);

class PlaylistsNotifier extends StateNotifier<List<PlaylistModel>> {
  PlaylistsNotifier() : super(const []) {
    unawaited(_restore());
  }

  static const _prefsKey = 'fadhkur.library.playlists.v1';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty || state.isNotEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      state = decoded
          .whereType<Map>()
          .map((row) => _playlistFromJson(Map<String, dynamic>.from(row)))
          .whereType<PlaylistModel>()
          .toList(growable: false);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(state.map(_playlistToJson).toList(growable: false)),
      );
    } catch (_) {}
  }

  void createPlaylist(String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    state = [
      ...state,
      PlaylistModel(
        id: 'pl-${DateTime.now().microsecondsSinceEpoch}',
        name: cleanName,
        createdAt: DateTime.now(),
      ),
    ];
    unawaited(_persist());
  }

  void renamePlaylist(String id, String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    state = state
        .map((p) => p.id == id ? p.copyWith(name: cleanName) : p)
        .toList(growable: false);
    unawaited(_persist());
  }

  void deletePlaylist(String id) {
    state = state.where((p) => p.id != id).toList(growable: false);
    unawaited(_persist());
  }

  void addItemToPlaylist(String id, PlaylistItemModel item) {
    state = state
        .map((p) => p.id == id ? p.copyWith(items: [...p.items, item]) : p)
        .toList(growable: false);
    unawaited(_persist());
  }

  static Map<String, dynamic> _playlistToJson(PlaylistModel playlist) => {
        'id': playlist.id,
        'name': playlist.name,
        'created_at': playlist.createdAt.toIso8601String(),
        'items': playlist.items
            .map((item) => {
                  'id': item.id,
                  'title': item.title,
                  'subtitle': item.subtitle,
                  'audio_url': item.audioUrl,
                  'surah_number': item.surahNumber,
                  'reciter_id': item.reciterId,
                })
            .toList(growable: false),
      };

  static PlaylistModel? _playlistFromJson(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final name = row['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final rawItems = row['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map((raw) {
            final item = Map<String, dynamic>.from(raw);
            final surah = (item['surah_number'] as num?)?.toInt() ?? 0;
            return PlaylistItemModel(
              id: item['id']?.toString() ?? '',
              title: item['title']?.toString() ?? '',
              subtitle: item['subtitle']?.toString() ?? '',
              audioUrl: item['audio_url']?.toString() ?? '',
              surahNumber: surah,
              reciterId: item['reciter_id']?.toString() ?? '',
            );
          }).where((item) => item.id.isNotEmpty).toList(growable: false)
        : const <PlaylistItemModel>[];
    return PlaylistModel(
      id: id,
      name: name,
      items: items,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

final playlistsProvider =
    StateNotifierProvider<PlaylistsNotifier, List<PlaylistModel>>(
  (ref) => PlaylistsNotifier(),
);

class DownloadsNotifier extends StateNotifier<List<DownloadTaskModel>> {
  DownloadsNotifier() : super(const []);

  Future<void> addDownload(
    int surahNumber,
    String surahName,
    String reciterName, [
    String reciterPath = 'Abdul_Basit_Murattal_64kbps',
  ]) async {
    final id = 'dl-${DateTime.now().millisecondsSinceEpoch}';
    final task = DownloadTaskModel(
      id: id,
      surahNumber: surahNumber,
      surahNameAr: surahName,
      reciterNameAr: reciterName,
      expectedSha256: '',
      status: DownloadStatus.downloading,
    );
    state = [...state, task];
    try {
      final result = await quranDownloadService.downloadSurah(
        surah: surahNumber,
        reciterPath: reciterPath,
        firstAyah: 1,
        lastAyah: _ayahCount(surahNumber),
        onProgress: (progress) => state = state
            .map(
              (d) => d.id == id
                  ? d.copyWith(
                      progressPercent: (progress * 100).round(),
                      downloadedBytes:
                          (progress * resultBytesEstimate).round(),
                    )
                  : d,
            )
            .toList(),
      );
      state = state
          .map(
            (d) => d.id == id
                ? d.copyWith(
                    progressPercent: 100,
                    status: DownloadStatus.completed,
                    localPath: result.path,
                    downloadedBytes: result.bytes,
                  )
                : d,
          )
          .toList();
    } catch (_) {
      state = state
          .map((d) =>
              d.id == id ? d.copyWith(status: DownloadStatus.failed) : d)
          .toList();
    }
  }

  static const resultBytesEstimate = 24000000;

  int _ayahCount(int surah) =>
      const {1: 7, 2: 286, 18: 110, 36: 83, 55: 78, 67: 30, 114: 6}[surah] ??
      7;

  void deleteDownload(String id) =>
      state = state.where((d) => d.id != id).toList();

  void togglePauseResume(String id) {
    state = state
        .map(
          (d) => d.id == id
              ? d.copyWith(
                  status: d.status == DownloadStatus.downloading
                      ? DownloadStatus.paused
                      : DownloadStatus.downloading,
                )
              : d,
        )
        .toList();
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, List<DownloadTaskModel>>(
  (ref) => DownloadsNotifier(),
);
