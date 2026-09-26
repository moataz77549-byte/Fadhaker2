import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/features/reminders/domain/personal_reminder.dart';
import 'package:fadhkur_mobile/core/services/notification_service.dart';

void main() {
  group('PersonalReminder', () {
    test('round-trips through a storage map', () {
      const reminder = PersonalReminder(
        id: 4,
        title: 'ورد القرآن',
        hour: 6,
        minute: 30,
        weekdays: {1, 3, 5},
        sound: ReminderSound.takbeer,
      );

      final restored = PersonalReminder.fromMap(reminder.toMap());

      expect(restored.id, 4);
      expect(restored.title, 'ورد القرآن');
      expect(restored.hour, 6);
      expect(restored.minute, 30);
      expect(restored.weekdays, {1, 3, 5});
      expect(restored.sound, ReminderSound.takbeer);
      expect(restored.enabled, isTrue);
    });

    test('empty weekdays means daily', () {
      const reminder =
          PersonalReminder(id: 1, title: 'أذكار الصباح', hour: 7, minute: 0);

      expect(reminder.isDaily, isTrue);
      expect(reminder.repeatLabel, 'يوميًا');
      expect(reminder.notificationIds, [10]);
      expect(reminder.timeLabel, '07:00');
    });

    test('weekly reminders own one notification id per day', () {
      const reminder = PersonalReminder(
        id: 3,
        title: 'ورد الجمعة',
        hour: 5,
        minute: 15,
        weekdays: {5, 7},
      );

      expect(reminder.isDaily, isFalse);
      expect(reminder.notificationIds, [35, 37]);
    });

    test('nextOccurrence rolls over to tomorrow when time has passed', () {
      const reminder =
          PersonalReminder(id: 2, title: 'ورد المساء', hour: 18, minute: 0);

      final next = reminder.nextOccurrence(DateTime(2026, 5, 10, 19, 0));

      expect(next, DateTime(2026, 5, 11, 18, 0));
    });

    test('nextOccurrence honours the weekday filter', () {
      const reminder = PersonalReminder(
        id: 9,
        title: 'ورد الجمعة',
        hour: 9,
        minute: 0,
        weekdays: {5},
      );

      // 2026-05-10 is a Sunday; the next Friday is 2026-05-15.
      final next = reminder.nextOccurrence(DateTime(2026, 5, 10, 9, 30));

      expect(next, DateTime(2026, 5, 15, 9, 0));
      expect(next.weekday, DateTime.friday);
    });

    test('sound ids fall back to the soft tone', () {
      expect(ReminderSoundLabel.fromId('takbeer'), ReminderSound.takbeer);
      expect(ReminderSoundLabel.fromId('nope'), ReminderSound.soft);
      expect(ReminderSound.recorded.androidResource, isNull);
    });

    test('phone audio gets a stable channel separate from prayer Adhan', () {
      const uri = 'content://app.fadhkur.reminder_sounds/'
          '123e4567-e89b-12d3-a456-426614174000.mp3';
      const reminder = PersonalReminder(id: 9, title: 'تنبيه', hour: 8,
          minute: 0, sound: ReminderSound.recorded, customSoundPath: uri);
      final restored = PersonalReminder.fromMap(reminder.toMap());
      final channel = NotificationChannels.personalForReminder(restored);
      expect(restored.customSoundPath, uri);
      expect(channel.id, contains('123e4567-e89b-12d3-a456-426614174000'));
      expect(channel.id, isNot(NotificationChannels.adhan.id));
      expect(channel.sound?.sound, uri);
    });
  });
}
