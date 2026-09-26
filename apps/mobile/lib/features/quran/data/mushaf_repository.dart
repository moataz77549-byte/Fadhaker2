import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_navigation.dart';
import '../domain/riwaya.dart';
import 'quran_api_repository.dart';

class QuranTopic {
  const QuranTopic({required this.id, required this.title, this.parentId});
  final int id;
  final String title;
  final int? parentId;
}

/// مستودع صفحات المصحف (وضع النص).
///
/// - يجلب نص الصفحات عبر [QuranApiRepository] أي عبر Supabase Edge Function
///   (لا اتصال مباشر ولا أسرار في التطبيق).
/// - يخزّن الصفحات محليًا في sqflite بمفتاح (الرواية + الصفحة).
/// - يتحقق من نطاق الصفحة حسب تخطيط الرواية — لا افتراض 604 للجميع.
class MushafRepository {
  MushafRepository({QuranApiRepository? api}) : _api = api ?? QuranApiRepository();
  final QuranApiRepository _api;
  Database? _database;

  Future<MushafPage> page({required Riwaya riwaya, required int page}) async {
    final validated = QuranNavigation.validateTextPage(page);
    final database = await _openDatabase();
    final cacheKey = '${riwaya.id}:$validated';
    final cached = await database.query(
      'mushaf_pages',
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (cached.isNotEmpty) {
      return MushafPage.decode(cached.first['payload'] as String);
    }
    final result = await _api.getPageText(riwaya: riwaya, page: validated);
    await database.insert(
      'mushaf_pages',
      {
        'cache_key': cacheKey,
        'payload': result.encode(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return result;
  }

  /// Sync the small subject index after first use and at most once per week.
  /// An interrupted sync leaves the previous complete catalog intact.
  Future<void> refreshTopicsIfNeeded({bool force = false}) async {
    final db = await _openDatabase();
    final state = await db.query('topic_sync', where: 'source = ?',
        whereArgs: ['quranpedia'], limit: 1);
    final updated = state.isEmpty ? 0 : state.first['updated_at'] as int;
    if (!force && DateTime.now().millisecondsSinceEpoch - updated <
        const Duration(days: 7).inMilliseconds) return;
    final catalog = await _api.topicCatalog();
    final raw = catalog['topics'];
    if (raw is! List || raw.isEmpty || raw.length > 30000) {
      throw StateError('فهرس الموضوعات غير متاح');
    }
    final topics = <Map<String, Object?>>[];
    final links = <Map<String, Object?>>[];
    for (final entry in raw) {
      if (entry is! Map) throw const FormatException('Invalid topic entry');
      final id = entry['id'];
      final title = entry['name'];
      final ayahs = entry['ayahs'];
      if (id is! int || title is! String || title.trim().isEmpty ||
          ayahs is! String) throw const FormatException('Invalid topic fields');
      topics.add({'id': id, 'title_ar': title, 'parent_id': entry['parent_id']});
      for (final key in ayahs.split(',')) {
        final verseKey = key.trim();
        if (verseKey.isEmpty) continue;
        QuranNavigation.parseAyahKey(verseKey);
        links.add({'verse_key': verseKey, 'topic_id': id});
      }
    }
    if (links.isEmpty) throw const FormatException('Empty verse-topic mapping');
    await db.transaction((txn) async {
      await txn.delete('verse_topics');
      await txn.delete('quran_topics');
      for (final topic in topics) {
        await txn.insert('quran_topics', topic);
      }
      for (final link in links) {
        await txn.insert('verse_topics', link,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.insert('topic_sync', {
        'source': 'quranpedia',
        'version': (catalog['version'] ?? 'api-v1').toString(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<QuranTopic>> topicsForVerse(String verseKey) async {
    QuranNavigation.parseAyahKey(verseKey);
    final db = await _openDatabase();
    final rows = await db.rawQuery('SELECT t.id, t.title_ar, t.parent_id '
        'FROM quran_topics t JOIN verse_topics v ON v.topic_id = t.id '
        'WHERE v.verse_key = ? ORDER BY t.id', [verseKey]);
    return rows.map(_topicFromRow).toList(growable: false);
  }

  Future<Map<String, List<QuranTopic>>> topicsForPage(MushafPage page) async {
    final result = <String, List<QuranTopic>>{};
    for (final ayah in page.ayahs) {
      result[ayah.key] = await topicsForVerse(ayah.key);
    }
    return result;
  }

  Future<List<QuranTopic>> searchTopics(String query) async {
    if (query.trim().isEmpty) return const [];
    final db = await _openDatabase();
    final escaped = query.trim().replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%').replaceAll('_', r'\_');
    final rows = await db.rawQuery(
      "SELECT id, title_ar, parent_id FROM quran_topics "
      "WHERE title_ar LIKE ? ESCAPE '\\' LIMIT 50", ['%$escaped%']);
    return rows.map(_topicFromRow).toList(growable: false);
  }

  Future<List<String>> versesForTopic(int topicId) async {
    final db = await _openDatabase();
    final rows = await db.query('verse_topics', columns: ['verse_key'],
        where: 'topic_id = ?', whereArgs: [topicId]);
    return rows.map((row) => row['verse_key'] as String).toList(growable: false);
  }

  static QuranTopic _topicFromRow(Map<String, Object?> row) => QuranTopic(
    id: row['id'] as int, title: row['title_ar'] as String,
    parentId: row['parent_id'] as int?,
  );

  Future<Database> _openDatabase() async {
    final existing = _database;
    if (existing != null) return existing;
    final database = await openDatabase(
      p.join(await getDatabasesPath(), 'fadhkur_mushaf.db'),
      version: 3,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE mushaf_pages(cache_key TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL)');
        await _createTopicTables(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          // Preserve already cached pages and all user data on older installs.
          await db.execute('CREATE TABLE IF NOT EXISTS mushaf_pages(cache_key TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL)');
        }
        if (oldVersion < 3) await _createTopicTables(db);
      },
    );
    _database = database;
    return database;
  }

  static Future<void> _createTopicTables(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE quran_topics(id INTEGER PRIMARY KEY, title_ar TEXT NOT NULL, parent_id INTEGER)');
    await db.execute('CREATE TABLE verse_topics(verse_key TEXT NOT NULL, topic_id INTEGER NOT NULL, PRIMARY KEY(verse_key, topic_id))');
    await db.execute('CREATE INDEX verse_topics_by_topic ON verse_topics(topic_id)');
    await db.execute('CREATE TABLE topic_sync(source TEXT PRIMARY KEY, version TEXT NOT NULL, updated_at INTEGER NOT NULL)');
  }

  void dispose() {
    _api.dispose();
    _database?.close();
    _database = null;
  }
}
