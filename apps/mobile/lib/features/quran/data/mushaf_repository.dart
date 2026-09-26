import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_navigation.dart';
import '../domain/riwaya.dart';
import 'quran_api_repository.dart';

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
      await database.update(
        'mushaf_pages',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
      );
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
    // Page payloads are reproducible cache, not user data. Keep a bounded LRU
    // window on disk so long-term browsing never grows storage without limit.
    await database.rawDelete(
      '''
      DELETE FROM mushaf_pages
      WHERE cache_key NOT IN (
        SELECT cache_key FROM mushaf_pages
        ORDER BY updated_at DESC
        LIMIT 180
      )
      ''',
    );
    return result;
  }

  Future<Database> _openDatabase() async {
    final existing = _database;
    if (existing != null) return existing;
    final database = await openDatabase(
      p.join(await getDatabasesPath(), 'fadhkur_mushaf.db'),
      version: 3,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE mushaf_pages(cache_key TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL)',
      ),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS mushaf_pages');
          await db.execute(
            'CREATE TABLE mushaf_pages(cache_key TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL)',
          );
        }
        // v3 adds QCF word/line metadata to the cached payload. This table is
        // cache-only, so clearing it is safe and preserves bookmarks/progress.
        if (oldVersion >= 2 && oldVersion < 3) {
          await db.delete('mushaf_pages');
        }
      },
    );
    _database = database;
    return database;
  }

  void dispose() {
    _api.dispose();
    _database?.close();
    _database = null;
  }
}
