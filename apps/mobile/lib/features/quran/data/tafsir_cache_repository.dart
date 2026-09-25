import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/tafsir_source.dart';

/// مخزن كاش التفاسير — قابل للحقن لتسهيل الاختبار دون قاعدة حقيقية.
abstract class TafsirCacheStore {
  Future<Map<String, dynamic>?> read(int resourceId, int chapter, int verse);
  Future<void> write(int resourceId, int chapter, int verse, Map<String, dynamic> json);
  Future<void> clear();
}

/// مخزن sqflite على القرص (fadhkur_tafsir.db).
///
/// لا يُحمَّل أي تفسير في الذاكرة إلا عند طلب الآية المشاهَدة مباشرةً؛
/// التخزين بمفتاح (المصدر + السورة + الآية) مع استبدال عند التحديث.
class SqfliteTafsirCacheStore implements TafsirCacheStore {
  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final database = await openDatabase(
      p.join(await getDatabasesPath(), 'fadhkur_tafsir.db'),
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE tafsir_entries('
        'resource_id INTEGER NOT NULL, '
        'chapter INTEGER NOT NULL, '
        'verse INTEGER NOT NULL, '
        'payload TEXT NOT NULL, '
        'updated_at INTEGER NOT NULL, '
        'PRIMARY KEY(resource_id, chapter, verse))',
      ),
    );
    _database = database;
    return database;
  }

  @override
  Future<Map<String, dynamic>?> read(int resourceId, int chapter, int verse) async {
    final db = await _open();
    final rows = await db.query(
      'tafsir_entries',
      columns: ['payload'],
      where: 'resource_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [resourceId, chapter, verse],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.first['payload'] as String);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(int resourceId, int chapter, int verse, Map<String, dynamic> json) async {
    final db = await _open();
    await db.insert(
      'tafsir_entries',
      {
        'resource_id': resourceId,
        'chapter': chapter,
        'verse': verse,
        'payload': jsonEncode(json),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clear() async {
    final db = await _open();
    await db.delete('tafsir_entries');
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}

/// مخزن في الذاكرة — للاختبارات فقط.
class InMemoryTafsirCacheStore implements TafsirCacheStore {
  final Map<String, Map<String, dynamic>> _entries = {};

  String _key(int resourceId, int chapter, int verse) => '$resourceId:$chapter:$verse';

  @override
  Future<Map<String, dynamic>?> read(int resourceId, int chapter, int verse) async =>
      _entries[_key(resourceId, chapter, verse)];

  @override
  Future<void> write(int resourceId, int chapter, int verse, Map<String, dynamic> json) async {
    _entries[_key(resourceId, chapter, verse)] = Map<String, dynamic>.from(json);
  }

  @override
  Future<void> clear() async => _entries.clear();
}

/// كاش التفاسير المشاهَدة: قراءة أولًا من القرص، وعند الغياب تُجلب من
/// الـ Backend عبر [api] ثم تُخزَّن للعرض دون اتصال.
///
/// [api] اختياري وحقنه ديناميكي (QuranApiRepository) لتفادي دورة استيراد.
class TafsirCacheRepository {
  TafsirCacheRepository({TafsirCacheStore? store, dynamic api})
      : _store = store ?? SqfliteTafsirCacheStore(),
        _api = api;

  final TafsirCacheStore _store;
  final dynamic _api;

  /// تفسير آية: من الكاش أولًا، ثم من الشبكة مع التخزين.
  /// إن غاب الكاش ولا يوجد api محقون رُمي StateError (لا بيانات وهمية).
  Future<TafsirEntry> get({
    required TafsirSource source,
    required String ayahKey,
  }) async {
    final parsed = _parseAyahKey(ayahKey);
    final cached = await _store.read(source.resourceId, parsed.chapter, parsed.verse);
    if (cached != null) {
      try {
        final entry = TafsirEntry.fromQuranFoundation(
          resourceId: source.resourceId,
          ayahKey: ayahKey,
          sourceNameAr: source.nameAr,
          json: cached,
        );
        if (entry.htmlText.isNotEmpty) return entry;
      } catch (_) {
        // كاش فاسد — نسقط للشبكة أدناه.
      }
    }
    final api = _api;
    if (api == null) {
      throw StateError('لا يوجد تفسير مخزّن لهذه الآية ولا اتصال متاح');
    }
    final entry = await api.getTafsir(source: source, ayahKey: ayahKey) as TafsirEntry;
    try {
      await _store.write(
        source.resourceId,
        parsed.chapter,
        parsed.verse,
        entry.toCacheJson(),
      );
    } catch (_) {
      // فشل التخزين لا يمنع عرض التفسير المجلوب.
    }
    return entry;
  }

  Future<void> clear() => _store.clear();

  static ({int chapter, int verse}) _parseAyahKey(String ayahKey) {
    final parts = ayahKey.trim().split(':');
    if (parts.length != 2) throw FormatException('مفتاح آية غير صالح: $ayahKey');
    final chapter = int.tryParse(parts[0]);
    final verse = int.tryParse(parts[1]);
    if (chapter == null || verse == null) {
      throw FormatException('مفتاح آية غير صالح: $ayahKey');
    }
    return (chapter: chapter, verse: verse);
  }
}
