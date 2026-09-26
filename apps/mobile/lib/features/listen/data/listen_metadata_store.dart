import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Small on-device catalog cache. Files and streams never enter SQLite.
class ListenMetadataStore {
  Database? _database;

  Future<Database> _open() async {
    if (_database != null) return _database!;
    final root = await getApplicationSupportDirectory();
    return _database = await openDatabase(
      '${root.path}/fadhkur_listen_metadata.db',
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE listen_catalog (
            dataset TEXT NOT NULL,
            cache_key TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (dataset, cache_key)
          )
        ''');
      },
    );
  }

  Future<({List<Map<String, dynamic>> rows, DateTime updatedAt})?> read(
      String dataset, String key) async {
    final db = await _open();
    final values = await db.query('listen_catalog',
      columns: ['payload', 'updated_at'],
      where: 'dataset = ? AND cache_key = ?', whereArgs: [dataset, key], limit: 1);
    if (values.isEmpty) return null;
    final raw = jsonDecode(values.first['payload'] as String);
    if (raw is! List) return null;
    return (
      rows: raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(values.first['updated_at'] as int),
    );
  }

  Future<void> write(String dataset, String key, List<Map<String, dynamic>> rows) async {
    final db = await _open();
    await db.insert('listen_catalog', {
      'dataset': dataset,
      'cache_key': key,
      'payload': jsonEncode(rows),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

final listenMetadataStore = ListenMetadataStore();
