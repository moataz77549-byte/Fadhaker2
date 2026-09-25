import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/services/notification_service.dart';
import '../domain/personal_reminder.dart';

/// Offline-first storage for user-created reminders, with automatic
/// (re)scheduling of the matching exact alarms.
class PersonalReminderRepository {
  PersonalReminderRepository({LocalAlarmScheduler? scheduler})
      : _scheduler = scheduler ?? localAlarmScheduler;

  final LocalAlarmScheduler _scheduler;
  Database? _db;

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;

    final directory = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      '${directory.path}/fadhkur_reminders.db',
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE personal_reminders (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            hour INTEGER NOT NULL,
            minute INTEGER NOT NULL,
            weekdays TEXT NOT NULL DEFAULT '',
            sound TEXT NOT NULL DEFAULT 'soft',
            custom_sound_path TEXT,
            enabled INTEGER NOT NULL DEFAULT 1
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  Future<List<PersonalReminder>> loadAll() async {
    final db = await _database();
    final rows = await db.query(
      'personal_reminders',
      orderBy: 'hour ASC, minute ASC',
    );
    return rows.map(PersonalReminder.fromMap).toList(growable: false);
  }

  Future<PersonalReminder> save(PersonalReminder reminder) async {
    final db = await _database();
    var stored = reminder;

    if (reminder.id == 0) {
      final id = await db.insert(
        'personal_reminders',
        Map<String, Object?>.from(reminder.toMap())..remove('id'),
      );
      stored = reminder.copyWith(id: id);
    } else {
      await db.insert(
        'personal_reminders',
        stored.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    try {
      await _scheduler.schedulePersonalReminder(stored);
    } catch (error) {
      debugPrint('Reminder schedule notice: $error');
    }
    return stored;
  }

  Future<void> delete(PersonalReminder reminder) async {
    final db = await _database();
    await db.delete(
      'personal_reminders',
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
    try {
      await _scheduler.cancelPersonalReminder(reminder);
    } catch (error) {
      debugPrint('Reminder cancel notice: $error');
    }
  }

  /// Re-arms every stored reminder; safe to call on each app start.
  Future<void> rescheduleAll() async {
    final reminders = await loadAll();
    await _scheduler.rescheduleAll(reminders);
  }
}

final personalReminderRepositoryProvider =
    Provider<PersonalReminderRepository>((ref) => PersonalReminderRepository());

final personalRemindersProvider =
    FutureProvider<List<PersonalReminder>>((ref) async {
  return ref.watch(personalReminderRepositoryProvider).loadAll();
});
