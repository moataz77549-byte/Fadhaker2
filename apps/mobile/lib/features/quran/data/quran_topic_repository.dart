import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/mushaf_page.dart';
import '../domain/quran_topic.dart';
import 'quran_topic_provider.dart';
import 'quranpedia_topic_provider.dart';

class QuranTopicRepository {
  QuranTopicRepository({QuranTopicProvider? provider})
      : _provider = provider ?? QuranpediaTopicProvider();

  final QuranTopicProvider _provider;
  Database? _database;
  Future<void>? _syncFuture;

  static const _dbName = 'fadhkur_quran_topics.db';
  static const _sourceId = 'quranpedia-topics-v1';

  Future<void> ensureSynced() {
    final inFlight = _syncFuture;
    if (inFlight != null) return inFlight;
    final next = _ensureSyncedInternal();
    _syncFuture = next;
    return next.whenComplete(() {
      if (identical(_syncFuture, next)) _syncFuture = null;
    });
  }

  Future<void> _ensureSyncedInternal() async {
    final db = await _openDatabase();
    final rows = await db.query(
      'topic_source',
      where: 'source_id = ?',
      whereArgs: [_sourceId],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _fullSync(db);
      return;
    }
    final lastUpdatedMs = (rows.first['last_updated'] as num?)?.toInt() ?? 0;
    final lastUpdated = DateTime.fromMillisecondsSinceEpoch(lastUpdatedMs);
    if (DateTime.now().difference(lastUpdated) < const Duration(hours: 24)) {
      return;
    }
    var changed = true;
    try {
      changed = await _provider.hasUpdatesSince(lastUpdated);
    } catch (_) {
      return;
    }
    if (changed) {
      try {
        await _fullSync(db);
      } catch (_) {
        // A cached dataset remains usable when a background refresh fails.
      }
    } else {
      await db.update(
        'topic_source',
        {'last_updated': DateTime.now().millisecondsSinceEpoch},
        where: 'source_id = ?',
        whereArgs: [_sourceId],
      );
    }
  }

  Future<void> _fullSync(Database db) async {
    final records = await _provider.fetchAllTopics();
    if (records.isEmpty) {
      throw StateError('قاعدة الموضوعات المستلمة فارغة');
    }
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.delete('verse_topic');
      await txn.delete('topic');
      final topicBatch = txn.batch();
      final linkBatch = txn.batch();
      for (final record in records) {
        final topic = record.topic;
        topicBatch.insert(
          'topic',
          {
            'id': topic.id,
            'title_ar': topic.titleAr,
            'parent_topic_id': topic.parentTopicId,
            'category': topic.category,
            'source': topic.source,
            'source_reference': topic.sourceReference,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        var order = 0;
        for (final key in record.verseKeys) {
          linkBatch.insert(
            'verse_topic',
            {
              'verse_key': key,
              'topic_id': topic.id,
              'segment_start': null,
              'segment_end': null,
              'sort_order': order++,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      await topicBatch.commit(noResult: true);
      await linkBatch.commit(noResult: true);
      await txn.insert(
        'topic_source',
        {
          'source_id': _sourceId,
          'source_name': _provider.sourceName,
          'source_version': _provider.sourceVersion,
          'license': _provider.licenseReference,
          'attribution': _provider.attribution,
          'last_updated': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<QuranTopic>> topicsForVerse(String verseKey) async {
    await ensureSynced();
    final db = await _openDatabase();
    final rows = await db.rawQuery(
      '''
      SELECT t.id, t.title_ar, t.parent_topic_id, t.category,
             t.source, t.source_reference
      FROM topic t
      INNER JOIN verse_topic vt ON vt.topic_id = t.id
      WHERE vt.verse_key = ?
      ORDER BY vt.sort_order, t.title_ar
      ''',
      [verseKey],
    );
    return rows.map(_topicFromRow).toList(growable: false);
  }

  Future<Map<String, List<QuranTopic>>> topicsForPage(MushafPage page) async {
    await ensureSynced();
    final keys = page.ayahs.map((a) => a.key).where((k) => k.isNotEmpty).toList();
    if (keys.isEmpty) return const {};
    final db = await _openDatabase();
    final placeholders = List.filled(keys.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT vt.verse_key, vt.sort_order,
             t.id, t.title_ar, t.parent_topic_id, t.category,
             t.source, t.source_reference
      FROM verse_topic vt
      INNER JOIN topic t ON t.id = vt.topic_id
      WHERE vt.verse_key IN ($placeholders)
      ORDER BY vt.verse_key, vt.sort_order, t.title_ar
      ''',
      keys,
    );
    final result = <String, List<QuranTopic>>{};
    for (final row in rows) {
      final key = row['verse_key'] as String;
      (result[key] ??= <QuranTopic>[]).add(_topicFromRow(row));
    }
    return result;
  }

  Future<List<QuranTopicRecord>> searchTopics(String query) async {
    await ensureSynced();
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    final db = await _openDatabase();
    final topics = await db.query(
      'topic',
      where: 'title_ar LIKE ?',
      whereArgs: ['%$normalized%'],
      orderBy: 'title_ar',
      limit: 40,
    );
    final result = <QuranTopicRecord>[];
    for (final row in topics) {
      final id = (row['id'] as num).toInt();
      final verseRows = await db.query(
        'verse_topic',
        columns: ['verse_key'],
        where: 'topic_id = ?',
        whereArgs: [id],
        orderBy: 'sort_order',
        limit: 100,
      );
      result.add(
        QuranTopicRecord(
          topic: _topicFromRow(row),
          verseKeys: verseRows
              .map((e) => e['verse_key'] as String)
              .toList(growable: false),
        ),
      );
    }
    return result;
  }

  Future<List<String>> relatedVerseKeys(int topicId) async {
    await ensureSynced();
    final db = await _openDatabase();
    final rows = await db.query(
      'verse_topic',
      columns: ['verse_key'],
      where: 'topic_id = ?',
      whereArgs: [topicId],
      orderBy: 'sort_order',
    );
    return rows.map((e) => e['verse_key'] as String).toList(growable: false);
  }

  QuranTopic _topicFromRow(Map<String, Object?> row) => QuranTopic(
        id: (row['id'] as num).toInt(),
        titleAr: row['title_ar'] as String,
        parentTopicId: (row['parent_topic_id'] as num?)?.toInt(),
        category: row['category'] as String?,
        source: (row['source'] as String?) ?? 'quranpedia',
        sourceReference: row['source_reference'] as String?,
      );

  Future<Database> _openDatabase() async {
    final existing = _database;
    if (existing != null) return existing;
    final db = await openDatabase(
      p.join(await getDatabasesPath(), _dbName),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE topic(
            id INTEGER PRIMARY KEY,
            title_ar TEXT NOT NULL,
            parent_topic_id INTEGER,
            category TEXT,
            source TEXT NOT NULL,
            source_reference TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE verse_topic(
            verse_key TEXT NOT NULL,
            topic_id INTEGER NOT NULL,
            segment_start INTEGER,
            segment_end INTEGER,
            sort_order INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(verse_key, topic_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_verse_topic_topic ON verse_topic(topic_id)',
        );
        await db.execute('''
          CREATE TABLE topic_source(
            source_id TEXT PRIMARY KEY,
            source_name TEXT NOT NULL,
            source_version TEXT NOT NULL,
            license TEXT NOT NULL,
            attribution TEXT NOT NULL,
            last_updated INTEGER NOT NULL
          )
        ''');
      },
    );
    _database = db;
    return db;
  }

  Future<void> dispose() async {
    final db = _database;
    _database = null;
    if (db != null) await db.close();
    if (_provider is QuranpediaTopicProvider) {
      _provider.dispose();
    }
  }
}
