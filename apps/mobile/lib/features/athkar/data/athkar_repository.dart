import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/services/content_sync_service.dart';
import '../domain/athkar_models.dart';
import 'athkar_source.dart';

/// Downloads the open-source Hisn al-Muslim collection once, stores it in a
/// local SQLite database (fully offline afterwards), and merges optional
/// seasonal athkar published through Supabase.
class AthkarRepository {
  AthkarRepository({ContentSyncService? syncService, http.Client? client})
      : _syncService = syncService ?? contentSyncService,
        _client = client ?? http.Client();

  static const sourceUrl =
      'https://raw.githubusercontent.com/rn0x/hisn_almuslim_json/main/hisn_almuslim.json';
  static const sourceLabel = 'حصن المسلم — hisn_almuslim_json (مصدر مفتوح)';
  static const seasonalTable = 'app_seasonal_athkar';
  static const _dbName = 'fadhkur_athkar.db';
  static const _dbVersion = 1;

  final ContentSyncService _syncService;
  final http.Client _client;
  Database? _db;
  AthkarLibrary? _cache;

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      '${dir.path}/$_dbName',
      version: _dbVersion,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE athkar_chapters (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            group_title TEXT NOT NULL,
            title TEXT NOT NULL,
            payload TEXT NOT NULL,
            sort_order INTEGER NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE athkar_counters (
            chapter_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            count INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (chapter_id, item_id)
          )
        ''');
        await database.execute('''
          CREATE TABLE tasbih_counters (
            id TEXT PRIMARY KEY,
            count INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  /// Offline-first: SQLite is the source of truth once it has been seeded.
  Future<AthkarLibrary> loadLibrary({bool forceRefresh = false}) async {
    final cached = _cache;
    if (cached != null && !forceRefresh) return cached;

    if (!forceRefresh) {
      final stored = await _readFromDatabase();
      if (stored.groups.isNotEmpty) {
        _cache = stored;
        return stored;
      }
    }

    final downloaded = await _download();
    if (downloaded != null) {
      await _persist(downloaded);
      _cache = downloaded;
      return downloaded;
    }

    final fallback = await _readFromDatabase();
    _cache = fallback;
    return fallback;
  }

  Future<AthkarLibrary?> _download() async {
    try {
      final response = await _client
          .get(Uri.parse(sourceUrl))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      return buildAthkarLibrary(
        Map<String, dynamic>.from(decoded),
        source: sourceLabel,
      );
    } catch (_) {
      return null;
    }
  }

  Future<AthkarLibrary> _readFromDatabase() async {
    try {
      final db = await _database();
      final rows = await db.query('athkar_chapters', orderBy: 'sort_order ASC');
      if (rows.isEmpty) return AthkarLibrary.empty;
      final grouped = <String, List<AthkarChapter>>{};
      final titles = <String, String>{};
      final order = <String>[];
      for (final row in rows) {
        final groupId = '${row['group_id']}';
        titles[groupId] = '${row['group_title']}';
        if (!order.contains(groupId)) order.add(groupId);
        final payload = jsonDecode('${row['payload']}');
        if (payload is! Map) continue;
        grouped
            .putIfAbsent(groupId, () => <AthkarChapter>[])
            .add(AthkarChapter.fromJson(Map<String, dynamic>.from(payload)));
      }
      return AthkarLibrary(
        source: sourceLabel,
        groups: order
            .map((id) => AthkarGroup(
                  id: id,
                  title: titles[id] ?? id,
                  chapters: grouped[id] ?? const [],
                ))
            .toList(growable: false),
      );
    } catch (_) {
      return AthkarLibrary.empty;
    }
  }

  Future<void> _persist(AthkarLibrary library) async {
    try {
      final db = await _database();
      final batch = db.batch();
      batch.delete('athkar_chapters');
      var order = 0;
      for (final group in library.groups) {
        for (final chapter in group.chapters) {
          batch.insert(
            'athkar_chapters',
            <String, Object?>{
              'id': chapter.id,
              'group_id': group.id,
              'group_title': group.title,
              'title': chapter.title,
              'payload': jsonEncode(chapter.toJson()),
              'sort_order': order++,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
    } catch (_) {
      // Keep serving the in-memory copy if storage is unavailable.
    }
  }

  /// Seasonal athkar (Ramadan, Hajj, Ashura...) published from Supabase.
  Future<AthkarGroup?> loadSeasonalGroup() async {
    try {
      final rows = await _syncService.loadCollection(seasonalTable, limit: 200);
      if (rows.isEmpty) return null;
      final chapters = <String, List<AthkarItem>>{};
      final titles = <String, String>{};
      for (final row in rows) {
        final chapterId = '${row['chapter_id'] ?? row['id'] ?? ''}'.trim();
        final text = '${row['text'] ?? ''}'.trim();
        if (chapterId.isEmpty || text.isEmpty) continue;
        titles[chapterId] = '${row['title'] ?? 'أذكار موسمية'}'.trim();
        final repeat = int.tryParse('${row['repeat'] ?? 1}') ?? 1;
        final bucket = chapters.putIfAbsent(chapterId, () => <AthkarItem>[]);
        bucket.add(
          AthkarItem(
            id: '${row['id'] ?? '$chapterId-${bucket.length}'}',
            text: text,
            repeat: repeat < 1 ? 1 : repeat,
            note: (row['note'] == null || '${row['note']}'.trim().isEmpty)
                ? null
                : '${row['note']}'.trim(),
          ),
        );
      }
      if (chapters.isEmpty) return null;
      return AthkarGroup(
        id: 'seasonal',
        title: 'أذكار موسمية',
        chapters: chapters.entries
            .map((entry) => AthkarChapter(
                  id: entry.key,
                  title: titles[entry.key] ?? 'أذكار موسمية',
                  items: entry.value,
                ))
            .toList(growable: false),
      );
    } catch (_) {
      return null;
    }
  }

  Future<AthkarProgress> loadProgress(String chapterId) async {
    try {
      final db = await _database();
      final rows = await db.query(
        'athkar_counters',
        where: 'chapter_id = ?',
        whereArgs: [chapterId],
      );
      final counts = <String, int>{
        for (final row in rows)
          '${row['item_id']}': (row['count'] as int?) ?? 0,
      };
      return AthkarProgress(chapterId: chapterId, counts: counts);
    } catch (_) {
      return AthkarProgress(chapterId: chapterId, counts: const {});
    }
  }

  Future<void> saveCount(String chapterId, String itemId, int count) async {
    try {
      final db = await _database();
      await db.insert(
        'athkar_counters',
        <String, Object?>{
          'chapter_id': chapterId,
          'item_id': itemId,
          'count': count,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> clearProgress(String chapterId) async {
    try {
      final db = await _database();
      await db.delete(
        'athkar_counters',
        where: 'chapter_id = ?',
        whereArgs: [chapterId],
      );
    } catch (_) {}
  }

  Future<int> loadTasbih(String id) async {
    try {
      final db = await _database();
      final rows = await db.query('tasbih_counters',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return 0;
      return (rows.first['count'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> saveTasbih(String id, int count) async {
    try {
      final db = await _database();
      await db.insert(
        'tasbih_counters',
        <String, Object?>{
          'id': id,
          'count': count,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }
}

final athkarRepositoryProvider =
    Provider<AthkarRepository>((ref) => AthkarRepository());

final athkarLibraryProvider = FutureProvider<AthkarLibrary>((ref) async {
  final repository = ref.watch(athkarRepositoryProvider);
  final library = await repository.loadLibrary();
  final seasonal = await repository.loadSeasonalGroup();
  if (seasonal == null) return library;
  return AthkarLibrary(
    source: library.source,
    groups: <AthkarGroup>[seasonal, ...library.groups],
  );
});
